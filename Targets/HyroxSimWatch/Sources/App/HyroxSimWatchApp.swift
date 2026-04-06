import SwiftUI
import HyroxKit

@main
struct HyroxSimWatchApp: App {
    @State private var persistence: PersistenceController?
    @State private var syncCoordinator: WatchConnectivitySyncCoordinator?

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
                    let p = try? PersistenceController()
                    persistence = p
                    if let p {
                        let s = WatchConnectivitySyncCoordinator(persistence: p)
                        s.activate()
                        syncCoordinator = s
                    }
                }
            }
        }
    }
}
