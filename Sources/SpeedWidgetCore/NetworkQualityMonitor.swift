import Combine
import Foundation

@MainActor
public final class NetworkQualityMonitor: ObservableObject {
    @Published public private(set) var snapshot: QualitySnapshot = .measuring
    @Published public private(set) var idleSnapshot: QualitySnapshot = .measuring
    @Published public private(set) var isUnderLoad = false
    @Published public private(set) var capacity: CapacityEstimate?
    @Published public private(set) var pathState: NetworkPathState = .unknown
    @Published public private(set) var qualityHistory: [QualityHistoryPoint] = []
    @Published public private(set) var dailyProbeBytes = 0
    @Published public private(set) var isRunningCapacityTest = false
    @Published public private(set) var capacityTestError: String?

    private let pathObserver: NetworkPathObserver
    private let probeClient: HTTPProbeClient
    private let trafficMonitor: InterfaceTrafficMonitor
    private var usage: DailyProbeUsage
    private var samples: [ProbeSample] = []
    private var loopTask: Task<Void, Never>?
    private var lastInterfaceName: String?

    public init(
        pathObserver: NetworkPathObserver = NetworkPathObserver(),
        probeClient: HTTPProbeClient = HTTPProbeClient(),
        trafficMonitor: InterfaceTrafficMonitor = InterfaceTrafficMonitor()
    ) {
        self.pathObserver = pathObserver
        self.probeClient = probeClient
        self.trafficMonitor = trafficMonitor
        usage = DailyProbeUsage()
        dailyProbeBytes = usage.consumedBytes()
        pathObserver.start()

        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    deinit {
        loopTask?.cancel()
    }

    public var menuBarScore: String {
        guard let currentScore = snapshot.score else { return "—" }
        if snapshot.grade == .offline { return String(currentScore) }
        guard let idleScore = idleSnapshot.score else { return String(currentScore) }
        if isUnderLoad {
            return "\(idleScore) (\(currentScore))"
        }
        return String(idleScore)
    }

    public var primarySnapshot: QualitySnapshot {
        if snapshot.grade == .offline { return snapshot }
        return idleSnapshot.score == nil ? snapshot : idleSnapshot
    }

    public var primaryScore: String {
        primarySnapshot.score.map(String.init) ?? "—"
    }

    public var underLoadScore: Int? {
        isUnderLoad ? snapshot.score : nil
    }

    public var menuBarAccessibilityLabel: String {
        if isUnderLoad,
           let idleScore = idleSnapshot.score,
           let currentScore = snapshot.score {
            return "Network quality \(idleScore) at idle, \(currentScore) under load"
        }
        return "Network quality, score \(primaryScore)"
    }

    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.measureOnce()
                let delay: Duration = self.pathState.isExpensive || self.pathState.isConstrained
                    ? .seconds(15)
                    : .seconds(5)
                try? await Task.sleep(for: delay)
            }
        }
    }

    public func measureNow() {
        Task { [weak self] in
            await self?.measureOnce()
        }
    }

    public func runCapacityTest() {
        guard !isRunningCapacityTest else { return }
        guard !pathState.isExpensive, !pathState.isConstrained else {
            capacityTestError = "Micro-test disabled on a constrained connection."
            return
        }

        isRunningCapacityTest = true
        capacityTestError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.probeClient.capacityTest(
                    baselineLatencyMilliseconds: self.snapshot.latencyMilliseconds
                )
                self.capacity = result
                self.usage.record(result.transferredBytes)
                self.dailyProbeBytes = self.usage.consumedBytes()
                self.snapshot = QualityScorer.snapshot(from: self.samples, capacity: result)
                self.idleSnapshot = QualityScorer.idleSnapshot(from: self.samples, capacity: result)
            } catch {
                self.capacityTestError = "Micro-test failed."
            }
            self.isRunningCapacityTest = false
        }
    }

    private func measureOnce() async {
        pathState = pathObserver.snapshot()

        if pathState.interfaceName != lastInterfaceName {
            lastInterfaceName = pathState.interfaceName
            samples.removeAll(keepingCapacity: true)
            qualityHistory.removeAll(keepingCapacity: true)
            capacity = nil
            trafficMonitor.reset(interfaceName: pathState.interfaceName)
            snapshot = pathState.isReachable ? .measuring : .offline
            idleSnapshot = .measuring
            isUnderLoad = false
        }

        guard pathState.isReachable else {
            appendFailure(transferredBytes: 0)
            return
        }

        dailyProbeBytes = usage.consumedBytes()

        let traffic = trafficMonitor.sample(interfaceName: pathState.interfaceName)
        let primary = await probeClient.probe(.cloudflareZeroByte)
        var selected = primary
        var totalTransferredBytes = primary.transferredBytes

        if !primary.succeeded || (primary.latencyMilliseconds ?? 0) > 500 {
            let fallback = await probeClient.probe(.appleFallback)
            totalTransferredBytes += fallback.transferredBytes
            if fallback.succeeded,
               !primary.succeeded || (fallback.latencyMilliseconds ?? .infinity) < (primary.latencyMilliseconds ?? .infinity) {
                selected = fallback
            }
        }

        usage.record(totalTransferredBytes)
        dailyProbeBytes = usage.consumedBytes()

        let sample = ProbeSample(
            latencyMilliseconds: selected.latencyMilliseconds,
            succeeded: selected.succeeded,
            observedDuringTraffic: traffic.hasMeaningfulTraffic,
            transferredBytes: totalTransferredBytes
        )
        samples.append(sample)
        trimSamples()
        updateSnapshot(
            QualityScorer.snapshot(from: samples, capacity: capacity),
            at: sample.date,
            underLoad: sample.observedDuringTraffic
        )
    }

    private func appendFailure(transferredBytes: Int) {
        let sample = ProbeSample(
            latencyMilliseconds: nil,
            succeeded: false,
            observedDuringTraffic: false,
            transferredBytes: transferredBytes
        )
        samples.append(sample)
        trimSamples()
        updateSnapshot(
            QualityScorer.snapshot(from: samples, capacity: capacity),
            at: sample.date,
            underLoad: false
        )
    }

    private func trimSamples() {
        let cutoff = Date.now.addingTimeInterval(-600)
        samples.removeAll { $0.date < cutoff }
    }

    private func updateSnapshot(_ nextSnapshot: QualitySnapshot, at date: Date, underLoad: Bool) {
        snapshot = nextSnapshot
        idleSnapshot = QualityScorer.idleSnapshot(from: samples, capacity: capacity)
        isUnderLoad = underLoad

        let cutoff = date.addingTimeInterval(-300)
        qualityHistory.removeAll { $0.date < cutoff }
        if let score = nextSnapshot.score {
            qualityHistory.append(QualityHistoryPoint(date: date, score: score))
        }
    }
}
