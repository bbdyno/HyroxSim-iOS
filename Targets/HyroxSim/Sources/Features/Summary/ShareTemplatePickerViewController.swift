//
//  ShareTemplatePickerViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import UIKit

/// 공유할 레이아웃을 고른다. 미리보기는 실제로 공유될 이미지 그대로다.
final class ShareTemplatePickerViewController: UIViewController {

    private let images: [ShareTemplate: UIImage]
    private let shareText: String
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    /// - Parameter images: 레이아웃별로 미리 그려 둔 이미지.
    init(images: [ShareTemplate: UIImage], shareText: String) {
        self.images = images
        self.shareText = shareText
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = HyroxSimStrings.Localizable.Share.title
        view.backgroundColor = DesignTokens.Color.background
        view.accessibilityIdentifier = "sharePicker.view"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped)
        )

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        for (index, template) in ShareTemplate.allCases.enumerated() {
            guard let image = images[template] else { continue }
            stack.addArrangedSubview(makeCard(template: template, image: image, index: index))
        }
    }

    private func makeCard(template: ShareTemplate, image: UIImage, index: Int) -> UIView {
        let locked = !PremiumAccess.gate().canUseShareTemplate(at: index)

        let preview = UIImageView(image: image)
        preview.contentMode = .scaleAspectFit
        preview.layer.borderWidth = 1
        preview.layer.borderColor = DesignTokens.Color.hairline.cgColor
        preview.alpha = locked ? 0.45 : 1
        let previewWidth: CGFloat = 220
        preview.widthAnchor.constraint(equalToConstant: previewWidth).isActive = true
        preview.heightAnchor.constraint(
            equalToConstant: previewWidth * image.size.height / image.size.width
        ).isActive = true

        let label = UILabel()
        label.font = DesignTokens.Font.wide(11, weight: .heavy)
        label.textColor = locked ? DesignTokens.Color.textSecondary : DesignTokens.Color.accent
        label.setTracked((locked ? "PRO · " : "") + template.title.uppercased(), kern: 1.4)

        let column = UIStackView(arrangedSubviews: [preview, label])
        column.axis = .vertical
        column.spacing = 10
        column.isUserInteractionEnabled = false
        column.translatesAutoresizingMaskIntoConstraints = false

        let control = UIControl()
        control.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: control.topAnchor),
            column.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: control.bottomAnchor)
        ])
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = template.title
        control.accessibilityIdentifier = "sharePicker.template.\(index)"
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let self else { return }
            if locked {
                PremiumAccess.presentPaywall(.shareTemplates)
            } else {
                self.share(image, from: control)
            }
        }, for: .touchUpInside)
        return control
    }

    private func share(_ image: UIImage, from source: UIView?) {
        let activity = UIActivityViewController(activityItems: [image, shareText], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = source ?? view
            popover.sourceRect = source?.bounds ?? view.bounds
        }
        present(activity, animated: true)
    }

    @objc private func closeTapped() { dismiss(animated: true) }
}
