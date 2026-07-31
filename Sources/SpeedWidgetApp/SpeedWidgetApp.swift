import AppKit
import SpeedWidgetCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct SpeedWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = NetworkQualityMonitor()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                Text(monitor.menuBarScore)
                    .monospacedDigit()
            }
            .accessibilityLabel("Qualité du réseau, score \(monitor.menuBarScore)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(monitor: monitor)
        }
    }
}
