import Foundation
import Dependencies
import DependenciesMacros

enum KeychainKeys {
    static let appStoreConnectKey = "appstore.connect.key"
}

@DependencyClient
struct AppStoreConnectKeyClient {
    var saveAPIKey: (_ key: AppStoreConnectKey) throws -> Void
    var loadAPIKey: () throws -> AppStoreConnectKey?
    var deleteAPIKey: () throws -> Void
    var hasAPIKey: () throws -> Bool
}

extension AppStoreConnectKeyClient: DependencyKey {
    static let liveValue = AppStoreConnectKeyClient(
        saveAPIKey: { key in
            @Dependency(\.keychain) var keychain
            let encoder = JSONEncoder()
            let data = try encoder.encode(key)
            try keychain.save(KeychainKeys.appStoreConnectKey, data)
        },
        loadAPIKey: {
            @Dependency(\.keychain) var keychain
            guard let data = try keychain.load(KeychainKeys.appStoreConnectKey) else {
                return nil
            }
            let decoder = JSONDecoder()
            return try decoder.decode(AppStoreConnectKey.self, from: data)
        },
        deleteAPIKey: {
            @Dependency(\.keychain) var keychain
            try keychain.delete(KeychainKeys.appStoreConnectKey)
        },
        hasAPIKey: {
            @Dependency(\.keychain) var keychain
            return try keychain.load(KeychainKeys.appStoreConnectKey) != nil
        }
    )
}


extension DependencyValues {
    var appStoreConnectKey: AppStoreConnectKeyClient {
        get { self[AppStoreConnectKeyClient.self] }
        set { self[AppStoreConnectKeyClient.self] = newValue }
    }
}
