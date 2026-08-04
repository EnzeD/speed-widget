import Foundation

public struct ProbeEndpoint: Sendable, Equatable {
    public let url: URL
    public let method: String

    public init(url: URL, method: String = "GET") {
        self.url = url
        self.method = method
    }

    public static let cloudflareZeroByte = ProbeEndpoint(
        url: URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
    )

    public static let appleFallback = ProbeEndpoint(
        url: URL(string: "https://www.apple.com/library/test/success.html")!,
        method: "HEAD"
    )
}

public struct ProbeResult: Sendable, Equatable {
    public let succeeded: Bool
    public let latencyMilliseconds: Double?
    public let transferredBytes: Int
    public let statusCode: Int?

    public init(succeeded: Bool, latencyMilliseconds: Double?, transferredBytes: Int, statusCode: Int?) {
        self.succeeded = succeeded
        self.latencyMilliseconds = latencyMilliseconds
        self.transferredBytes = transferredBytes
        self.statusCode = statusCode
    }
}

private final class TaskMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var byteCount = 0
    private var newConnectionCount = 0

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        lock.lock()
        defer { lock.unlock() }

        for transaction in metrics.transactionMetrics {
            byteCount += Int(transaction.countOfRequestHeaderBytesSent)
            byteCount += Int(transaction.countOfRequestBodyBytesSent)
            byteCount += Int(transaction.countOfResponseHeaderBytesReceived)
            byteCount += Int(transaction.countOfResponseBodyBytesReceived)
            if !transaction.isReusedConnection {
                newConnectionCount += 1
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // The two probe endpoints do not need redirects. Rejecting them prevents a
        // probe from silently being sent to an unexpected host or downgraded URL.
        completionHandler(nil)
    }

    func estimatedWireBytes(fallbackBodyBytes: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        // Transaction metrics omit part of the IP, transport and TLS overhead.
        let measured = max(byteCount, fallbackBodyBytes + 256)
        return Int(Double(measured) * 1.20) + newConnectionCount * 2_500
    }
}

public actor HTTPProbeClient {
    public static let maximumCapacityTestBytes = 2_000_000

    private static let maximumProbeResponseBytes = 32_768
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpShouldUsePipelining = true
        session = URLSession(configuration: configuration)
    }

    public func probe(_ endpoint: ProbeEndpoint) async -> ProbeResult {
        guard endpoint.url.scheme?.lowercased() == "https", endpoint.url.host != nil else {
            return ProbeResult(
                succeeded: false,
                latencyMilliseconds: nil,
                transferredBytes: 0,
                statusCode: nil
            )
        }

        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.method
        request.timeoutInterval = 3
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("SpeedWidget/0.1", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false

        let metrics = TaskMetricsCollector()
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let (receivedBytes, response) = try await receive(
                request,
                maximumResponseBytes: Self.maximumProbeResponseBytes,
                delegate: metrics
            )
            let elapsed = durationSeconds(start.duration(to: clock.now))
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let succeeded = statusCode.map { (200...299).contains($0) } ?? false
            return ProbeResult(
                succeeded: succeeded,
                latencyMilliseconds: succeeded ? elapsed * 1_000 : nil,
                transferredBytes: metrics.estimatedWireBytes(fallbackBodyBytes: receivedBytes),
                statusCode: statusCode
            )
        } catch {
            return ProbeResult(
                succeeded: false,
                latencyMilliseconds: nil,
                transferredBytes: metrics.estimatedWireBytes(fallbackBodyBytes: 0),
                statusCode: nil
            )
        }
    }

    public func capacityTest(
        baselineLatencyMilliseconds: Double?,
        maximumBytes: Int = HTTPProbeClient.maximumCapacityTestBytes
    ) async throws -> CapacityEstimate {
        let boundedMaximumBytes = try Self.boundedCapacityTestBytes(maximumBytes)

        let firstStageBytes = min(250_000, boundedMaximumBytes)
        let first = try await download(byteCount: firstStageBytes, baselineLatencyMilliseconds: baselineLatencyMilliseconds)

        if boundedMaximumBytes == firstStageBytes || first.durationSeconds >= 0.75 {
            return CapacityEstimate(
                megabitsPerSecond: first.megabitsPerSecond,
                transferredBytes: first.transferredBytes
            )
        }

        let secondStageBytes = boundedMaximumBytes - firstStageBytes
        let second = try await download(byteCount: secondStageBytes, baselineLatencyMilliseconds: baselineLatencyMilliseconds)
        let weightedRate = (
            first.megabitsPerSecond * Double(first.transferredBytes)
                + second.megabitsPerSecond * Double(second.transferredBytes)
        ) / Double(first.transferredBytes + second.transferredBytes)

        return CapacityEstimate(
            megabitsPerSecond: weightedRate,
            transferredBytes: first.transferredBytes + second.transferredBytes
        )
    }

    private func download(
        byteCount: Int,
        baselineLatencyMilliseconds: Double?
    ) async throws -> (megabitsPerSecond: Double, durationSeconds: Double, transferredBytes: Int) {
        var components = URLComponents(string: "https://speed.cloudflare.com/__down")!
        components.queryItems = [URLQueryItem(name: "bytes", value: String(byteCount))]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("SpeedWidget/0.1", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false

        let clock = ContinuousClock()
        let start = clock.now
        let (receivedBytes, response) = try await receive(
            request,
            maximumResponseBytes: byteCount,
            delegate: TaskMetricsCollector()
        )
        let elapsed = durationSeconds(start.duration(to: clock.now))
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode),
              receivedBytes > 0 else {
            throw URLError(.badServerResponse)
        }

        let baseline = min(elapsed * 0.8, (baselineLatencyMilliseconds ?? 0) / 1_000)
        let transferDuration = max(0.01, elapsed - baseline)
        let rate = Double(receivedBytes) * 8 / transferDuration / 1_000_000
        return (rate, elapsed, receivedBytes)
    }

    private func receive(
        _ request: URLRequest,
        maximumResponseBytes: Int,
        delegate: URLSessionTaskDelegate?
    ) async throws -> (receivedBytes: Int, response: URLResponse) {
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        if response.expectedContentLength > Int64(maximumResponseBytes) {
            throw URLError(.dataLengthExceedsMaximum)
        }

        var receivedBytes = 0
        for try await _ in bytes {
            receivedBytes += 1
            if receivedBytes > maximumResponseBytes {
                throw URLError(.dataLengthExceedsMaximum)
            }
        }

        return (receivedBytes, response)
    }

    static func boundedCapacityTestBytes(_ requestedBytes: Int) throws -> Int {
        guard requestedBytes > 0 else {
            throw URLError(.badURL)
        }
        return min(requestedBytes, maximumCapacityTestBytes)
    }
}

private func durationSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
}
