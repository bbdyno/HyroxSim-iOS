//
//  CoursePageCell.swift
//  HyroxSim
//
//  Created by bbdyno on 10/7/26.
//

import UIKit
import HyroxCore

/// One full-width page of the home division pager: division name + race course.
final class CoursePageCell: UICollectionViewCell {

    static let reuseId = "CoursePageCell"
    static let horizontalInset: CGFloat = 24

    private static let titleHeight: CGFloat = 38
    private static let metaHeight: CGFloat = 14
    private static let mapTopSpacing: CGFloat = 20

    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let mapView = CourseMapView(style: .regular)

    static func height(stationCount: Int) -> CGFloat {
        titleHeight + 4 + metaHeight + mapTopSpacing + CourseMapView.height(stationCount: stationCount, style: .regular)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        titleLabel.font = DesignTokens.Font.wide(30, weight: .heavy)
        titleLabel.textColor = DesignTokens.Color.textPrimary
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6

        metaLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        metaLabel.textColor = DesignTokens.Color.textSecondary
        metaLabel.adjustsFontSizeToFitWidth = true
        metaLabel.minimumScaleFactor = 0.7

        for view in [titleLabel, metaLabel, mapView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        let inset = Self.horizontalInset
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset),
            titleLabel.heightAnchor.constraint(equalToConstant: Self.titleHeight),

            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            metaLabel.heightAnchor.constraint(equalToConstant: Self.metaHeight),

            mapView.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: Self.mapTopSpacing),
            mapView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])
    }

    func configure(with template: WorkoutTemplate) {
        let stations = template.courseStations
        let mins = Int(template.estimatedDurationSeconds / 60)

        var title = template.name.uppercased()
        var meta = "\(stations.count) STATIONS  ·  ~\(mins) MIN"
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
        mapView.stations = stations

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = template.division?.displayName ?? template.name
    }
}
