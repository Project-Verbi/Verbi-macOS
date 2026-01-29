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

struct AppDetailLanguagePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let locales: [String]
    let selectedLocale: String?
    let displayName: (String) -> String
    let onLocaleSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Language")
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

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(locales, id: \.self) { locale in
                        LocaleRow(
                            locale: locale,
                            displayName: displayName(locale),
                            isSelected: locale == selectedLocale,
                            onTap: { onLocaleSelected(locale) }
                        )
                    }
                }
            }
        }
        .frame(minWidth: 300, minHeight: 400)
    }
}

struct LocaleRow: View {
    let locale: String
    let displayName: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.body)
                    Text(locale.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(backgroundColor)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.3)
        } else {
            return Color.clear
        }
    }
}
