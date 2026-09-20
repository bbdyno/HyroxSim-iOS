//
//  RaceDayChecklistCell.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import UIKit
import HyroxCore

/// 체크리스트 한 줄. 시스템 기본 셀 대신 쓰는 커스텀 셀.
///
/// 룰 항목은 근거 한 줄과 페널티 배지(골드)를 달아 장비·영양 항목과 한눈에 구분된다.
/// 대회장에서 "이건 규정이고 저건 내 준비물"이 섞이면 판단이 느려지기 때문이다.
final class RaceDayChecklistCell: UITableViewCell {

    static let reuseIdentifier = "RaceDayChecklistCell"

    private let container = UIView()
    private let checkIcon = UIImageView()
    private let titleLabel = UILabel()
    private let evidenceLabel = UILabel()
    private let penaltyBadge = PaddedLabel()
    private let accentBar = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 구성

    func configure(item: RaceDayChecklistItem, isChecked: Bool) {
        titleLabel.text = RaceDayLocalization.title(for: item)
        titleLabel.textColor = isChecked
            ? DesignTokens.Color.textSecondary
            : DesignTokens.Color.textPrimary

        let evidence = RaceDayLocalization.evidence(for: item)
        evidenceLabel.text = evidence
        evidenceLabel.isHidden = evidence == nil

        penaltyBadge.text = item.penaltyBadge
        penaltyBadge.isHidden = item.penaltyBadge == nil

        // 룰 항목만 골드 바를 단다 — 규정과 개인 준비물의 무게가 다르다는 신호.
        accentBar.isHidden = item.category != .rule
        container.backgroundColor = item.category == .rule
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.white.withAlphaComponent(0.03)

        checkIcon.image = UIImage(systemName: isChecked ? "checkmark.circle.fill" : "circle")
        checkIcon.tintColor = isChecked
            ? DesignTokens.Color.accent
            : DesignTokens.Color.textTertiary

        accessibilityLabel = titleLabel.text
        accessibilityValue = evidence
        accessibilityTraits = isChecked ? [.button, .selected] : [.button]
        isAccessibilityElement = true
    }

    // MARK: - 레이아웃

    private func setupViews() {
        container.layer.cornerRadius = DesignTokens.Radius.card
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        accentBar.backgroundColor = DesignTokens.Color.accent
        accentBar.layer.cornerRadius = 2
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(accentBar)

        checkIcon.contentMode = .scaleAspectFit
        checkIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(checkIcon)

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.numberOfLines = 0

        evidenceLabel.font = .systemFont(ofSize: 12, weight: .medium)
        evidenceLabel.textColor = DesignTokens.Color.textSecondary
        evidenceLabel.numberOfLines = 0

        penaltyBadge.font = .systemFont(ofSize: 10, weight: .black)
        penaltyBadge.textColor = .black
        penaltyBadge.backgroundColor = DesignTokens.Color.accent
        penaltyBadge.layer.cornerRadius = DesignTokens.Radius.badge
        penaltyBadge.layer.masksToBounds = true
        penaltyBadge.setContentHuggingPriority(.required, for: .horizontal)
        penaltyBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, penaltyBadge])
        titleRow.axis = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 8

        let textStack = UIStackView(arrangedSubviews: [titleRow, evidenceLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textStack)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DesignTokens.Spacing.l),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DesignTokens.Spacing.l),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            accentBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            accentBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            accentBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 4),

            checkIcon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            checkIcon.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            checkIcon.widthAnchor.constraint(equalToConstant: 26),
            checkIcon.heightAnchor.constraint(equalToConstant: 26),

            textStack.leadingAnchor.constraint(equalTo: checkIcon.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            textStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
    }
}

/// 배지처럼 좌우 여백이 필요한 라벨.
private final class PaddedLabel: UILabel {

    private let insets = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }
}
