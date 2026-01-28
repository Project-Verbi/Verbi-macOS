import SwiftUI

struct AppDetailChangelogSectionView: View {
    let selectedVersion: AppStoreVersionSummary?
    let canEditChangelog: Bool
    let canSaveChangelog: Bool
    let isSaving: Bool
    let changelogText: String
    let changelogFooterText: String
    let locales: [String]
    let selectedLocale: String?
    let onChangelogChanged: (String) -> Void
    let onSaveTapped: () -> Void
    let onLanguagePickerTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if selectedVersion == nil {
                Text("Select a version to view changelogs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if locales.isEmpty {
                Text("No localized changelogs available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TextField("What's new", text: changelogBinding, axis: .vertical)
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

    private var header: some View {
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
                    onSaveTapped()
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
                AppDetailLanguagePickerButton(
                    selectedLocale: selectedLocale,
                    onTapped: onLanguagePickerTapped
                )
            }
        }
    }

    private var changelogBinding: Binding<String> {
        Binding(
            get: { changelogText },
            set: { newValue in
                onChangelogChanged(newValue)
            }
        )
    }
}
