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

    static var stub: AppStoreApp {
        AppStoreApp(
            id: "stub-app-id",
            name: "Stub App",
            bundleId: "com.example.stub",
            platform: "IOS",
            sku: "stub-sku",
            version: "1.0.0",
            versionState: "PREPARE_FOR_SUBMISSION",
            hasReleased: false,
            iconURL: nil
        )
    }
}

struct AppStoreVersionSummary: Identifiable, Hashable {
    enum Kind: String {
        case current = "Current"
        case upcoming = "Upcoming"
    }

    let id: String
    let version: String
    let state: String?
    let platform: String?
    let kind: Kind
    let isEditable: Bool
}

struct AppChangelog: Identifiable, Hashable {
    let id: String
    let locale: String
    var text: String
}
