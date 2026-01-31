import SwiftUI

struct AppDetailBuildPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let builds: [AppStoreBuild]
    let selectedBuildID: String?
    let isLoading: Bool
    let errorMessage: String?
    let onBuildSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            content
        }
        .frame(minWidth: 360, minHeight: 400)
    }

    private var header: some View {
        HStack {
            Text("Select Build")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if let errorMessage {
            errorView(message: errorMessage)
        } else if builds.isEmpty {
            emptyView
        } else {
            buildsList
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading builds...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            VStack(spacing: 4) {
                Text("Failed to load builds")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.box")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("No builds available")
                    .font(.headline)
                Text("There are no builds for this version.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var buildsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(builds) { build in
                    BuildRow(
                        build: build,
                        isSelected: build.id == selectedBuildID,
                        onTap: {
                            onBuildSelected(build.id)
                            dismiss()
                        }
                    )
                }
            }
        }
    }
}

private struct BuildRow: View {
    let build: AppStoreBuild
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build \(build.version)")
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)

                    if let uploadedDate = build.uploadedDate {
                        Text("Uploaded \(uploadedDate, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let state = build.processingState {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stateColor)
                                .frame(width: 6, height: 6)
                            Text(state.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body)
                        .foregroundStyle(.primary)
                }

                if !build.isSelectable {
                    Image(systemName: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(backgroundColor)
        .disabled(!build.isSelectable)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.3)
        } else {
            return Color.clear
        }
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

#Preview("With Builds") {
    AppDetailBuildPickerSheet(
        builds: [
            AppStoreBuild(
                id: "b1",
                version: "1234",
                uploadedDate: Date(),
                processingState: "VALID",
                isSelectable: true
            ),
            AppStoreBuild(
                id: "b2",
                version: "1233",
                uploadedDate: Date().addingTimeInterval(-86400),
                processingState: "VALID",
                isSelectable: true
            ),
            AppStoreBuild(
                id: "b3",
                version: "1232",
                uploadedDate: Date().addingTimeInterval(-172800),
                processingState: "PROCESSING",
                isSelectable: false
            )
        ],
        selectedBuildID: "b1",
        isLoading: false,
        errorMessage: nil,
        onBuildSelected: { _ in }
    )
}

#Preview("Loading") {
    AppDetailBuildPickerSheet(
        builds: [],
        selectedBuildID: nil,
        isLoading: true,
        errorMessage: nil,
        onBuildSelected: { _ in }
    )
}

#Preview("Error") {
    AppDetailBuildPickerSheet(
        builds: [],
        selectedBuildID: nil,
        isLoading: false,
        errorMessage: "Network connection lost. Please try again later.",
        onBuildSelected: { _ in }
    )
}

#Preview("Empty") {
    AppDetailBuildPickerSheet(
        builds: [],
        selectedBuildID: nil,
        isLoading: false,
        errorMessage: nil,
        onBuildSelected: { _ in }
    )
}
