import SwiftUI

struct AppDetailLanguagePickerButton: View {
    let selectedLocale: String?
    let onTapped: () -> Void

    var body: some View {
        Button {
            onTapped()
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
    }
}

struct AppDetailLanguagePickerPopover: View {
    let locales: [String]
    let selectedLocale: String?
    let displayName: (String) -> String
    let onLocaleSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Language")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(locales, id: \.self) { locale in
                        Button {
                            onLocaleSelected(locale)
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(locale))
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
