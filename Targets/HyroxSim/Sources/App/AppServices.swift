//
//  AppServices.swift
//  HyroxSim
//
//  Created by Codex on 4/8/26.
//

import Foundation
import HyroxKit

@MainActor
final class AppServices {
    let persistence: PersistenceController
    let syncCoordinator: WatchConnectivitySyncCoordinator
    let workoutMirrorController: WorkoutMirrorController

    private var isStarted = false

    init() throws {
        self.persistence = try PersistenceController()
        self.syncCoordinator = WatchConnectivitySyncCoordinator(persistence: persistence)
        self.workoutMirrorController = WorkoutMirrorController()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        syncCoordinator.activate()
        workoutMirrorController.activate()
    }
}
