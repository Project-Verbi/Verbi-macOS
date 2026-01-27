import SwiftUI
import Dependencies

struct AppDetailView: View {
    let app: AppStoreApp

    @Dependency(\.appStoreConnect)
    private var appStoreConnect

    @State private var versions: [AppStoreVersionSummary] = []
    @State private var selectedVersionID: String?
    @State private var changelogByLocale: [String: String] = [:]
    @State private var changelogIDByLocale: [String: String] = [:]
    @State private var dirtyLocales: Set<String> = []
    @State private var locales: [String] = []
    @State private var selectedLocale: String?
    @State private var showLanguagePicker = false
    @State private var isLoadingVersions = false
    @State private var isLoadingChangelogs = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showNewVersionSheet = false
    @State private var newVersionString = ""
    @State private var actionMessage: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationTitle(app.name)
        .task {
            await loadVersions()
        }
        .task(id: selectedVersionID) {
            await loadChangelogs()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedVersionID) {
            Section {
                sidebarHeader
            }
            
            HStack {
                Text("Versions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showNewVersionSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(platformRawForNewVersion == nil)
                .help(platformRawForNewVersion == nil ? "Version creation unavailable" : "Create new version")
            }
            .padding(.vertical, 6)

            if versions.isEmpty {
                Text("No versions available yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(versions) { version in
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
        .sheet(isPresented: $showNewVersionSheet) {
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

            if isLoadingVersions || isLoadingChangelogs {
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
                if let selectedVersion {
                    Text("Version \(selectedVersion.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if canEditChangelog {
                    Button {
                        Task {
                            await saveCurrentChangelog()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canSaveChangelog)
                }
                if !locales.isEmpty {
                    languagePickerButton
                }
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else if let actionMessage = actionMessage {
                Text(actionMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if selectedVersion == nil {
                Text("Select a version to view changelogs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if locales.isEmpty {
                Text("No localized changelogs available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TextField("What's new", text: selectedChangelogBinding, axis: .vertical)
                    .font(.body)
                    .lineLimit(5...10)
                    .textFieldStyle(.plain)
                    .disabled(!canEditChangelog)
            }
            
            if !canEditChangelog, selectedVersion != nil {
                Text(changelogFooterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 700, alignment: .leading)
    }

    private var languagePickerButton: some View {
        Button {
            showLanguagePicker = true
        } label: {
            HStack(spacing: 6) {
                Text(selectedLocale?.uppercased() ?? "—")
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
        .popover(isPresented: $showLanguagePicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Language")
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(locales, id: \.self) { locale in
                            Button {
                                selectedLocale = locale
                                showLanguagePicker = false
                            } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(displayName(for: locale))
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(locale.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    if locale == selectedLocale {
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
            get: {
                guard let key = selectedLocale, !key.isEmpty else { return "" }
                return changelogByLocale[key] ?? ""
            },
            set: { newValue in
                guard let key = selectedLocale, !key.isEmpty else { return }
                changelogByLocale[key] = newValue
                dirtyLocales.insert(key)
                actionMessage = nil
            }
        )
    }

    private func loadChangelogs() async {
        guard let versionID = selectedVersionID else {
            changelogByLocale = [:]
            changelogIDByLocale = [:]
            locales = []
            selectedLocale = nil
            return
        }

        isLoadingChangelogs = true
        errorMessage = nil
        actionMessage = nil
        changelogByLocale = [:]
        changelogIDByLocale = [:]
        locales = []
        selectedLocale = nil
        dirtyLocales.removeAll()

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

    private func displayName(for locale: String) -> String {
        Locale.current.localizedString(forIdentifier: locale) ?? locale
    }

    private var selectedVersion: AppStoreVersionSummary? {
        versions.first { $0.id == selectedVersionID }
    }

    private var canEditChangelog: Bool {
        selectedVersion?.isEditable ?? false
    }

    private var changelogFooterText: String {
        guard let state = selectedVersion?.state?.uppercased() else {
            return "Changelog editing is unavailable for released versions."
        }
        if state == "PENDING_DEVELOPER_RELEASE" {
            return "Changelog editing is unavailable while the app is pending developer release."
        }
        return "Changelog editing is unavailable for released versions."
    }

    private var canCreateVersion: Bool {
        let normalizedState = selectedVersion?.state?.uppercased()
        return normalizedState != "PENDING_DEVELOPER_RELEASE"
    }

    private var canSaveChangelog: Bool {
        guard let locale = selectedLocale,
              dirtyLocales.contains(locale),
              let localizationID = changelogIDByLocale[locale],
              !localizationID.isEmpty,
              canEditChangelog
        else { return false }
        return !isSaving
    }

    private var platformRawForNewVersion: String? {
        guard canCreateVersion else { return nil }
        return selectedVersion?.platform ?? versions.first?.platform
    }

    private var newVersionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New Version")
                .font(.headline)
            TextField("Version number", text: $newVersionString)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    newVersionString = ""
                    showNewVersionSheet = false
                }
                Button {
                    Task {
                        await createNewVersion()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create")
                    }
                }
                .disabled(isSaving || newVersionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || platformRawForNewVersion == nil)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func loadVersions() async {
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

    private func saveCurrentChangelog() async {
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
            actionMessage = "Changelog updated."
        } catch {
            errorMessage = "Failed to update changelog: \(error.localizedDescription)"
        }

        isSaving = false
    }

    private func createNewVersion() async {
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
}
