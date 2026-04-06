import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var coordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .dark
        self.window = window

        do {
            let coord = try AppCoordinator(window: window)
            self.coordinator = coord
            coord.start()
        } catch {
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            window.rootViewController = vc
            window.makeKeyAndVisible()
            assertionFailure("Failed to start coordinator: \(error)")
        }
    }
}
