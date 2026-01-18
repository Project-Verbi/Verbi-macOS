import SwiftUI
import Dependencies
import AppStoreConnect_Swift_SDK

struct HomeView: View {
    let onResetAPIKey: () -> Void

    @Dependency(\.appStoreConnect)
    private var appStoreConnect
    
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
        VStack(spacing: 32) {
            header
            
            if isLoading {
                ProgressView("Loading apps...")
                    .frame(maxWidth: .infinity)
            } else if let errorMessage = errorMessage {
                errorView(errorMessage, showResetAction: showResetAction)
            } else if apps.isEmpty {
                featuresGrid
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
        .task {
            await loadApps()
        }
    }
    
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Apps")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(apps.isEmpty ? "Connect your App Store Connect apps." : "\(apps.count) total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: 800)
    }
    
    private var appsList: some View {
        List {
            if !releasedApps.isEmpty {
                Section("Released Apps") {
                    ForEach(releasedApps) { app in
                        AppRow(app: app)
                            .listRowSeparator(.visible)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            if !unreleasedApps.isEmpty {
                Section("Not Yet Released") {
                    ForEach(unreleasedApps) { app in
                        AppRow(app: app)
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
    
    private var featuresGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 20) {
            FeatureCard(
                icon: "chart.bar.fill",
                title: "Analytics",
                description: "View your app analytics"
            )
            
            FeatureCard(
                icon: "star.fill",
                title: "Reviews",
                description: "Manage user reviews"
            )
            
            FeatureCard(
                icon: "square.stack.3d.up.fill",
                title: "Builds",
                description: "Track your builds"
            )
            
            FeatureCard(
                icon: "doc.text.fill",
                title: "Submissions",
                description: "Manage submissions"
            )
        }
        .frame(maxWidth: 700)
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
            apps = try await appStoreConnect.fetchApps()
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

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.blue.gradient)
            
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

#Preview {
    HomeView(onResetAPIKey: {})
}
