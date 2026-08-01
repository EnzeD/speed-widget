import Foundation
import Testing
@testable import SpeedWidgetCore

struct QualityScorerTests {
    @Test("A stable and fast connection gets an excellent score")
    func excellentConnection() {
        let now = Date()
        var samples: [ProbeSample] = []
        for index in 0..<40 {
            let date = now.addingTimeInterval(Double(index - 40) * 5)
            let latency = 18 + Double(index % 3)
            samples.append(ProbeSample(
                date: date,
                latencyMilliseconds: latency,
                succeeded: true,
                observedDuringTraffic: index % 5 == 0
            ))
        }

        let result = QualityScorer.snapshot(from: samples, now: now)

        #expect(result.score != nil)
        #expect(result.score! >= 85)
        #expect(result.grade == QualityGrade.excellent)
        #expect(result.confidence == MeasurementConfidence.high)
    }

    @Test("Three consecutive failures indicate an outage")
    func detectsOfflineState() {
        let now = Date()
        let samples = (0..<3).map { index in
            ProbeSample(
                date: now.addingTimeInterval(Double(index - 3) * 5),
                latencyMilliseconds: nil,
                succeeded: false,
                observedDuringTraffic: false
            )
        }

        let result = QualityScorer.snapshot(from: samples, now: now)

        #expect(result.score == 0)
        #expect(result.grade == QualityGrade.offline)
        #expect(result.lossPercent == 100)
    }

    @Test("Latency under load penalizes the score")
    func penalizesLatencyInflation() {
        let now = Date()
        let idle = (0..<20).map { index in
            ProbeSample(
                date: now.addingTimeInterval(Double(index - 40) * 5),
                latencyMilliseconds: 20,
                succeeded: true,
                observedDuringTraffic: false
            )
        }
        let active = (0..<20).map { index in
            ProbeSample(
                date: now.addingTimeInterval(Double(index - 20) * 5),
                latencyMilliseconds: 140,
                succeeded: true,
                observedDuringTraffic: true
            )
        }

        let result = QualityScorer.snapshot(from: idle + active, now: now)

        #expect(result.loadInflation == 7)
        #expect(result.score != nil)
        #expect(result.score! < 80)
    }

    @Test("The micro-test has limited influence on the score")
    func capacityHasLimitedWeight() {
        let now = Date()
        let samples = (0..<20).map { index in
            ProbeSample(
                date: now.addingTimeInterval(Double(index - 20) * 5),
                latencyMilliseconds: 35,
                succeeded: true,
                observedDuringTraffic: false
            )
        }
        let withoutCapacity = QualityScorer.snapshot(from: samples, now: now)
        let withCapacity = QualityScorer.snapshot(
            from: samples,
            capacity: CapacityEstimate(megabitsPerSecond: 2, measuredAt: now, transferredBytes: 250_000),
            now: now
        )

        #expect(withoutCapacity.score != nil)
        #expect(withCapacity.score != nil)
        #expect(withoutCapacity.score! - withCapacity.score! <= 10)
    }

    @Test("A recent loss immediately affects the score")
    func recentFailureAffectsCurrentScore() {
        let now = Date()
        var samples: [ProbeSample] = []
        for index in 0..<8 {
            samples.append(
                ProbeSample(
                    date: now.addingTimeInterval(Double(index - 8) * 5),
                    latencyMilliseconds: index == 3 ? nil : 20,
                    succeeded: index != 3,
                    observedDuringTraffic: false
                )
            )
        }

        let result = QualityScorer.snapshot(from: samples, now: now)

        #expect(abs((result.lossPercent ?? 0) - 16.67) < 0.01)
        #expect(result.score != nil)
        #expect((70...80).contains(result.score!))
    }

    @Test("The score prioritizes the last thirty seconds")
    func recentQualityOverridesOldHistory() {
        let now = Date()
        var samples: [ProbeSample] = []

        for index in 0..<20 {
            samples.append(
                ProbeSample(
                    date: now.addingTimeInterval(Double(index - 40) * 5),
                    latencyMilliseconds: 20,
                    succeeded: true,
                    observedDuringTraffic: false
                )
            )
        }
        for index in 0..<6 {
            samples.append(
                ProbeSample(
                    date: now.addingTimeInterval(Double(index - 6) * 5),
                    latencyMilliseconds: 300,
                    succeeded: true,
                    observedDuringTraffic: false
                )
            )
        }

        let result = QualityScorer.snapshot(from: samples, now: now)

        #expect(result.latencyMilliseconds == 300)
        #expect(result.score != nil)
        #expect(result.score! < 70)
    }
}
