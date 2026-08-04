import Foundation

public enum QualityScorer {
    public static func idleSnapshot(
        from allSamples: [ProbeSample],
        capacity: CapacityEstimate? = nil
    ) -> QualitySnapshot {
        let idleSamples = allSamples.filter { !$0.observedDuringTraffic }
        guard let lastIdleDate = idleSamples.last?.date else {
            return .measuring
        }

        return snapshot(from: idleSamples, capacity: capacity, now: lastIdleDate)
    }

    public static func snapshot(
        from allSamples: [ProbeSample],
        capacity: CapacityEstimate? = nil,
        now: Date = .now
    ) -> QualitySnapshot {
        let historyCutoff = now.addingTimeInterval(-300)
        let history = allSamples.filter { $0.date >= historyCutoff }
        let recentCutoff = now.addingTimeInterval(-45)
        let samples = Array(history.filter { $0.date >= recentCutoff }.suffix(6))

        guard !samples.isEmpty else {
            return .measuring
        }

        let lastThree = samples.suffix(3)
        if lastThree.count == 3, lastThree.allSatisfy({ !$0.succeeded }) {
            return QualitySnapshot(
                score: 0,
                grade: .offline,
                confidence: confidence(
                    for: history,
                    successfulCount: history.filter(\.succeeded).count
                ),
                latencyMilliseconds: nil,
                jitterMilliseconds: nil,
                lossPercent: 100,
                idleLatencyMilliseconds: nil,
                activeLatencyMilliseconds: nil,
                loadInflation: nil,
                sampleCount: history.count,
                recentLatencies: []
            )
        }

        let successful = samples.filter { $0.succeeded && $0.latencyMilliseconds != nil }
        let latencies = successful.compactMap(\.latencyMilliseconds)
        let latencyWindow = Array(latencies.suffix(3))
        guard let currentLatency = median(latencyWindow) else {
            return .measuring
        }

        let differences = zip(latencies, latencies.dropFirst()).map { abs($1 - $0) }
        let jitter = median(differences) ?? 0
        let lossRatio = Double(samples.count - successful.count) / Double(samples.count)

        let historicalSuccessful = history.filter { $0.succeeded && $0.latencyMilliseconds != nil }
        let idleLatency = median(
            historicalSuccessful.filter { !$0.observedDuringTraffic }.compactMap(\.latencyMilliseconds)
        )
        let activeLatency = median(successful.filter(\.observedDuringTraffic).compactMap(\.latencyMilliseconds))
        let inflation: Double?
        if let idleLatency, let activeLatency, idleLatency > 0 {
            inflation = activeLatency / idleLatency
        } else {
            inflation = nil
        }

        let measurementConfidence = confidence(
            for: history,
            successfulCount: historicalSuccessful.count
        )

        guard samples.count >= 3 else {
            return QualitySnapshot(
                score: nil,
                grade: .measuring,
                confidence: measurementConfidence,
                latencyMilliseconds: currentLatency,
                jitterMilliseconds: jitter,
                lossPercent: lossRatio * 100,
                idleLatencyMilliseconds: idleLatency,
                activeLatencyMilliseconds: activeLatency,
                loadInflation: inflation,
                sampleCount: history.count,
                recentLatencies: Array(historicalSuccessful.compactMap(\.latencyMilliseconds).suffix(30))
            )
        }

        let latencyComponent = interpolate(
            currentLatency,
            points: [(0, 100), (20, 100), (50, 85), (100, 60), (250, 20), (1_000, 0)]
        )
        let jitterComponent = interpolate(
            jitter,
            points: [(0, 100), (5, 100), (15, 85), (30, 60), (80, 20), (250, 0)]
        )
        let lossComponent = interpolate(
            lossRatio * 100,
            points: [(0, 100), (0.5, 92), (1, 82), (3, 55), (8, 15), (20, 0)]
        )

        var score = latencyComponent * 0.45 + jitterComponent * 0.30 + lossComponent * 0.25

        if let capacity, now.timeIntervalSince(capacity.measuredAt) < 86_400 {
            let capacityComponent = interpolate(
                capacity.megabitsPerSecond,
                points: [(0, 0), (2, 15), (5, 40), (25, 80), (100, 100)]
            )
            score = score * 0.90 + capacityComponent * 0.10
        }

        if let inflation, inflation > 2 {
            let penalty = min(20, (inflation - 2) * 4)
            score -= penalty
        }

        let roundedScore = max(0, min(100, Int(score.rounded())))
        return QualitySnapshot(
            score: roundedScore,
            grade: grade(for: roundedScore),
            confidence: measurementConfidence,
            latencyMilliseconds: currentLatency,
            jitterMilliseconds: jitter,
            lossPercent: lossRatio * 100,
            idleLatencyMilliseconds: idleLatency,
            activeLatencyMilliseconds: activeLatency,
            loadInflation: inflation,
            sampleCount: history.count,
            recentLatencies: Array(historicalSuccessful.compactMap(\.latencyMilliseconds).suffix(30))
        )
    }

    static func grade(for score: Int) -> QualityGrade {
        switch score {
        case 85...: .excellent
        case 70...: .good
        case 45...: .fair
        case 1...: .poor
        default: .offline
        }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func interpolate(_ value: Double, points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if value <= first.0 { return first.1 }
        if value >= last.0 { return last.1 }

        for (lower, upper) in zip(points, points.dropFirst()) where value <= upper.0 {
            let progress = (value - lower.0) / (upper.0 - lower.0)
            return lower.1 + (upper.1 - lower.1) * progress
        }
        return last.1
    }

    private static func confidence(for samples: [ProbeSample], successfulCount: Int) -> MeasurementConfidence {
        let activeCount = samples.filter(\.observedDuringTraffic).count
        if samples.count >= 36, successfulCount >= 30, activeCount >= 4 {
            return .high
        }
        if samples.count >= 12, successfulCount >= 8 {
            return .medium
        }
        return .low
    }
}
