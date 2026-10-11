//
//  DivisionPageCell.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import UIKit
import HyroxCore

/// 홈 디비전 페이저의 한 페이지: 디비전 이름과 구성 한 줄.
final class DivisionPageCell: UICollectionViewCell {

    static let reuseId = "DivisionPageCell"
    static let horizontalInset: CGFloat = 24
    static let height: CGFloat = 54

    private let titleLabel = UILabel()
    private let metaLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = DesignTokens.Font.wide(24, weight: .heavy)
        titleLabel.textColor = DesignTokens.Color.textPrimary
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6

        metaLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        metaLabel.textColor = DesignTokens.Color.textSecondary
        metaLabel.adjustsFontSizeToFitWidth = true
        metaLabel.minimumScaleFactor = 0.7

        let stack = UIStackView(arrangedSubviews: [titleLabel, metaLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.horizontalInset),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.horizontalInset)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with template: WorkoutTemplate) {
        let stations = template.segments.filter { $0.type == .station }.count
        let mins = Int(template.estimatedDurationSeconds / 60)

        var title = template.name.uppercased()
        var meta = "\(stations) STATIONS  ·  ~\(mins) MIN"
        if let division = template.division {
            let parts = division.displayName.components(separatedBy: " — ")
            title = (parts.first ?? division.displayName)
                .replacingOccurrences(of: "'s", with: "")
                .uppercased()
            if parts.count > 1 {
                meta = "\(parts[1].uppercased())  ·  " + meta
            }
        }

        titleLabel.text = title
        metaLabel.setTracked(meta, kern: 1.2)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = template.division?.displayName ?? template.name
    }
}
