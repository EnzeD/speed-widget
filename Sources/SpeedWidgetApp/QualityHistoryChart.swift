import Charts
import SpeedWidgetCore
import SwiftUI

struct QualityHistoryChart: View {
    let points: [QualityHistoryPoint]
    let color: Color

    private var timeDomain: ClosedRange<Date> {
        let now = Date.now
        return now.addingTimeInterval(-300)...now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History")
                    .font(.subheadline.weight(.medium))
                Text("5 min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let score = points.last?.score {
                    Text("\(score)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(color)
                }
            }

            if points.count < 2 {
                ContentUnavailableView {
                    Label("History loading", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Two measurements are required.")
                }
                .frame(height: 104)
            } else {
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Minimum", 0),
                            yEnd: .value("Score", point.score)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.24), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }

                    RuleMark(y: .value("Good", 70))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXScale(domain: timeDomain)
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let score = value.as(Int.self) {
                                Text("\(score)")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 104)
            }

            HStack {
                Text("−5 min")
                Spacer()
                Text("Now")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(14)
    }
}
