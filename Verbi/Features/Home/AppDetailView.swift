import SwiftUI
import Dependencies

struct AppDetailView: View {
    let app: AppStoreApp

    @Dependency(\.appStoreConnect)
    private var appStoreConnect

    @State private var changelogByLocale: [String: String] = [:]
    @State private var locales: [String] = []
    @State private var selectedLocale: String?
    @State private var showLanguagePicker = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .task {
            await loadChangelogs()
        }
    }

    private var sidebar: some View {
        List {
            Section {
                sidebarHeader
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Localizations")
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

            if isLoading {
                ProgressView("Loading changelogs...")
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
        .navigationTitle(app.name)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            .frame(width: 64, height: 64)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            Text(app.name)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(2)

            Text(app.bundleId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                if let version = app.version {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                if let state = app.versionState {
                    Text(state.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
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
                Spacer()
                if !locales.isEmpty {
                    languagePickerButton
                }
            }

            if isLoading {
                ProgressView("Loading changelogs...")
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else if locales.isEmpty {
                Text("No localized changelogs available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TextField("What's new", text: selectedChangelogBinding, axis: .vertical)
                    .font(.body)
                    .lineLimit(5...10)
                    .textFieldStyle(.plain)
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
            }
        )
    }

    private func loadChangelogs() async {
        isLoading = true
        errorMessage = nil

        do {
            let changelogs = try await appStoreConnect.fetchChangelogs(app.id)
            changelogByLocale = Dictionary(uniqueKeysWithValues: changelogs.map { ($0.locale, $0.text) })
            locales = changelogs.map(\.locale).sorted { displayName(for: $0) < displayName(for: $1) }
            if selectedLocale == nil {
                selectedLocale = locales.first
            }
        } catch {
            errorMessage = "Failed to load changelogs: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func displayName(for locale: String) -> String {
        Locale.current.localizedString(forIdentifier: locale) ?? locale
    }
}
