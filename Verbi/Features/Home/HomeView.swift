import SwiftUI
import Dependencies
import AppStoreConnect_Swift_SDK

struct HomeView: View {
    let onResetAPIKey: () -> Void

    @Dependency(\.appStoreConnectAPI)
    private var apiClient

    @Environment(\.openWindow)
    private var openWindow
    
    @State private var apps: [AppStoreApp] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showResetAction = false

    private var releasedApps: [AppStoreApp] {
        apps.filter { $0.hasReleased }
    }

    private var unreleasedApps: [AppStoreApp] {
        apps.filter { !$0.hasReleased }
    }

    private func isLive(_ app: AppStoreApp) -> Bool {
        app.versionState?.uppercased() == "READY_FOR_SALE"
    }
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .task {
            await loadApps()
        }
    }
    
    private var sidebar: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    sidebarHeader
                }
            }
            .listStyle(.sidebar)

            Spacer()

            settingsButton
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .navigationTitle("Apps")
        .frame(minWidth: 220)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Verbi")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Select an app to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(.vertical, 8)
    }

    private var settingsButton: some View {
        SettingsLink {
            Label("Settings", systemImage: "gearshape.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailContent: some View {
        VStack(spacing: 32) {
            if isLoading {
                ProgressView("Loading apps...")
                    .frame(maxWidth: .infinity)
            } else if let errorMessage = errorMessage {
                errorView(errorMessage, showResetAction: showResetAction)
            } else {
                appsList
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    private var appsList: some View {
        List {
            if !releasedApps.isEmpty {
                Section("Released Apps") {
                    ForEach(releasedApps) { app in
                        Button {
                            openWindow(value: app)
                        } label: {
                            AppRow(app: app)
                        }
                        .buttonStyle(.plain)
                            .listRowSeparator(.visible)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            if !unreleasedApps.isEmpty {
                Section("Not Yet Released") {
                    ForEach(unreleasedApps) { app in
                        Button {
                            openWindow(value: app)
                        } label: {
                            AppRow(app: app)
                        }
                        .buttonStyle(.plain)
                            .listRowSeparator(.visible)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: 800)
        .scrollContentBackground(.hidden)
    }
    
    private func errorView(_ message: String, showResetAction: Bool) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if showResetAction {
                Button("Update API Key") {
                    onResetAPIKey()
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 220)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func loadApps() async {
        isLoading = true
        errorMessage = nil
        
        do {
            apps = try await apiClient.fetchApps()
            showResetAction = false
        } catch let error as JWT.Error {
            switch error {
            case .invalidPrivateKey:
                showResetAction = true
                errorMessage = "Invalid private key. Update your API key to continue."
            case .invalidBase64EncodedPrivateKey:
                showResetAction = true
                errorMessage = "Private key contains invalid base64 data. Update your API key to continue."
            default:
                showResetAction = false
                errorMessage = "Failed to load apps: \(error)"
            }
        } catch let error as APIProvider.Error {
            switch error {
            case .requestFailure(let statusCode, _, _):
                if statusCode == 401 || statusCode == 403 {
                    showResetAction = true
                } else {
                    showResetAction = false
                }
                errorMessage = formatRequestFailure(statusCode: statusCode, error: error)
            default:
                showResetAction = false
                errorMessage = "Failed to load apps: \(error)"
            }
        } catch {
            showResetAction = false
            errorMessage = "Failed to load apps: \(error)"
        }
        
        isLoading = false
    }

    private func formatRequestFailure(statusCode: Int, error: APIProvider.Error) -> String {
        guard case .requestFailure(_, let errorResponse, _) = error else {
            return "Request failed (\(statusCode))."
        }
        if let responseError = errorResponse?.errors?.first {
            let detail = responseError.detail.map { " \($0)" } ?? ""
            return "Request failed (\(statusCode)): \(responseError.title).\(detail)"
        }
        return "Request failed (\(statusCode))."
    }

}

struct AppRow: View {
    let app: AppStoreApp
    
    var body: some View {
        HStack(spacing: 12) {
            AppIconView(url: app.iconURL)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    StatusIndicator(state: app.versionState)
                }

                Text(app.bundleId)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Version \(app.version ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }
}

private struct StatusIndicator: View {
    let state: String?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
            )
    }

    private var color: Color {
        guard let state else { return Color(nsColor: .systemGray) }
        if state.uppercased() == "READY_FOR_SALE" {
            return Color(nsColor: .systemGreen)
        }
        return Color(nsColor: .systemOrange)
    }
}

private struct AppIconView: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure, .empty:
                PlaceholderIcon()
            @unknown default:
                PlaceholderIcon()
            }
        }
        .frame(width: 52, height: 52)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct PlaceholderIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .systemBlue).opacity(0.9),
                            Color(nsColor: .systemTeal).opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(6)
    }
}

#Preview {
    HomeView(onResetAPIKey: {})
}
