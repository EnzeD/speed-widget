import Foundation

public enum QualityGrade: String, Sendable {
    case measuring
    case excellent
    case good
    case fair
    case poor
    case offline

    public var label: String {
        switch self {
        case .measuring: "Mesure…"
        case .excellent: "Excellente"
        case .good: "Bonne"
        case .fair: "Moyenne"
        case .poor: "Mauvaise"
        case .offline: "Hors ligne"
        }
    }
}

public enum MeasurementConfidence: String, Sendable {
    case low
    case medium
    case high

    public var label: String {
        switch self {
        case .low: "Faible"
        case .medium: "Moyenne"
        case .high: "Élevée"
        }
    }
}

public struct ProbeSample: Sendable, Equatable {
    public let date: Date
    public let latencyMilliseconds: Double?
    public let succeeded: Bool
    public let observedDuringTraffic: Bool
    public let transferredBytes: Int

    public init(
        date: Date = .now,
        latencyMilliseconds: Double?,
        succeeded: Bool,
        observedDuringTraffic: Bool,
        transferredBytes: Int = 0
    ) {
        self.date = date
        self.latencyMilliseconds = latencyMilliseconds
        self.succeeded = succeeded
        self.observedDuringTraffic = observedDuringTraffic
        self.transferredBytes = transferredBytes
    }
}

public struct CapacityEstimate: Sendable, Equatable {
    public let megabitsPerSecond: Double
    public let measuredAt: Date
    public let transferredBytes: Int

    public init(megabitsPerSecond: Double, measuredAt: Date = .now, transferredBytes: Int) {
        self.megabitsPerSecond = megabitsPerSecond
        self.measuredAt = measuredAt
        self.transferredBytes = transferredBytes
    }

    public var tierLabel: String {
        switch megabitsPerSecond {
        case ..<5: "< 5 Mb/s"
        case ..<25: "5–25 Mb/s"
        case ..<100: "25–100 Mb/s"
        default: "100+ Mb/s"
        }
    }
}

public struct QualitySnapshot: Sendable, Equatable {
    public let score: Int?
    public let grade: QualityGrade
    public let confidence: MeasurementConfidence
    public let latencyMilliseconds: Double?
    public let jitterMilliseconds: Double?
    public let lossPercent: Double?
    public let idleLatencyMilliseconds: Double?
    public let activeLatencyMilliseconds: Double?
    public let loadInflation: Double?
    public let sampleCount: Int
    public let recentLatencies: [Double]

    public init(
        score: Int?,
        grade: QualityGrade,
        confidence: MeasurementConfidence,
        latencyMilliseconds: Double?,
        jitterMilliseconds: Double?,
        lossPercent: Double?,
        idleLatencyMilliseconds: Double?,
        activeLatencyMilliseconds: Double?,
        loadInflation: Double?,
        sampleCount: Int,
        recentLatencies: [Double]
    ) {
        self.score = score
        self.grade = grade
        self.confidence = confidence
        self.latencyMilliseconds = latencyMilliseconds
        self.jitterMilliseconds = jitterMilliseconds
        self.lossPercent = lossPercent
        self.idleLatencyMilliseconds = idleLatencyMilliseconds
        self.activeLatencyMilliseconds = activeLatencyMilliseconds
        self.loadInflation = loadInflation
        self.sampleCount = sampleCount
        self.recentLatencies = recentLatencies
    }

    public static let measuring = QualitySnapshot(
        score: nil,
        grade: .measuring,
        confidence: .low,
        latencyMilliseconds: nil,
        jitterMilliseconds: nil,
        lossPercent: nil,
        idleLatencyMilliseconds: nil,
        activeLatencyMilliseconds: nil,
        loadInflation: nil,
        sampleCount: 0,
        recentLatencies: []
    )

    public static let offline = QualitySnapshot(
        score: 0,
        grade: .offline,
        confidence: .low,
        latencyMilliseconds: nil,
        jitterMilliseconds: nil,
        lossPercent: 100,
        idleLatencyMilliseconds: nil,
        activeLatencyMilliseconds: nil,
        loadInflation: nil,
        sampleCount: 0,
        recentLatencies: []
    )
}
