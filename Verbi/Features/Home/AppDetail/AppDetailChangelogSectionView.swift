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
    let canCopyFromPrevious: Bool
    let canApplyToAllLanguages: Bool
    let isCopyingFromPrevious: Bool
    let onChangelogChanged: (String) -> Void
    let onLanguagePickerTapped: () -> Void
    let onCopyFromPreviousTapped: () -> Void
    let onApplyToAllTapped: () -> Void

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
                TextEditor(text: changelogBinding)
                    .font(.body)
                    .frame(minHeight: 100, maxHeight: 200)
                    .padding(8)
                    .background(Color.black.opacity(0.1))
                    .scrollContentBackground(.hidden)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(!canEditChangelog || isCopyingFromPrevious)
                    .overlay {
                        if isCopyingFromPrevious {
                            ZStack {
                                Color(nsColor: .windowBackgroundColor).opacity(0.8)
                                ProgressView("Copying from previous version...")
                                    .controlSize(.small)
                            }
                        }
                    }

                if canCopyFromPrevious || canApplyToAllLanguages {
                    HStack(spacing: 8) {
                        if canCopyFromPrevious {
                            copyFromPreviousButton
                        }
                        if canApplyToAllLanguages {
                            applyToAllButton
                        }
                    }
                }
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

    private var copyFromPreviousButton: some View {
        Button {
            onCopyFromPreviousTapped()
        } label: {
            if isCopyingFromPrevious {
                ProgressView()
                    .controlSize(.small)
                    .padding(4)
            } else {
                Image(systemName: "doc.on.doc")
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .disabled(isCopyingFromPrevious)
        .help("Copy the changelog from the previous version")
    }

    private var applyToAllButton: some View {
        Button {
            onApplyToAllTapped()
        } label: {
            Image(systemName: "arrow.left.arrow.right.circle")
                .padding(4)
        }
        .buttonStyle(.plain)
        .disabled(isCopyingFromPrevious)
        .help("Apply current text to all other languages")
    }
}

#Preview("Editable with Copy") {
    AppDetailChangelogSectionView(
        selectedVersion: AppStoreVersionSummary(
            id: "v1",
            version: "2.0.0",
            state: "PREPARE_FOR_SUBMISSION",
            platform: "IOS",
            kind: .current,
            isEditable: true
        ),
        canEditChangelog: true,
        canSaveChangelog: true,
        isSaving: false,
        changelogText: "New features in this version...",
        changelogFooterText: "",
        locales: ["en-US", "de-DE"],
        selectedLocale: "en-US",
        canCopyFromPrevious: true,
        canApplyToAllLanguages: true,
        isCopyingFromPrevious: false,
        onChangelogChanged: { _ in },
        onLanguagePickerTapped: { },
        onCopyFromPreviousTapped: { },
        onApplyToAllTapped: { }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Non-editable") {
    AppDetailChangelogSectionView(
        selectedVersion: AppStoreVersionSummary(
            id: "v1",
            version: "1.0.0",
            state: "READY_FOR_SALE",
            platform: "IOS",
            kind: .current,
            isEditable: false
        ),
        canEditChangelog: false,
        canSaveChangelog: false,
        isSaving: false,
        changelogText: "Released version changelog",
        changelogFooterText: "Changelog editing is unavailable for released versions.",
        locales: ["en-US"],
        selectedLocale: "en-US",
        canCopyFromPrevious: false,
        canApplyToAllLanguages: false,
        isCopyingFromPrevious: false,
        onChangelogChanged: { _ in },
        onLanguagePickerTapped: { },
        onCopyFromPreviousTapped: { },
        onApplyToAllTapped: { }
    )
    .padding()
    .frame(width: 600)
}

#Preview("No Version Selected") {
    AppDetailChangelogSectionView(
        selectedVersion: nil,
        canEditChangelog: false,
        canSaveChangelog: false,
        isSaving: false,
        changelogText: "",
        changelogFooterText: "",
        locales: [],
        selectedLocale: nil,
        canCopyFromPrevious: false,
        canApplyToAllLanguages: false,
        isCopyingFromPrevious: false,
        onChangelogChanged: { _ in },
        onLanguagePickerTapped: { },
        onCopyFromPreviousTapped: { },
        onApplyToAllTapped: { }
    )
    .padding()
    .frame(width: 600)
}
