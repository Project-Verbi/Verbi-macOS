import SwiftUI
import Dependencies
import Observation
import AppStoreConnect_Swift_SDK

@MainActor
@Observable
final class AppDetailViewModel {
    let app: AppStoreApp

    @ObservationIgnored
    @Dependency(\.appStoreConnectAPI)
    private var apiClient
    
    @ObservationIgnored
    @Dependency(\.locale)
    private var locale

    var versions: [AppStoreVersionSummary] = []
    var selectedVersionID: String?
    var changelogByLocale: [String: String] = [:]
    var changelogIDByLocale: [String: String] = [:]
    var dirtyLocales: Set<String> = []
    var locales: [String] = []
    var selectedLocale: String?
    var showLanguagePicker = false
    var isLoadingVersions = false
    var isLoadingChangelogs = false
    var isSaving = false
    var errorMessage: String?
    var showNewVersionSheet = false
    var newVersionString = ""
    var actionMessage: String?

    private var draftsByVersion: [String: VersionDraft] = [:]

    init(app: AppStoreApp) {
        self.app = app
    }

    var selectedVersion: AppStoreVersionSummary? {
        versions.first { $0.id == selectedVersionID }
    }

    var canEditChangelog: Bool {
        selectedVersion?.isEditable ?? false
    }

    var changelogFooterText: String {
        guard let state = selectedVersion?.state?.uppercased() else {
            return "Changelog editing is unavailable for released versions."
        }
        if state == "PENDING_DEVELOPER_RELEASE" {
            return "Changelog editing is unavailable while the app is pending developer release."
        }
        return "Changelog editing is unavailable for released versions."
    }

    var canCreateVersion: Bool {
        let normalizedState = selectedVersion?.state?.uppercased()
        return normalizedState != "PENDING_DEVELOPER_RELEASE"
    }

    var canSaveChangelog: Bool {
        guard let locale = selectedLocale,
              dirtyLocales.contains(locale),
              let localizationID = changelogIDByLocale[locale],
              !localizationID.isEmpty,
              canEditChangelog
        else { return false }
        return !isSaving
    }

    var platformRawForNewVersion: String? {
        guard canCreateVersion else { return nil }
        return selectedVersion?.platform ?? versions.first?.platform ?? app.platform
    }

    var selectedChangelogText: String {
        guard let key = selectedLocale, !key.isEmpty else { return "" }
        return changelogByLocale[key] ?? ""
    }

    /// Returns the version that comes immediately before the currently selected version.
    var previousVersion: AppStoreVersionSummary? {
        guard let selectedVersionID = selectedVersionID,
              let selectedIndex = versions.firstIndex(where: { $0.id == selectedVersionID }),
              selectedIndex < versions.count - 1 else {
            return nil
        }
        return versions[selectedIndex + 1]
    }

    /// Checks if the previous version exists and has changelogs that could be copied.
    var canCopyChangelogFromPreviousVersion: Bool {
        guard previousVersion != nil else { return false }
        return !locales.isEmpty && canEditChangelog
    }

    func setSelectedVersionID(_ newValue: String?) {
        if let currentID = selectedVersionID, currentID != newValue, !dirtyLocales.isEmpty {
            draftsByVersion[currentID] = VersionDraft(
                changelogByLocale: changelogByLocale,
                changelogIDByLocale: changelogIDByLocale,
                locales: locales,
                selectedLocale: selectedLocale,
                dirtyLocales: dirtyLocales
            )
        }
        selectedVersionID = newValue
    }

    func updateSelectedChangelogText(_ newValue: String) {
        guard let key = selectedLocale, !key.isEmpty else { return }
        changelogByLocale[key] = newValue
        dirtyLocales.insert(key)
        actionMessage = nil
    }

    func loadVersions() async {
        isLoadingVersions = true
        errorMessage = nil
        actionMessage = nil

        do {
            let fetched = try await apiClient.fetchAppVersions(app.id)
            versions = fetched
            if let selected = selectedVersionID, fetched.contains(where: { $0.id == selected }) {
                selectedVersionID = selected
            } else {
                selectedVersionID = fetched.first?.id
            }
        } catch {
            errorMessage = "Failed to load versions: \(error.localizedDescription)"
        }

        isLoadingVersions = false
    }

    func loadChangelogs() async {
        guard let versionID = selectedVersionID else {
            changelogByLocale = [:]
            changelogIDByLocale = [:]
            locales = []
            selectedLocale = nil
            return
        }

        if let draft = draftsByVersion[versionID] {
            changelogByLocale = draft.changelogByLocale
            changelogIDByLocale = draft.changelogIDByLocale
            locales = draft.locales
            selectedLocale = draft.selectedLocale ?? locales.first
            dirtyLocales = draft.dirtyLocales
            errorMessage = nil
            actionMessage = "Loaded unsaved draft."
            isLoadingChangelogs = false
            return
        }

        isLoadingChangelogs = true
        errorMessage = nil
        actionMessage = nil

        do {
            let changelogs = try await apiClient.fetchChangelogs(versionID)
            changelogByLocale = Dictionary(
                changelogs.map { ($0.locale, $0.text) },
                uniquingKeysWith: { first, _ in first }
            )
            changelogIDByLocale = Dictionary(
                changelogs.map { ($0.locale, $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
            locales = changelogs
                .map(\.locale)
                .reduce(into: [String]()) { result, locale in
                    if !result.contains(locale) {
                        result.append(locale)
                    }
                }
                .sorted { displayName(for: $0) < displayName(for: $1) }
            if locales.isEmpty {
                selectedLocale = nil
            }
            if selectedLocale == nil || (selectedLocale != nil && !locales.contains(selectedLocale ?? "")) {
                selectedLocale = locales.first
            }
            dirtyLocales.removeAll()
        } catch {
            errorMessage = "Failed to load changelogs: \(error.localizedDescription)"
        }

        isLoadingChangelogs = false
    }

    func saveCurrentChangelog() async {
        guard let locale = selectedLocale,
              let localizationID = changelogIDByLocale[locale],
              let text = changelogByLocale[locale]
        else { return }

        isSaving = true
        errorMessage = nil
        actionMessage = nil

        do {
            try await apiClient.updateChangelog(localizationID, text)
            dirtyLocales.remove(locale)
            if dirtyLocales.isEmpty, let versionID = selectedVersionID {
                draftsByVersion[versionID] = nil
            }
            actionMessage = "Changelog updated."
        } catch {
            errorMessage = "Failed to update changelog: \(error.localizedDescription)"
        }

        isSaving = false
    }

    /// Copies the changelog text from the previous version for all current locales.
    /// Locales that don't exist in the previous version will remain empty.
    func copyChangelogFromPreviousVersion() async {
        guard let previousVersion = previousVersion,
              canEditChangelog else { return }

        isLoadingChangelogs = true
        errorMessage = nil
        actionMessage = nil

        do {
            let previousChangelogs = try await apiClient.fetchChangelogs(previousVersion.id)
            let previousChangelogsByLocale = Dictionary(
                previousChangelogs.map { ($0.locale, $0.text) },
                uniquingKeysWith: { first, _ in first }
            )

            var copiedCount = 0
            for locale in locales {
                if let changelogText = previousChangelogsByLocale[locale], !changelogText.isEmpty {
                    changelogByLocale[locale] = changelogText
                    dirtyLocales.insert(locale)
                    copiedCount += 1
                }
                // If locale doesn't exist in previous version, leave it empty (no action needed)
            }

            if copiedCount > 0 {
                actionMessage = "Copied changelogs from version \(previousVersion.version) for \(copiedCount) locale(s)."
            } else {
                errorMessage = "No changelogs found in version \(previousVersion.version) for any of the current locales."
            }
        } catch {
            errorMessage = "Failed to copy changelog: \(error.localizedDescription)"
        }

        isLoadingChangelogs = false
    }

    func createNewVersion() async {
        guard let platformRaw = platformRawForNewVersion else { return }
        let trimmed = newVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        errorMessage = nil
        actionMessage = nil

        do {
            let newVersion = try await apiClient.createAppVersion(app.id, trimmed, platformRaw)
            newVersionString = ""
            showNewVersionSheet = false
            await loadVersions()
            selectedVersionID = newVersion.id
            actionMessage = "Created version \(newVersion.version)."
        } catch {
            errorMessage = "Failed to create version: \(error.localizedDescription)"
        }

        isSaving = false
    }

    func displayName(for locale: String) -> String {
        Locale.current.localizedString(forIdentifier: locale) ?? locale
    }
}

private struct VersionDraft: Hashable {
    var changelogByLocale: [String: String]
    var changelogIDByLocale: [String: String]
    var locales: [String]
    var selectedLocale: String?
    var dirtyLocales: Set<String>
}
