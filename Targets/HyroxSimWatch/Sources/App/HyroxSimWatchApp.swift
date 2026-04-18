//
//  HyroxSimWatchApp.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import Observation
import HyroxCore
import HyroxPersistenceApple

/// 폰 미러 시트 상태를 들고 있는 레퍼런스 타입. SwiftUI App struct 에서 @State + [self]
/// 캡처 조합이 WCSession 콜백에서 업데이트 전파가 지연/누락되는 경우가 있어 Observable
/// 클래스로 상태를 외부화한다.
@Observable
@MainActor
final class WatchMirrorPresenter {
    var phoneMirrorModel: PhoneMirrorWorkoutModel?
    var showPhoneMirror: Bool = false
}

@main
struct HyroxSimWatchApp: App {
    @State private var persistence: PersistenceController?
    @State private var syncCoordinator: WatchConnectivitySyncCoordinator?
    @State private var presenter = WatchMirrorPresenter()
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
                    } else if presenter.showPhoneMirror, let model = presenter.phoneMirrorModel {
                        NavigationStack {
                            PhoneMirrorWorkoutView(model: model)
                        }
                    } else {
                        HomeView(persistence: persistence, syncCoordinator: syncCoordinator)
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
        let presenter = presenter
        sync.onWorkoutStarted = { template, origin in
            guard origin == .phone else { return } // 워치 자신이 시작한 운동은 미러 안 함
            let model = PhoneMirrorWorkoutModel(templateName: template.name, syncCoordinator: sync)
            presenter.phoneMirrorModel = model
            presenter.showPhoneMirror = true
        }
        sync.onLiveStateReceived = { state in
            guard state.origin == .phone else { return }
            presenter.phoneMirrorModel?.updateState(state)
        }
        sync.onWorkoutFinished = { origin in
            guard origin == .phone else { return }
            presenter.phoneMirrorModel?.stopHRSession()
            presenter.phoneMirrorModel = nil
            presenter.showPhoneMirror = false
        }
        sync.onReachabilityChanged = { reachable in
            presenter.phoneMirrorModel?.setConnected(reachable)
        }
    }
}
