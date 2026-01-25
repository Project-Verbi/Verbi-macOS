import Foundation
import Dependencies
import DependenciesMacros
import AppStoreConnect_Swift_SDK

enum KeychainKeys {
    static let appStoreConnectKey = "appstore.connect.key"
}

@DependencyClient
struct AppStoreConnectClient {
    var saveAPIKey: (_ key: AppStoreConnectKey) throws -> Void
    var loadAPIKey: () throws -> AppStoreConnectKey?
    var deleteAPIKey: () throws -> Void
    var hasAPIKey: () throws -> Bool
    var validateAPIKey: @Sendable @MainActor (_ key: AppStoreConnectKey) async throws -> Void
    var fetchApps: @Sendable () async throws -> [AppStoreApp]
    var fetchChangelogs: @Sendable @MainActor (_ appID: String) async throws -> [AppChangelog]
}

extension AppStoreConnectClient: DependencyKey {
    static let liveValue = AppStoreConnectClient(
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
        },
        validateAPIKey: { apiKey in
            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )
            

            let provider = APIProvider(configuration: configuration)

            let request = APIEndpoint
                .v1
                .apps
                .get(parameters: .init(
                    sort: [.name],
                    fieldsApps: [.appInfos, .name, .bundleID],
                ))

            _ = try await provider.request(request)
        },
        fetchApps: {
            @Dependency(\.appStoreConnect) var appStoreConnect
            
            guard let apiKey = try appStoreConnect.loadAPIKey() else {
                throw AppStoreConnectError.noAPIKey
            }

            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )
            
            let provider = APIProvider(configuration: configuration)
            
            let request = APIEndpoint
                .v1
                .apps
                .get(parameters: .init(
                    sort: [.name],
                    fieldsApps: [.name, .bundleID, .sku, .primaryLocale, .appStoreIcon],
                    include: [.appStoreIcon]
                ))
            
            let response = try await provider.request(request)
            let apps = response.data
            let included = response.included ?? []
            let buildIcons = Dictionary(uniqueKeysWithValues: included.compactMap { item -> (String, BuildIcon)? in
                guard case let .buildIcon(icon) = item else { return nil }
                return (icon.id, icon)
            })
            let versionInfoByAppID = try await fetchLatestVersions(for: apps, provider: provider)

            return apps.compactMap { app -> AppStoreApp? in
                guard
                    let attributes = app.attributes,
                    let name = attributes.name,
                    let bundleId = attributes.bundleID,
                    let primaryLocale = attributes.primaryLocale,
                    let sku = attributes.sku
                else { return nil }

                let versionInfo = versionInfoByAppID[app.id]
                let iconURL = currentIconURL(for: app, from: buildIcons)

                return AppStoreApp(
                    id: app.id,
                    name: name,
                    bundleId: bundleId,
                    platform: primaryLocale,
                    sku: sku,
                    version: versionInfo?.version,
                    versionState: versionInfo?.state,
                    hasReleased: versionInfo?.hasReleased ?? false,
                    iconURL: iconURL
                )
            }
        },
        fetchChangelogs: { appID in
            @Dependency(\.appStoreConnect) var appStoreConnect

            guard let apiKey = try appStoreConnect.loadAPIKey() else {
                throw AppStoreConnectError.noAPIKey
            }

            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )

            let provider = APIProvider(configuration: configuration)
            guard let versionID = try await fetchLatestVersionID(for: appID, provider: provider) else {
                return []
            }
            return try await fetchVersionLocalizations(for: versionID, provider: provider)
        }
    )
}

extension DependencyValues {
    var appStoreConnect: AppStoreConnectClient {
        get { self[AppStoreConnectClient.self] }
        set { self[AppStoreConnectClient.self] = newValue }
    }
}

enum AppStoreConnectError: Error {
    case noAPIKey
}

private func makeConfiguration(issuerID: String, keyID: String, privateKey: String) throws -> APIConfiguration {
    let base64Body = extractBase64Body(from: privateKey)
    return try APIConfiguration(issuerID: issuerID, privateKeyID: keyID, privateKey: base64Body, expirationDuration: 60 * 5)
}

private func extractBase64Body(from value: String) -> String {
    var key = value
    if key.hasPrefix("\u{FEFF}") {
        key.removeFirst()
    }
    key = key.replacingOccurrences(of: "\r\n", with: "\n")
    key = key.trimmingCharacters(in: .whitespacesAndNewlines)

    let header = "-----BEGIN PRIVATE KEY-----"
    let footer = "-----END PRIVATE KEY-----"
    let body = key
        .replacingOccurrences(of: header, with: "")
        .replacingOccurrences(of: footer, with: "")
        .components(separatedBy: .whitespacesAndNewlines)
        .joined()

    return body.isEmpty ? key : body
}

private struct AppStoreVersionInfo {
    let version: String?
    let state: String?
    let hasReleased: Bool
}

private func fetchLatestVersions(for apps: [App], provider: APIProvider) async throws -> [String: AppStoreVersionInfo] {
    guard !apps.isEmpty else { return [:] }
    var results: [String: AppStoreVersionInfo] = [:]
    for app in apps {
        let versions = try await fetchAppStoreVersions(for: app.id, provider: provider)
        let hasReleased = try await fetchHasReleasedVersion(for: app.id, provider: provider)
        let versionInfo = currentVersionInfo(from: versions, hasReleased: hasReleased)
        results[app.id] = versionInfo
    }
    return results
}

private func fetchAppStoreVersions(for appID: String, provider: APIProvider) async throws -> [AppStoreVersion] {
    let request = APIEndpoint
        .v1
        .apps
        .id(appID)
        .appStoreVersions
        .get(parameters: .init(
            fieldsAppStoreVersions: [.versionString, .appStoreState, .createdDate],
            limit: 5
        ))
    let response = try await provider.request(request)
    return response.data
}

private func fetchHasReleasedVersion(for appID: String, provider: APIProvider) async throws -> Bool {
    let request = APIEndpoint
        .v1
        .apps
        .id(appID)
        .appStoreVersions
        .get(parameters: .init(
            filterAppStoreState: [.readyForSale],
            fieldsAppStoreVersions: [.appStoreState],
            limit: 1
        ))
    let response = try await provider.request(request)
    return !response.data.isEmpty
}

private func currentVersionInfo(from versions: [AppStoreVersion], hasReleased: Bool) -> AppStoreVersionInfo {
    guard !versions.isEmpty else {
        return AppStoreVersionInfo(version: nil, state: nil, hasReleased: hasReleased)
    }
    let sorted = versions.sorted {
        let lhsDate = $0.attributes?.createdDate ?? .distantPast
        let rhsDate = $1.attributes?.createdDate ?? .distantPast
        return lhsDate > rhsDate
    }
    let chosen = sorted.first
    return AppStoreVersionInfo(
        version: chosen?.attributes?.versionString,
        state: chosen?.attributes?.appStoreState?.rawValue,
        hasReleased: hasReleased
    )
}

private func currentIconURL(for app: App, from buildIcons: [String: BuildIcon]) -> URL? {
    guard let iconID = app.relationships?.appStoreIcon?.data?.id,
          let icon = buildIcons[iconID],
          let templateURL = icon.attributes?.iconAsset?.templateURL
    else {
        return nil
    }
    let size = 128
    let urlString = templateURL
        .replacingOccurrences(of: "{w}", with: "\(size)")
        .replacingOccurrences(of: "{h}", with: "\(size)")
        .replacingOccurrences(of: "{f}", with: "png")
    return URL(string: urlString)
}

private func fetchLatestVersionID(for appID: String, provider: APIProvider) async throws -> String? {
    let versions = try await fetchAppStoreVersions(for: appID, provider: provider)
    guard !versions.isEmpty else { return nil }
    let sorted = versions.sorted {
        let lhsDate = $0.attributes?.createdDate ?? .distantPast
        let rhsDate = $1.attributes?.createdDate ?? .distantPast
        return lhsDate > rhsDate
    }
    return sorted.first?.id
}

private func fetchVersionLocalizations(for versionID: String, provider: APIProvider) async throws -> [AppChangelog] {
    let request = APIEndpoint
        .v1
        .appStoreVersions
        .id(versionID)
        .appStoreVersionLocalizations
        .get(parameters: .init(
            fieldsAppStoreVersionLocalizations: [.locale, .whatsNew],
            limit: 200
        ))
    let response = try await provider.request(request)
    return response.data.compactMap { localization in
        guard let attributes = localization.attributes,
              let locale = attributes.locale
        else { return nil }
        return AppChangelog(id: locale, locale: locale, text: attributes.whatsNew ?? "")
    }
}

struct AppsResponse: Codable {
    let data: [AppData]
    
    struct AppData: Codable {
        let id: String
        let attributes: AppAttributes
    }
    
    struct AppAttributes: Codable {
        let name: String
        let bundleID: String
        let primaryLocale: String
        let sku: String
    }
}
