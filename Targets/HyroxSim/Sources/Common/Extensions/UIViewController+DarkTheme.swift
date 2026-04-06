//
//  UIViewController+DarkTheme.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit

extension UIViewController {

    /// Apply consistent dark nav bar appearance across all screens
    func applyDarkNavBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = DesignTokens.Color.background
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = DesignTokens.Color.accent
    }

    /// Apply dark toolbar appearance
    func applyDarkToolbarAppearance() {
        let tbAppearance = UIToolbarAppearance()
        tbAppearance.configureWithOpaqueBackground()
        tbAppearance.backgroundColor = DesignTokens.Color.background
        navigationController?.toolbar.standardAppearance = tbAppearance
        navigationController?.toolbar.scrollEdgeAppearance = tbAppearance
        navigationController?.toolbar.tintColor = DesignTokens.Color.accent
    }
}

extension UITextField {

    /// Style a text field for the dark theme
    func applyDarkStyle() {
        backgroundColor = DesignTokens.Color.surface
        textColor = .white
        borderStyle = .none
        layer.cornerRadius = 10
        let padding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        leftView = padding
        leftViewMode = .always
        attributedPlaceholder = NSAttributedString(
            string: placeholder ?? "",
            attributes: [.foregroundColor: DesignTokens.Color.textTertiary]
        )
    }
}
