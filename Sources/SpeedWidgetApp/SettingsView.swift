import SpeedWidgetCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: NetworkQualityMonitor

    var body: some View {
        Form {
            Section("Mesures") {
                LabeledContent("Fréquence", value: "Toutes les 5 secondes")
                LabeledContent("Sur réseau limité", value: "Toutes les 15 secondes")
                LabeledContent("Consommation", value: "Compteur journalier")
                LabeledContent("Micro-test", value: "Manuel · 2 Mo maximum")
            }

            Section("Confidentialité") {
                Text("Les sondes utilisent l’edge Cloudflare. Speed Widget ne collecte et ne transmet aucune analytique. Les résultats restent sur ce Mac.")
                    .foregroundStyle(.secondary)
            }

            Section("Méthode") {
                Text("Le score réagit aux dernières sondes : latence sur environ 15 secondes, gigue et pertes sur environ 30 secondes. L’activité naturelle du réseau permet aussi d’estimer l’inflation de latence.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
    }
}
