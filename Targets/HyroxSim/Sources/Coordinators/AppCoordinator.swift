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
        // TODO: 08 단계 — Workout Builder
        let alert = UIAlertController(
            title: "New Workout",
            message: "Builder coming soon",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        navigationController.present(alert, animated: true)
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
        // TODO: Summary detail view
        let alert = UIAlertController(
            title: workout.templateName,
            message: DurationFormatter.hms(workout.totalDuration),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        navigationController.present(alert, animated: true)
    }
}
