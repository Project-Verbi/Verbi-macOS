import SwiftUI
import Dependencies
import Observation
import AppStoreConnect_Swift_SDK

enum AsyncOperationState: Equatable {
    case idle
    case inProgress
    case success(versionNumber: String?)
    case error(message: String?)
}

typealias ReleaseState = AsyncOperationState
typealias SubmitForReviewState = AsyncOperationState

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
    var showApplyToAllConfirmation = false
    var localesToBeOverridden: [String] = []
    var showReleaseConfirmation = false
    var releaseState: ReleaseState = .idle
    var showSubmitForReviewConfirmation = false
    var submitForReviewState: SubmitForReviewState = .idle
    var selectedReleaseOption: ReleaseOption = .manual
    var isPhasedReleaseEnabled = false
    var isCopyingFromPrevious = false
    var builds: [AppStoreBuild] = []
    var selectedBuildID: String?
    var initialSelectedBuildID: String?
    var isLoadingBuilds = false
    var isLoadingAvailableBuilds = false
    var buildLoadError: String?
    var showBuildPicker = false
    var hasLoadedAvailableBuilds = false
    var isRefreshing = false

    private var draftsByVersion: [String: VersionDraft] = [:]

    init(app: AppStoreApp) {
        self.app = app
    }

    var selectedVersion: AppStoreVersionSummary? {
        versions.first { $0.id == selectedVersionID }
    }

    var isReleasing: Bool {
        releaseState == .inProgress
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

    var canReleaseVersion: Bool {
        guard let state = selectedVersion?.state?.uppercased() else { return false }
        return state == "PENDING_DEVELOPER_RELEASE" && !isReleasing
    }

    var releaseButtonTitle: String {
        if canReleaseVersion {
            return "Release to App Store"
        }
        return ""
    }

    var isSubmittingForReview: Bool {
        submitForReviewState == .inProgress
    }

    var canSubmitForReview: Bool {
        guard let state = selectedVersion?.state?.uppercased() else { return false }
        let editableStates = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED"]
        return editableStates.contains(state) && !isSubmittingForReview && !isReleasing
    }

    var submitForReviewButtonTitle: String {
        if canSubmitForReview {
            return "Submit for Review"
        }
        return ""
    }

    var canSaveChangelog: Bool {
        guard let locale = selectedLocale,
              dirtyLocales.contains(locale),
              let localizationID = changelogIDByLocale[locale],
              !localizationID.isEmpty,
              canEditChangelog,
              !isCopyingFromPrevious
        else { return false }
        return !isSaving
    }

    var canSaveChanges: Bool {
        if isSaving || isCopyingFromPrevious { return false }
        return shouldSaveCurrentChangelog || shouldSaveBuildSelection
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

    var canSelectBuild: Bool {
        selectedVersion?.isEditable ?? false
    }

    var selectedBuild: AppStoreBuild? {
        builds.first { $0.id == selectedBuildID }
    }

    var isBuildSelectionDirty: Bool {
        selectedBuildID != initialSelectedBuildID
    }

    /// Checks if current text can be applied to all other locales.
    var canApplyToAllLanguages: Bool {
        guard let currentLocale = selectedLocale,
              !currentLocale.isEmpty,
              canEditChangelog,
              locales.count > 1 else { return false }
        let currentText = changelogByLocale[currentLocale] ?? ""
        return !currentText.isEmpty
    }

    /// Returns the locales that would be overridden when applying current text to all.
    func computeLocalesToBeOverridden() -> [String] {
        guard let currentLocale = selectedLocale,
              canEditChangelog else { return [] }
        let currentText = changelogByLocale[currentLocale] ?? ""
        guard !currentText.isEmpty else { return [] }

        return locales.filter { locale in
            guard locale != currentLocale else { return false }
            let existingText = changelogByLocale[locale] ?? ""
            return !existingText.isEmpty
        }
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
        if selectedVersionID != newValue {
            resetBuildState()
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

    func loadSelectedBuild() async {
        guard let versionID = selectedVersionID else {
            resetBuildState()
            return
        }

        isLoadingBuilds = true
        buildLoadError = nil

        do {
            let selectedBuild = try await apiClient.fetchSelectedBuild(versionID)
            if let selectedBuild {
                builds = [selectedBuild]
                selectedBuildID = selectedBuild.id
                initialSelectedBuildID = selectedBuild.id
            } else {
                builds = []
                selectedBuildID = nil
                initialSelectedBuildID = nil
            }
        } catch {
            builds = []
            selectedBuildID = nil
            initialSelectedBuildID = nil
            buildLoadError = "Failed to load selected build: \(error.localizedDescription)"
        }

        isLoadingBuilds = false
    }

    func loadAvailableBuilds() async {
        guard let version = selectedVersion else {
            resetBuildState()
            return
        }

        if hasLoadedAvailableBuilds {
            return
        }

        isLoadingAvailableBuilds = true
        buildLoadError = nil

        do {
            let fetchedBuilds = try await apiClient.fetchBuilds(app.id, version.version)
            builds = fetchedBuilds
            hasLoadedAvailableBuilds = true
            if let selectedBuildID, !builds.contains(where: { $0.id == selectedBuildID }) {
                self.selectedBuildID = nil
            }
        } catch {
            buildLoadError = "Failed to load builds: \(error.localizedDescription)"
        }

        isLoadingAvailableBuilds = false
    }

    func selectBuild(_ buildID: String) {
        selectedBuildID = buildID
    }

    func saveChanges() async {
        guard canSaveChanges else { return }

        let shouldSaveChangelog = shouldSaveCurrentChangelog
        let shouldSaveBuild = shouldSaveBuildSelection

        isSaving = true
        errorMessage = nil
        actionMessage = nil

        do {
            if shouldSaveChangelog,
               let locale = selectedLocale,
               let localizationID = changelogIDByLocale[locale],
               let text = changelogByLocale[locale] {
                try await apiClient.updateChangelog(localizationID, text)
                dirtyLocales.remove(locale)
                if dirtyLocales.isEmpty, let versionID = selectedVersionID {
                    draftsByVersion[versionID] = nil
                }
            }

            if shouldSaveBuild, let versionID = selectedVersionID, let selectedBuildID {
                try await apiClient.updateBuildSelection(versionID, selectedBuildID)
                initialSelectedBuildID = selectedBuildID
            }

            if shouldSaveChangelog || shouldSaveBuild {
                actionMessage = "Saved changes."
            }
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
        }

        isSaving = false
    }

    private func resetBuildState() {
        builds = []
        selectedBuildID = nil
        initialSelectedBuildID = nil
        buildLoadError = nil
        isLoadingBuilds = false
        isLoadingAvailableBuilds = false
        hasLoadedAvailableBuilds = false
    }

    func saveCurrentChangelog() async {
        await saveChanges()
    }

    /// Copies the changelog text from the previous version for all current locales.
    /// Locales that don't exist in the previous version will remain empty.
    func copyChangelogFromPreviousVersion() async {
        guard let previousVersion = previousVersion,
              canEditChangelog else { return }

        isCopyingFromPrevious = true
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

        isCopyingFromPrevious = false
    }

    /// Applies the current changelog text to all other locales.
    func applyCurrentTextToAllLanguages() {
        guard let currentLocale = selectedLocale,
              canEditChangelog else { return }
        let currentText = changelogByLocale[currentLocale] ?? ""
        guard !currentText.isEmpty else { return }

        var appliedCount = 0
        for locale in locales {
            guard locale != currentLocale else { continue }
            changelogByLocale[locale] = currentText
            dirtyLocales.insert(locale)
            appliedCount += 1
        }

        if appliedCount > 0 {
            actionMessage = "Applied text to \(appliedCount) other locale(s)."
        }
        localesToBeOverridden = []
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

    func releaseVersion() async {
        guard let versionID = selectedVersionID, canReleaseVersion else { return }

        releaseState = .inProgress
        errorMessage = nil
        actionMessage = nil

        do {
            try await apiClient.releaseVersion(versionID)
            releaseState = .success(versionNumber: selectedVersion?.version)
            await loadVersions()
        } catch {
            releaseState = .error(message: error.localizedDescription)
        }
    }

    func submitForReview() async {
        guard let versionID = selectedVersionID, canSubmitForReview else { return }

        submitForReviewState = .inProgress
        errorMessage = nil
        actionMessage = nil

        do {
            let phasedReleaseEnabled = selectedReleaseOption.kind == .afterApproval && isPhasedReleaseEnabled
            try await apiClient.submitForReview(
                versionID,
                selectedReleaseOption.releaseType,
                selectedReleaseOption.scheduledDate,
                phasedReleaseEnabled
            )
            submitForReviewState = .success(versionNumber: selectedVersion?.version)
            await loadVersions()
        } catch {
            submitForReviewState = .error(message: error.localizedDescription)
        }
    }

    private var shouldSaveCurrentChangelog: Bool {
        guard let locale = selectedLocale,
              dirtyLocales.contains(locale),
              let localizationID = changelogIDByLocale[locale],
              !localizationID.isEmpty,
              canEditChangelog
        else { return false }
        return true
    }

    private var shouldSaveBuildSelection: Bool {
        guard canSelectBuild,
              let selectedBuildID,
              !selectedBuildID.isEmpty
        else { return false }
        return isBuildSelectionDirty
    }

    func displayName(for locale: String) -> String {
        Locale.current.localizedString(forIdentifier: locale) ?? locale
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let previousSelectedVersionID = selectedVersionID
        let previousSelectedLocale = selectedLocale

        await loadVersions()

        if let previousSelectedVersionID = previousSelectedVersionID,
           versions.contains(where: { $0.id == previousSelectedVersionID }) {
            selectedVersionID = previousSelectedVersionID
        }

        await loadChangelogs()

        if let previousSelectedLocale = previousSelectedLocale,
           locales.contains(previousSelectedLocale) {
            selectedLocale = previousSelectedLocale
        }

        await loadSelectedBuild()

        hasLoadedAvailableBuilds = false
    }
}

private struct VersionDraft: Hashable {
    var changelogByLocale: [String: String]
    var changelogIDByLocale: [String: String]
    var locales: [String]
    var selectedLocale: String?
    var dirtyLocales: Set<String>
}
