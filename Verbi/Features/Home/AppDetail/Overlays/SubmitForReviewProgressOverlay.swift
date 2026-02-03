import SwiftUI

struct SubmitForReviewProgressOverlay: View {
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.5)
                
                Text("Submitting for Review...")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
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
