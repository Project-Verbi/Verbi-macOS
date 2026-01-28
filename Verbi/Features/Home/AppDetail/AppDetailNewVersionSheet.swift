import SwiftUI

struct AppDetailNewVersionSheet: View {
    @Binding var versionString: String
    let isSaving: Bool
    let canCreate: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New Version")
                .font(.headline)
            TextField("Version number", text: $versionString)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button {
                    onCreate()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create")
                    }
                }
                .disabled(isSaving || !canCreate)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
