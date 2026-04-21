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
    let garminImportService: GarminImportService
    let garminTemplateSyncService: GarminTemplateSyncService

    private var isStarted = false

    init() throws {
        let screenshotMode = PhoneScreenshotSeeder.isEnabled
        let persistence = try PersistenceController(inMemory: screenshotMode)
        self.persistence = persistence
        self.syncCoordinator = WatchConnectivitySyncCoordinator(persistence: persistence)
        self.workoutMirrorController = WorkoutMirrorController()
        self.garminImportService = GarminImportService(
            makePersistence: { persistence }
        )
        self.garminTemplateSyncService = GarminTemplateSyncService()
        if screenshotMode {
            PhoneScreenshotSeeder.seed(into: persistence)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        syncCoordinator.activate()
        workoutMirrorController.activate()
        garminImportService.start()
    }
}
