import Foundation
import Testing
@testable import SpeedWidgetCore

struct QualityScorerTests {
    @Test("The probe client refuses non-HTTPS endpoints")
    func refusesNonHTTPSEndpoints() async {
        let client = HTTPProbeClient()
        let endpoint = ProbeEndpoint(url: URL(string: "http://example.com")!)

        let result = await client.probe(endpoint)

        #expect(!result.succeeded)
        #expect(result.statusCode == nil)
        #expect(result.transferredBytes == 0)
    }

    @Test("Capacity requests cannot exceed the micro-test limit")
    func capsCapacityTestBytes() throws {
        let bounded = try HTTPProbeClient.boundedCapacityTestBytes(10_000_000)

        #expect(bounded == HTTPProbeClient.maximumCapacityTestBytes)
    }

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

    @Test("Idle and active scores use separate samples")
    func separatesIdleAndUnderLoadScores() {
        let now = Date()
        let idle = (0..<6).map { index in
            ProbeSample(
                date: now.addingTimeInterval(Double(index - 12) * 5),
                latencyMilliseconds: 20,
                succeeded: true,
                observedDuringTraffic: false
            )
        }
        let active = (0..<6).map { index in
            ProbeSample(
                date: now.addingTimeInterval(Double(index - 6) * 5),
                latencyMilliseconds: 180,
                succeeded: true,
                observedDuringTraffic: true
            )
        }

        let samples = idle + active
        let idleResult = QualityScorer.idleSnapshot(from: samples, now: now)
        let activeResult = QualityScorer.activeSnapshot(from: samples, now: now)

        #expect(idleResult.score != nil)
        #expect(activeResult.score != nil)
        #expect(idleResult.score! >= 85)
        #expect(activeResult.score! < idleResult.score!)
        #expect(QualityScorer.credibleUnderLoadScore(idle: idleResult, active: activeResult) == activeResult.score)
    }

    @Test("A better active score is not presented as degradation")
    func ignoresApparentImprovementUnderLoad() {
        let now = Date()
        let idle = (0..<6).map { index in
            ProbeSample(
                date: now.addingTimeInterval(Double(index - 12) * 5),
                latencyMilliseconds: 180,
                succeeded: true,
                observedDuringTraffic: false
            )
        }
        let active = (0..<6).map { index in
            ProbeSample(
                date: now.addingTimeInterval(Double(index - 6) * 5),
                latencyMilliseconds: 20,
                succeeded: true,
                observedDuringTraffic: true
            )
        }

        let idleResult = QualityScorer.idleSnapshot(from: idle + active, now: now)
        let activeResult = QualityScorer.activeSnapshot(from: idle + active, now: now)

        #expect(activeResult.score! > idleResult.score!)
        #expect(QualityScorer.credibleUnderLoadScore(idle: idleResult, active: activeResult) == nil)
    }

    @Test("Three loaded probes are required before comparing scores")
    func waitsForEnoughActiveSamples() {
        let now = Date()
        let idle = (0..<6).map { index in
            ProbeSample(
                date: now.addingTimeInterval(Double(index - 8) * 5),
                latencyMilliseconds: 20,
                succeeded: true,
                observedDuringTraffic: false
            )
        }
        let active = (0..<2).map { index in
            ProbeSample(
                date: now.addingTimeInterval(Double(index - 2) * 5),
                latencyMilliseconds: 250,
                succeeded: true,
                observedDuringTraffic: true
            )
        }

        let idleResult = QualityScorer.idleSnapshot(from: idle + active, now: now)
        let activeResult = QualityScorer.activeSnapshot(from: idle + active, now: now)

        #expect(activeResult.score == nil)
        #expect(QualityScorer.credibleUnderLoadScore(idle: idleResult, active: activeResult) == nil)
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
