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
            for context in connectionOptions.urlContexts {
                _ = GarminBridge.shared.handle(url: context.url)
            }
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

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            _ = GarminBridge.shared.handle(url: context.url)
        }
    }

    // The CIQ phone-app message channel does not buffer for an offline watch
    // app, so a hello sent while the watch app was closed is lost. The iOS
    // app coming to the foreground is our best signal that the user is
    // about to (or just did) open the watch app — resend hello here so the
    // watch's PairingStore flips on the very first message.
    func sceneDidBecomeActive(_ scene: UIScene) {
        GarminBridge.shared.sendHello()
    }
}
