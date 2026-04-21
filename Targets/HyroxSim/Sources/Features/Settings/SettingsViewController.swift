//
//  SettingsViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/21/26.
//

import UIKit

@MainActor
protocol SettingsViewControllerDelegate: AnyObject {
    func settingsDidTapGarminPairing()
    func settingsDidTapOpenSource()
}

/// Settings tab root. Two sections:
///   - DEVICE: Garmin pairing entry
///   - ABOUT: GitHub repo link, open-source licenses, app version
final class SettingsViewController: UIViewController {

    weak var delegate: SettingsViewControllerDelegate?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let hMargin: CGFloat = 20

    private var garminStatusLabel: UILabel?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        title = HyroxSimStrings.Localizable.Settings.title
        setupLayout()
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshGarminStatus()
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40)
        ])
    }

    private func buildContent() {
        contentStack.addArrangedSubview(makeSectionHeader(HyroxSimStrings.Localizable.Settings.Section.device))
        let garminRow = makeActionRow(
            title: HyroxSimStrings.Localizable.Settings.Row.garmin,
            subtitle: HyroxSimStrings.Localizable.Settings.Row.Garmin.Subtitle.disconnected,
            icon: "applewatch.radiowaves.left.and.right",
            action: #selector(garminTapped)
        )
        if let subtitleLabel = garminRow.viewWithTag(Tags.garminSubtitle) as? UILabel {
            garminStatusLabel = subtitleLabel
        }
        contentStack.addArrangedSubview(garminRow)

        contentStack.addArrangedSubview(makeSectionHeader(HyroxSimStrings.Localizable.Settings.Section.about))
        contentStack.addArrangedSubview(makeActionRow(
            title: HyroxSimStrings.Localizable.Settings.Row.github,
            subtitle: HyroxSimStrings.Localizable.Settings.Row.Github.subtitle,
            icon: "chevron.left.forwardslash.chevron.right",
            action: #selector(githubTapped)
        ))
        contentStack.addArrangedSubview(makeActionRow(
            title: HyroxSimStrings.Localizable.Settings.Row.opensource,
            subtitle: nil,
            icon: "doc.text",
            action: #selector(openSourceTapped)
        ))
        contentStack.addArrangedSubview(makeActionRow(
            title: HyroxSimStrings.Localizable.Settings.Row.version,
            subtitle: Self.appVersionString,
            icon: "info.circle",
            action: nil
        ))
    }

    // MARK: - Status refresh

    private func refreshGarminStatus() {
        let connected = GarminBridge.shared.isPaired
        garminStatusLabel?.text = connected
            ? HyroxSimStrings.Localizable.Settings.Row.Garmin.Subtitle.connected
            : HyroxSimStrings.Localizable.Settings.Row.Garmin.Subtitle.disconnected
    }

    // MARK: - Actions

    @objc private func garminTapped() { delegate?.settingsDidTapGarminPairing() }
    @objc private func githubTapped() {
        guard let url = URL(string: "https://github.com/bbdyno") else { return }
        UIApplication.shared.open(url)
    }
    @objc private func openSourceTapped() { delegate?.settingsDidTapOpenSource() }

    // MARK: - Row builders

    private enum Tags {
        static let garminSubtitle = 901
    }

    private func makeSectionHeader(_ title: String) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = DesignTokens.Color.accent
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hMargin),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hMargin),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    private func makeActionRow(title: String, subtitle: String?, icon: String, action: Selector?) -> UIView {
        let container = UIView()

        let card = UIView()
        card.backgroundColor = DesignTokens.Color.surface
        card.layer.cornerRadius = DesignTokens.Radius.card
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hMargin),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hMargin),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = DesignTokens.Color.accent
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = DesignTokens.Color.textSecondary
        subtitleLabel.isHidden = subtitle == nil
        subtitleLabel.tag = Tags.garminSubtitle

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = DesignTokens.Color.textTertiary
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.isHidden = action == nil

        let row = UIStackView(arrangedSubviews: [iconView, textStack, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22)
        ])

        if let action {
            let tap = UITapGestureRecognizer(target: self, action: action)
            card.addGestureRecognizer(tap)
            card.isUserInteractionEnabled = true
        }
        return container
    }

    private static var appVersionString: String {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
        return "\(version) (\(build))"
    }
}
