import SwiftUI

@main
struct VerbiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }

        WindowGroup(for: AppStoreApp.self) { $app in
            if let app {
                AppDetailView(app: app)
            } else {
                Text("Select an app to view details.")
                    .frame(minWidth: 320, minHeight: 240)
            }
        }
        .defaultSize(width: 860, height: 640)
    }
}
