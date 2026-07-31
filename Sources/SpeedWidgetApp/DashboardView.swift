import AppKit
import SpeedWidgetCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: NetworkQualityMonitor

    private var gradeColor: Color {
        switch monitor.snapshot.grade {
        case .excellent: .green
        case .good: .mint
        case .fair: .orange
        case .poor: .red
        case .offline: .secondary
        case .measuring: .blue
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            metrics
            Divider()
            capacitySection
            Divider()
            footer
        }
        .frame(width: 330)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(gradeColor.opacity(0.14))
                Circle()
                    .strokeBorder(gradeColor.opacity(0.35), lineWidth: 1)
                Text(monitor.menuBarScore)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text(monitor.snapshot.grade.label)
                    .font(.title3.weight(.semibold))
                Text("Qualité du réseau")
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Circle().fill(gradeColor).frame(width: 7, height: 7)
                    Text(monitor.pathState.interfaceLabel)
                    Text("·")
                    Text("Confiance \(monitor.snapshot.confidence.label.lowercased())")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var metrics: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MetricView(
                    title: "Latence",
                    value: milliseconds(monitor.snapshot.latencyMilliseconds),
                    systemImage: "arrow.left.arrow.right"
                )
                MetricView(
                    title: "Gigue",
                    value: milliseconds(monitor.snapshot.jitterMilliseconds),
                    systemImage: "waveform.path"
                )
            }
            GridRow {
                MetricView(
                    title: "Pertes",
                    value: percent(monitor.snapshot.lossPercent),
                    systemImage: "drop.triangle"
                )
                MetricView(
                    title: "En activité",
                    value: activeLatencyLabel,
                    systemImage: "bolt.horizontal"
                )
            }
        }
        .padding(14)
    }

    private var capacitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Capacité approximative")
                        .font(.subheadline.weight(.medium))
                    Text(monitor.capacity?.tierLabel ?? "Non mesurée")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    monitor.runCapacityTest()
                } label: {
                    if monitor.isRunningCapacityTest {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Micro-test")
                    }
                }
                .disabled(
                    monitor.isRunningCapacityTest
                        || !monitor.pathState.isReachable
                        || monitor.pathState.isExpensive
                        || monitor.pathState.isConstrained
                )
            }

            if let error = monitor.capacityTestError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Maximum 2 Mo, uniquement à la demande.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sondes aujourd’hui")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(usageLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Réglages")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quitter Speed Widget")
        }
        .padding(14)
    }

    private var activeLatencyLabel: String {
        guard let active = monitor.snapshot.activeLatencyMilliseconds else { return "En attente" }
        if let inflation = monitor.snapshot.loadInflation {
            return "\(Int(active.rounded())) ms · ×\(inflation.formatted(.number.precision(.fractionLength(1))))"
        }
        return "\(Int(active.rounded())) ms"
    }

    private var usageLabel: String {
        let consumed = Double(monitor.dailyProbeBytes) / 1_000_000
        return "\(consumed.formatted(.number.precision(.fractionLength(2)))) Mo"
    }

    private func milliseconds(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) ms" } ?? "—"
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength($0 < 1 ? 1 : 0)))) %" } ?? "—"
    }
}

private struct MetricView: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}
