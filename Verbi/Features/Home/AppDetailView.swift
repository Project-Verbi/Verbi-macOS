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
                sidebarHeader
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
            newVersionSheet
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
                        changelogSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: app.iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(nsColor: .systemBlue),
                                        Color(nsColor: .systemTeal)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    @unknown default:
                        Color(nsColor: .controlBackgroundColor)
                    }
                }
                .frame(width: 52, height: 52)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    Text(app.bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var changelogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Changelog")
                    .font(.title3)
                    .fontWeight(.semibold)
                if let selectedVersion = viewModel.selectedVersion {
                    Text("Version \(selectedVersion.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.canEditChangelog {
                    Button {
                        Task {
                            await viewModel.saveCurrentChangelog()
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canSaveChangelog)
                }
                if !viewModel.locales.isEmpty {
                    languagePickerButton
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else if viewModel.selectedVersion == nil {
                Text("Select a version to view changelogs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.locales.isEmpty {
                Text("No localized changelogs available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TextField("What's new", text: selectedChangelogBinding, axis: .vertical)
                    .font(.body)
                    .lineLimit(5...10)
                    .textFieldStyle(.plain)
                    .disabled(!viewModel.canEditChangelog)
            }

            if !viewModel.canEditChangelog, viewModel.selectedVersion != nil {
                Text(viewModel.changelogFooterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 700, alignment: .leading)
    }

    private var languagePickerButton: some View {
        Button {
            viewModel.showLanguagePicker = true
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.selectedLocale?.uppercased() ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $viewModel.showLanguagePicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Language")
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.locales, id: \.self) { locale in
                            Button {
                                viewModel.selectedLocale = locale
                                viewModel.showLanguagePicker = false
                            } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(viewModel.displayName(for: locale))
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(locale.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if locale == viewModel.selectedLocale {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                    }

                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minWidth: 220, maxWidth: 260, maxHeight: 280)
            }
            .padding(16)
        }
    }

    private var selectedChangelogBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedChangelogText },
            set: { newValue in
                viewModel.updateSelectedChangelogText(newValue)
            }
        )
    }

    private var versionSelectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedVersionID },
            set: { newValue in
                viewModel.setSelectedVersionID(newValue)
            }
        )
    }

    private var newVersionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New Version")
                .font(.headline)
            TextField("Version number", text: $viewModel.newVersionString)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.newVersionString = ""
                    viewModel.showNewVersionSheet = false
                }
                Button {
                    Task {
                        await viewModel.createNewVersion()
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create")
                    }
                }
                .disabled(viewModel.isSaving || viewModel.newVersionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.platformRawForNewVersion == nil)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
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
