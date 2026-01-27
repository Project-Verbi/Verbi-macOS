import Foundation
import Testing
import Dependencies
import Synchronization
import CustomDump
@testable import Verbi

@MainActor
struct AppDetailViewModelTests {

    // MARK: - loadVersions Tests

    @Test
    func loadVersions_success_setsVersionsAndSelectsFirst() async throws {
        // GIVEN a view model with mocked dependencies
        let versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.1.0",
                state: "READY_FOR_REVIEW",
                platform: "IOS",
                kind: .upcoming,
                isEditable: true
            )
        ]

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchAppVersions = { _ in versions }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        // WHEN loading versions
        await sut.loadVersions()

        // THEN the versions are set and the first one is selected
        expectNoDifference(sut.versions, versions)
        #expect(sut.selectedVersionID == "version-1")
        #expect(sut.isLoadingVersions == false)
        #expect(sut.errorMessage == nil)
    }

    @Test
    func loadVersions_error_setsErrorMessage() async throws {
        // GIVEN a view model with a failing fetch
        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchAppVersions = { _ in
                throw NSError(domain: "test", code: 1)
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        // WHEN loading versions
        await sut.loadVersions()

        // THEN an error message is set
        #expect(sut.errorMessage != nil)
        #expect(sut.errorMessage?.contains("Failed to load versions") == true)
        #expect(sut.isLoadingVersions == false)
    }

    @Test
    func loadVersions_preservesSelectedVersionIfStillAvailable() async throws {
        // GIVEN a view model with an already selected version
        let versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchAppVersions = { _ in versions }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
        sut.selectedVersionID = "version-1"

        // WHEN loading versions again with the same version still available
        await sut.loadVersions()

        // THEN the selected version is preserved
        #expect(sut.selectedVersionID == "version-1")
    }

    // MARK: - loadChangelogs Tests

    @Test
    func loadChangelogs_withNoSelectedVersion_clearsChangelogs() async throws {
        // GIVEN a view model with no selected version but existing changelogs
        let sut = AppDetailViewModel(app: .stub)
        sut.changelogByLocale = ["en-US": "Some changelog"]
        sut.locales = ["en-US"]
        sut.selectedLocale = "en-US"

        // WHEN loading changelogs without a selected version
        await sut.loadChangelogs()

        // THEN all changelog data is cleared
        #expect(sut.changelogByLocale.isEmpty)
        #expect(sut.changelogIDByLocale.isEmpty)
        #expect(sut.locales.isEmpty)
        #expect(sut.selectedLocale == nil)
    }

    @Test
    func loadChangelogs_success_setsChangelogsAndSelectsFirstLocale() async throws {
        // GIVEN a view model with a selected version
        let changelogs = [
            AppChangelog(id: "loc-1", locale: "en-US", text: "English changelog"),
            AppChangelog(id: "loc-2", locale: "de-DE", text: "German changelog")
        ]

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchChangelogs = { _ in changelogs }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
        sut.selectedVersionID = "version-1"

        // WHEN loading changelogs
        await sut.loadChangelogs()

        // THEN the changelogs are set and the first locale is selected
        #expect(sut.changelogByLocale["en-US"] == "English changelog")
        #expect(sut.changelogByLocale["de-DE"] == "German changelog")
        #expect(sut.changelogIDByLocale["en-US"] == "loc-1")
        #expect(sut.changelogIDByLocale["de-DE"] == "loc-2")
        #expect(sut.locales.contains("en-US"))
        #expect(sut.locales.contains("de-DE"))
        #expect(sut.selectedLocale != nil)
        #expect(sut.isLoadingChangelogs == false)
    }

    @Test
    func loadChangelogs_restoresDraftIfAvailable() async throws {
        // GIVEN a view model with a saved draft
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedVersionID = "version-1"

        // Create a draft by setting data and switching versions
        sut.changelogByLocale = ["en-US": "Draft changelog"]
        sut.changelogIDByLocale = ["en-US": "loc-1"]
        sut.locales = ["en-US"]
        sut.selectedLocale = "en-US"
        sut.dirtyLocales = ["en-US"]

        // Switch to a different version to trigger draft save
        sut.setSelectedVersionID("version-2")

        // Reset and go back to version-1
        sut.changelogByLocale = [:]
        sut.changelogIDByLocale = [:]
        sut.locales = []
        sut.selectedLocale = nil
        sut.selectedVersionID = "version-1"

        // WHEN loading changelogs for version-1
        await sut.loadChangelogs()

        // THEN the draft is restored
        #expect(sut.changelogByLocale["en-US"] == "Draft changelog")
        #expect(sut.selectedLocale == "en-US")
        #expect(sut.actionMessage == "Loaded unsaved draft.")
    }

    @Test
    func loadChangelogs_error_setsErrorMessage() async throws {
        // GIVEN a view model with a failing fetch
        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchChangelogs = { _ in
                throw NSError(domain: "test", code: 1)
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
        sut.selectedVersionID = "version-1"

        // WHEN loading changelogs
        await sut.loadChangelogs()

        // THEN an error message is set
        #expect(sut.errorMessage != nil)
        #expect(sut.errorMessage?.contains("Failed to load changelogs") == true)
        #expect(sut.isLoadingChangelogs == false)
    }

    // MARK: - saveCurrentChangelog Tests

    @Test
    func saveCurrentChangelog_success_clearsDirtyFlagAndSetsActionMessage() async throws {
        // GIVEN a view model with a changelog to save
        let updatedLocalizationID = Mutex<String?>(nil)
        let updatedText = Mutex<String?>(nil)

        let sut = withDependencies {
            $0.appStoreConnectAPI.updateChangelog = { localizationID, text in
                updatedLocalizationID.withLock { $0 = localizationID }
                updatedText.withLock { $0 = text }
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.changelogIDByLocale = ["en-US": "loc-1"]
        sut.changelogByLocale = ["en-US": "Updated changelog"]
        sut.dirtyLocales = ["en-US"]

        // WHEN saving the changelog
        await sut.saveCurrentChangelog()

        // THEN the changelog is saved, dirty flag is cleared, and success message is set
        #expect(updatedLocalizationID.withLock { $0 } == "loc-1")
        #expect(updatedText.withLock { $0 } == "Updated changelog")
        #expect(sut.dirtyLocales.contains("en-US") == false)
        #expect(sut.actionMessage == "Changelog updated.")
        #expect(sut.isSaving == false)
    }

    @Test
    func saveCurrentChangelog_error_setsErrorMessage() async throws {
        // GIVEN a view model with a failing update
        let sut = withDependencies {
            $0.appStoreConnectAPI.updateChangelog = { _, _ in
                throw NSError(domain: "test", code: 1)
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.changelogIDByLocale = ["en-US": "loc-1"]
        sut.changelogByLocale = ["en-US": "Updated changelog"]

        // WHEN saving the changelog
        await sut.saveCurrentChangelog()

        // THEN an error message is set
        #expect(sut.errorMessage != nil)
        #expect(sut.errorMessage?.contains("Failed to update changelog") == true)
        #expect(sut.isSaving == false)
    }

    @Test
    func saveCurrentChangelog_withMissingData_doesNothing() async throws {
        // GIVEN a view model without proper changelog data
        var updateCalled = false
        let sut = withDependencies {
            $0.appStoreConnectAPI.updateChangelog = { _, _ in
                updateCalled = true
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
        // Missing selectedLocale

        // WHEN saving the changelog
        await sut.saveCurrentChangelog()

        // THEN the update is not called
        #expect(updateCalled == false)
        #expect(sut.isSaving == false)
    }

    // MARK: - createNewVersion Tests

    @Test
    func createNewVersion_success_createsVersionAndReloads() async throws {
        // GIVEN a view model ready to create a new version
        let createdAppID = Mutex<String?>(nil)
        let createdVersionString = Mutex<String?>(nil)

        let newVersion = AppStoreVersionSummary(
            id: "new-version-id",
            version: "2.0.0",
            state: "PREPARE_FOR_SUBMISSION",
            platform: "IOS",
            kind: .upcoming,
            isEditable: true
        )

        let sut = withDependencies {
            $0.appStoreConnectAPI.createAppVersion = { appID, versionString, _ in
                createdAppID.withLock { $0 = appID }
                createdVersionString.withLock { $0 = versionString }
                return newVersion
            }
            $0.appStoreConnectAPI.fetchAppVersions = { _ in [newVersion] }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.newVersionString = "2.0.0"
        sut.versions = [
            AppStoreVersionSummary(
                id: "existing-version",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]

        // WHEN creating a new version
        await sut.createNewVersion()

        // THEN the version is created with correct parameters
        #expect(createdAppID.withLock { $0 } == "stub-app-id")
        #expect(createdVersionString.withLock { $0 } == "2.0.0")
        #expect(sut.newVersionString == "")
        #expect(sut.showNewVersionSheet == false)
        #expect(sut.selectedVersionID == "new-version-id")
        #expect(sut.actionMessage == "Created version 2.0.0.")
        #expect(sut.isSaving == false)
    }

    @Test
    func createNewVersion_error_setsErrorMessage() async throws {
        // GIVEN a view model with a failing create
        let sut = withDependencies {
            $0.appStoreConnectAPI.createAppVersion = { _, _, _ in
                throw NSError(domain: "test", code: 1)
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.newVersionString = "2.0.0"
        sut.versions = [
            AppStoreVersionSummary(
                id: "existing-version",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]

        // WHEN creating a new version
        await sut.createNewVersion()

        // THEN an error message is set
        #expect(sut.errorMessage != nil)
        #expect(sut.errorMessage?.contains("Failed to create version") == true)
        #expect(sut.isSaving == false)
    }

    @Test
    func createNewVersion_withEmptyString_doesNothing() async throws {
        // GIVEN a view model with an empty version string
        var createCalled = false
        let sut = withDependencies {
            $0.appStoreConnectAPI.createAppVersion = { _, _, _ in
                createCalled = true
                return AppStoreVersionSummary(
                    id: "id",
                    version: "1.0",
                    state: nil,
                    platform: nil,
                    kind: .upcoming,
                    isEditable: true
                )
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.newVersionString = "   " // Only whitespace
        sut.versions = [
            AppStoreVersionSummary(
                id: "existing-version",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]

        // WHEN creating a new version
        await sut.createNewVersion()

        // THEN the create is not called
        #expect(createCalled == false)
        #expect(sut.isSaving == false)
    }

    // MARK: - updateSelectedChangelogText Tests

    @Test
    func updateSelectedChangelogText_updatesTextAndMarksLocaleDirty() {
        // GIVEN a view model with a selected locale
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedLocale = "en-US"
        sut.changelogByLocale = [:]
        sut.dirtyLocales = []

        // WHEN updating the changelog text
        sut.updateSelectedChangelogText("New changelog text")

        // THEN the text is updated and the locale is marked as dirty
        #expect(sut.changelogByLocale["en-US"] == "New changelog text")
        #expect(sut.dirtyLocales.contains("en-US"))
    }

    @Test
    func updateSelectedChangelogText_clearsActionMessage() {
        // GIVEN a view model with an existing action message
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedLocale = "en-US"
        sut.actionMessage = "Previous action"

        // WHEN updating the changelog text
        sut.updateSelectedChangelogText("New text")

        // THEN the action message is cleared
        #expect(sut.actionMessage == nil)
    }

    // MARK: - setSelectedVersionID Tests

    @Test
    func setSelectedVersionID_savesDraftWhenSwitchingWithDirtyChanges() {
        // GIVEN a view model with dirty changes
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedVersionID = "version-1"
        sut.changelogByLocale = ["en-US": "Draft text"]
        sut.changelogIDByLocale = ["en-US": "loc-1"]
        sut.locales = ["en-US"]
        sut.selectedLocale = "en-US"
        sut.dirtyLocales = ["en-US"]

        // WHEN switching to a different version
        sut.setSelectedVersionID("version-2")

        // THEN the draft is saved for the old version and the new version is selected
        #expect(sut.selectedVersionID == "version-2")
        // The draft should be saved internally for version-1
    }

    @Test
    func setSelectedVersionID_doesNotSaveDraftWhenNoDirtyChanges() {
        // GIVEN a view model without dirty changes
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedVersionID = "version-1"
        sut.dirtyLocales = []

        // WHEN switching to a different version
        sut.setSelectedVersionID("version-2")

        // THEN only the version is changed
        #expect(sut.selectedVersionID == "version-2")
    }

    // MARK: - Computed Properties Tests

    @Test
    func selectedVersion_returnsCurrentlySelectedVersion() {
        // GIVEN a view model with versions
        let sut = AppDetailViewModel(app: .stub)
        let version = AppStoreVersionSummary(
            id: "version-1",
            version: "1.0.0",
            state: "PREPARE_FOR_SUBMISSION",
            platform: "IOS",
            kind: .current,
            isEditable: true
        )
        sut.versions = [version]
        sut.selectedVersionID = "version-1"

        // WHEN accessing the selected version
        let selected = sut.selectedVersion

        // THEN the correct version is returned
        #expect(selected?.id == "version-1")
        #expect(selected?.version == "1.0.0")
    }

    @Test
    func canEditChangelog_returnsTrueForEditableVersion() {
        // GIVEN a view model with an editable version selected
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"

        // WHEN checking if changelog can be edited
        let canEdit = sut.canEditChangelog

        // THEN it returns true
        #expect(canEdit == true)
    }

    @Test
    func canEditChangelog_returnsFalseForNonEditableVersion() {
        // GIVEN a view model with a non-editable version selected
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"

        // WHEN checking if changelog can be edited
        let canEdit = sut.canEditChangelog

        // THEN it returns false
        #expect(canEdit == false)
    }

    @Test
    func canSaveChangelog_returnsTrueWhenConditionsMet() {
        // GIVEN a view model with all save conditions met
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.changelogIDByLocale = ["en-US": "loc-1"]
        sut.dirtyLocales = ["en-US"]
        sut.isSaving = false

        // WHEN checking if changelog can be saved
        let canSave = sut.canSaveChangelog

        // THEN it returns true
        #expect(canSave == true)
    }

    @Test
    func canSaveChangelog_returnsFalseWhenNotDirty() {
        // GIVEN a view model with no dirty changes
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.changelogIDByLocale = ["en-US": "loc-1"]
        sut.dirtyLocales = [] // Not dirty

        // WHEN checking if changelog can be saved
        let canSave = sut.canSaveChangelog

        // THEN it returns false
        #expect(canSave == false)
    }

    @Test
    func canSaveChangelog_returnsFalseWhenSaving() {
        // GIVEN a view model that is currently saving
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.changelogIDByLocale = ["en-US": "loc-1"]
        sut.dirtyLocales = ["en-US"]
        sut.isSaving = true

        // WHEN checking if changelog can be saved
        let canSave = sut.canSaveChangelog

        // THEN it returns false
        #expect(canSave == false)
    }

    @Test
    func platformRawForNewVersion_returnsPlatformWhenEditable() {
        // GIVEN a view model with an editable version
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"

        // WHEN getting the platform for new version
        let platform = sut.platformRawForNewVersion

        // THEN it returns the platform
        #expect(platform == "IOS")
    }

    @Test
    func platformRawForNewVersion_returnsNilWhenPendingDeveloperRelease() {
        // GIVEN a view model with a version pending developer release
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "PENDING_DEVELOPER_RELEASE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"

        // WHEN getting the platform for new version
        let platform = sut.platformRawForNewVersion

        // THEN it returns nil because new versions cannot be created
        #expect(platform == nil)
    }

    @Test
    func platformRawForNewVersion_fallsBackToFirstVersion() {
        // GIVEN a view model with no selected version but with versions available
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "MAC_OS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = nil

        // WHEN getting the platform for new version
        let platform = sut.platformRawForNewVersion

        // THEN it falls back to the first version's platform
        #expect(platform == "MAC_OS")
    }

    @Test
    func changelogFooterText_returnsPendingReleaseMessage() {
        // GIVEN a view model with a version pending developer release
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "PENDING_DEVELOPER_RELEASE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"

        // WHEN getting the changelog footer text
        let text = sut.changelogFooterText

        // THEN it returns the pending developer release message
        #expect(text.contains("pending developer release"))
    }

    @Test
    func changelogFooterText_returnsDefaultMessageForOtherStates() {
        // GIVEN a view model with a released version
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "1.0.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"

        // WHEN getting the changelog footer text
        let text = sut.changelogFooterText

        // THEN it returns the default unavailable message
        #expect(text == "Changelog editing is unavailable for released versions.")
    }

    @Test
    func selectedChangelogText_returnsTextForSelectedLocale() {
        // GIVEN a view model with changelog data
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedLocale = "en-US"
        sut.changelogByLocale = ["en-US": "English text", "de-DE": "German text"]

        // WHEN getting the selected changelog text
        let text = sut.selectedChangelogText

        // THEN it returns the text for the selected locale
        #expect(text == "English text")
    }

    @Test
    func selectedChangelogText_returnsEmptyStringForNoLocale() {
        // GIVEN a view model with no selected locale
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedLocale = nil
        sut.changelogByLocale = ["en-US": "English text"]

        // WHEN getting the selected changelog text
        let text = sut.selectedChangelogText

        // THEN it returns an empty string
        #expect(text == "")
    }
}
