//
//  AppServices.swift
//  HyroxSim
//
//  Created by bbdyno on 4/8/26.
//

import Foundation
import HyroxCore
import HyroxPersistenceApple

@MainActor
final class AppServices {
    let persistence: PersistenceController
    let syncCoordinator: WatchConnectivitySyncCoordinator
    let workoutMirrorController: WorkoutMirrorController

    private var isStarted = false

    init() throws {
        let screenshotMode = PhoneScreenshotSeeder.isEnabled
        self.persistence = try PersistenceController(inMemory: screenshotMode)
        self.syncCoordinator = WatchConnectivitySyncCoordinator(persistence: persistence)
        self.workoutMirrorController = WorkoutMirrorController()
        if screenshotMode {
            PhoneScreenshotSeeder.seed(into: persistence)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        syncCoordinator.activate()
        workoutMirrorController.activate()
    }
}
