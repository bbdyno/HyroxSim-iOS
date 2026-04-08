//
//  SceneDelegate.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit

@MainActor
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

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            window.rootViewController = vc
            window.makeKeyAndVisible()
            assertionFailure("Failed to resolve AppDelegate")
            return
        }

        if let services = appDelegate.services {
            let coord = AppCoordinator(window: window, services: services)
            self.coordinator = coord
            coord.start()
        } else {
            let error = appDelegate.startupError ?? NSError(
                domain: "HyroxSim.SceneDelegate",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "App services unavailable"]
            )
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            window.rootViewController = vc
            window.makeKeyAndVisible()
            assertionFailure("Failed to start coordinator: \(error)")
        }
    }
}
