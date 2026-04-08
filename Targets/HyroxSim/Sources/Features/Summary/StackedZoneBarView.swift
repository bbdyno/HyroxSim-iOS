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

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 8
        clipsToBounds = true
        backgroundColor = .systemFill

        labelsStack.axis = .horizontal
        labelsStack.distribution = .fillEqually
        labelsStack.spacing = 2
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelsStack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        zoneLayers.forEach { $0.removeFromSuperlayer() }
        zoneLayers.removeAll()
        labelsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let barHeight: CGFloat = 24
        var xOffset: CGFloat = 0
        let totalWidth = bounds.width

        for data in zones {
            let width = totalWidth * data.ratio
            let zoneLayer = CALayer()
            zoneLayer.frame = CGRect(x: xOffset, y: 0, width: width, height: barHeight)
            zoneLayer.backgroundColor = color(for: data.zone).cgColor
            layer.addSublayer(zoneLayer)
            zoneLayers.append(zoneLayer)
            xOffset += width

            let label = UILabel()
            label.text = "\(data.zone.label) \(data.durationText)"
            label.font = .preferredFont(forTextStyle: .caption2)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            labelsStack.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            labelsStack.topAnchor.constraint(equalTo: topAnchor, constant: barHeight + 4),
            labelsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelsStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
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
