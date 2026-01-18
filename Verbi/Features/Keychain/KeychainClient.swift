import Foundation
import Security
import Dependencies
import DependenciesMacros

@DependencyClient
struct KeychainClient {
    var save: (_ key: String, _ data: Data) throws -> Void
    var load: (_ key: String) throws -> Data?
    var delete: (_ key: String) throws -> Void
}

extension KeychainClient: DependencyKey {
    static let liveValue = KeychainClient(
        save: { key, data in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecValueData as String: data
            ]
            
            let status = SecItemAdd(query as CFDictionary, nil)
            
            if status == errSecDuplicateItem {
                let updateQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: key
                ]
                
                let updateAttributes: [String: Any] = [
                    kSecValueData as String: data
                ]
                
                let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
                
                guard updateStatus == errSecSuccess else {
                    throw KeychainError.unableToUpdate
                }
            } else {
                guard status == errSecSuccess else {
                    throw KeychainError.unableToSave
                }
            }
        },
        load: { key in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            
            guard status == errSecSuccess, let data = result as? Data else {
                if status == errSecItemNotFound {
                    return nil
                }
                throw KeychainError.unableToLoad
            }
            
            return data
        },
        delete: { key in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key
            ]
            
            let status = SecItemDelete(query as CFDictionary)
            
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unableToDelete
            }
        }
    )
}

extension DependencyValues {
    var keychain: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}

enum KeychainError: Error {
    case unableToSave
    case unableToUpdate
    case unableToLoad
    case unableToDelete
}

extension KeychainError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unableToSave:
            return "Unable to save item to keychain"
        case .unableToUpdate:
            return "Unable to update item in keychain"
        case .unableToLoad:
            return "Unable to load item from keychain"
        case .unableToDelete:
            return "Unable to delete item from keychain"
        }
    }
}
