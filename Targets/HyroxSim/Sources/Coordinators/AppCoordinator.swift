//
//  AppCoordinator.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore
import HyroxPersistenceApple

@MainActor
public final class AppCoordinator {

    private let window: UIWindow
    /// Home-tab nav controller. Named `navigationController` for legacy
    /// compatibility — all push destinations (Detail, History, etc.) live here.
    private let navigationController: UINavigationController
    private let settingsNavigationController: UINavigationController
    private let tabBarController: UITabBarController
    let persistence: PersistenceController
    private let syncCoordinator: WatchConnectivitySyncCoordinator
    private let workoutMirrorController: WorkoutMirrorController
    private let garminTemplateSyncService: GarminTemplateSyncService
    /// 진척 화면의 퍼센타일 기준. 번들 스냅샷이든 내려받은 표든 여기서 나온다.
    private let paceData: PaceDataRepository
    private let templateGoalOverrideStore = TemplateGoalOverrideStore()
    private let heartRateProfile = HeartRateProfile()
    private let checkpointStore: WorkoutCheckpointStore
    private let forceDisconnectedMirrorUITest = ProcessInfo.processInfo.arguments.contains("UITestWatchMirrorDisconnected")
    private let isMirrorUITestScenario = ProcessInfo.processInfo.arguments.contains("UITestWatchMirror")

    /// 워치 상태가 이 시간 이상 안 들어오면 "끊김" 으로 표시한다.
    private static let mirrorDisconnectThreshold: TimeInterval = 12
    /// 이 시간 이상 무수신이면 미러를 자동 정리한다(화면에 갇히지 않도록).
    private static let mirrorAutoCloseThreshold: TimeInterval = 180
    /// 이보다 짧은 중단 기록은 복구하지 않는다(시작 직후 종료 등).
    private static let minimumRecoverableDuration: TimeInterval = 30

    /// All modal presentations (builder sheet, live mirror) use the tab bar
    /// as host so they work regardless of which tab is foregrounded.
    private var presentationHost: UIViewController { tabBarController }

    /// 지금 실제로 화면 맨 위에 있는 VC. 모달이 떠 있어도 present 가 조용히 실패하지 않도록 한다.
    private var topmostPresentedViewController: UIViewController {
        var top: UIViewController = presentationHost
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// 최상단 VC 위에 present. 전환 애니메이션 중이면 끝난 뒤에 올린다
    /// (전환 중 present 는 조용히 무시되기 때문).
    private func presentOnTop(_ viewController: UIViewController, animated: Bool = true) {
        let host = topmostPresentedViewController
        if let coordinator = host.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self else { return }
                self.topmostPresentedViewController.present(viewController, animated: animated)
            }
        } else {
            host.present(viewController, animated: animated)
        }
    }

    init(
        window: UIWindow,
        services: AppServices,
        checkpointStore: WorkoutCheckpointStore = .shared
    ) {
        self.window = window
        self.navigationController = UINavigationController()
        self.settingsNavigationController = UINavigationController()
        self.tabBarController = UITabBarController()
        self.checkpointStore = checkpointStore
        self.persistence = services.persistence
        self.syncCoordinator = services.syncCoordinator
        self.workoutMirrorController = services.workoutMirrorController
        self.garminTemplateSyncService = services.garminTemplateSyncService
        self.paceData = services.paceData

        // Global dark nav bar appearance
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = DesignTokens.Color.background
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 34, weight: .black)
        ]
        for nav in [navigationController, settingsNavigationController] {
            nav.navigationBar.standardAppearance = navAppearance
            nav.navigationBar.scrollEdgeAppearance = navAppearance
            nav.navigationBar.compactAppearance = navAppearance
            nav.navigationBar.tintColor = DesignTokens.Color.accent
            nav.navigationBar.prefersLargeTitles = true
        }

        // Tab bar appearance (dark + gold accent)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = DesignTokens.Color.background
        tabBarController.tabBar.standardAppearance = tabAppearance
        tabBarController.tabBar.scrollEdgeAppearance = tabAppearance
        tabBarController.tabBar.tintColor = DesignTokens.Color.accent
        tabBarController.tabBar.unselectedItemTintColor = DesignTokens.Color.textSecondary
    }

    public func start() {
        let homeVC = makeHomeViewController()
        navigationController.viewControllers = [homeVC]
        navigationController.tabBarItem = UITabBarItem(
            title: HyroxSimStrings.Localizable.Tab.home,
            image: UIImage(systemName: "house.fill"),
            tag: 0
        )

        let settingsVC = makeSettingsViewController()
        settingsNavigationController.viewControllers = [settingsVC]
        settingsNavigationController.tabBarItem = UITabBarItem(
            title: HyroxSimStrings.Localizable.Tab.settings,
            image: UIImage(systemName: "gearshape.fill"),
            tag: 1
        )

        tabBarController.viewControllers = [navigationController, settingsNavigationController]
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()

        syncCoordinator.onReceiveCompletedWorkout = { [weak self] _ in
            self?.refreshHomeIfVisible()
        }
        syncCoordinator.onReceiveTemplate = { [weak self] _ in
            self?.refreshHomeIfVisible()
        }
        syncCoordinator.onReceiveTemplateDeleted = { [weak self] _ in
            self?.refreshHomeIfVisible()
        }
        // 원격 삭제는 에코 루프를 막으려고 알림을 쏘지 않으므로 여기서 직접 새로고침한다.
        syncCoordinator.onReceiveCompletedWorkoutDeleted = { [weak self] _ in
            self?.refreshHomeIfVisible()
        }
        // 워치에서 대회 목표가 올라오는 일은 (아직) 없지만, 메시지는 양방향이라 받으면
        // 홈을 새로고침한다. 앱 시작 시 워치로 밀어 주는 일은 세션 활성화 콜백이 맡는다.
        syncCoordinator.onReceiveRaceTarget = { [weak self] _ in
            self?.refreshHomeIfVisible()
        }

        // 워치 운동 미러링 - HealthKit mirrored session 경로
        workoutMirrorController.onWorkoutStarted = { [weak self] template, origin in
            guard origin == .watch else { return }
            self?.handleWatchWorkoutStarted(template: template)
        }
        workoutMirrorController.onLiveStateReceived = { [weak self] state in
            guard let self, state.origin == .watch else { return }
            if self.activeMirrorVC == nil {
                let template = self.workoutMirrorController.currentTemplate
                    ?? Self.placeholderTemplate(for: state)
                self.showLiveMirror(template: template)
            }
            self.applyLiveMirrorState(state)
        }
        workoutMirrorController.onWorkoutFinished = { [weak self] origin in
            guard origin == .watch else { return }
            self?.handleWatchWorkoutFinished()
        }
        workoutMirrorController.onConnectionChanged = { [weak self] connected in
            if self?.forceDisconnectedMirrorUITest == true {
                self?.activeMirrorVC?.showDisconnected()
                return
            }
            if connected {
                self?.activeMirrorVC?.showReconnected()
            } else {
                self?.activeMirrorVC?.showDisconnected()
            }
        }

        // WatchConnectivity fallback 경로
        syncCoordinator.onWorkoutStarted = { [weak self] template, origin in
            guard origin == .watch else { return } // 폰 자신이 시작한 운동은 미러 안 함
            self?.handleWatchWorkoutStarted(template: template)
        }
        syncCoordinator.onLiveStateReceived = { [weak self] state in
            guard let self, state.origin == .watch else { return }
            if self.activeMirrorVC == nil {
                self.showLiveMirror(template: Self.placeholderTemplate(for: state))
            }
            self.applyLiveMirrorState(state)
        }
        syncCoordinator.onWorkoutFinished = { [weak self] origin in
            guard origin == .watch else { return }
            self?.handleWatchWorkoutFinished()
        }
        syncCoordinator.onReachabilityChanged = { [weak self] reachable in
            guard let self, !self.workoutMirrorController.hasActiveWorkout else { return }
            if self.forceDisconnectedMirrorUITest {
                self.activeMirrorVC?.showDisconnected()
                return
            }
            if reachable {
                self.activeMirrorVC?.showReconnected()
            } else {
                self.activeMirrorVC?.showDisconnected()
            }
        }

        if let template = workoutMirrorController.currentTemplate {
            showLiveMirror(template: template)
            if let state = workoutMirrorController.currentState {
                applyLiveMirrorState(state)
            }
            if forceDisconnectedMirrorUITest {
                activeMirrorVC?.showDisconnected()
            } else if !workoutMirrorController.isConnected {
                activeMirrorVC?.showDisconnected()
            }
        }

        recoverInterruptedWorkoutIfNeeded()
        applyUITestScenarioIfNeeded()
        applyScreenshotScenarioIfNeeded()
    }

    // MARK: - 워치 실시간 미러

    /// present 가 완료된 미러.
    private var liveMirrorVC: LiveWorkoutMirrorViewController?
    /// present 를 요청했지만 아직 완료 콜백이 오지 않은 미러.
    /// present 가 실패하면 이 값이 남지 않도록 정리해, 이후 미러가 영영 안 뜨는 상태를 막는다.
    private var pendingMirrorVC: LiveWorkoutMirrorViewController?
    /// 폰 운동 때문에 미러를 보류해 둔 템플릿. 폰 운동이 끝나면 이어서 띄운다.
    private var deferredMirrorTemplate: WorkoutTemplate?
    private var isDismissingMirror = false
    /// 사용자가 미러를 직접 닫은 뒤에는, 다음 운동이 시작될 때까지 자동으로 다시 띄우지 않는다.
    /// (0.5초마다 들어오는 상태 때문에 닫자마자 다시 뜨는 것을 막는다.)
    private var isMirrorSuppressed = false
    private var mirrorShownAt: Date?
    private var mirrorWatchdogTimer: Timer?

    /// 화면에 떠 있거나 뜨는 중인 미러.
    private var activeMirrorVC: LiveWorkoutMirrorViewController? {
        liveMirrorVC ?? pendingMirrorVC
    }

    /// 폰에서 진행 중인 운동 화면. 있으면 미러를 띄우지 않는다.
    private var activeWorkoutVC: ActiveWorkoutViewController?

    private var isPhoneWorkoutRunning: Bool { activeWorkoutVC != nil }

    /// 워치 운동이 새로 시작됐다 — 사용자가 직접 닫았던 이력은 리셋하고 미러를 띄운다.
    private func handleWatchWorkoutStarted(template: WorkoutTemplate) {
        isMirrorSuppressed = false
        showLiveMirror(template: template)
    }

    /// 워치 운동 종료. HealthKit / WatchConnectivity 양쪽에서 중복 호출돼도 안전하다.
    private func handleWatchWorkoutFinished() {
        isMirrorSuppressed = false
        dismissLiveMirror()
    }

    private func showLiveMirror(template: WorkoutTemplate) {
        guard activeMirrorVC == nil, !isDismissingMirror, !isMirrorSuppressed else { return }

        // 폰 운동 중에는 미러를 띄우지 않고 보류한다 — 진행 중인 폰 운동을 가리거나
        // 정리 전에 화면이 바뀌면 기록이 날아갈 수 있다.
        guard !isPhoneWorkoutRunning else {
            deferredMirrorTemplate = template
            return
        }

        let vc = LiveWorkoutMirrorViewController()
        vc.delegate = self
        pendingMirrorVC = vc
        mirrorShownAt = Date()

        // 모달(플래너/빌더/요약 등)이 떠 있으면 tabBarController.present 는 조용히 실패한다.
        // 항상 최상단 VC 위에 present 하고, 성공 시점(완료 콜백)에 소유권을 옮긴다.
        topmostPresentedViewController.present(vc, animated: true) { [weak self] in
            guard let self else { return }
            guard self.pendingMirrorVC === vc else {
                // present 도중에 종료 신호가 와서 이미 정리된 경우 — 그대로 닫는다.
                if vc.presentingViewController != nil { vc.dismiss(animated: false) }
                return
            }
            self.pendingMirrorVC = nil
            self.liveMirrorVC = vc
        }
        startMirrorWatchdog()
    }

    /// 종료 신호는 HealthKit / WatchConnectivity 두 경로로 중복 도착한다.
    /// 두 번 와도 한 번만 처리되도록 멱등하게 만든다.
    private func dismissLiveMirror() {
        deferredMirrorTemplate = nil
        stopMirrorWatchdog()

        guard let mirror = activeMirrorVC else {
            // 미러가 없으면 아무것도 닫지 않는다.
            // (예전에는 여기서 presentationHost.dismiss 를 불러 진행 중인 폰 운동 화면까지
            //  닫아버렸고, 정리·저장 전에 화면이 사라져 기록이 유실될 수 있었다.)
            refreshHomeIfVisible()
            return
        }
        guard !isDismissingMirror else { return }
        isDismissingMirror = true

        let finishDismissal = { [weak self] in
            guard let self else { return }
            self.liveMirrorVC = nil
            self.pendingMirrorVC = nil
            self.isDismissingMirror = false
            self.mirrorShownAt = nil
            self.refreshHomeIfVisible()
        }

        let dismissMirror = {
            mirror.dismiss(animated: true, completion: finishDismissal)
        }

        if let presented = mirror.presentedViewController {
            presented.dismiss(animated: false, completion: dismissMirror)
        } else {
            dismissMirror()
        }
    }

    private static func placeholderTemplate(for state: LiveWorkoutState) -> WorkoutTemplate {
        WorkoutTemplate(name: state.templateName, segments: [.run(distanceMeters: 1000)])
    }

    private func applyLiveMirrorState(_ state: LiveWorkoutState) {
        activeMirrorVC?.updateState(state)
        if forceDisconnectedMirrorUITest {
            activeMirrorVC?.showDisconnected()
        }
    }

    // MARK: - 미러 무수신 워치독

    /// 워치 상태가 한동안 안 들어오면 "끊김" 으로 표시하고, 아주 오래 끊기면 미러를 정리한다.
    /// UI 테스트/스크린샷 시나리오는 실제 워치 없이 한 번만 상태를 주입하므로 제외한다.
    private func startMirrorWatchdog() {
        guard !isMirrorUITestScenario, PhoneScreenshotScenario.current == nil else { return }
        stopMirrorWatchdog()
        mirrorWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkMirrorStaleness() }
        }
    }

    private func stopMirrorWatchdog() {
        mirrorWatchdogTimer?.invalidate()
        mirrorWatchdogTimer = nil
    }

    private func checkMirrorStaleness() {
        guard let mirror = activeMirrorVC else {
            stopMirrorWatchdog()
            return
        }
        // 연결 판단 기준은 "마지막으로 워치 상태를 받은 시각".
        let now = Date()
        let reference = mirror.lastStateReceivedAt ?? mirrorShownAt ?? now
        let idle = now.timeIntervalSince(reference)

        if idle > Self.mirrorAutoCloseThreshold {
            workoutMirrorController.abandonActiveWorkout()
            dismissLiveMirror()
            return
        }
        if idle > Self.mirrorDisconnectThreshold {
            mirror.showDisconnected()
        }
    }

    private func refreshHomeIfVisible() {
        // Trigger viewWillAppear-equivalent reload by popping to root if possible,
        // or just set a flag. Simplest: call reload if the VC exposes it.
        // HomeViewController reloads in viewWillAppear, so next appearance is fine.
        // For immediate update, post a notification.
        NotificationCenter.default.post(name: .syncDataUpdated, object: nil)
    }

    private func applyUITestScenarioIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("UITestWatchMirror") else { return }

        let template = WorkoutTemplate(
            name: "UI Test Mirror",
            segments: [
                .run(distanceMeters: 1000),
                .roxZone(),
                .station(.skiErg, target: .distance(meters: 1000))
            ]
        )
        let state = LiveWorkoutState(
            segmentLabel: "RUN 1 / 1",
            segmentSubLabel: nil,
            currentDisplayTitle: "RUNNING 1",
            nextDisplayTitle: nil,
            segmentElapsedText: "01:23",
            totalElapsedText: "0:12:34",
            paceText: "4'12\" /km",
            distanceText: "820 m",
            heartRateText: "168",
            heartRateZoneRaw: HeartRateZone.z4.rawValue,
            goalText: "06:00",
            goalDeltaText: "-4:37",
            isOverGoal: false,
            stationNameText: nil,
            stationTargetText: nil,
            accentKindRaw: "run",
            isPaused: false,
            isFinished: false,
            isLastSegment: false,
            gpsStrong: true,
            gpsActive: true,
            templateName: template.name,
            totalSegmentCount: template.segments.count,
            currentSegmentIndex: 0,
            origin: .watch
        )

        showLiveMirror(template: template)
        applyLiveMirrorState(state)

        if forceDisconnectedMirrorUITest {
            activeMirrorVC?.showDisconnected()
        }
    }

    private func applyScreenshotScenarioIfNeeded() {
        guard let scenario = PhoneScreenshotScenario.current else { return }

        switch scenario {
        case .home:
            return
        case .builder:
            presentBuilder(startingFrom: ScreenshotFixtures.customTemplate, animated: false)
        case .pacePlanner:
            let preset = HyroxPresets.menProSingle
            guard preset.isStandardHyroxCourse,
                  let planner = try? PaceReferenceLoader.loadPacePlanner() else { return }
            let vc = PacePlannerViewController(
                template: preset,
                planner: planner,
                goalOverrideStore: templateGoalOverrideStore
            )
            navigationController.setViewControllers([vc], animated: false)
        case .history:
            navigationController.pushViewController(makeHistoryViewController(), animated: false)
        case .summary:
            showSummary(for: ScreenshotFixtures.summaryWorkout, fromHistory: true, animated: false)
        case .mirror:
            showLiveMirror(template: ScreenshotFixtures.liveMirrorTemplate)
            activeMirrorVC?.updateState(ScreenshotFixtures.liveMirrorState)
        }
    }

    // MARK: - 중단된 폰 운동 복구

    /// 앱이 운동 중에 강제 종료/크래시된 경우, 마지막 체크포인트를 완료 기록으로 저장한다.
    /// 복구할 운동이 없으면 이전 세션에서 남은 Live Activity 만 정리한다.
    private func recoverInterruptedWorkoutIfNeeded() {
        // UI 테스트/스크린샷 시나리오는 고정된 화면을 기대하므로 건드리지 않는다.
        guard !isMirrorUITestScenario, PhoneScreenshotScenario.current == nil else { return }

        // 워치 운동이 미러링 중이면 그쪽 Live Activity 를 죽이면 안 된다.
        let hasMirrorWorkout = workoutMirrorController.hasActiveWorkout
        let checkpoint = checkpointStore.load()

        // 이전 세션에서 멈춘 채 잠금화면에 남은 Live Activity 정리.
        if !hasMirrorWorkout {
            ActiveWorkoutViewModel.endStaleActivities()
        }

        guard let checkpoint else { return }
        // 같은 체크포인트로 두 번 복구하지 않도록 먼저 지운다.
        checkpointStore.clear()

        // 시작 직후 종료처럼 너무 짧은 기록은 히스토리를 어지럽히기만 한다.
        guard checkpoint.workout.totalDuration >= Self.minimumRecoverableDuration else { return }

        do {
            // 같은 id 로 두 번 저장돼도 1개만 남도록 upsert.
            let saved = try persistence.upsertCompletedWorkout(checkpoint.workout)
            guard saved else { return }
            refreshHomeIfVisible()
            presentRecoveredWorkoutNotice(for: checkpoint.workout)
        } catch {
            print("[Recovery] Failed to save interrupted workout: \(error)")
        }
    }

    private func presentRecoveredWorkoutNotice(for workout: CompletedWorkout) {
        // 윈도우가 막 key 가 된 직후라 다음 런루프에서 present 한다.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = DarkAlertController(
                title: "Workout recovered",
                message: """
                \(workout.templateName) — \(DurationFormatter.hms(workout.totalDuration))
                The app closed mid-workout, so your progress up to that point was saved.
                """
            )
            alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.ok, style: .normal, handler: nil))
            self.presentOnTop(alert)
        }
    }

    // MARK: - Factory

    private func makeHomeViewController() -> UIViewController {
        let vm = HomeViewModel(persistence: persistence)
        let vc = HomeViewController(viewModel: vm)
        vc.delegate = self
        return vc
    }

    private func makeSettingsViewController() -> UIViewController {
        let vc = SettingsViewController()
        vc.delegate = self
        return vc
    }

    private func makeHistoryViewController() -> UIViewController {
        let vm = HistoryViewModel(persistence: persistence)
        let vc = HistoryViewController(viewModel: vm)
        vc.delegate = self
        return vc
    }

    private func makeProgressViewController() -> UIViewController {
        // v4 표가 아직 준비되지 않았으면 nil 이 넘어가고, 분석은 번들 v3 버킷으로 떨어진다.
        let vm = ProgressViewModel(
            persistence: persistence,
            paceData: paceData.currentProvider()
        )
        return ProgressViewController(viewModel: vm)
    }

    private func showTemplateDetail(_ template: WorkoutTemplate) {
        let resolvedTemplate = templateWithOverrides(template)
        let vc = TemplateDetailViewController(template: resolvedTemplate) { [weak self] updatedTemplate in
            self?.persistTemplateChanges(updatedTemplate)
        }
        vc.delegate = self
        navigationController.pushViewController(vc, animated: true)
    }

    private func presentBuilderEntry() {
        let vc = BuilderEntrySheetViewController()
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        nav.applyDarkTheme()
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        presentationHost.present(nav, animated: true)
    }

    private func presentBuilder(startingFrom template: WorkoutTemplate?, animated: Bool = true) {
        let resolvedTemplate = template.map(templateWithOverrides)
        let vm = WorkoutBuilderViewModel(startingFrom: resolvedTemplate, persistence: persistence)
        let vc = WorkoutBuilderViewController(viewModel: vm)
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        nav.applyDarkTheme()
        nav.modalPresentationStyle = .formSheet
        presentationHost.present(nav, animated: animated)
    }
}

// MARK: - HomeViewControllerDelegate

extension AppCoordinator: HomeViewControllerDelegate {

    func homeDidSelectTemplate(_ template: WorkoutTemplate) {
        showTemplateDetail(template)
    }

    func homeDidRequestDeleteTemplate(_ template: WorkoutTemplate) {
        deleteCustomTemplate(template)
    }

    func homeDidTapNewWorkout() {
        presentBuilderEntry()
    }

    func homeDidTapHistory() {
        let vc = makeHistoryViewController()
        navigationController.pushViewController(vc, animated: true)
    }

    func homeDidTapRaceDay() {
        // 대회 당일 도구는 등록한 대회(있으면)와 그 디비전 프리셋을 기준으로 연다.
        let race = try? persistence.fetchUpcomingRaceTarget()
        let division = race?.division ?? .menOpenSingle
        let preset = templateGoalOverrideStore.resolvedTemplate(from: HyroxPresets.template(for: division))
        RaceDayEntry.present(
            from: topmostPresentedViewController,
            context: RaceDayContext(template: preset, raceTarget: race)
        )
    }

    func homeDidTapProgress() {
        navigationController.pushViewController(makeProgressViewController(), animated: true)
    }

    func homeDidSelectRecent(_ workout: CompletedWorkout) {
        showSummary(for: workout, fromHistory: true)
    }

    func homeDidTapRaceTarget(_ target: RaceTarget?) {
        presentRaceTargetEditor(for: target)
    }
}

// MARK: - 내 대회

extension AppCoordinator {

    private func presentRaceTargetEditor(for target: RaceTarget?) {
        let vc = RaceTargetEditorViewController(
            target: target,
            // 새 대회는 직전에 등록해 둔 대회의 디비전을 기본값으로 제안한다.
            defaultDivision: target?.division ?? lastKnownRaceDivision()
        )
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        nav.applyDarkTheme()
        nav.modalPresentationStyle = .formSheet
        presentationHost.present(nav, animated: true)
    }

    private func lastKnownRaceDivision() -> HyroxDivision? {
        // `fetchRaceTargets()` 는 날짜 오름차순 — 뒤에서부터 보면 가장 나중 대회다.
        let stored = (try? persistence.fetchRaceTargets()) ?? []
        return stored.reversed().compactMap(\.division).first
    }
}

// MARK: - RaceTargetEditorViewControllerDelegate

extension AppCoordinator: RaceTargetEditorViewControllerDelegate {

    func raceTargetEditorDidCancel() {
        presentationHost.dismiss(animated: true)
    }

    func raceTargetEditorDidSave(_ target: RaceTarget) {
        do {
            try persistence.upsertRaceTarget(target)
        } catch {
            print("[RaceTarget] save failed: \(error)")
        }
        try? syncCoordinator.sendRaceTarget(target)
        presentationHost.dismiss(animated: true)
        refreshHomeIfVisible()
    }

    func raceTargetEditorDidRequestDelete(_ target: RaceTarget) {
        try? persistence.deleteRaceTarget(id: target.id)
        // 대회가 사라지면 그 대회에 묶인 분담 계획도 남길 이유가 없다.
        TeamSplitPlanStore().remove(raceTargetId: target.id)
        // 삭제 전용 동기화 메시지가 아직 없다. 남아 있는 대회 중 가장 가까운 것을 다시
        // 보내 워치가 최신 대회를 잡게 하고, 하나도 없으면 워치는 날짜가 지날 때까지
        // 마지막 값을 들고 있는다. (TODO: `raceTargetDeleted` 메시지 종류 추가)
        syncCoordinator.syncAllRaceTargets()
        presentationHost.dismiss(animated: true)
        refreshHomeIfVisible()
    }
}

// MARK: - SettingsViewControllerDelegate

extension AppCoordinator: SettingsViewControllerDelegate {

    func settingsDidTapGarminPairing() {
        let vc = GarminPairingViewController()
        settingsNavigationController.pushViewController(vc, animated: true)
    }

    func settingsDidTapOpenSource() {
        let vc = OpenSourceLicensesViewController()
        settingsNavigationController.pushViewController(vc, animated: true)
    }
}

// MARK: - HistoryViewControllerDelegate

extension AppCoordinator: HistoryViewControllerDelegate {

    func historyDidSelect(_ workout: CompletedWorkout) {
        showSummary(for: workout, fromHistory: true)
    }
}

// MARK: - BuilderEntrySheetDelegate

extension AppCoordinator: BuilderEntrySheetDelegate {

    func builderEntryDidSelectPreset(_ template: WorkoutTemplate) {
        presentationHost.dismiss(animated: true) { [self] in
            presentBuilder(startingFrom: template)
        }
    }

    func builderEntryDidSelectScratch() {
        presentationHost.dismiss(animated: true) { [self] in
            presentBuilder(startingFrom: nil)
        }
    }
}

// MARK: - WorkoutBuilderViewControllerDelegate

extension AppCoordinator: WorkoutBuilderViewControllerDelegate {

    func builderDidCancel() {
        presentationHost.dismiss(animated: true)
    }

    func builderDidRequestStart(template: WorkoutTemplate) {
        presentationHost.dismiss(animated: true) { [self] in
            startWorkout(template: template)
        }
    }

    func builderDidSaveTemplate(_ template: WorkoutTemplate) {
        try? syncCoordinator.sendTemplate(template)
        garminTemplateSyncService.push(template)
        presentationHost.dismiss(animated: true)
        refreshHomeIfVisible()
    }
}

// MARK: - Workout Lifecycle

extension AppCoordinator {

    func startWorkout(template: WorkoutTemplate) {
        beginWorkout(template: templateWithOverrides(template))
    }

    private func beginWorkout(template: WorkoutTemplate) {
        // 워치 운동이 진행/미러링 중이면 폰에서 새 운동을 시작하지 않는다.
        // (시작하면 워치 쪽 운동이 조용히 사라진다.)
        guard !workoutMirrorController.hasActiveWorkout, activeMirrorVC == nil else {
            presentWatchWorkoutInProgressAlert()
            return
        }
        guard !isPhoneWorkoutRunning else { return }

        let location = CoreLocationAdapter()
        let heartRate = HealthKitHeartRateAdapter()
        let vm = ActiveWorkoutViewModel(
            template: template,
            locationStream: location,
            heartRateStream: heartRate,
            persistence: persistence,
            maxHeartRate: heartRateProfile.observedMax ?? 190,
            syncCoordinator: syncCoordinator,
            checkpointStore: checkpointStore
        )
        let vc = ActiveWorkoutViewController(viewModel: vm)

        vm.errorHandler = { [weak self] error in
            self?.presentWorkoutError(error)
        }
        vm.finishHandler = { [weak self] completed in
            self?.dismissWorkout(showingSummaryFor: completed)
        }
        vm.cancelHandler = { [weak self] in
            self?.dismissWorkout(showingSummaryFor: nil)
        }

        vc.modalPresentationStyle = .fullScreen
        activeWorkoutVC = vc
        topmostPresentedViewController.present(vc, animated: true)
    }

    /// 센서 오류는 내부 덤프(`"\(error)"`) 대신 사용자용 문구로 보여준다.
    private func presentWorkoutError(_ error: Error) {
        let message: String
        if let sensorError = error as? SensorError {
            message = sensorError.userFacingMessage
        } else {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        let alert = DarkAlertController(
            title: HyroxSimStrings.Localizable.Alert.Error.title,
            message: message
        )
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.ok, style: .normal, handler: nil))
        presentOnTop(alert)
    }

    private func presentWatchWorkoutInProgressAlert() {
        let alert = DarkAlertController(
            title: "Watch workout in progress",
            message: "A workout is already running on your Apple Watch. End it before starting a new one on your phone."
        )
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.ok, style: .normal, handler: nil))
        presentOnTop(alert)
    }

    private func dismissWorkout(showingSummaryFor workout: CompletedWorkout?) {
        let workoutVC = activeWorkoutVC
        activeWorkoutVC = nil
        let presenter = workoutVC ?? presentationHost.presentedViewController
        let completion: () -> Void = { [weak self] in
            guard let self else { return }
            if let workout {
                self.showSummary(for: workout, fromHistory: false)
            }
            // 폰 운동 때문에 보류해 둔 워치 미러가 있으면 이제 띄운다.
            if let deferred = self.deferredMirrorTemplate {
                self.deferredMirrorTemplate = nil
                if self.workoutMirrorController.hasActiveWorkout {
                    self.showLiveMirror(template: deferred)
                }
            }
        }

        guard let presenter, presenter.presentingViewController != nil else {
            completion()
            return
        }
        presenter.dismiss(animated: true, completion: completion)
    }

    /// 등록해 둔 다가오는 대회의 목표 시간을 격차 분석 기준으로 쓴다.
    /// 디비전이 다르거나 목표가 없으면 nil — 이때는 운동에 찍힌 구간 목표 합을 쓴다.
    private func raceGapTarget(for workout: CompletedWorkout) -> GapTarget? {
        guard
            let race = try? persistence.fetchUpcomingRaceTarget(),
            let goal = race.goalDurationSeconds,
            goal > 0,
            race.division == workout.division
        else { return nil }
        return .finishTime(seconds: TimeInterval(goal))
    }

    func showSummary(for workout: CompletedWorkout, fromHistory: Bool, animated: Bool = true) {
        // 방금 끝난 운동이면 관측 최대 심박을 먼저 갱신해 존 표시에 반영한다.
        if !fromHistory { heartRateProfile.record(workout) }
        let vm = WorkoutSummaryViewModel(
            workout: workout,
            maxHeartRate: heartRateProfile.observedMax,
            gapTarget: raceGapTarget(for: workout)
        )
        let vc = WorkoutSummaryViewController(viewModel: vm)
        vc.delegate = self
        if fromHistory {
            navigationController.pushViewController(vc, animated: animated)
        } else {
            // After workout: present modally (no "back" destination — builder was dismissed)
            let nav = UINavigationController(rootViewController: vc)
            nav.applyDarkTheme()
            topmostPresentedViewController.present(nav, animated: animated)
        }
    }

    private func templateWithOverrides(_ template: WorkoutTemplate) -> WorkoutTemplate {
        templateGoalOverrideStore.resolvedTemplate(from: template)
    }

    private func persistTemplateChanges(_ template: WorkoutTemplate) {
        if template.isBuiltIn {
            templateGoalOverrideStore.save(template)
            try? syncCoordinator.sendTemplate(template)
            garminTemplateSyncService.push(template)
            return
        }

        try? persistence.upsertTemplate(template)
        try? syncCoordinator.sendTemplate(template)
        garminTemplateSyncService.push(template)
        refreshHomeIfVisible()
    }

    /// 커스텀 템플릿 삭제 — 폰 SwiftData + 워치(WatchConnectivity) + 가민(ConnectIQ).
    /// 빌트인 프리셋은 영속화되어 있지 않으므로 호출 측에서 걸러져야 함.
    /// 모든 외부 sink(`try?`/`silent drop`) 처리 — 한쪽이 실패해도 나머지는 진행.
    fileprivate func deleteCustomTemplate(_ template: WorkoutTemplate) {
        guard !template.isBuiltIn else { return }
        try? persistence.deleteTemplate(id: template.id)
        try? syncCoordinator.sendTemplateDeleted(id: template.id)
        garminTemplateSyncService.delete(id: template.id)
        refreshHomeIfVisible()
    }
}

// MARK: - WorkoutSummaryViewControllerDelegate

extension AppCoordinator: WorkoutSummaryViewControllerDelegate {

    func summaryDidTapDone() {
        if presentationHost.presentedViewController != nil {
            presentationHost.dismiss(animated: true)
        } else {
            navigationController.popViewController(animated: true)
        }
    }
}

// MARK: - TemplateDetailViewControllerDelegate

extension AppCoordinator: TemplateDetailViewControllerDelegate {

    func templateDetailDidTapStart(_ template: WorkoutTemplate) {
        navigationController.popViewController(animated: false)
        startWorkout(template: template)
    }

    func templateDetailDidRequestDelete(_ template: WorkoutTemplate) {
        // detail은 push로 띄워졌으므로 먼저 pop. 이후 sink에서 홈을 즉시 새로고침.
        navigationController.popViewController(animated: true)
        deleteCustomTemplate(template)
    }
}

// MARK: - LiveWorkoutMirrorDelegate

extension AppCoordinator: LiveWorkoutMirrorDelegate {

    func mirrorDidClose() {
        // 사용자가 직접 닫았으면 다음 운동 시작 전까지 다시 띄우지 않는다.
        isMirrorSuppressed = true
        dismissLiveMirror()
    }

    func mirrorSendCommand(_ command: WorkoutCommand) {
        if workoutMirrorController.hasActiveWorkout {
            workoutMirrorController.sendCommand(command)
        }
        syncCoordinator.sendCommand(command)
    }
}
