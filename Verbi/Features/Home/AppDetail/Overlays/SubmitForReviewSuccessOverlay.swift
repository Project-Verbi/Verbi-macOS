import SwiftUI

struct SubmitForReviewSuccessOverlay: View {
    let versionNumber: String?
    let onDismiss: () -> Void
    
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                
                Text("Submitted for Review!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                if let version = versionNumber {
                    Text("Version \(version) has been submitted for review.")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Your version has been submitted for review.")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                
                Text("You'll receive an email notification once the review is complete.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
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
            try? await Task.sleep(for: .seconds(4))
            
            withAnimation {
                opacity = 0
            } completion: {
                onDismiss()
            }
        }
    }
}

#Preview {
    SubmitForReviewSuccessOverlay(versionNumber: "1.2.0", onDismiss: {})
}
