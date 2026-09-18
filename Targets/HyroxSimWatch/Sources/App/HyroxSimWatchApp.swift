//
//  HyroxSimWatchApp.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import Observation
import WatchKit
import HealthKit
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

    /// 미러 종료 — HR 릴레이 세션을 정리하고 홈으로 되돌린다.
    func dismissMirror() {
        phoneMirrorModel?.stopHRSession()
        phoneMirrorModel = nil
        showPhoneMirror = false
    }
}

/// 워치 자체 운동이 진행 중인지 나타내는 앱 수준 스위치.
/// 폰이 보낸 운동 시작 신호로 진행 중인 로컬 운동 화면/모델이 교체되는 것을 막는다.
@Observable
@MainActor
final class WatchLocalWorkoutActivity {
    static let shared = WatchLocalWorkoutActivity()

    private(set) var isActive: Bool = false

    func begin() { isActive = true }
    func end() { isActive = false }
}

/// 크래시로 남아 있는 HKWorkoutSession 을 정리하기 위한 델리게이트.
/// 정리하지 않으면 다음 운동에서 새 세션이 시작되지 않을 수 있다.
@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private let healthStore = HKHealthStore()

    func handleActiveWorkoutRecovery() {
        healthStore.recoverActiveWorkoutSession { session, error in
            if let error {
                print("[WatchRecovery] recoverActiveWorkoutSession failed: \(error)")
            }
            // 세션을 이어받지 않고 종료만 한다 — 기록 복구는 WorkoutCheckpointStore 가 담당.
            session?.end()
        }
    }
}

@main
struct HyroxSimWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @State private var persistence: PersistenceController?
    @State private var syncCoordinator: WatchConnectivitySyncCoordinator?
    @State private var presenter = WatchMirrorPresenter()
    @State private var automationNavigationPath = NavigationPath()
    @State private var recoveredWorkout: CompletedWorkout?

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
                            // 폰이 새 운동을 시작해 모델이 교체되면 onAppear 가 다시 돌도록 id 고정.
                            PhoneMirrorWorkoutView(model: model)
                                .id(ObjectIdentifier(model))
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
                        // 세션 활성화 전에 복구해야 활성화 직후 동기화가 복구본까지 폰에 보낸다.
                        recoverCheckpointIfNeeded(persistence: p)
                        let s = WatchConnectivitySyncCoordinator(persistence: p)
                        s.activate()
                        setupLiveSync(s)
                        syncCoordinator = s
                    }
                }
            }
            .sheet(item: $recoveredWorkout) { workout in
                NavigationStack {
                    SummaryView(workout: workout, onDone: { recoveredWorkout = nil })
                }
            }
        }
    }

    /// 크래시·강제 종료로 남은 체크포인트를 완료 기록으로 저장하고 요약으로 안내한다.
    /// 저장에 실패하면 체크포인트를 남겨 다음 실행에서 다시 시도한다.
    /// 폰 전송은 하지 않는다 — 활성화 직후 `syncAllCompletedWorkouts()` 가 저장된 기록을 모두 보낸다.
    private func recoverCheckpointIfNeeded(persistence: PersistenceController) {
        guard !WatchScreenshotSeeder.isEnabled, automationTemplate == nil else { return }
        guard let checkpoint = WorkoutCheckpointStore.shared.load() else { return }
        guard let workout = checkpoint.makeCompletedWorkout() else {
            WorkoutCheckpointStore.shared.clear()
            return
        }
        do {
            try persistence.saveCompletedWorkout(workout)
            WorkoutCheckpointStore.shared.clear()
            NotificationCenter.default.post(name: .hyroxCompletedWorkoutsUpdated, object: nil)
            // 첫 onAppear 와 같은 사이클에 시트를 올리면 표시가 누락될 수 있어 한 틱 미룬다.
            Task { @MainActor in recoveredWorkout = workout }
        } catch {
            print("[WatchRecovery] Failed to save recovered workout: \(error)")
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
            // 워치에서 운동 중이면 로컬 운동이 우선 — 미러로 화면/모델을 빼앗기면 기록이 사라진다.
            guard !WatchLocalWorkoutActivity.shared.isActive else {
                print("[WatchMirror] Ignored phone workout start — local workout in progress")
                return
            }
            presenter.phoneMirrorModel?.stopHRSession()
            let model = PhoneMirrorWorkoutModel(templateName: template.name, syncCoordinator: sync)
            // presenter → model → onFinished 순환을 끊기 위해 약한 참조로 잡는다
            model.onFinished = { [weak mirrorPresenter = presenter] in mirrorPresenter?.dismissMirror() }
            presenter.phoneMirrorModel = model
            presenter.showPhoneMirror = true
        }
        sync.onLiveStateReceived = { state in
            guard state.origin == .phone else { return }
            presenter.phoneMirrorModel?.updateState(state)
        }
        sync.onWorkoutFinished = { origin in
            guard origin == .phone else { return }
            presenter.dismissMirror()
        }
        sync.onReachabilityChanged = { reachable in
            presenter.phoneMirrorModel?.setConnected(reachable)
        }
    }
}
