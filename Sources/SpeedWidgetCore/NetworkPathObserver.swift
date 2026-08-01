import Foundation
import Network

public struct NetworkPathState: Sendable, Equatable {
    public let isReachable: Bool
    public let interfaceName: String?
    public let interfaceLabel: String
    public let isExpensive: Bool
    public let isConstrained: Bool

    public init(
        isReachable: Bool,
        interfaceName: String?,
        interfaceLabel: String,
        isExpensive: Bool,
        isConstrained: Bool
    ) {
        self.isReachable = isReachable
        self.interfaceName = interfaceName
        self.interfaceLabel = interfaceLabel
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }

    public static let unknown = NetworkPathState(
        isReachable: false,
        interfaceName: nil,
        interfaceLabel: "Network",
        isExpensive: false,
        isConstrained: false
    )
}

public final class NetworkPathObserver: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.speedwidget.path-monitor", qos: .utility)
    private let lock = NSLock()
    private var state = NetworkPathState.unknown
    private var started = false

    public init() {}

    public func start() {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            let activeInterface = path.availableInterfaces.first { path.usesInterfaceType($0.type) }
            let nextState = NetworkPathState(
                isReachable: path.status == .satisfied,
                interfaceName: activeInterface?.name,
                interfaceLabel: Self.label(for: activeInterface?.type),
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )
            self?.setState(nextState)
        }
        monitor.start(queue: queue)
    }

    public func snapshot() -> NetworkPathState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    private func setState(_ state: NetworkPathState) {
        lock.lock()
        self.state = state
        lock.unlock()
    }

    private static func label(for type: NWInterface.InterfaceType?) -> String {
        switch type {
        case .wifi: "Wi-Fi"
        case .wiredEthernet: "Ethernet"
        case .cellular: "Cellular"
        case .loopback: "Local loopback"
        case .other: "Other network"
        case nil: "Network"
        @unknown default: "Network"
        }
    }
}
