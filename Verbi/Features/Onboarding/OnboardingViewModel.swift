import SwiftUI
import Dependencies
import Observation
import AppStoreConnect_Swift_SDK

@Observable
final class OnboardingViewModel {
    var keyID: String = ""
    var issuerID: String = ""
    var privateKey: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var showSuccess: Bool = false
    
    
    @ObservationIgnored
    @Dependency(\.appStoreConnectKey)
    private var keyClient
    
    @ObservationIgnored
    @Dependency(\.appStoreConnectAPI)
    private var apiClient
    
    @MainActor
    func saveAPIKey() async {
        isLoading = true
        errorMessage = nil
        
        guard !keyID.isEmpty, !issuerID.isEmpty, !privateKey.isEmpty else {
            errorMessage = "Please fill in all fields"
            isLoading = false
            return
        }

        let normalizedPrivateKey = normalizePrivateKey(privateKey)
        let apiKey = AppStoreConnectKey(
            keyID: normalizeIdentifier(keyID),
            issuerID: normalizeIdentifier(issuerID),
            privateKey: normalizedPrivateKey
        )
        
        do {
            try await apiClient.validateAPIKey(apiKey)
            try keyClient.saveAPIKey(apiKey)
            showSuccess = true
            clearForm()
        } catch let error as JWT.Error {
            switch error {
            case .invalidPrivateKey:
                errorMessage = "Invalid private key. Check the .p8 file contents."
            case .invalidBase64EncodedPrivateKey:
                errorMessage = "Private key contains invalid base64 data. Re-export the .p8 file."
            default:
                errorMessage = "Failed to validate API key: \(error.localizedDescription)"
            }
        } catch let error as APIProvider.Error {
            switch error {
            case .requestFailure(let statusCode, _, _):
                errorMessage = formatRequestFailure(statusCode: statusCode, error: error)
            default:
                errorMessage = "Failed to validate API key: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = "Failed to validate API key: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func clearForm() {
        keyID = ""
        issuerID = ""
        privateKey = ""
    }

    private func normalizePrivateKey(_ value: String) -> String {
        let header = "-----BEGIN PRIVATE KEY-----"
        let footer = "-----END PRIVATE KEY-----"
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed
            .replacingOccurrences(of: header, with: "")
            .replacingOccurrences(of: footer, with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        return body.isEmpty ? trimmed : body
    }

    private func normalizeIdentifier(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private func formatRequestFailure(statusCode: Int, error: APIProvider.Error) -> String {
        guard case .requestFailure(_, let errorResponse, _) = error else {
            return "Failed to validate API key: \(error.localizedDescription)"
        }
        if let responseError = errorResponse?.errors?.first {
            let detail = responseError.detail.map { " \($0)" } ?? ""
            return "Request failed (\(statusCode)): \(responseError.title).\(detail)"
        }
        return "Request failed (\(statusCode))."
    }
}
