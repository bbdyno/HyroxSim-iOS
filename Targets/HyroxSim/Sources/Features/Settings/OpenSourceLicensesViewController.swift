//
//  OpenSourceLicensesViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/21/26.
//

import UIKit

/// Static list of third-party dependencies + their licenses. Edit
/// `Self.entries` when adding or removing a dependency.
final class OpenSourceLicensesViewController: UIViewController {

    private struct Entry {
        let name: String
        let license: String
        let url: String
    }

    private static let entries: [Entry] = [
        Entry(
            name: "Firebase iOS SDK",
            license: "Apache License 2.0",
            url: "https://github.com/firebase/firebase-ios-sdk"
        ),
        Entry(
            name: "Connect IQ SDK",
            license: "Garmin Proprietary SDK (redistribution permitted)",
            url: "https://developer.garmin.com/connect-iq/overview/"
        )
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        title = HyroxSimStrings.Localizable.Opensource.title

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40)
        ])

        for entry in Self.entries {
            stack.addArrangedSubview(makeEntryCard(entry))
        }
    }

    private func makeEntryCard(_ entry: Entry) -> UIView {
        let card = UIView()
        card.backgroundColor = DesignTokens.Color.surface
        card.layer.cornerRadius = DesignTokens.Radius.card

        let nameLabel = UILabel()
        nameLabel.text = entry.name
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .white

        let licenseLabel = UILabel()
        licenseLabel.text = entry.license
        licenseLabel.font = .systemFont(ofSize: 13)
        licenseLabel.textColor = DesignTokens.Color.accent

        let urlLabel = UILabel()
        urlLabel.text = entry.url
        urlLabel.font = .systemFont(ofSize: 12)
        urlLabel.textColor = DesignTokens.Color.textSecondary
        urlLabel.numberOfLines = 0

        let inner = UIStackView(arrangedSubviews: [nameLabel, licenseLabel, urlLabel])
        inner.axis = .vertical
        inner.spacing = 4
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }
}
