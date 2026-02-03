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
        sut.changelogByLocale = ["en-US": "Updated changelog"]
        sut.dirtyLocales = ["en-US"]

        // WHEN saving the changelog
        await sut.saveCurrentChangelog()

        // THEN the changelog is saved, dirty flag is cleared, and success message is set
        #expect(updatedLocalizationID.withLock { $0 } == "loc-1")
        #expect(updatedText.withLock { $0 } == "Updated changelog")
        #expect(sut.dirtyLocales.contains("en-US") == false)
        #expect(sut.actionMessage == "Saved changes.")
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
        sut.changelogByLocale = ["en-US": "Updated changelog"]
        sut.dirtyLocales = ["en-US"]

        // WHEN saving the changelog
        await sut.saveCurrentChangelog()

        // THEN an error message is set
        #expect(sut.errorMessage != nil)
        #expect(sut.errorMessage?.contains("Failed to save changes") == true)
        #expect(sut.isSaving == false)
    }

    @Test
    func saveCurrentChangelog_withMissingData_doesNothing() async throws {
        // GIVEN a view model without proper changelog data
        let updateCalled = Mutex(false)
        let sut = withDependencies {
            $0.appStoreConnectAPI.updateChangelog = { _, _ in
                updateCalled.withLock { $0 = true }
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
        // Missing selectedLocale

        // WHEN saving the changelog
        await sut.saveCurrentChangelog()

        // THEN the update is not called
        #expect(updateCalled.withLock { $0 } == false)
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
        let createCalled = Mutex(false)
        let sut = withDependencies {
            $0.appStoreConnectAPI.createAppVersion = { _, _, _ in
                createCalled.withLock { $0 = true }
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
        #expect(createCalled.withLock { $0 } == false)
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

    // MARK: - previousVersion Tests

    @Test
    func previousVersion_returnsVersionBeforeSelected() {
        // GIVEN a view model with multiple versions where the first is selected
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"

        // WHEN getting the previous version
        let previous = sut.previousVersion

        // THEN it returns the version immediately after in the list (which is the previous version)
        #expect(previous?.id == "version-2")
        #expect(previous?.version == "1.9.0")
    }

    @Test
    func previousVersion_returnsNilWhenLastVersionSelected() {
        // GIVEN a view model with the last version selected
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-2"

        // WHEN getting the previous version
        let previous = sut.previousVersion

        // THEN it returns nil because this is the last version in the list
        #expect(previous == nil)
    }

    @Test
    func previousVersion_returnsNilWhenNoVersions() {
        // GIVEN a view model with no versions
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = []
        sut.selectedVersionID = nil

        // WHEN getting the previous version
        let previous = sut.previousVersion

        // THEN it returns nil
        #expect(previous == nil)
    }

    @Test
    func previousVersion_returnsNilWhenNoVersionSelected() {
        // GIVEN a view model with versions but none selected
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
        sut.selectedVersionID = nil

        // WHEN getting the previous version
        let previous = sut.previousVersion

        // THEN it returns nil
        #expect(previous == nil)
    }

    @Test
    func previousVersion_returnsNilWhenOnlyOneVersion() {
        // GIVEN a view model with only one version
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

        // WHEN getting the previous version
        let previous = sut.previousVersion

        // THEN it returns nil because there's no previous version
        #expect(previous == nil)
    }

    // MARK: - canCopyChangelogFromPreviousVersion Tests

    @Test
    func canCopyChangelogFromPreviousVersion_returnsTrueWhenConditionsMet() {
        // GIVEN a view model with editable version and available locales
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.locales = ["en-US"]

        // WHEN checking if can copy from previous
        let canCopy = sut.canCopyChangelogFromPreviousVersion

        // THEN it returns true
        #expect(canCopy == true)
    }

    @Test
    func canCopyChangelogFromPreviousVersion_returnsFalseWhenNoPreviousVersion() {
        // GIVEN a view model with only one version (no previous)
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
        sut.locales = ["en-US"]

        // WHEN checking if can copy from previous
        let canCopy = sut.canCopyChangelogFromPreviousVersion

        // THEN it returns false because there's no previous version
        #expect(canCopy == false)
    }

    @Test
    func canCopyChangelogFromPreviousVersion_returnsFalseWhenNoLocales() {
        // GIVEN a view model with editable version but no locales
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.locales = []

        // WHEN checking if can copy from previous
        let canCopy = sut.canCopyChangelogFromPreviousVersion

        // THEN it returns false because there are no locales to copy to
        #expect(canCopy == false)
    }

    @Test
    func canCopyChangelogFromPreviousVersion_returnsFalseWhenNotEditable() {
        // GIVEN a view model with non-editable version
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.locales = ["en-US"]

        // WHEN checking if can copy from previous
        let canCopy = sut.canCopyChangelogFromPreviousVersion

        // THEN it returns false because the version is not editable
        #expect(canCopy == false)
    }

    // MARK: - copyChangelogFromPreviousVersion Tests

    @Test
    func copyChangelogFromPreviousVersion_success_copiesChangelogForAllLocales() async throws {
        // GIVEN a view model with multiple locales and previous version has changelogs for some
        let previousChangelogs = [
            AppChangelog(id: "loc-1", locale: "en-US", text: "English changelog"),
            AppChangelog(id: "loc-2", locale: "de-DE", text: "German changelog")
        ]

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchChangelogs = { versionID in
                if versionID == "version-2" {
                    return previousChangelogs
                }
                return []
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.changelogIDByLocale = ["en-US": "loc-en", "de-DE": "loc-de", "fr-FR": "loc-fr"]
        sut.locales = ["en-US", "de-DE", "fr-FR"] // fr-FR doesn't exist in previous
        sut.changelogByLocale = ["en-US": "", "de-DE": "", "fr-FR": ""]
        sut.dirtyLocales = []

        // WHEN copying changelog from previous version
        await sut.copyChangelogFromPreviousVersion()

        // THEN changelogs are copied for matching locales and marked as dirty
        #expect(sut.changelogByLocale["en-US"] == "English changelog")
        #expect(sut.changelogByLocale["de-DE"] == "German changelog")
        #expect(sut.changelogByLocale["fr-FR"] == "") // New locale remains empty
        #expect(sut.dirtyLocales.contains("en-US"))
        #expect(sut.dirtyLocales.contains("de-DE"))
        #expect(!sut.dirtyLocales.contains("fr-FR")) // Not marked dirty since not copied
        #expect(sut.actionMessage == "Copied changelogs from version 1.9.0 for 2 locale(s).")
        #expect(sut.isCopyingFromPrevious == false)
        #expect(sut.errorMessage == nil)
    }

    @Test
    func copyChangelogFromPreviousVersion_withNewLocale_keepsEmpty() async throws {
        // GIVEN a view model with a new locale not in previous version
        let previousChangelogs = [
            AppChangelog(id: "loc-1", locale: "en-US", text: "English changelog")
        ]

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchChangelogs = { _ in previousChangelogs }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.locales = ["en-US", "es-ES"] // es-ES is new, not in previous
        sut.changelogByLocale = ["en-US": "", "es-ES": ""]

        // WHEN copying changelog from previous version
        await sut.copyChangelogFromPreviousVersion()

        // THEN en-US is copied, es-ES remains empty
        #expect(sut.changelogByLocale["en-US"] == "English changelog")
        #expect(sut.changelogByLocale["es-ES"] == "")
        #expect(sut.dirtyLocales.contains("en-US"))
        #expect(!sut.dirtyLocales.contains("es-ES"))
    }

    @Test
    func copyChangelogFromPreviousVersion_withEmptyChangelogs_skipsEmptyOnes() async throws {
        // GIVEN a view model where previous version has empty changelog for some locales
        let previousChangelogs = [
            AppChangelog(id: "loc-1", locale: "en-US", text: "English changelog"),
            AppChangelog(id: "loc-2", locale: "de-DE", text: "") // Empty
        ]

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchChangelogs = { _ in previousChangelogs }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.locales = ["en-US", "de-DE"]
        sut.changelogByLocale = ["en-US": "", "de-DE": ""]
        sut.dirtyLocales = []

        // WHEN copying changelog from previous version
        await sut.copyChangelogFromPreviousVersion()

        // THEN only non-empty changelog is copied
        #expect(sut.changelogByLocale["en-US"] == "English changelog")
        #expect(sut.changelogByLocale["de-DE"] == "") // Still empty
        #expect(sut.dirtyLocales.contains("en-US"))
        #expect(!sut.dirtyLocales.contains("de-DE"))
        #expect(sut.actionMessage == "Copied changelogs from version 1.9.0 for 1 locale(s).")
    }

    @Test
    func copyChangelogFromPreviousVersion_withNoMatchingLocales_showsError() async throws {
        // GIVEN a view model where previous version has no matching locales
        let previousChangelogs = [
            AppChangelog(id: "loc-1", locale: "ja-JP", text: "Japanese changelog")
        ]

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchChangelogs = { _ in previousChangelogs }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.locales = ["en-US", "de-DE"] // None match previous version
        sut.changelogByLocale = ["en-US": "", "de-DE": ""]

        // WHEN copying changelog from previous version
        await sut.copyChangelogFromPreviousVersion()

        // THEN an error is shown because no locales were copied
        #expect(sut.errorMessage?.contains("No changelogs found") == true)
        #expect(sut.isCopyingFromPrevious == false)
    }

    @Test
    func copyChangelogFromPreviousVersion_withNoChangelogs_showsError() async throws {
        // GIVEN a view model where previous version has no changelogs
        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchChangelogs = { _ in [] }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.locales = ["en-US"]
        sut.changelogByLocale = ["en-US": ""]

        // WHEN copying changelog from previous version
        await sut.copyChangelogFromPreviousVersion()

        // THEN an error message is shown
        #expect(sut.errorMessage?.contains("No changelogs found") == true)
        #expect(sut.isCopyingFromPrevious == false)
    }

    @Test
    func copyChangelogFromPreviousVersion_withError_showsErrorMessage() async throws {
        // GIVEN a view model with a failing fetch
        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchChangelogs = { _ in
                throw NSError(domain: "test", code: 1)
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            ),
            AppStoreVersionSummary(
                id: "version-2",
                version: "1.9.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.locales = ["en-US"]

        // WHEN copying changelog from previous version
        await sut.copyChangelogFromPreviousVersion()

        // THEN an error message is set
        #expect(sut.errorMessage?.contains("Failed to copy changelog") == true)
        #expect(sut.isCopyingFromPrevious == false)
    }

    @Test
    func copyChangelogFromPreviousVersion_withNoPreviousVersion_doesNothing() async throws {
        // GIVEN a view model with no previous version
        let fetchCalled = Mutex(false)
        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchChangelogs = { _ in
                fetchCalled.withLock { $0 = true }
                return []
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

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

        // WHEN copying changelog from previous version
        await sut.copyChangelogFromPreviousVersion()

        // THEN the fetch is not called and nothing changes
        #expect(fetchCalled.withLock { $0 } == false)
        #expect(sut.isCopyingFromPrevious == false)
    }

    // MARK: - canApplyToAllLanguages Tests

    @Test
    func canApplyToAllLanguages_returnsTrueWhenConditionsMet() {
        // GIVEN a view model with multiple locales, editable version, and non-empty text
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE", "fr-FR"]
        sut.changelogByLocale = ["en-US": "Some changelog text"]

        // WHEN checking if can apply to all languages
        let canApply = sut.canApplyToAllLanguages

        // THEN it returns true
        #expect(canApply == true)
    }

    @Test
    func canApplyToAllLanguages_returnsFalseWhenOnlyOneLocale() {
        // GIVEN a view model with only one locale
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US"]
        sut.changelogByLocale = ["en-US": "Some changelog text"]

        // WHEN checking if can apply to all languages
        let canApply = sut.canApplyToAllLanguages

        // THEN it returns false because there's only one locale
        #expect(canApply == false)
    }

    @Test
    func canApplyToAllLanguages_returnsFalseWhenEmptyText() {
        // GIVEN a view model with empty changelog text
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE"]
        sut.changelogByLocale = ["en-US": ""]

        // WHEN checking if can apply to all languages
        let canApply = sut.canApplyToAllLanguages

        // THEN it returns false because the text is empty
        #expect(canApply == false)
    }

    @Test
    func canApplyToAllLanguages_returnsFalseWhenNotEditable() {
        // GIVEN a view model with non-editable version
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE"]
        sut.changelogByLocale = ["en-US": "Some changelog text"]

        // WHEN checking if can apply to all languages
        let canApply = sut.canApplyToAllLanguages

        // THEN it returns false because the version is not editable
        #expect(canApply == false)
    }

    @Test
    func canApplyToAllLanguages_returnsFalseWhenNoLocaleSelected() {
        // GIVEN a view model with no selected locale
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = nil
        sut.locales = ["en-US", "de-DE"]

        // WHEN checking if can apply to all languages
        let canApply = sut.canApplyToAllLanguages

        // THEN it returns false because no locale is selected
        #expect(canApply == false)
    }

    // MARK: - computeLocalesToBeOverridden Tests

    @Test
    func computeLocalesToBeOverridden_returnsLocalesWithExistingText() {
        // GIVEN a view model where some locales have existing text
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE", "fr-FR"]
        sut.changelogByLocale = [
            "en-US": "English text",
            "de-DE": "German text",
            "fr-FR": ""
        ]

        // WHEN computing locales to be overridden
        let localesToOverride = sut.computeLocalesToBeOverridden()

        // THEN it returns only the locales with non-empty text (excluding current)
        #expect(localesToOverride.count == 1)
        #expect(localesToOverride.contains("de-DE"))
        #expect(!localesToOverride.contains("en-US")) // Current locale excluded
        #expect(!localesToOverride.contains("fr-FR")) // Empty text excluded
    }

    @Test
    func computeLocalesToBeOverridden_returnsEmptyWhenNoOtherLocalesHaveText() {
        // GIVEN a view model where no other locales have text
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE", "fr-FR"]
        sut.changelogByLocale = [
            "en-US": "English text",
            "de-DE": "",
            "fr-FR": ""
        ]

        // WHEN computing locales to be overridden
        let localesToOverride = sut.computeLocalesToBeOverridden()

        // THEN it returns an empty array
        #expect(localesToOverride.isEmpty)
    }

    @Test
    func computeLocalesToBeOverridden_returnsEmptyWhenNotEditable() {
        // GIVEN a view model with non-editable version
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE"]
        sut.changelogByLocale = [
            "en-US": "English text",
            "de-DE": "German text"
        ]

        // WHEN computing locales to be overridden
        let localesToOverride = sut.computeLocalesToBeOverridden()

        // THEN it returns an empty array because editing is not allowed
        #expect(localesToOverride.isEmpty)
    }

    @Test
    func computeLocalesToBeOverridden_returnsEmptyWhenCurrentTextEmpty() {
        // GIVEN a view model with empty current text
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE"]
        sut.changelogByLocale = [
            "en-US": "",
            "de-DE": "German text"
        ]

        // WHEN computing locales to be overridden
        let localesToOverride = sut.computeLocalesToBeOverridden()

        // THEN it returns an empty array because current text is empty
        #expect(localesToOverride.isEmpty)
    }

    // MARK: - applyCurrentTextToAllLanguages Tests

    @Test
    func applyCurrentTextToAllLanguages_appliesTextToAllOtherLocales() {
        // GIVEN a view model with text in current locale
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE", "fr-FR"]
        sut.changelogByLocale = [
            "en-US": "New features",
            "de-DE": "",
            "fr-FR": ""
        ]
        sut.dirtyLocales = []

        // WHEN applying current text to all languages
        sut.applyCurrentTextToAllLanguages()

        // THEN the text is applied to all other locales and marked as dirty
        #expect(sut.changelogByLocale["en-US"] == "New features")
        #expect(sut.changelogByLocale["de-DE"] == "New features")
        #expect(sut.changelogByLocale["fr-FR"] == "New features")
        #expect(sut.dirtyLocales.contains("de-DE"))
        #expect(sut.dirtyLocales.contains("fr-FR"))
        #expect(!sut.dirtyLocales.contains("en-US")) // Current locale not marked dirty
        #expect(sut.actionMessage == "Applied text to 2 other locale(s).")
    }

    @Test
    func applyCurrentTextToAllLanguages_overridesExistingText() {
        // GIVEN a view model with existing text in other locales
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE", "fr-FR"]
        sut.changelogByLocale = [
            "en-US": "New features",
            "de-DE": "Alte Features",
            "fr-FR": "Anciennes fonctionnalités"
        ]
        sut.dirtyLocales = ["de-DE"]

        // WHEN applying current text to all languages
        sut.applyCurrentTextToAllLanguages()

        // THEN the existing text is overridden
        #expect(sut.changelogByLocale["de-DE"] == "New features")
        #expect(sut.changelogByLocale["fr-FR"] == "New features")
        #expect(sut.dirtyLocales.contains("de-DE"))
        #expect(sut.dirtyLocales.contains("fr-FR"))
    }

    @Test
    func applyCurrentTextToAllLanguages_doesNothingWhenNotEditable() {
        // GIVEN a view model with non-editable version
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "READY_FOR_SALE",
                platform: "IOS",
                kind: .current,
                isEditable: false
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE"]
        sut.changelogByLocale = [
            "en-US": "New features",
            "de-DE": ""
        ]

        // WHEN applying current text to all languages
        sut.applyCurrentTextToAllLanguages()

        // THEN nothing changes
        #expect(sut.changelogByLocale["de-DE"] == "")
        #expect(sut.actionMessage == nil)
    }

    @Test
    func applyCurrentTextToAllLanguages_doesNothingWhenCurrentTextEmpty() {
        // GIVEN a view model with empty current text
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE"]
        sut.changelogByLocale = [
            "en-US": "",
            "de-DE": "German text"
        ]

        // WHEN applying current text to all languages
        sut.applyCurrentTextToAllLanguages()

        // THEN nothing changes
        #expect(sut.changelogByLocale["de-DE"] == "German text")
        #expect(sut.actionMessage == nil)
    }

    @Test
    func applyCurrentTextToAllLanguages_clearsLocalesToBeOverridden() {
        // GIVEN a view model with locales to be overridden set
        let sut = AppDetailViewModel(app: .stub)
        sut.versions = [
            AppStoreVersionSummary(
                id: "version-1",
                version: "2.0.0",
                state: "PREPARE_FOR_SUBMISSION",
                platform: "IOS",
                kind: .current,
                isEditable: true
            )
        ]
        sut.selectedVersionID = "version-1"
        sut.selectedLocale = "en-US"
        sut.locales = ["en-US", "de-DE"]
        sut.changelogByLocale = ["en-US": "New features"]
        sut.localesToBeOverridden = ["de-DE"]

        // WHEN applying current text to all languages
        sut.applyCurrentTextToAllLanguages()

        // THEN the localesToBeOverridden is cleared
        #expect(sut.localesToBeOverridden.isEmpty)
    }

    // MARK: - loadSelectedBuild Tests

    @Test
    func loadSelectedBuild_success_setsBuildAndSelection() async throws {
        // GIVEN a view model with a selected version and mocked build
        let selectedBuild = AppStoreBuild(
            id: "build-1",
            version: "1.0.0",
            uploadedDate: Date(),
            processingState: nil,
            isSelectable: true
        )

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchSelectedBuild = { _ in selectedBuild }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
        sut.selectedVersionID = "version-1"

        // WHEN loading selected build
        await sut.loadSelectedBuild()

        // THEN the build is set and selected
        #expect(sut.builds.count == 1)
        #expect(sut.builds.first?.id == "build-1")
        #expect(sut.selectedBuildID == "build-1")
        #expect(sut.initialSelectedBuildID == "build-1")
        #expect(sut.isLoadingBuilds == false)
        #expect(sut.buildLoadError == nil)
    }

    @Test
    func loadSelectedBuild_withNoBuild_clearsBuildState() async throws {
        // GIVEN a view model with existing build data but no build returned
        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchSelectedBuild = { _ in nil }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
        sut.selectedVersionID = "version-1"
        sut.builds = [AppStoreBuild(id: "old-build", version: "0.9.0", uploadedDate: Date(), processingState: nil, isSelectable: true)]
        sut.selectedBuildID = "old-build"
        sut.initialSelectedBuildID = "old-build"

        // WHEN loading selected build with no build
        await sut.loadSelectedBuild()

        // THEN the build state is cleared
        #expect(sut.builds.isEmpty)
        #expect(sut.selectedBuildID == nil)
        #expect(sut.initialSelectedBuildID == nil)
    }

    @Test
    func loadSelectedBuild_withNoSelectedVersion_clearsBuildState() async throws {
        // GIVEN a view model with no selected version
        let fetchCalled = Mutex(false)
        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchSelectedBuild = { _ in
                fetchCalled.withLock { $0 = true }
                return nil
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
        sut.builds = [AppStoreBuild(id: "build-1", version: "1.0.0", uploadedDate: Date(), processingState: nil, isSelectable: true)]
        sut.selectedBuildID = "build-1"

        // WHEN loading selected build without a version
        await sut.loadSelectedBuild()

        // THEN the fetch is not called and build state is cleared
        #expect(fetchCalled.withLock { $0 } == false)
        #expect(sut.builds.isEmpty)
        #expect(sut.selectedBuildID == nil)
        #expect(sut.initialSelectedBuildID == nil)
    }

    @Test
    func loadSelectedBuild_error_clearsBuildState() async throws {
        // GIVEN a view model with a failing fetch
        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchSelectedBuild = { _ in
                throw NSError(domain: "test", code: 1)
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
        sut.selectedVersionID = "version-1"
        sut.builds = [AppStoreBuild(id: "old-build", version: "0.9.0", uploadedDate: Date(), processingState: nil, isSelectable: true)]
        sut.selectedBuildID = "old-build"

        // WHEN loading selected build with error
        await sut.loadSelectedBuild()

        // THEN the build state is cleared (error is silently handled)
        #expect(sut.builds.isEmpty)
        #expect(sut.selectedBuildID == nil)
        #expect(sut.initialSelectedBuildID == nil)
        #expect(sut.isLoadingBuilds == false)
    }

    // MARK: - loadAvailableBuilds Tests

    @Test
    func loadAvailableBuilds_success_setsBuilds() async throws {
        // GIVEN a view model with a selected version
        let builds = [
            AppStoreBuild(id: "build-1", version: "1.0.0", uploadedDate: Date(), processingState: nil, isSelectable: true),
            AppStoreBuild(id: "build-2", version: "1.0.1", uploadedDate: Date(), processingState: nil, isSelectable: true)
        ]

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchBuilds = { _, _ in builds }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
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

        // WHEN loading available builds
        await sut.loadAvailableBuilds()

        // THEN the builds are set
        #expect(sut.builds.count == 2)
        #expect(sut.hasLoadedAvailableBuilds == true)
        #expect(sut.isLoadingAvailableBuilds == false)
        #expect(sut.buildLoadError == nil)
    }

    @Test
    func loadAvailableBuilds_cachesResults() async throws {
        // GIVEN a view model that has already loaded builds
        let fetchCallCount = Mutex(0)
        let builds = [AppStoreBuild(id: "build-1", version: "1.0.0", uploadedDate: Date(), processingState: nil, isSelectable: true)]

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchBuilds = { _, _ in
                fetchCallCount.withLock { $0 += 1 }
                return builds
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
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
        sut.hasLoadedAvailableBuilds = true

        // WHEN loading available builds again
        await sut.loadAvailableBuilds()

        // THEN the fetch is not called again
        #expect(fetchCallCount.withLock { $0 } == 0)
    }

    @Test
    func loadAvailableBuilds_withNoSelectedVersion_clearsBuildState() async throws {
        // GIVEN a view model with no selected version
        let fetchCalled = Mutex(false)
        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchBuilds = { _, _ in
                fetchCalled.withLock { $0 = true }
                return []
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
        sut.builds = [AppStoreBuild(id: "build-1", version: "1.0.0", uploadedDate: Date(), processingState: nil, isSelectable: true)]

        // WHEN loading available builds without a version
        await sut.loadAvailableBuilds()

        // THEN the fetch is not called and build state is cleared
        #expect(fetchCalled.withLock { $0 } == false)
        #expect(sut.builds.isEmpty)
    }

    @Test
    func loadAvailableBuilds_error_setsErrorMessage() async throws {
        // GIVEN a view model with a failing fetch
        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchBuilds = { _, _ in
                throw NSError(domain: "test", code: 1)
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
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

        // WHEN loading available builds with error
        await sut.loadAvailableBuilds()

        // THEN an error message is set
        #expect(sut.buildLoadError?.contains("Failed to load builds") == true)
        #expect(sut.isLoadingAvailableBuilds == false)
        #expect(sut.hasLoadedAvailableBuilds == false)
    }

    @Test
    func loadAvailableBuilds_clearsSelectedBuildIfNotInList() async throws {
        // GIVEN a view model with a selected build that won't be in the fetched list
        let builds = [AppStoreBuild(id: "build-2", version: "1.0.1", uploadedDate: Date(), processingState: nil, isSelectable: true)]

        let sut = withDependencies {
            $0.appStoreConnectAPI.fetchBuilds = { _, _ in builds }
        } operation: {
            AppDetailViewModel(app: .stub)
        }
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
        sut.selectedBuildID = "build-1" // This won't be in the fetched list

        // WHEN loading available builds
        await sut.loadAvailableBuilds()

        // THEN the selected build ID is cleared since it's not in the list
        #expect(sut.selectedBuildID == nil)
    }

    // MARK: - selectBuild Tests

    @Test
    func selectBuild_updatesSelectedBuildID() {
        // GIVEN a view model
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedBuildID = nil

        // WHEN selecting a build
        sut.selectBuild("build-1")

        // THEN the selected build ID is updated
        #expect(sut.selectedBuildID == "build-1")
    }

    // MARK: - Build Computed Properties Tests

    @Test
    func canSelectBuild_returnsTrueForEditableVersion() {
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

        // WHEN checking if build can be selected
        let canSelect = sut.canSelectBuild

        // THEN it returns true
        #expect(canSelect == true)
    }

    @Test
    func canSelectBuild_returnsFalseForNonEditableVersion() {
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

        // WHEN checking if build can be selected
        let canSelect = sut.canSelectBuild

        // THEN it returns false
        #expect(canSelect == false)
    }

    @Test
    func selectedBuild_returnsCurrentlySelectedBuild() {
        // GIVEN a view model with builds
        let sut = AppDetailViewModel(app: .stub)
        let build = AppStoreBuild(id: "build-1", version: "1.0.0", uploadedDate: Date(), processingState: nil, isSelectable: true)
        sut.builds = [build]
        sut.selectedBuildID = "build-1"

        // WHEN accessing the selected build
        let selected = sut.selectedBuild

        // THEN the correct build is returned
        #expect(selected?.id == "build-1")
        #expect(selected?.version == "1.0.0")
    }

    @Test
    func selectedBuild_returnsNilWhenNoSelection() {
        // GIVEN a view model with builds but no selection
        let sut = AppDetailViewModel(app: .stub)
        let build = AppStoreBuild(id: "build-1", version: "1.0.0", uploadedDate: Date(), processingState: nil, isSelectable: true)
        sut.builds = [build]
        sut.selectedBuildID = nil

        // WHEN accessing the selected build
        let selected = sut.selectedBuild

        // THEN it returns nil
        #expect(selected == nil)
    }

    @Test
    func isBuildSelectionDirty_returnsTrueWhenChanged() {
        // GIVEN a view model with different selected and initial build IDs
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedBuildID = "build-2"
        sut.initialSelectedBuildID = "build-1"

        // WHEN checking if build selection is dirty
        let isDirty = sut.isBuildSelectionDirty

        // THEN it returns true
        #expect(isDirty == true)
    }

    @Test
    func isBuildSelectionDirty_returnsFalseWhenSame() {
        // GIVEN a view model with same selected and initial build IDs
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedBuildID = "build-1"
        sut.initialSelectedBuildID = "build-1"

        // WHEN checking if build selection is dirty
        let isDirty = sut.isBuildSelectionDirty

        // THEN it returns false
        #expect(isDirty == false)
    }

    @Test
    func isBuildSelectionDirty_returnsFalseWhenBothNil() {
        // GIVEN a view model with both IDs nil
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedBuildID = nil
        sut.initialSelectedBuildID = nil

        // WHEN checking if build selection is dirty
        let isDirty = sut.isBuildSelectionDirty

        // THEN it returns false
        #expect(isDirty == false)
    }

    // MARK: - saveChanges with Build Selection Tests

    @Test
    func saveChanges_savesBuildSelectionWhenDirty() async throws {
        // GIVEN a view model with dirty build selection
        let updatedVersionID = Mutex<String?>(nil)
        let updatedBuildID = Mutex<String?>(nil)

        let sut = withDependencies {
            $0.appStoreConnectAPI.updateBuildSelection = { versionID, buildID in
                updatedVersionID.withLock { $0 = versionID }
                updatedBuildID.withLock { $0 = buildID }
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

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
        sut.selectedBuildID = "build-2"
        sut.initialSelectedBuildID = "build-1"

        // WHEN saving changes
        await sut.saveChanges()

        // THEN the build selection is saved
        #expect(updatedVersionID.withLock { $0 } == "version-1")
        #expect(updatedBuildID.withLock { $0 } == "build-2")
        #expect(sut.initialSelectedBuildID == "build-2") // Updated to match
        #expect(sut.actionMessage == "Saved changes.")
    }

    @Test
    func saveChanges_doesNotSaveBuildWhenNotDirty() async throws {
        // GIVEN a view model with clean build selection
        let updateCalled = Mutex(false)

        let sut = withDependencies {
            $0.appStoreConnectAPI.updateBuildSelection = { _, _ in
                updateCalled.withLock { $0 = true }
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

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
        sut.selectedBuildID = "build-1"
        sut.initialSelectedBuildID = "build-1" // Same, not dirty

        // WHEN saving changes
        await sut.saveChanges()

        // THEN the build selection is not saved
        #expect(updateCalled.withLock { $0 } == false)
    }

    @Test
    func saveChanges_savesBothChangelogAndBuild() async throws {
        // GIVEN a view model with both changelog and build changes
        let changelogUpdated = Mutex(false)
        let buildUpdated = Mutex(false)

        let sut = withDependencies {
            $0.appStoreConnectAPI.updateChangelog = { _, _ in
                changelogUpdated.withLock { $0 = true }
            }
            $0.appStoreConnectAPI.updateBuildSelection = { _, _ in
                buildUpdated.withLock { $0 = true }
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

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
        sut.changelogByLocale = ["en-US": "Updated changelog"]
        sut.dirtyLocales = ["en-US"]
        sut.selectedBuildID = "build-2"
        sut.initialSelectedBuildID = "build-1"

        // WHEN saving changes
        await sut.saveChanges()

        // THEN both changelog and build are saved
        #expect(changelogUpdated.withLock { $0 } == true)
        #expect(buildUpdated.withLock { $0 } == true)
        #expect(sut.actionMessage == "Saved changes.")
    }

    @Test
    func saveChanges_withBuildError_showsErrorMessage() async throws {
        // GIVEN a view model with failing build update
        let sut = withDependencies {
            $0.appStoreConnectAPI.updateBuildSelection = { _, _ in
                throw NSError(domain: "test", code: 1)
            }
        } operation: {
            AppDetailViewModel(app: .stub)
        }

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
        sut.selectedBuildID = "build-2"
        sut.initialSelectedBuildID = "build-1"

        // WHEN saving changes
        await sut.saveChanges()

        // THEN an error message is shown
        #expect(sut.errorMessage?.contains("Failed to save changes") == true)
        #expect(sut.isSaving == false)
    }

    @Test
    func canSaveChanges_returnsTrueWhenBuildSelectionDirty() {
        // GIVEN a view model with dirty build selection
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
        sut.selectedBuildID = "build-2"
        sut.initialSelectedBuildID = "build-1"
        sut.isSaving = false
        sut.isCopyingFromPrevious = false

        // WHEN checking if can save changes
        let canSave = sut.canSaveChanges

        // THEN it returns true
        #expect(canSave == true)
    }

    @Test
    func canSaveChanges_returnsFalseWhenCannotSelectBuild() {
        // GIVEN a view model with non-editable version
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
        sut.selectedBuildID = "build-2"
        sut.initialSelectedBuildID = "build-1"

        // WHEN checking if can save changes
        let canSave = sut.canSaveChanges

        // THEN it returns false because build selection is not allowed
        #expect(canSave == false)
    }

    // MARK: - setSelectedVersionID with Build Reset Tests

    @Test
    func setSelectedVersionID_resetsBuildState() {
        // GIVEN a view model with build data
        let sut = AppDetailViewModel(app: .stub)
        sut.selectedVersionID = "version-1"
        sut.builds = [AppStoreBuild(id: "build-1", version: "1.0.0", uploadedDate: Date(), processingState: nil, isSelectable: true)]
        sut.selectedBuildID = "build-1"
        sut.initialSelectedBuildID = "build-1"
        sut.hasLoadedAvailableBuilds = true
        sut.buildLoadError = "Some error"

        // WHEN switching to a different version
        sut.setSelectedVersionID("version-2")

        // THEN the build state is reset
        #expect(sut.builds.isEmpty)
        #expect(sut.selectedBuildID == nil)
        #expect(sut.initialSelectedBuildID == nil)
        #expect(sut.hasLoadedAvailableBuilds == false)
        #expect(sut.buildLoadError == nil)
        #expect(sut.selectedVersionID == "version-2")
    }
}
