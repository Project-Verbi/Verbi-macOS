import SwiftUI

struct RefreshButton: View {
    let action: () -> Void
    var isLoading: Bool = false
    
    var body: some View {
        Button {
            action()
        } label: {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isLoading)
        .help("Refresh")
    }
}

#Preview {
    HStack(spacing: 16) {
        RefreshButton(action: {})
        RefreshButton(action: {}, isLoading: true)
    }
    .padding()
}
