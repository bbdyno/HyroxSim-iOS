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
        wireGarminPostPairingResync()
    }

    // hello.ack from the watch is our only confirmation that the watch app
    // is open and has accepted pairing. CIQ does not buffer messages for an
    // offline watch app, so any `template.upsert` / `goal.set` sent before
    // the watch app was opened was silently dropped — re-push everything
    // here so state created pre-pairing finally lands.
    private func wireGarminPostPairingResync() {
        let overrideStore = TemplateGoalOverrideStore()
        GarminBridge.shared.onHelloAck = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Custom user templates: full push (template.upsert + goal.set).
                let customs = (try? self.persistence.fetchAllTemplates()) ?? []
                self.garminTemplateSyncService.pushAll(customs)
                // Built-in HYROX presets: goal-only re-push so user-saved
                // PacePlanner targets survive a re-pair. The watch
                // generates the preset structure itself, so we deliberately
                // skip template.upsert to keep MY WORKOUTS clean.
                for preset in HyroxPresets.all {
                    let resolved = overrideStore.resolvedTemplate(from: preset)
                    self.garminTemplateSyncService.pushGoal(for: resolved)
                }
            }
        }
    }
}
