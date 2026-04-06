//
//  MetricView.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit

/// Reusable view displaying a large value with a small caption below.
/// Prevents truncation by using adjustsFontSizeToFitWidth.
final class MetricView: UIView {

    let valueLabel = UILabel()
    let captionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        let stack = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 36, weight: .bold)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.5
        valueLabel.numberOfLines = 1

        captionLabel.font = .systemFont(ofSize: 11, weight: .bold)
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        captionLabel.textAlignment = .center
    }

    func setValue(_ text: String, caption: String) {
        valueLabel.text = text
        captionLabel.text = caption
    }

    func setValueColor(_ color: UIColor) {
        valueLabel.textColor = color
    }
}
