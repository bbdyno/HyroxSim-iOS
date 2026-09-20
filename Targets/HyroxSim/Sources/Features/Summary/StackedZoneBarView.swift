//
//  StackedZoneBarView.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

/// Horizontal stacked bar showing HR zone distribution.
final class StackedZoneBarView: UIView {

    struct ZoneData {
        let zone: HeartRateZone
        let ratio: Double
        let durationText: String
    }

    var zones: [ZoneData] = [] { didSet { setNeedsLayout() } }
    private var zoneLayers: [CALayer] = []
    private let labelsStack = UIStackView()

    private static let barHeight: CGFloat = 24

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 8
        clipsToBounds = true
        backgroundColor = DesignTokens.Color.surfaceElevated

        labelsStack.axis = .horizontal
        labelsStack.distribution = .fillEqually
        labelsStack.spacing = 2
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelsStack)

        // 레이아웃마다 다시 걸면 같은 제약이 무한히 쌓인다. 한 번만 건다.
        NSLayoutConstraint.activate([
            labelsStack.topAnchor.constraint(equalTo: topAnchor, constant: Self.barHeight + 4),
            labelsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelsStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        zoneLayers.forEach { $0.removeFromSuperlayer() }
        zoneLayers.removeAll()
        labelsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        var xOffset: CGFloat = 0
        let totalWidth = bounds.width

        for data in zones {
            let width = totalWidth * data.ratio
            let zoneLayer = CALayer()
            zoneLayer.frame = CGRect(x: xOffset, y: 0, width: width, height: Self.barHeight)
            zoneLayer.backgroundColor = color(for: data.zone).cgColor
            layer.addSublayer(zoneLayer)
            zoneLayers.append(zoneLayer)
            xOffset += width

            let label = UILabel()
            label.text = "\(data.zone.label) \(data.durationText)"
            label.font = .preferredFont(forTextStyle: .caption2)
            label.textColor = DesignTokens.Color.textSecondary
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            labelsStack.addArrangedSubview(label)
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 50)
    }

    private func color(for zone: HeartRateZone) -> UIColor {
        switch zone {
        case .z1: return .lightGray
        case .z2: return .systemBlue
        case .z3: return .systemGreen
        case .z4: return .systemOrange
        case .z5: return .systemRed
        }
    }
}
