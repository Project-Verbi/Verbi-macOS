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
                            },
                            onCopyFromPreviousTapped: {
                                Task {
                                    await viewModel.copyChangelogFromPreviousVersion()
                                }
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
