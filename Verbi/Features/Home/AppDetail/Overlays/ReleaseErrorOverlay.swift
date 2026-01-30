import SwiftUI

struct ReleaseErrorOverlay: View {
    let errorMessage: String?
    let onDismiss: () -> Void
    
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                
                Text("Release Failed")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                if let message = errorMessage {
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                } else {
                    Text("An error occurred while releasing the version.")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                
                Button("OK") {
                    withAnimation {
                        opacity = 0
                    } completion: {
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 10)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
        .opacity(opacity)
        .task {
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 1
            }
        }
    }
}
