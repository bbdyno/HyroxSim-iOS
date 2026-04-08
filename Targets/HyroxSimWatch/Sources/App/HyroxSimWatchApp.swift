//
//  HyroxSimWatchApp.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import HyroxCore
import HyroxPersistenceApple

@main
struct HyroxSimWatchApp: App {
    @State private var persistence: PersistenceController?
    @State private var syncCoordinator: WatchConnectivitySyncCoordinator?
    @State private var phoneMirrorModel: PhoneMirrorWorkoutModel?
    @State private var showPhoneMirror = false
    @State private var automationNavigationPath = NavigationPath()

    var body: some Scene {
        WindowGroup {
            Group {
                if let persistence {
                    if screenshotScenario == .summary {
                        NavigationStack {
                            SummaryView(workout: ScreenshotFixtures.watchSummaryWorkout)
                        }
                    } else if screenshotScenario == .active {
                        NavigationStack {
                            WatchScreenshotActiveWorkoutView()
                        }
                    } else if let template = automationTemplate {
                        NavigationStack(path: $automationNavigationPath) {
                            ActiveWorkoutView(
                                template: template,
                                persistence: persistence,
                                syncCoordinator: syncCoordinator,
                                navigationPath: $automationNavigationPath
                            )
                        }
                    } else {
                        HomeView(persistence: persistence, syncCoordinator: syncCoordinator)
                            .sheet(isPresented: $showPhoneMirror) {
                                if let model = phoneMirrorModel {
                                    NavigationStack {
                                        PhoneMirrorWorkoutView(model: model)
                                    }
                                }
                            }
                    }
                } else {
                    ProgressView()
                }
            }
            .onAppear {
                if persistence == nil {
                    let p = try? PersistenceController(inMemory: WatchScreenshotSeeder.isEnabled)
                    persistence = p
                    if let p, WatchScreenshotSeeder.isEnabled {
                        WatchScreenshotSeeder.seed(into: p)
                    }
                    if let p {
                        let s = WatchConnectivitySyncCoordinator(persistence: p)
                        s.activate()
                        setupLiveSync(s)
                        syncCoordinator = s
                    }
                }
            }
        }
    }

    private var screenshotScenario: WatchScreenshotScenario? {
        WatchScreenshotScenario.current
    }

    private var automationTemplate: WorkoutTemplate? {
        guard ProcessInfo.processInfo.arguments.contains("UITestAutoStartWatchWorkout") else {
            return nil
        }

        return ScreenshotFixtures.liveMirrorTemplate
    }

    private func setupLiveSync(_ sync: WatchConnectivitySyncCoordinator) {
        sync.onWorkoutStarted = { [self] template, origin in
            guard origin == .phone else { return } // 워치 자신이 시작한 운동은 미러 안 함
            let model = PhoneMirrorWorkoutModel(templateName: template.name, syncCoordinator: sync)
            phoneMirrorModel = model
            showPhoneMirror = true
        }
        sync.onLiveStateReceived = { [self] state in
            guard state.origin == .phone else { return }
            phoneMirrorModel?.updateState(state)
        }
        sync.onWorkoutFinished = { [self] origin in
            guard origin == .phone else { return }
            phoneMirrorModel?.stopHRSession()
            phoneMirrorModel = nil
            showPhoneMirror = false
        }
        sync.onReachabilityChanged = { [self] reachable in
            phoneMirrorModel?.setConnected(reachable)
        }
    }
}
