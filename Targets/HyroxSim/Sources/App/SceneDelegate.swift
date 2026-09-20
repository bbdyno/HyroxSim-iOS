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
    //
    // 다만 포그라운드 전환마다 무조건 보내지는 않는다. `sendHello` 는 마지막
    // 전송 이후 `GarminBridge.helloMinimumInterval`(60초)이 지났거나 연결
    // 상태가 바뀐 경우에만 실제로 보낸다. 예전에는 전환할 때마다 hello →
    // hello.ack → 커스텀 템플릿 전체 + 프리셋 목표 9건 재전송이 반복됐다.
    func sceneDidBecomeActive(_ scene: UIScene) {
        GarminBridge.shared.sendHello(reason: "scene-active")
        // 지난 세션에서 못 보낸 template.delete 등이 남아 있으면 지금 비운다.
        GarminSyncDispatcher.shared.flush(reason: "scene-active")
    }
}
