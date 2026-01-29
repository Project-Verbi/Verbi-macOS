import SwiftUI
import Dependencies

struct RootView: View {
    @State private var showOnboarding = false
    @State private var errorMessage: String?
    @Dependency(\.appStoreConnectKey) var appStoreConnectKey
    
    var body: some View {
        Group {
            if let errorMessage = errorMessage {
                errorView(errorMessage)
            } else if showOnboarding {
                OnboardingView()
            } else {
                HomeView(onResetAPIKey: resetAPIKey)
            }
        }
        .task {
            await checkOnboardingState()
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            Text("Error Loading App")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                Task {
                    await checkOnboardingState()
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 200)
        }
        .padding(40)
    }
    
    private func checkOnboardingState() async {
        errorMessage = nil
        
        do {
            let hasKey = try appStoreConnectKey.hasAPIKey()
            showOnboarding = !hasKey
        } catch {
            errorMessage = "Failed to access keychain: \(error.localizedDescription)"
        }
    }

    private func resetAPIKey() {
        do {
            try appStoreConnectKey.deleteAPIKey()
            showOnboarding = true
        } catch {
            errorMessage = "Failed to reset API key: \(error.localizedDescription)"
        }
    }
}

#Preview {
    RootView()
}
