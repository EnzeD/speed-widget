import AppKit
import SpeedWidgetCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: NetworkQualityMonitor
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some View {
        Form {
            Section("Measurements") {
                LabeledContent("Frequency", value: "Every 5 seconds")
                LabeledContent("On constrained networks", value: "Every 15 seconds")
                LabeledContent("Usage", value: "Daily counter")
                LabeledContent("Micro-test", value: "Manual · 2 MB maximum")
            }

            Section("Startup") {
                Toggle("Launch Speed Widget at login", isOn: launchAtLoginBinding)

                if launchAtLogin.requiresApproval {
                    HStack {
                        Text("Approval is required in macOS Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") {
                            launchAtLogin.openLoginItemsSettings()
                        }
                    }
                }

                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
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
        .frame(width: 480, height: 460)
        .onAppear {
            launchAtLogin.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }
}
