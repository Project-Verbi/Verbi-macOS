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
        .overlay {
            Group {
                switch viewModel.releaseState {
                case .idle:
                    EmptyView()
                case .inProgress:
                    ReleaseProgressOverlay()
                case .success(let versionNumber):
                    ReleaseCelebrationOverlay(
                        versionNumber: versionNumber,
                        onDismiss: {
                            viewModel.releaseState = .idle
                        }
                    )
                case .error(let message):
                    ReleaseErrorOverlay(
                        errorMessage: message,
                        onDismiss: {
                            viewModel.releaseState = .idle
                        }
                    )
                }
            }
        }
        .overlay {
            Group {
                switch viewModel.submitForReviewState {
                case .idle:
                    EmptyView()
                case .inProgress:
                    SubmitForReviewProgressOverlay()
                case .success(let versionNumber):
                    SubmitForReviewSuccessOverlay(
                        versionNumber: versionNumber,
                        onDismiss: {
                            viewModel.submitForReviewState = .idle
                        }
                    )
                case .error(let message):
                    SubmitForReviewErrorOverlay(
                        errorMessage: message,
                        onDismiss: {
                            viewModel.submitForReviewState = .idle
                        }
                    )
                }
            }
        }
        .task {
            await viewModel.loadVersions()
        }
        .task(id: viewModel.selectedVersionID) {
            await viewModel.loadChangelogs()
        }
        .task(id: viewModel.selectedVersionID) {
            await viewModel.loadSelectedBuild()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Apply to All Languages", isPresented: $viewModel.showApplyToAllConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.localesToBeOverridden = []
            }
            Button("Apply", role: .destructive) {
                viewModel.applyCurrentTextToAllLanguages()
            }
        } message: {
            if viewModel.localesToBeOverridden.isEmpty {
                Text("This will apply the current text to all other languages.")
            } else {
                let localeNames = viewModel.localesToBeOverridden
                    .map { viewModel.displayName(for: $0) }
                    .joined(separator: ", ")
                Text("This will override existing text for: \(localeNames)")
            }
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
                            changelogText: viewModel.selectedChangelogText,
                            changelogFooterText: viewModel.changelogFooterText,
                            locales: viewModel.locales,
                            selectedLocale: viewModel.selectedLocale,
                            canCopyFromPrevious: viewModel.canCopyChangelogFromPreviousVersion,
                            canApplyToAllLanguages: viewModel.canApplyToAllLanguages,
                            isCopyingFromPrevious: viewModel.isCopyingFromPrevious,
                            onChangelogChanged: { newValue in
                                viewModel.updateSelectedChangelogText(newValue)
                            },
                            onLanguagePickerTapped: {
                                viewModel.showLanguagePicker = true
                            },
                            onCopyFromPreviousTapped: {
                                Task {
                                    await viewModel.copyChangelogFromPreviousVersion()
                                }
                            },
                            onApplyToAllTapped: {
                                viewModel.localesToBeOverridden = viewModel.computeLocalesToBeOverridden()
                                viewModel.showApplyToAllConfirmation = true
                            }
                        )
                        .sheet(isPresented: $viewModel.showLanguagePicker) {
                            AppDetailLanguagePickerSheet(
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

                        AppDetailBuildSectionView(
                            selectedVersion: viewModel.selectedVersion,
                            canSelectBuild: viewModel.canSelectBuild,
                            selectedBuild: viewModel.selectedBuild,
                            isLoading: viewModel.isLoadingBuilds,
                            errorMessage: viewModel.buildLoadError,
                            onSelectBuildTapped: {
                                viewModel.showBuildPicker = true
                                Task {
                                    await viewModel.loadAvailableBuilds()
                                }
                            }
                        )
                        .sheet(isPresented: $viewModel.showBuildPicker) {
                            AppDetailBuildPickerSheet(
                                builds: viewModel.builds,
                                selectedBuildID: viewModel.selectedBuildID,
                                isLoading: viewModel.isLoadingAvailableBuilds,
                                errorMessage: viewModel.buildLoadError,
                                onBuildSelected: { buildID in
                                    viewModel.selectBuild(buildID)
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RefreshButton {
                    Task {
                        await viewModel.refresh()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                if viewModel.canEditChangelog || viewModel.canSelectBuild {
                    Button {
                        Task {
                            await viewModel.saveChanges()
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
                    .disabled(!viewModel.canSaveChanges)
                }
                if viewModel.canSubmitForReview {
                    Button {
                        viewModel.showSubmitForReviewConfirmation = true
                    } label: {
                        if viewModel.isSubmittingForReview {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(viewModel.submitForReviewButtonTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(viewModel.isSubmittingForReview)
                    .padding(.leading, 12)
                }
                if viewModel.canReleaseVersion {
                    Button {
                        viewModel.showReleaseConfirmation = true
                    } label: {
                        if viewModel.isReleasing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(viewModel.releaseButtonTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isReleasing)
                    .padding(.leading, 12)
                }
            }
            .padding(.trailing, 28)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .alert("Release to App Store", isPresented: $viewModel.showReleaseConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Release", role: .destructive) {
                Task {
                    await viewModel.releaseVersion()
                }
            }
        } message: {
            Text("Are you sure you want to release this version to the App Store? This action cannot be undone.")
        }
        .sheet(isPresented: $viewModel.showSubmitForReviewConfirmation) {
            SubmitForReviewConfirmationSheet(
                releaseOption: $viewModel.selectedReleaseOption,
                isPhasedReleaseEnabled: $viewModel.isPhasedReleaseEnabled,
                versionNumber: viewModel.selectedVersion?.version,
                onCancel: {
                    viewModel.showSubmitForReviewConfirmation = false
                },
                onSubmit: {
                    viewModel.showSubmitForReviewConfirmation = false
                    Task {
                        await viewModel.submitForReview()
                    }
                }
            )
        }
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
