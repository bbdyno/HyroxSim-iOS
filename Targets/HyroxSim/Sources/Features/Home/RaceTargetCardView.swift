//
//  RaceTargetCardView.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import UIKit
import HyroxCore

/// 홈 최상단 "내 대회" 카드.
///
/// 대회가 등록돼 있으면 D-day 를 가장 크게 보여 주고, 없으면 등록을 유도하는
/// 빈 상태 카드로 바뀐다. 두 상태 모두 탭하면 편집 화면으로 간다.
final class RaceTargetCardView: UIControl {

    private let badgeLabel = UILabel()
    private let dDayLabel = UILabel()
    private let eventLabel = UILabel()
    private let placeLabel = UILabel()
    private let goalLabel = UILabel()
    private let chevron = UIImageView()
    private let textStack = UIStackView()

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
        layer.borderColor = DesignTokens.Color.accentDim.cgColor
        clipsToBounds = true

        badgeLabel.font = DesignTokens.Font.label
        badgeLabel.textColor = DesignTokens.Color.accent

        dDayLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .black)
        dDayLabel.textColor = DesignTokens.Color.accent
        dDayLabel.adjustsFontSizeToFitWidth = true
        dDayLabel.minimumScaleFactor = 0.6

        eventLabel.font = .systemFont(ofSize: 17, weight: .bold)
        eventLabel.textColor = DesignTokens.Color.textPrimary
        eventLabel.numberOfLines = 2

        placeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        placeLabel.textColor = DesignTokens.Color.textSecondary

        goalLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        goalLabel.textColor = DesignTokens.Color.textTertiary

        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false
        [badgeLabel, dDayLabel, eventLabel, placeLabel, goalLabel].forEach(textStack.addArrangedSubview)
        textStack.setCustomSpacing(6, after: badgeLabel)
        textStack.setCustomSpacing(6, after: dDayLabel)
        addSubview(textStack)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = DesignTokens.Color.textTertiary
        chevron.contentMode = .scaleAspectFit
        chevron.isUserInteractionEnabled = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            textStack.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -12),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    /// 등록된 대회가 있을 때.
    func configure(with countdown: HomeViewModel.RaceCountdown) {
        let target = countdown.target
        badgeLabel.text = HyroxSimStrings.Localizable.Home.RaceTarget.badge
        badgeLabel.isHidden = false

        dDayLabel.text = countdown.dDayText
        dDayLabel.isHidden = false

        eventLabel.text = target.eventName

        let place = [target.city, target.division?.shortName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
        placeLabel.text = place
        placeLabel.isHidden = place.isEmpty

        if let goalText = countdown.goalText {
            goalLabel.text = HyroxSimStrings.Localizable.Home.RaceTarget.goalFormat(goalText)
        } else {
            goalLabel.text = HyroxSimStrings.Localizable.Home.RaceTarget.noGoal
        }
        goalLabel.isHidden = false

        layer.borderColor = DesignTokens.Color.accentDim.cgColor
        accessibilityLabel = "\(countdown.dDayText). \(target.eventName)"
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    /// 등록된 대회가 없을 때 — 추가를 유도한다.
    func configureEmpty() {
        badgeLabel.text = HyroxSimStrings.Localizable.Home.RaceTarget.badge
        badgeLabel.isHidden = false
        dDayLabel.isHidden = true
        eventLabel.text = HyroxSimStrings.Localizable.Home.RaceTarget.Empty.title
        placeLabel.text = HyroxSimStrings.Localizable.Home.RaceTarget.Empty.subtitle
        placeLabel.isHidden = false
        goalLabel.isHidden = true

        layer.borderColor = UIColor.white.withAlphaComponent(0.06).cgColor
        accessibilityLabel = HyroxSimStrings.Localizable.Home.RaceTarget.Empty.title
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
}
