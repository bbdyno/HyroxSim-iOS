import UIKit
import HyroxKit

@MainActor
public final class AppCoordinator {

    private let window: UIWindow
    private let navigationController: UINavigationController
    let persistence: PersistenceController

    public init(window: UIWindow) throws {
        self.window = window
        self.navigationController = UINavigationController()
        self.persistence = try PersistenceController()
        navigationController.navigationBar.prefersLargeTitles = true
    }

    public func start() {
        let homeVC = makeHomeViewController()
        navigationController.viewControllers = [homeVC]
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
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
        startWorkout(template: template)
    }

    func homeDidTapNewWorkout() {
        presentBuilderEntry()
    }

    func homeDidTapHistory() {
        let vc = makeHistoryViewController()
        navigationController.pushViewController(vc, animated: true)
    }

    func homeDidSelectRecent(_ workout: CompletedWorkout) {
        // TODO: Summary detail view
        let alert = UIAlertController(
            title: workout.templateName,
            message: "Detail view coming soon",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        navigationController.present(alert, animated: true)
    }
}

// MARK: - HistoryViewControllerDelegate

extension AppCoordinator: HistoryViewControllerDelegate {

    func historyDidSelect(_ workout: CompletedWorkout) {
        let alert = UIAlertController(
            title: workout.templateName,
            message: DurationFormatter.hms(workout.totalDuration),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        navigationController.present(alert, animated: true)
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
                // TODO: 10 단계 — Summary screen
                let alert = UIAlertController(
                    title: "Workout Complete!",
                    message: "Total: \(DurationFormatter.hms(workout.totalDuration))\nSegments: \(workout.segments.count)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                navigationController.present(alert, animated: true)
            }
        }
    }
}
