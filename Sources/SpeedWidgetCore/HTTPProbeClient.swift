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

    func estimatedWireBytes(fallbackBodyBytes: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        // Transaction metrics omit part of the IP, transport and TLS overhead.
        let measured = max(byteCount, fallbackBodyBytes + 256)
        return Int(Double(measured) * 1.20) + newConnectionCount * 2_500
    }
}

public actor HTTPProbeClient {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpShouldUsePipelining = true
        session = URLSession(configuration: configuration)
    }

    public func probe(_ endpoint: ProbeEndpoint) async -> ProbeResult {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.method
        request.timeoutInterval = 3
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("SpeedWidget/0.1", forHTTPHeaderField: "User-Agent")

        let metrics = TaskMetricsCollector()
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let (data, response) = try await session.data(for: request, delegate: metrics)
            let elapsed = durationSeconds(start.duration(to: clock.now))
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let succeeded = statusCode.map { (200...399).contains($0) } ?? false
            return ProbeResult(
                succeeded: succeeded,
                latencyMilliseconds: succeeded ? elapsed * 1_000 : nil,
                transferredBytes: metrics.estimatedWireBytes(fallbackBodyBytes: data.count),
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
        maximumBytes: Int = 2_000_000
    ) async throws -> CapacityEstimate {
        let firstStageBytes = min(250_000, maximumBytes)
        let first = try await download(byteCount: firstStageBytes, baselineLatencyMilliseconds: baselineLatencyMilliseconds)

        if maximumBytes == firstStageBytes || first.durationSeconds >= 0.75 {
            return CapacityEstimate(
                megabitsPerSecond: first.megabitsPerSecond,
                transferredBytes: first.transferredBytes
            )
        }

        let secondStageBytes = maximumBytes - firstStageBytes
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

        let clock = ContinuousClock()
        let start = clock.now
        let (data, response) = try await session.data(for: request)
        let elapsed = durationSeconds(start.duration(to: clock.now))
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode),
              !data.isEmpty else {
            throw URLError(.badServerResponse)
        }

        let baseline = min(elapsed * 0.8, (baselineLatencyMilliseconds ?? 0) / 1_000)
        let transferDuration = max(0.01, elapsed - baseline)
        let rate = Double(data.count) * 8 / transferDuration / 1_000_000
        return (rate, elapsed, data.count)
    }
}

private func durationSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
}
