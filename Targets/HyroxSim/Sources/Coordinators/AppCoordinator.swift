//
//  AppCoordinator.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxKit

@MainActor
public final class AppCoordinator {

    private let window: UIWindow
    private let navigationController: UINavigationController
    let persistence: PersistenceController
    private let syncCoordinator: WatchConnectivitySyncCoordinator

    public init(window: UIWindow) throws {
        self.window = window
        self.navigationController = UINavigationController()
        self.persistence = try PersistenceController()
        self.syncCoordinator = WatchConnectivitySyncCoordinator(persistence: persistence)
        navigationController.navigationBar.prefersLargeTitles = true
    }

    public func start() {
        let homeVC = makeHomeViewController()
        navigationController.viewControllers = [homeVC]
        window.rootViewController = navigationController
        window.makeKeyAndVisible()

        syncCoordinator.activate()
        syncCoordinator.onReceiveCompletedWorkout = { [weak self] _ in
            self?.refreshHomeIfVisible()
        }
        syncCoordinator.onReceiveTemplate = { [weak self] _ in
            self?.refreshHomeIfVisible()
        }
        syncCoordinator.onReceiveTemplateDeleted = { [weak self] _ in
            self?.refreshHomeIfVisible()
        }
    }

    private func refreshHomeIfVisible() {
        // Trigger viewWillAppear-equivalent reload by popping to root if possible,
        // or just set a flag. Simplest: call reload if the VC exposes it.
        // HomeViewController reloads in viewWillAppear, so next appearance is fine.
        // For immediate update, post a notification.
        NotificationCenter.default.post(name: .syncDataUpdated, object: nil)
    }

    // MARK: - Factory

    private func makeHomeViewController() -> UIViewController {
        let vm = HomeViewModel(persistence: persistence)
        let vc = HomeViewController(viewModel: vm)
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
        let vc = TemplateDetailViewController(template: template)
        vc.delegate = self
        navigationController.pushViewController(vc, animated: true)
    }

    private func presentBuilderEntry() {
        let vc = BuilderEntrySheetViewController()
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        navigationController.present(nav, animated: true)
    }

    private func presentBuilder(startingFrom template: WorkoutTemplate?) {
        let vm = WorkoutBuilderViewModel(startingFrom: template, persistence: persistence)
        let vc = WorkoutBuilderViewController(viewModel: vm)
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        navigationController.present(nav, animated: true)
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

// MARK: - HistoryViewControllerDelegate

extension AppCoordinator: HistoryViewControllerDelegate {

    func historyDidSelect(_ workout: CompletedWorkout) {
        showSummary(for: workout, fromHistory: true)
    }
}

// MARK: - BuilderEntrySheetDelegate

extension AppCoordinator: BuilderEntrySheetDelegate {

    func builderEntryDidSelectPreset(_ template: WorkoutTemplate) {
        navigationController.dismiss(animated: true) { [self] in
            presentBuilder(startingFrom: template)
        }
    }

    func builderEntryDidSelectScratch() {
        navigationController.dismiss(animated: true) { [self] in
            presentBuilder(startingFrom: nil)
        }
    }
}

// MARK: - WorkoutBuilderViewControllerDelegate

extension AppCoordinator: WorkoutBuilderViewControllerDelegate {

    func builderDidCancel() {
        navigationController.dismiss(animated: true)
    }

    func builderDidRequestStart(template: WorkoutTemplate) {
        navigationController.dismiss(animated: true) { [self] in
            startWorkout(template: template)
        }
    }

    func builderDidSaveTemplate(_ template: WorkoutTemplate) {
        try? syncCoordinator.sendTemplate(template)
        navigationController.dismiss(animated: true)
    }
}

// MARK: - Workout Lifecycle

extension AppCoordinator {

    func startWorkout(template: WorkoutTemplate) {
        let location = CoreLocationAdapter()
        let heartRate = HealthKitHeartRateAdapter()
        let vm = ActiveWorkoutViewModel(
            template: template,
            locationStream: location,
            heartRateStream: heartRate,
            persistence: persistence,
            maxHeartRate: 190 // TODO: user settings
        )
        let vc = ActiveWorkoutViewController(viewModel: vm)

        vm.errorHandler = { [weak self] error in
            let alert = UIAlertController(title: "Error", message: "\(error)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.navigationController.presentedViewController?.present(alert, animated: true)
        }
        vm.finishHandler = { [weak self] completed in
            self?.dismissWorkout(showingSummaryFor: completed)
        }
        vm.cancelHandler = { [weak self] in
            self?.dismissWorkout(showingSummaryFor: nil)
        }

        vc.modalPresentationStyle = .fullScreen
        navigationController.present(vc, animated: true)
    }

    private func dismissWorkout(showingSummaryFor workout: CompletedWorkout?) {
        navigationController.dismiss(animated: true) { [self] in
            if let workout {
                showSummary(for: workout, fromHistory: false)
            }
        }
    }

    func showSummary(for workout: CompletedWorkout, fromHistory: Bool) {
        let vm = WorkoutSummaryViewModel(workout: workout)
        let vc = WorkoutSummaryViewController(viewModel: vm)
        vc.delegate = self
        if fromHistory {
            navigationController.pushViewController(vc, animated: true)
        } else {
            // After workout: present modally (no "back" destination — builder was dismissed)
            let nav = UINavigationController(rootViewController: vc)
            navigationController.present(nav, animated: true)
        }
    }
}

// MARK: - WorkoutSummaryViewControllerDelegate

extension AppCoordinator: WorkoutSummaryViewControllerDelegate {

    func summaryDidTapDone() {
        if navigationController.presentedViewController != nil {
            navigationController.dismiss(animated: true)
        } else {
            navigationController.popViewController(animated: true)
        }
    }

    func summaryDidTapShare(_ workout: CompletedWorkout) {
        let vm = WorkoutSummaryViewModel(workout: workout)
        let avc = UIActivityViewController(activityItems: [vm.shareText], applicationActivities: nil)
        if let presented = navigationController.presentedViewController {
            presented.present(avc, animated: true)
        } else {
            navigationController.present(avc, animated: true)
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
