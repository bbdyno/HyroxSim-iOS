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
    private let templateGoalOverrideStore = TemplateGoalOverrideStore()
    private let forceDisconnectedMirrorUITest = ProcessInfo.processInfo.arguments.contains("UITestWatchMirrorDisconnected")

    /// All modal presentations (builder sheet, live mirror) use the tab bar
    /// as host so they work regardless of which tab is foregrounded.
    private var presentationHost: UIViewController { tabBarController }

    init(window: UIWindow, services: AppServices) {
        self.window = window
        self.navigationController = UINavigationController()
        self.settingsNavigationController = UINavigationController()
        self.tabBarController = UITabBarController()
        self.persistence = services.persistence
        self.syncCoordinator = services.syncCoordinator
        self.workoutMirrorController = services.workoutMirrorController

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

        // 워치 운동 미러링 - HealthKit mirrored session 경로
        workoutMirrorController.onWorkoutStarted = { [weak self] template, origin in
            guard origin == .watch else { return }
            self?.showLiveMirror(template: template)
        }
        workoutMirrorController.onLiveStateReceived = { [weak self] state in
            guard state.origin == .watch else { return }
            if self?.liveMirrorVC == nil {
                let template = self?.workoutMirrorController.currentTemplate
                    ?? Self.placeholderTemplate(for: state)
                self?.showLiveMirror(template: template)
            }
            self?.applyLiveMirrorState(state)
        }
        workoutMirrorController.onWorkoutFinished = { [weak self] origin in
            guard origin == .watch else { return }
            self?.dismissLiveMirror()
        }
        workoutMirrorController.onConnectionChanged = { [weak self] connected in
            if self?.forceDisconnectedMirrorUITest == true {
                self?.liveMirrorVC?.showDisconnected()
                return
            }
            if connected {
                self?.liveMirrorVC?.showReconnected()
            } else {
                self?.liveMirrorVC?.showDisconnected()
            }
        }

        // WatchConnectivity fallback 경로
        syncCoordinator.onWorkoutStarted = { [weak self] template, origin in
            guard origin == .watch else { return } // 폰 자신이 시작한 운동은 미러 안 함
            self?.showLiveMirror(template: template)
        }
        syncCoordinator.onLiveStateReceived = { [weak self] state in
            guard state.origin == .watch else { return }
            if self?.liveMirrorVC == nil {
                self?.showLiveMirror(template: Self.placeholderTemplate(for: state))
            }
            self?.applyLiveMirrorState(state)
        }
        syncCoordinator.onWorkoutFinished = { [weak self] origin in
            guard origin == .watch else { return }
            self?.dismissLiveMirror()
        }
        syncCoordinator.onReachabilityChanged = { [weak self] reachable in
            guard let self, !self.workoutMirrorController.hasActiveWorkout else { return }
            if self.forceDisconnectedMirrorUITest {
                self.liveMirrorVC?.showDisconnected()
                return
            }
            if reachable {
                self.liveMirrorVC?.showReconnected()
            } else {
                self.liveMirrorVC?.showDisconnected()
            }
        }

        if let template = workoutMirrorController.currentTemplate {
            showLiveMirror(template: template)
            if let state = workoutMirrorController.currentState {
                applyLiveMirrorState(state)
            }
            if forceDisconnectedMirrorUITest {
                liveMirrorVC?.showDisconnected()
            } else if !workoutMirrorController.isConnected {
                liveMirrorVC?.showDisconnected()
            }
        }

        applyUITestScenarioIfNeeded()
        applyScreenshotScenarioIfNeeded()
    }

    // MARK: - 워치 실시간 미러

    private var liveMirrorVC: LiveWorkoutMirrorViewController?

    private func showLiveMirror(template: WorkoutTemplate) {
        guard liveMirrorVC == nil else { return }
        let vc = LiveWorkoutMirrorViewController()
        vc.delegate = self
        liveMirrorVC = vc
        presentationHost.present(vc, animated: true)
    }

    private func dismissLiveMirror() {
        guard let liveMirrorVC else {
            presentationHost.dismiss(animated: true)
            refreshHomeIfVisible()
            return
        }

        let finishDismissal = { [weak self] in
            guard let self else { return }
            self.liveMirrorVC = nil
            self.refreshHomeIfVisible()
        }

        let dismissMirror = {
            liveMirrorVC.dismiss(animated: true, completion: finishDismissal)
        }

        if let presented = liveMirrorVC.presentedViewController {
            presented.dismiss(animated: false, completion: dismissMirror)
        } else {
            dismissMirror()
        }
    }

    private static func placeholderTemplate(for state: LiveWorkoutState) -> WorkoutTemplate {
        WorkoutTemplate(name: state.templateName, segments: [.run(distanceMeters: 1000)])
    }

    private func applyLiveMirrorState(_ state: LiveWorkoutState) {
        liveMirrorVC?.updateState(state)
        if forceDisconnectedMirrorUITest {
            liveMirrorVC?.showDisconnected()
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
            liveMirrorVC?.showDisconnected()
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
            guard let planner = try? PaceReferenceLoader.loadPacePlanner() else { return }
            let vc = PacePlannerViewController(template: HyroxPresets.menProSingle, planner: planner)
            navigationController.setViewControllers([vc], animated: false)
        case .history:
            navigationController.pushViewController(makeHistoryViewController(), animated: false)
        case .summary:
            showSummary(for: ScreenshotFixtures.summaryWorkout, fromHistory: true, animated: false)
        case .mirror:
            showLiveMirror(template: ScreenshotFixtures.liveMirrorTemplate)
            liveMirrorVC?.updateState(ScreenshotFixtures.liveMirrorState)
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

    func homeDidTapNewWorkout() {
        presentBuilderEntry()
    }

    func homeDidTapHistory() {
        let vc = makeHistoryViewController()
        navigationController.pushViewController(vc, animated: true)
    }

    func homeDidSelectRecent(_ workout: CompletedWorkout) {
        showSummary(for: workout, fromHistory: true)
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
        let location = CoreLocationAdapter()
        let heartRate = HealthKitHeartRateAdapter()
        let vm = ActiveWorkoutViewModel(
            template: template,
            locationStream: location,
            heartRateStream: heartRate,
            persistence: persistence,
            maxHeartRate: 190, // TODO: user settings
            syncCoordinator: syncCoordinator
        )
        let vc = ActiveWorkoutViewController(viewModel: vm)

        vm.errorHandler = { [weak self] error in
            let alert = DarkAlertController(
                title: HyroxSimStrings.Localizable.Alert.Error.title,
                message: "\(error)"
            )
            alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.ok, style: .normal, handler: nil))
            self?.presentationHost.presentedViewController?.present(alert, animated: true)
        }
        vm.finishHandler = { [weak self] completed in
            self?.dismissWorkout(showingSummaryFor: completed)
        }
        vm.cancelHandler = { [weak self] in
            self?.dismissWorkout(showingSummaryFor: nil)
        }

        vc.modalPresentationStyle = .fullScreen
        presentationHost.present(vc, animated: true)
    }

    private func dismissWorkout(showingSummaryFor workout: CompletedWorkout?) {
        presentationHost.dismiss(animated: true) { [self] in
            if let workout {
                showSummary(for: workout, fromHistory: false)
            }
        }
    }

    func showSummary(for workout: CompletedWorkout, fromHistory: Bool, animated: Bool = true) {
        let vm = WorkoutSummaryViewModel(workout: workout)
        let vc = WorkoutSummaryViewController(viewModel: vm)
        vc.delegate = self
        if fromHistory {
            navigationController.pushViewController(vc, animated: animated)
        } else {
            // After workout: present modally (no "back" destination — builder was dismissed)
            let nav = UINavigationController(rootViewController: vc)
            nav.applyDarkTheme()
            presentationHost.present(nav, animated: animated)
        }
    }

    private func templateWithOverrides(_ template: WorkoutTemplate) -> WorkoutTemplate {
        templateGoalOverrideStore.resolvedTemplate(from: template)
    }

    private func persistTemplateChanges(_ template: WorkoutTemplate) {
        if template.isBuiltIn {
            templateGoalOverrideStore.save(template)
            try? syncCoordinator.sendTemplate(template)
            return
        }

        try? persistence.upsertTemplate(template)
        try? syncCoordinator.sendTemplate(template)
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
}

// MARK: - LiveWorkoutMirrorDelegate

extension AppCoordinator: LiveWorkoutMirrorDelegate {

    func mirrorDidClose() {
        dismissLiveMirror()
    }

    func mirrorSendCommand(_ command: WorkoutCommand) {
        if workoutMirrorController.hasActiveWorkout {
            workoutMirrorController.sendCommand(command)
        }
        syncCoordinator.sendCommand(command)
    }
}
