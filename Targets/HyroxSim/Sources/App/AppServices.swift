//
//  AppServices.swift
//  HyroxSim
//
//  Created by bbdyno on 4/8/26.
//

import Foundation
import HyroxCore
import HyroxPersistenceApple
import UIKit

@MainActor
final class AppServices {
    let persistence: PersistenceController
    let syncCoordinator: WatchConnectivitySyncCoordinator
    let workoutMirrorController: WorkoutMirrorController
    let garminImportService: GarminImportService
    let garminTemplateSyncService: GarminTemplateSyncService
    let paceData: PaceDataRepository

    private var isStarted = false
    private var paceDataForegroundObserver: PaceDataForegroundObserver?

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
        self.paceData = PaceDataRepository()
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
        startPaceDataUpdates()
    }

    // Competition-record tables are read from the bundled snapshot or the downloaded
    // cache, so decoding them is pure disk work: warm it off the main thread rather
    // than making the first planner screen pay for it.
    //
    // Both the app-level and the scene-level activation notifications are observed.
    // This app uses scenes, where `applicationDidBecomeActive(_:)` is never called on
    // the delegate, and the two notifications differ across OS versions in ways not
    // worth depending on. Duplicate triggers cost nothing: the repository collapses
    // concurrent calls into one attempt and skips entirely until the next check is due.
    private func startPaceDataUpdates() {
        paceData.warmUp()

        // Screenshot runs must render the snapshot that shipped in the binary, and must
        // not depend on a network the CI machine may not have.
        guard !PhoneScreenshotSeeder.isEnabled else { return }

        paceData.refreshInBackground()

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.didBecomeActiveNotification,
            UIScene.didActivateNotification
        ]

        let tokens = names.map { name in
            // The repository is captured instead of `self`: it is `Sendable` and owns
            // its own locking, so the observer needs no hop back to the main actor.
            center.addObserver(forName: name, object: nil, queue: nil) { [repository = paceData] _ in
                repository.refreshInBackground()
            }
        }
        paceDataForegroundObserver = PaceDataForegroundObserver(tokens: tokens)
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

/// Holds block-based notification observers for as long as ``AppServices`` lives.
///
/// Observers registered with a closure are not unregistered automatically, and doing
/// it from `AppServices.deinit` would mean reaching into main-actor state from a
/// non-isolated context. Parking the tokens on a plain class keeps the teardown
/// ordinary.
private final class PaceDataForegroundObserver {

    private let tokens: [NSObjectProtocol]

    init(tokens: [NSObjectProtocol]) {
        self.tokens = tokens
    }

    deinit {
        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
    }
}
