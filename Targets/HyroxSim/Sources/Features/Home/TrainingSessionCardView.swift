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

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? DesignTokens.Color.surface : .clear
        }
    }

    private func setupUI() {
        // 코스 맵 방향: 카드 대신 헤어라인으로 구분되는 행.
        backgroundColor = .clear

        let hairline = UIView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = DesignTokens.Color.hairline
        hairline.isUserInteractionEnabled = false
        addSubview(hairline)

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

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
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

        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            badgeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            badgeView.widthAnchor.constraint(equalToConstant: 36),
            badgeView.heightAnchor.constraint(equalToConstant: 20),
            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),

            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            textStack.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    func configure(with item: HomeViewModel.TrainingSessionItem) {
        let template = item.template
        badgeLabel.text = TrainingSessionLocalization.badge(for: item.kind)
        titleLabel.text = template.name.uppercased()
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
