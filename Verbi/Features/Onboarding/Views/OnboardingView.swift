import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingFileImporter = false
    
    var body: some View {
        VStack(spacing: 24) {
            header
            
            if viewModel.showSuccess {
                successView
            } else {
                formView
            }
        }
        .padding(40)
        .frame(maxWidth: 500, maxHeight: 600)
        .shadow(radius: 20)
    }
    
    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.badge.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)
            
            Text("Connect to App Store Connect")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
            
            Text("Add your API key to manage your apps")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var formView: some View {
        VStack(spacing: 20) {
            TextField("Key ID", text: $viewModel.keyID)
                .textFieldStyle(.plain)
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            
            TextField("Issuer ID", text: $viewModel.issuerID)
                .textFieldStyle(.plain)
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            
            ZStack(alignment: .topLeading) {
                if viewModel.privateKey.isEmpty {
                    Text("Private Key")
                        .foregroundStyle(.tertiary)
                        .padding(16)
                }
                TextEditor(text: $viewModel.privateKey)
                    .font(.system(.body, design: .monospaced))
                    .padding(16)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }

            Text("Paste the .p8 key contents, including the header and footer, or import the file directly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showingFileImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                    Text("Import .p8 File")
                        .font(.subheadline)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: 200, minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            
            if let errorMessage = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.top, -8)
            }
            
            Button {
                Task {
                    await viewModel.saveAPIKey()
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("Save API Key")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .frame(maxWidth: 280)
            .padding(16)
            .background(
                viewModel.keyID.isEmpty || viewModel.issuerID.isEmpty || viewModel.privateKey.isEmpty
                    ? Color.gray
                    : Color.blue
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(viewModel.isLoading || viewModel.keyID.isEmpty || viewModel.issuerID.isEmpty || viewModel.privateKey.isEmpty)
            .buttonStyle(.plain)
            
            Link("Learn more about API keys", destination: URL(string: "https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api")!)
                .font(.subheadline)
                .foregroundStyle(.blue)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard didAccess else {
                    viewModel.errorMessage = "Could not access the selected file. Please try again."
                    return
                }
                do {
                    let contents = try String(contentsOf: url, encoding: .utf8)
                    viewModel.privateKey = extractPrivateKeyBody(from: contents)
                    if viewModel.keyID.isEmpty,
                       let inferredKeyID = inferKeyID(from: url.lastPathComponent) {
                        viewModel.keyID = inferredKeyID
                    }
                } catch {
                    viewModel.errorMessage = "Failed to read private key file: \(error.localizedDescription)"
                }
            case .failure(let error):
                viewModel.errorMessage = "Failed to import private key file: \(error.localizedDescription)"
            }
        }
    }

    private func inferKeyID(from fileName: String) -> String? {
        guard fileName.lowercased().hasSuffix(".p8") else { return nil }
        let baseName = String(fileName.dropLast(3))
        let prefix = "AuthKey_"
        guard baseName.hasPrefix(prefix) else { return nil }
        let keyID = String(baseName.dropFirst(prefix.count))
        return keyID.isEmpty ? nil : keyID
    }

    private func extractPrivateKeyBody(from contents: String) -> String {
        let header = "-----BEGIN PRIVATE KEY-----"
        let footer = "-----END PRIVATE KEY-----"
        let stripped = contents
            .replacingOccurrences(of: header, with: "")
            .replacingOccurrences(of: footer, with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    
    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            Text("API Key Saved Successfully!")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("You can now manage your App Store Connect apps.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Continue") {
                dismiss()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }
}

#Preview {
    OnboardingView()
}
