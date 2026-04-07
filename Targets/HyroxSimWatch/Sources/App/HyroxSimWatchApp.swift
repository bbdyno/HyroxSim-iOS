//
//  HyroxSimWatchApp.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

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
                    HomeView(persistence: persistence, syncCoordinator: syncCoordinator)
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
                        s.syncAllCompletedWorkouts()
                        syncCoordinator = s
                    }
                }
            }
        }
    }
}
