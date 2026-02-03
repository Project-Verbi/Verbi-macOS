import SwiftUI

struct AppDetailBuildSectionView: View {
    let selectedVersion: AppStoreVersionSummary?
    let canSelectBuild: Bool
    let selectedBuild: AppStoreBuild?
    let isLoading: Bool
    let errorMessage: String?
    let onSelectBuildTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if selectedVersion == nil {
                Text("Select a version to view build information.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading builds...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                BuildErrorView(message: errorMessage)
            } else if let selectedBuild {
                BuildInfoRow(build: selectedBuild, canSelect: canSelectBuild, onTap: onSelectBuildTapped)
            } else {
                EmptyBuildView(canSelect: canSelectBuild, onTap: onSelectBuildTapped)
            }
        }
        .frame(maxWidth: 700, alignment: .leading)
    }

    private var header: some View {
        HStack {
            Text("Build")
                .font(.title3)
                .fontWeight(.semibold)
            if let selectedVersion {
                Text("Version \(selectedVersion.version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct BuildInfoRow: View {
    let build: AppStoreBuild
    let canSelect: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build \(build.version)")
                        .font(.body)
                        .fontWeight(.medium)

                    if let uploadedDate = build.uploadedDate {
                        Text("Uploaded \(uploadedDate, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let state = build.processingState {
                        Text(state.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2)
                            .foregroundStyle(stateColor)
                    }
                }

                Spacer()

                if canSelect {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
    }

    private var stateColor: Color {
        guard let state = build.processingState?.uppercased() else { return .secondary }
        switch state {
        case "VALID":
            return .green
        case "PROCESSING", "VALIDATING":
            return .orange
        case "FAILED":
            return .red
        default:
            return .secondary
        }
    }
}

private struct EmptyBuildView: View {
    let canSelect: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "cube.box")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("No build selected")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(canSelect ? "Tap to select a build" : "Build selection unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if canSelect {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
    }
}

private struct BuildErrorView: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Failed to load builds")
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("With Build") {
    AppDetailBuildSectionView(
        selectedVersion: AppStoreVersionSummary(
            id: "v1",
            version: "2.0.0",
            state: "PREPARE_FOR_SUBMISSION",
            platform: "IOS",
            kind: .current,
            isEditable: true
        ),
        canSelectBuild: true,
        selectedBuild: AppStoreBuild(
            id: "b1",
            version: "1234",
            uploadedDate: Date(),
            processingState: "VALID",
            isSelectable: true
        ),
        isLoading: false,
        errorMessage: nil,
        onSelectBuildTapped: {}
    )
    .padding()
    .frame(width: 600)
}

#Preview("Loading") {
    AppDetailBuildSectionView(
        selectedVersion: AppStoreVersionSummary(
            id: "v1",
            version: "2.0.0",
            state: "PREPARE_FOR_SUBMISSION",
            platform: "IOS",
            kind: .current,
            isEditable: true
        ),
        canSelectBuild: true,
        selectedBuild: nil,
        isLoading: true,
        errorMessage: nil,
        onSelectBuildTapped: {}
    )
    .padding()
    .frame(width: 600)
}

#Preview("Error") {
    AppDetailBuildSectionView(
        selectedVersion: AppStoreVersionSummary(
            id: "v1",
            version: "2.0.0",
            state: "PREPARE_FOR_SUBMISSION",
            platform: "IOS",
            kind: .current,
            isEditable: true
        ),
        canSelectBuild: true,
        selectedBuild: nil,
        isLoading: false,
        errorMessage: "Network connection lost. Please try again.",
        onSelectBuildTapped: {}
    )
    .padding()
    .frame(width: 600)
}

#Preview("Empty - Selectable") {
    AppDetailBuildSectionView(
        selectedVersion: AppStoreVersionSummary(
            id: "v1",
            version: "2.0.0",
            state: "PREPARE_FOR_SUBMISSION",
            platform: "IOS",
            kind: .current,
            isEditable: true
        ),
        canSelectBuild: true,
        selectedBuild: nil,
        isLoading: false,
        errorMessage: nil,
        onSelectBuildTapped: {}
    )
    .padding()
    .frame(width: 600)
}

#Preview("Empty - Non-selectable") {
    AppDetailBuildSectionView(
        selectedVersion: AppStoreVersionSummary(
            id: "v1",
            version: "1.0.0",
            state: "READY_FOR_SALE",
            platform: "IOS",
            kind: .current,
            isEditable: false
        ),
        canSelectBuild: false,
        selectedBuild: nil,
        isLoading: false,
        errorMessage: nil,
        onSelectBuildTapped: {}
    )
    .padding()
    .frame(width: 600)
}

#Preview("No Version Selected") {
    AppDetailBuildSectionView(
        selectedVersion: nil,
        canSelectBuild: false,
        selectedBuild: nil,
        isLoading: false,
        errorMessage: nil,
        onSelectBuildTapped: {}
    )
    .padding()
    .frame(width: 600)
}
