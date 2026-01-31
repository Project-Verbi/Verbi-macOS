import Foundation
import Dependencies
import DependenciesMacros
import AppStoreConnect_Swift_SDK

@DependencyClient
struct AppStoreConnectAPIClient {
    var validateAPIKey: @Sendable @MainActor (_ key: AppStoreConnectKey) async throws -> Void
    var fetchApps: @Sendable () async throws -> [AppStoreApp]
    var fetchAppVersions: @Sendable @MainActor (_ appID: String) async throws -> [AppStoreVersionSummary]
    var fetchChangelogs: @Sendable @MainActor (_ versionID: String) async throws -> [AppChangelog]
    var updateChangelog: @Sendable @MainActor (_ localizationID: String, _ text: String) async throws -> Void
    var createAppVersion: @Sendable @MainActor (_ appID: String, _ versionString: String, _ platformRaw: String?) async throws -> AppStoreVersionSummary
    var releaseVersion: @Sendable @MainActor (_ versionID: String) async throws -> Void
    var fetchSelectedBuild: @Sendable @MainActor (_ versionID: String) async throws -> AppStoreBuild?
    var updateBuildSelection: @Sendable @MainActor (_ versionID: String, _ buildID: String) async throws -> Void
    var fetchBuilds: @Sendable @MainActor (_ appID: String, _ versionString: String) async throws -> [AppStoreBuild]
}

extension AppStoreConnectAPIClient: DependencyKey {
    static let testValue = AppStoreConnectAPIClient()
    static let liveValue = AppStoreConnectAPIClient(
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
            @Dependency(\.appStoreConnectKey) var keyClient

            guard let apiKey = try keyClient.loadAPIKey() else {
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
        fetchAppVersions: { appID in
            @Dependency(\.appStoreConnectKey) var keyClient

            guard let apiKey = try keyClient.loadAPIKey() else {
                throw AppStoreConnectError.noAPIKey
            }

            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )

            let provider = APIProvider(configuration: configuration)
            let versions = try await fetchAppStoreVersions(for: appID, provider: provider)
            return selectVersionSummaries(from: versions)
        },
        fetchChangelogs: { versionID in
            @Dependency(\.appStoreConnectKey) var keyClient

            guard let apiKey = try keyClient.loadAPIKey() else {
                throw AppStoreConnectError.noAPIKey
            }

            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )

            let provider = APIProvider(configuration: configuration)
            return try await fetchVersionLocalizations(for: versionID, provider: provider)
        },
        updateChangelog: { localizationID, text in
            @Dependency(\.appStoreConnectKey) var keyClient

            guard let apiKey = try keyClient.loadAPIKey() else {
                throw AppStoreConnectError.noAPIKey
            }

            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )

            let provider = APIProvider(configuration: configuration)
            let requestBody = AppStoreVersionLocalizationUpdateRequest(
                data: .init(
                    type: .appStoreVersionLocalizations,
                    id: localizationID,
                    attributes: .init(whatsNew: text)
                )
            )
            let request = APIEndpoint
                .v1
                .appStoreVersionLocalizations
                .id(localizationID)
                .patch(requestBody)
            _ = try await provider.request(request)
        },
        createAppVersion: { appID, versionString, platformRaw in
            @Dependency(\.appStoreConnectKey) var keyClient

            guard let apiKey = try keyClient.loadAPIKey() else {
                throw AppStoreConnectError.noAPIKey
            }

            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )

            let provider = APIProvider(configuration: configuration)
            guard let platformRaw,
                  let platform = Platform(rawValue: platformRaw)
            else {
                throw AppStoreConnectError.unsupportedPlatform
            }

            let requestBody = AppStoreVersionCreateRequest(
                data: .init(
                    type: .appStoreVersions,
                    attributes: .init(
                        platform: platform,
                        versionString: versionString
                    ),
                    relationships: .init(
                        app: .init(
                            data: .init(
                                type: .apps,
                                id: appID
                            )
                        )
                    )
                )
            )
            let request = APIEndpoint.v1.appStoreVersions.post(requestBody)
            let response = try await provider.request(request)
            guard let summary = makeVersionSummary(from: response.data, kind: .upcoming) else {
                throw AppStoreConnectError.unexpectedResponse
            }
            return summary
        },
        releaseVersion: { versionID in
            @Dependency(\.appStoreConnectKey) var keyClient

            guard let apiKey = try keyClient.loadAPIKey() else {
                throw AppStoreConnectError.noAPIKey
            }

            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )

            let provider = APIProvider(configuration: configuration)
            let requestBody = AppStoreVersionReleaseRequestCreateRequest(
                data: .init(
                    type: .appStoreVersionReleaseRequests,
                    relationships: .init(
                        appStoreVersion: .init(
                            data: .init(
                                type: .appStoreVersions,
                                id: versionID
                            )
                        )
                    )
                )
            )
            let request = APIEndpoint.v1.appStoreVersionReleaseRequests.post(requestBody)
            _ = try await provider.request(request)
        },
        fetchSelectedBuild: { versionID in
            @Dependency(\.appStoreConnectKey) var keyClient

            guard let apiKey = try keyClient.loadAPIKey() else {
                throw AppStoreConnectError.noAPIKey
            }

            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )

            let provider = APIProvider(configuration: configuration)
            return try await fetchSelectedBuildForVersion(versionID: versionID, provider: provider)
        },
        updateBuildSelection: { versionID, buildID in
            @Dependency(\.appStoreConnectKey) var keyClient

            guard let apiKey = try keyClient.loadAPIKey() else {
                throw AppStoreConnectError.noAPIKey
            }

            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )

            let provider = APIProvider(configuration: configuration)
            try await Verbi.updateBuildSelection(versionID: versionID, buildID: buildID, provider: provider)
        },
        fetchBuilds: { appID, versionString in
            @Dependency(\.appStoreConnectKey) var keyClient

            guard let apiKey = try keyClient.loadAPIKey() else {
                throw AppStoreConnectError.noAPIKey
            }

            let configuration = try makeConfiguration(
                issuerID: apiKey.issuerID,
                keyID: apiKey.keyID,
                privateKey: apiKey.privateKey
            )

            let provider = APIProvider(configuration: configuration)
            return try await fetchAllBuildsForVersion(appID: appID, versionString: versionString, provider: provider)
        }
    )
}

extension DependencyValues {
    var appStoreConnectAPI: AppStoreConnectAPIClient {
        get { self[AppStoreConnectAPIClient.self] }
        set { self[AppStoreConnectAPIClient.self] = newValue }
    }
}

enum AppStoreConnectError: Error {
    case noAPIKey
    case unsupportedPlatform
    case unexpectedResponse
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
            fieldsAppStoreVersions: [.versionString, .appStoreState, .createdDate, .platform],
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
    guard let chosen = latestVersion(from: versions) else {
        return AppStoreVersionInfo(version: nil, state: nil, hasReleased: hasReleased)
    }
    return AppStoreVersionInfo(
        version: chosen.attributes?.versionString,
        state: chosen.attributes?.appStoreState?.rawValue,
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

private func latestVersion(from versions: [AppStoreVersion]) -> AppStoreVersion? {
    versions.max { lhs, rhs in
        let lhsDate = lhs.attributes?.createdDate ?? .distantPast
        let rhsDate = rhs.attributes?.createdDate ?? .distantPast
        return lhsDate < rhsDate
    }
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
        return AppChangelog(id: localization.id, locale: locale, text: attributes.whatsNew ?? "")
    }
}

private func selectVersionSummaries(from versions: [AppStoreVersion]) -> [AppStoreVersionSummary] {
    guard !versions.isEmpty else { return [] }
    let finalStates: Set<AppStoreVersionState> = [.readyForSale, .pendingDeveloperRelease]
    let released = latestVersion(from: versions.filter { version in
        guard let state = version.attributes?.appStoreState else { return false }
        return finalStates.contains(state)
    })
    let upcoming = latestVersion(from: versions.filter { version in
        guard let state = version.attributes?.appStoreState else { return true }
        return !finalStates.contains(state)
    })

    var summaries: [AppStoreVersionSummary] = []
    if let upcoming, let summary = makeVersionSummary(from: upcoming, kind: .upcoming) {
        summaries.append(summary)
    }
    if let released, released.id != upcoming?.id,
       let summary = makeVersionSummary(from: released, kind: .current) {
        summaries.append(summary)
    }
    if summaries.isEmpty, let summary = makeVersionSummary(from: versions.sorted { $0.attributes?.createdDate ?? .distantPast > $1.attributes?.createdDate ?? .distantPast }.first, kind: .current) {
        summaries.append(summary)
    }
    return summaries
}

private func makeVersionSummary(from version: AppStoreVersion?, kind: AppStoreVersionSummary.Kind) -> AppStoreVersionSummary? {
    guard let version, let attributes = version.attributes, let versionString = attributes.versionString else {
        return nil
    }
    let state = attributes.appStoreState?.rawValue
    let normalizedState = state?.uppercased()
    let isEditable = normalizedState != "READY_FOR_SALE" && normalizedState != "PENDING_DEVELOPER_RELEASE"
    return AppStoreVersionSummary(
        id: version.id,
        version: versionString,
        state: state,
        platform: attributes.platform?.rawValue,
        kind: kind,
        isEditable: isEditable
    )
}

private func fetchSelectedBuildForVersion(versionID: String, provider: APIProvider) async throws -> AppStoreBuild? {
    let buildRequest = APIEndpoint
        .v1
        .appStoreVersions
        .id(versionID)
        .build
        .get()

    let buildResponse = try await provider.request(buildRequest)
    let build = buildResponse.data
    guard let attributes = build.attributes,
          let buildVersion = attributes.version else {
        return nil
    }

    let processingState = attributes.processingState?.rawValue
    let isSelectable = processingState == "VALID" || processingState == nil
    return AppStoreBuild(
        id: build.id,
        version: buildVersion,
        uploadedDate: attributes.uploadedDate,
        processingState: processingState,
        isSelectable: isSelectable
    )
}

private func updateBuildSelection(versionID: String, buildID: String, provider: APIProvider) async throws {
    let requestBody = AppStoreVersionUpdateRequest(
        data: .init(
            type: .appStoreVersions,
            id: versionID,
            relationships: .init(
                build: .init(
                    data: .init(
                        type: .builds,
                        id: buildID
                    )
                )
            )
        )
    )
    let request = APIEndpoint
        .v1
        .appStoreVersions
        .id(versionID)
        .patch(requestBody)
    _ = try await provider.request(request)
}

private func fetchAllBuildsForVersion(appID: String, versionString: String, provider: APIProvider) async throws -> [AppStoreBuild] {
    // Now fetch builds filtered by this preReleaseVersion
    let buildsRequest = APIEndpoint
        .v1
        .builds
        .get(parameters: .init(
            filterPreReleaseVersionVersion: [versionString],
            filterApp: [appID],
            limit: 200
        ))
    
    let buildsResponse = try await provider.request(buildsRequest)
    return buildsResponse.data.compactMap { build -> AppStoreBuild? in
        guard let attributes = build.attributes,
              let buildNumber = attributes.version
        else { return nil }
        
        let processingState = attributes.processingState?.rawValue
        let isSelectable = processingState == "VALID" || processingState == nil
        return AppStoreBuild(
            id: build.id,
            version: buildNumber,
            uploadedDate: attributes.uploadedDate,
            processingState: processingState,
            isSelectable: isSelectable
        )
    }.sorted { lhs, rhs in
        guard let lhsDate = lhs.uploadedDate, let rhsDate = rhs.uploadedDate else {
            return lhs.version > rhs.version
        }
        return lhsDate > rhsDate
    }
}
