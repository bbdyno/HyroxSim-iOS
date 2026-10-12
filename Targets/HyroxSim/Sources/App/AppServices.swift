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
    let subscription: SubscriptionStore

    private var isStarted = false
    private var paceDataForegroundObserver: PaceDataForegroundObserver?

    init() throws {
        let screenshotMode = PhoneScreenshotSeeder.isEnabled
        // 저장소를 열기 전에 봐야 한다. 열고 나면 새 설치에도 파일이 생긴다.
        if !screenshotMode {
            SubscriptionStore.recordInstallOrigin(storeExists: SubscriptionStore.defaultStoreExists())
        }
        self.subscription = SubscriptionStore(forcedTier: Self.forcedTier(screenshotMode: screenshotMode))
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

    /// 스크린샷은 모든 기능이 열린 화면을 찍는다. 디버그 빌드에서는
    /// `-HyroxTier free|subscriber|legacyBuyer` 실행 인자로 등급을 고정해 화면을 확인할 수 있다.
    private static func forcedTier(screenshotMode: Bool) -> AccessTier? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-HyroxTier"), arguments.indices.contains(index + 1),
           let tier = AccessTier(rawValue: arguments[index + 1]) {
            return tier
        }
        #endif
        return screenshotMode ? .subscriber : nil
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        // 단위 테스트의 호스트로 뜰 때는 스토어에 손대지 않는다. 앱이 먼저 App Store 에
        // 연결하면 테스트가 여는 로컬 StoreKit 세션이 적용되지 않는다.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            subscription.start()
        }
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
