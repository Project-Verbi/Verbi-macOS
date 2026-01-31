import ConfettiSwiftUI
import SwiftUI

struct ReleaseCelebrationOverlay: View {
    let versionNumber: String?
    let onDismiss: () -> Void
    
    @State private var opacity: Double = 0
    @State private var trigger = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                
                Text("Congratulations!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                if let version = versionNumber {
                    Text("Version \(version) has been released successfully.")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Your version has been released successfully.")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
        .opacity(opacity)
        .confettiCannon(trigger: $trigger)
        .task {
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 1
            }
            trigger = true
            try? await Task.sleep(for: .seconds(5))
            
            withAnimation {
                opacity = 0
            } completion: {
                onDismiss()
            }
        }
    }
}
