import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text("Verbi Settings")
                    .font(.headline)
                Text("Configure your App Store Connect API settings and preferences here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
