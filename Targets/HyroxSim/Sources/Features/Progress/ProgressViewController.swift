//
//  ProgressViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import SwiftUI
import UIKit
import HyroxCore

/// 진척 추적 화면.
///
/// 내용은 Swift Charts 로 그려야 해서 SwiftUI(`ProgressChartsView`)로 두고, 화면 자체는
/// 다른 화면들과 같은 UIKit 네비게이션 스택에 그대로 올라가도록 호스팅한다.
final class ProgressViewController: UIViewController {

    private let viewModel: ProgressViewModel
    private let hostingController: UIHostingController<ProgressChartsView>

    init(viewModel: ProgressViewModel) {
        self.viewModel = viewModel
        self.hostingController = UIHostingController(
            rootView: ProgressChartsView(viewModel: viewModel)
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = HyroxSimStrings.Localizable.Progress.title
        view.backgroundColor = DesignTokens.Color.background
        navigationItem.largeTitleDisplayMode = .never
        applyDarkNavBarAppearance()
        embedChartsView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 기록은 요약 화면이나 워치 동기화로도 늘어난다. 화면에 들어올 때마다 다시 읽는다.
        viewModel.load()
    }

    private func embedChartsView() {
        // 호스팅 뷰의 기본 배경은 시스템 배경이라, 다크 화면 위에서 흰 띠로 보인다.
        hostingController.view.backgroundColor = DesignTokens.Color.background
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }
}
