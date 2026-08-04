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
                Text("The score reacts to recent probes: latency over roughly 15 seconds, jitter and loss over roughly 30 seconds. During network activity, the menu bar shows the idle baseline first and the current score under load in parentheses, for example 88 (58).")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
    }
}
