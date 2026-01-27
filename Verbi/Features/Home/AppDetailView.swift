import SwiftUI
import Dependencies
import Observation


struct AppDetailView: View {
    let app: AppStoreApp

    @State private var viewModel: AppDetailViewModel

    init(app: AppStoreApp) {
        self.app = app
        _viewModel = State(wrappedValue: AppDetailViewModel(app: app))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationTitle(app.name)
        .task {
            await viewModel.loadVersions()
        }
        .task(id: viewModel.selectedVersionID) {
            await viewModel.loadChangelogs()
        }
    }

    private var sidebar: some View {
        List(selection: versionSelectionBinding) {
            Section {
                AppDetailSidebarHeaderView(app: app)
            }

            HStack {
                Text("Versions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.showNewVersionSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.platformRawForNewVersion == nil)
                .help(viewModel.platformRawForNewVersion == nil ? "Version creation unavailable" : "Create new version")
            }
            .padding(.vertical, 6)

            if viewModel.versions.isEmpty {
                Text("No versions available yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.versions) { version in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version \(version.version)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(version.kind.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let state = version.state {
                            Text(state.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(version.id)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
        .sheet(isPresented: $viewModel.showNewVersionSheet) {
            AppDetailNewVersionSheet(
                versionString: $viewModel.newVersionString,
                isSaving: viewModel.isSaving,
                canCreate: !viewModel.newVersionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.platformRawForNewVersion != nil,
                onCancel: {
                    viewModel.newVersionString = ""
                    viewModel.showNewVersionSheet = false
                },
                onCreate: {
                    Task {
                        await viewModel.createNewVersion()
                    }
                }
            )
        }
    }

    private var detailContent: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if viewModel.isLoadingVersions || viewModel.isLoadingChangelogs {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        AppDetailChangelogSectionView(
                            selectedVersion: viewModel.selectedVersion,
                            canEditChangelog: viewModel.canEditChangelog,
                            canSaveChangelog: viewModel.canSaveChangelog,
                            isSaving: viewModel.isSaving,
                            errorMessage: viewModel.errorMessage,
                            changelogText: viewModel.selectedChangelogText,
                            changelogFooterText: viewModel.changelogFooterText,
                            locales: viewModel.locales,
                            selectedLocale: viewModel.selectedLocale,
                            onChangelogChanged: { newValue in
                                viewModel.updateSelectedChangelogText(newValue)
                            },
                            onSaveTapped: {
                                Task {
                                    await viewModel.saveCurrentChangelog()
                                }
                            },
                            onLanguagePickerTapped: {
                                viewModel.showLanguagePicker = true
                            }
                        )
                        .popover(isPresented: $viewModel.showLanguagePicker, arrowEdge: .bottom) {
                            AppDetailLanguagePickerPopover(
                                locales: viewModel.locales,
                                selectedLocale: viewModel.selectedLocale,
                                displayName: { locale in
                                    viewModel.displayName(for: locale)
                                },
                                onLocaleSelected: { locale in
                                    viewModel.selectedLocale = locale
                                    viewModel.showLanguagePicker = false
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionSelectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedVersionID },
            set: { newValue in
                viewModel.setSelectedVersionID(newValue)
            }
        )
    }
}

@MainActor
@Observable
final class AppDetailViewModel {
    let app: AppStoreApp

    @ObservationIgnored
    @Dependency(\.appStoreConnect)
    private var appStoreConnect

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
        return selectedVersion?.platform ?? versions.first?.platform
    }

    var selectedChangelogText: String {
        guard let key = selectedLocale, !key.isEmpty else { return "" }
        return changelogByLocale[key] ?? ""
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
            let fetched = try await appStoreConnect.fetchAppVersions(app.id)
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
            let changelogs = try await appStoreConnect.fetchChangelogs(versionID)
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
            try await appStoreConnect.updateChangelog(localizationID, text)
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

    func createNewVersion() async {
        guard let platformRaw = platformRawForNewVersion else { return }
        let trimmed = newVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        errorMessage = nil
        actionMessage = nil

        do {
            let newVersion = try await appStoreConnect.createAppVersion(app.id, trimmed, platformRaw)
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
