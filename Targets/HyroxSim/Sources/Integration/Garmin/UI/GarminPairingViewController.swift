//
//  GarminPairingViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//

import UIKit

/// Minimal pairing UI: explains that Garmin Connect Mobile is required,
/// opens the Garmin device picker, and shows current pairing status.
///
/// This screen compiles without ConnectIQ.framework but the pairing button
/// will log a warning until the framework is dropped into `Frameworks/`.
public final class GarminPairingViewController: UIViewController {

    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let pairButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        overrideUserInterfaceStyle = .dark
        navigationItem.title = "Garmin"
        configureLayout()
        refreshStatus()
    }

    private func configureLayout() {
        titleLabel.text = "가민 워치 연결"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        bodyLabel.text = """
        가민 워치로 HYROX 운동을 기록하려면:

        1. 폰에 "Garmin Connect" 앱이 설치·로그인되어 있어야 합니다
        2. 워치가 Garmin Connect에 이미 페어링되어 있어야 합니다
        3. Connect IQ Store에서 HyroxSim 워치앱 설치
        4. 아래 "기기 선택" 버튼으로 연결
        """
        bodyLabel.font = .systemFont(ofSize: 14)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = "기기 선택"
        buttonConfig.baseBackgroundColor = UIColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 1.0)
        buttonConfig.baseForegroundColor = .black
        pairButton.configuration = buttonConfig
        pairButton.addTarget(self, action: #selector(pairTapped), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, bodyLabel, pairButton, statusLabel
        ])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32)
        ])
    }

    @objc private func pairTapped() {
        GarminBridge.shared.requestDeviceSelection()
    }

    private func refreshStatus() {
        #if canImport(ConnectIQ)
        statusLabel.text = "SDK 활성화됨"
        #else
        statusLabel.text = "ConnectIQ.xcframework 미연결 — Frameworks/README.md 참조"
        #endif
    }
}
