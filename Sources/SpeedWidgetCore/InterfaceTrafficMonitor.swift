import Darwin
import Foundation

public struct TrafficRate: Sendable, Equatable {
    public let receivedBytesPerSecond: Double
    public let sentBytesPerSecond: Double

    public var totalBytesPerSecond: Double {
        receivedBytesPerSecond + sentBytesPerSecond
    }

    public var hasMeaningfulTraffic: Bool {
        totalBytesPerSecond >= 128_000
    }
}

public final class InterfaceTrafficMonitor {
    private struct Counters {
        let received: UInt64
        let sent: UInt64
    }

    private var previousCounters: Counters?
    private var previousUptime: TimeInterval?
    private var previousInterfaceName: String?

    public init() {}

    public func sample(interfaceName: String?) -> TrafficRate {
        guard let current = counters(for: interfaceName) else {
            reset(interfaceName: interfaceName)
            return TrafficRate(receivedBytesPerSecond: 0, sentBytesPerSecond: 0)
        }

        let uptime = ProcessInfo.processInfo.systemUptime
        defer {
            previousCounters = current
            previousUptime = uptime
            previousInterfaceName = interfaceName
        }

        guard previousInterfaceName == interfaceName,
              let previousCounters,
              let previousUptime,
              uptime > previousUptime else {
            return TrafficRate(receivedBytesPerSecond: 0, sentBytesPerSecond: 0)
        }

        let elapsed = uptime - previousUptime
        let receivedDelta = current.received >= previousCounters.received
            ? current.received - previousCounters.received
            : 0
        let sentDelta = current.sent >= previousCounters.sent
            ? current.sent - previousCounters.sent
            : 0

        return TrafficRate(
            receivedBytesPerSecond: Double(receivedDelta) / elapsed,
            sentBytesPerSecond: Double(sentDelta) / elapsed
        )
    }

    public func reset(interfaceName: String?) {
        previousCounters = nil
        previousUptime = nil
        previousInterfaceName = interfaceName
    }

    private func counters(for requestedInterfaceName: String?) -> Counters? {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return nil }
        defer { freeifaddrs(firstAddress) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var matched = false

        while let interface = cursor {
            let value = interface.pointee
            let name = String(cString: value.ifa_name)
            let flags = Int32(value.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let nameMatches = requestedInterfaceName.map { $0 == name } ?? true

            if isUp, !isLoopback, nameMatches, let rawData = value.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
                matched = true
            }
            cursor = value.ifa_next
        }

        return matched ? Counters(received: received, sent: sent) : nil
    }
}
