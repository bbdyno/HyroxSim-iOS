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
        navigationItem.title = HyroxSimStrings.Localizable.Garmin.Pairing.title
        configureLayout()
        GarminBridge.shared.onConnectedDeviceChanged = { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        refreshStatus()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshStatus()
    }

    private func configureLayout() {
        titleLabel.text = HyroxSimStrings.Localizable.Garmin.Pairing.header
        titleLabel.font = DesignTokens.Font.wide(22, weight: .heavy)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        bodyLabel.text = HyroxSimStrings.Localizable.Garmin.Pairing.instructions
        bodyLabel.font = .systemFont(ofSize: 14)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.attributedTitle = AttributedString(
            HyroxSimStrings.Localizable.Garmin.Pairing.button,
            attributes: AttributeContainer([.font: DesignTokens.Font.wide(15, weight: .heavy)])
        )
        buttonConfig.baseBackgroundColor = DesignTokens.Color.accent
        buttonConfig.baseForegroundColor = .black
        buttonConfig.cornerStyle = .fixed
        buttonConfig.background.cornerRadius = 0
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
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
        if let name = GarminBridge.shared.connectedDeviceName {
            statusLabel.text = "✓ \(name)"
            statusLabel.textColor = UIColor(red: 0.0, green: 0.85, blue: 0.4, alpha: 1.0)
        } else {
            statusLabel.text = HyroxSimStrings.Localizable.Garmin.Pairing.Status.ready
            statusLabel.textColor = .tertiaryLabel
        }
        #else
        statusLabel.text = HyroxSimStrings.Localizable.Garmin.Pairing.Status.missingFramework
        #endif
    }
}
