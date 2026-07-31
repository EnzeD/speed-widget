import Combine
import Foundation

@MainActor
public final class NetworkQualityMonitor: ObservableObject {
    @Published public private(set) var snapshot: QualitySnapshot = .measuring
    @Published public private(set) var capacity: CapacityEstimate?
    @Published public private(set) var pathState: NetworkPathState = .unknown
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
        snapshot.score.map(String.init) ?? "—"
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
            capacityTestError = "Micro-test désactivé sur une connexion limitée."
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
            } catch {
                self.capacityTestError = "Le micro-test a échoué."
            }
            self.isRunningCapacityTest = false
        }
    }

    private func measureOnce() async {
        pathState = pathObserver.snapshot()

        if pathState.interfaceName != lastInterfaceName {
            lastInterfaceName = pathState.interfaceName
            samples.removeAll(keepingCapacity: true)
            capacity = nil
            trafficMonitor.reset(interfaceName: pathState.interfaceName)
            snapshot = pathState.isReachable ? .measuring : .offline
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
        snapshot = QualityScorer.snapshot(from: samples, capacity: capacity)
    }

    private func appendFailure(transferredBytes: Int) {
        samples.append(
            ProbeSample(
                latencyMilliseconds: nil,
                succeeded: false,
                observedDuringTraffic: false,
                transferredBytes: transferredBytes
            )
        )
        trimSamples()
        snapshot = QualityScorer.snapshot(from: samples, capacity: capacity)
    }

    private func trimSamples() {
        let cutoff = Date.now.addingTimeInterval(-600)
        samples.removeAll { $0.date < cutoff }
    }
}
