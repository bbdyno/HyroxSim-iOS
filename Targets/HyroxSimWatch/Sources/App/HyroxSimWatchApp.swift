import SwiftUI
import HyroxKit

@main
struct HyroxSimWatchApp: App {
    @State private var persistence: PersistenceController?

    var body: some Scene {
        WindowGroup {
            Group {
                if let persistence {
                    HomeView(persistence: persistence)
                } else {
                    ProgressView()
                }
            }
            .onAppear {
                if persistence == nil {
                    persistence = try? PersistenceController()
                }
            }
        }
    }
}
