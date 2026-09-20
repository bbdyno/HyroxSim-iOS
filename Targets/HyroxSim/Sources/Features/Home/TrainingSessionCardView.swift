//
//  TrainingSessionCardView.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import UIKit
import HyroxCore

/// 홈의 훈련 세션 카드.
/// `PresetCardCell` 과 같은 시각 언어(surface + 왼쪽 골드 바 + 골드 배지 + 셰브런)를 쓰되,
/// 캐러셀이 아니라 세로 목록에 들어가므로 설명 줄까지 담을 수 있게 따로 그린다.
final class TrainingSessionCardView: UIControl {

    private let badgeView = UIView()
    private let badgeLabel = UILabel()
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let detailLabel = UILabel()
    private let chevron = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? DesignTokens.Color.surfaceElevated
                : DesignTokens.Color.surface
        }
    }

    private func setupUI() {
        backgroundColor = DesignTokens.Color.surface
        layer.cornerRadius = DesignTokens.Radius.card
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.06).cgColor
        clipsToBounds = true

        let leftBar = UIView()
        leftBar.translatesAutoresizingMaskIntoConstraints = false
        leftBar.backgroundColor = DesignTokens.Color.accent
        leftBar.isUserInteractionEnabled = false
        addSubview(leftBar)

        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.backgroundColor = DesignTokens.Color.accent
        badgeView.layer.cornerRadius = DesignTokens.Radius.badge
        badgeView.isUserInteractionEnabled = false
        addSubview(badgeView)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 10, weight: .black)
        badgeLabel.textColor = .black
        badgeLabel.textAlignment = .center
        badgeView.addSubview(badgeLabel)

        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = DesignTokens.Color.textPrimary
        titleLabel.numberOfLines = 2

        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = DesignTokens.Color.textSecondary
        summaryLabel.numberOfLines = 3

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        detailLabel.textColor = DesignTokens.Color.textTertiary

        let textStack = UIStackView(arrangedSubviews: [titleLabel, summaryLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.setCustomSpacing(8, after: summaryLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false
        addSubview(textStack)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = DesignTokens.Color.textTertiary
        chevron.contentMode = .scaleAspectFit
        chevron.isUserInteractionEnabled = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            leftBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftBar.topAnchor.constraint(equalTo: topAnchor),
            leftBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftBar.widthAnchor.constraint(equalToConstant: 3),

            badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            badgeView.widthAnchor.constraint(equalToConstant: 36),
            badgeView.heightAnchor.constraint(equalToConstant: 20),
            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),

            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            textStack.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -12),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    func configure(with item: HomeViewModel.TrainingSessionItem) {
        let template = item.template
        badgeLabel.text = TrainingSessionLocalization.badge(for: item.kind)
        titleLabel.text = template.name
        summaryLabel.text = TrainingSessionLocalization.summary(for: item.kind)

        let stations = template.segments.filter { $0.type == .station }.count
        let runs = template.segments.filter { $0.type == .run }.count
        let minutes = Int(template.estimatedDurationSeconds / 60)
        var parts = ["\(stations) stations"]
        if runs > 0 { parts.append("\(runs) runs") }
        parts.append("~\(minutes) min")
        detailLabel.text = parts.joined(separator: "  ·  ")

        accessibilityLabel = "\(template.name). \(summaryLabel.text ?? "")"
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
}
