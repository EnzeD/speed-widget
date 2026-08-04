import SpeedWidgetCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: NetworkQualityMonitor

    var body: some View {
        Form {
            Section("Measurements") {
                LabeledContent("Frequency", value: "Every 5 seconds")
                LabeledContent("On constrained networks", value: "Every 15 seconds")
                LabeledContent("Usage", value: "Daily counter")
                LabeledContent("Micro-test", value: "Manual · 2 MB maximum")
            }

            Section("Privacy") {
                Text("Probes use the Cloudflare edge. Speed Widget does not collect or send analytics. Results stay on this Mac.")
                    .foregroundStyle(.secondary)
            }

            Section("Method") {
                Text("The score reacts to recent probes: latency over roughly 15 seconds, jitter and loss over roughly 30 seconds. During network activity, a separate score uses only probes observed under load. It appears in parentheses after three loaded probes and only for a meaningful drop of at least five points, for example 88 (58).")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
    }
}
