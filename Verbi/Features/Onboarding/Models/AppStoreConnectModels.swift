import Foundation

struct AppStoreConnectKey: Codable, Sendable {
    var keyID: String
    var issuerID: String
    var privateKey: String
    
    var encodedPrivateKey: Data? {
        privateKey.data(using: .utf8)
    }
    
    var isValid: Bool {
        !keyID.isEmpty && !issuerID.isEmpty && !privateKey.isEmpty
    }
}

struct AppStoreApp: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let bundleId: String
    let platform: String
    let sku: String
    let version: String?
    let versionState: String?
    let hasReleased: Bool
    let iconURL: URL?
}

struct AppChangelog: Identifiable, Hashable {
    let id: String
    let locale: String
    var text: String
}
