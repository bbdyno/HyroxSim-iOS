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
        // TODO: 09 단계 — 실제 운동 시작
        let alert = UIAlertController(
            title: template.name,
            message: "Workout will start here (coming soon)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        navigationController.present(alert, animated: true)
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
        navigationController.dismiss(animated: true) {
            // TODO: 09 단계 — 운동 시작
            let alert = UIAlertController(
                title: "Start Workout",
                message: "\(template.name)\nComing in next stage",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.navigationController.present(alert, animated: true)
        }
    }

    func builderDidSaveTemplate(_ template: WorkoutTemplate) {
        navigationController.dismiss(animated: true)
        // Home's viewWillAppear will reload data automatically
    }
}
