//
//  TeamSplitStationRowView.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import UIKit
import HyroxCore

/// 팀원 색. 순서는 슬롯 순서(A · B · C · D)와 같다.
enum TeamSplitPalette {

    static let colors: [UIColor] = [
        DesignTokens.Color.accent,
        DesignTokens.Color.runAccent,
        DesignTokens.Color.roxZoneAccent,
        DesignTokens.Color.success
    ]

    static func color(forSlot slot: Int) -> UIColor {
        colors.indices.contains(slot) ? colors[slot] : DesignTokens.Color.textSecondary
    }
}

/// 분담 비율을 색 막대 하나로 보여 준다.
///
/// 막대 폭을 제약의 multiplier 로 잡기 때문에 값이 바뀔 때마다 제약을 새로 건다.
/// 8개 스테이션 × 팀원 수 정도의 규모라 매번 다시 만드는 편이 상태를 들고 있는 것보다 안전하다.
final class TeamSplitShareBarView: UIView {

    private var segments: [UIView] = []
    private var widthConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DesignTokens.Color.surfaceElevated
        layer.cornerRadius = 3
        clipsToBounds = true
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(shares: [Double]) {
        segments.forEach { $0.removeFromSuperview() }
        segments = []
        NSLayoutConstraint.deactivate(widthConstraints)
        widthConstraints = []

        var leading = leadingAnchor
        for (slot, share) in shares.enumerated() {
            guard share > 0 else { continue }
            let segment = UIView()
            segment.backgroundColor = TeamSplitPalette.color(forSlot: slot)
            segment.translatesAutoresizingMaskIntoConstraints = false
            addSubview(segment)

            let width = segment.widthAnchor.constraint(
                equalTo: widthAnchor,
                multiplier: min(max(share, 0), 1)
            )
            widthConstraints.append(width)

            NSLayoutConstraint.activate([
                segment.topAnchor.constraint(equalTo: topAnchor),
                segment.bottomAnchor.constraint(equalTo: bottomAnchor),
                segment.leadingAnchor.constraint(equalTo: leading),
                width
            ])
            segments.append(segment)
            leading = segment.trailingAnchor
        }
    }
}

/// 스테이션 한 줄. 더블스는 슬라이더로 비율을, 릴레이는 세그먼트로 담당자를 고른다.
final class TeamSplitStationRowView: UIView {

    /// 더블스: 0번 팀원의 비율이 바뀌었다.
    var onShareChanged: ((Double) -> Void)?
    /// 릴레이: 이 구간을 맡을 팀원이 바뀌었다.
    var onOwnerChanged: ((Int) -> Void)?

    /// 슬라이더 눈금. 1 % 단위는 손가락으로 맞출 수 없고 숫자만 흔들린다.
    private static let shareStep: Double = 0.05

    private let indexLabel = UILabel()
    private let titleLabel = UILabel()
    private let specLabel = UILabel()
    private let totalLabel = UILabel()
    private let slider = UISlider()
    private let ownerControl = UISegmentedControl()
    private let shareBar = TeamSplitShareBarView()
    private let breakdownStack = UIStackView()

    private var isRelay = false
    /// 마지막으로 알린 비율. 슬라이더는 손가락이 움직일 때마다 값을 쏘는데, 눈금에 맞추고 나면
    /// 대부분 같은 값이다 — 같은 값으로 화면 전체를 다시 그리지 않도록 여기서 거른다.
    private var lastNotifiedShare: Double?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        backgroundColor = DesignTokens.Color.surface
        layer.cornerRadius = DesignTokens.Radius.card

        indexLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        indexLabel.textColor = DesignTokens.Color.textTertiary
        indexLabel.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white

        specLabel.font = .systemFont(ofSize: 11, weight: .medium)
        specLabel.textColor = DesignTokens.Color.textTertiary

        totalLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        totalLabel.textColor = DesignTokens.Color.accent
        totalLabel.textAlignment = .right
        totalLabel.setContentHuggingPriority(.required, for: .horizontal)

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.minimumTrackTintColor = TeamSplitPalette.color(forSlot: 0)
        slider.maximumTrackTintColor = TeamSplitPalette.color(forSlot: 1)
        slider.thumbTintColor = .white
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        ownerControl.selectedSegmentTintColor = DesignTokens.Color.accent
        ownerControl.backgroundColor = DesignTokens.Color.surfaceElevated
        ownerControl.setTitleTextAttributes(
            [.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 13, weight: .bold)],
            for: .selected
        )
        ownerControl.setTitleTextAttributes(
            [.foregroundColor: DesignTokens.Color.textSecondary, .font: UIFont.systemFont(ofSize: 13, weight: .medium)],
            for: .normal
        )
        ownerControl.addTarget(self, action: #selector(ownerChanged), for: .valueChanged)

        breakdownStack.axis = .horizontal
        breakdownStack.spacing = 10
        breakdownStack.distribution = .fillEqually

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, specLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        let headerStack = UIStackView(arrangedSubviews: [indexLabel, titleStack, totalLabel])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 10

        let container = UIStackView(arrangedSubviews: [
            headerStack, shareBar, slider, ownerControl, breakdownStack
        ])
        container.axis = .vertical
        container.spacing = 8
        container.setCustomSpacing(10, after: headerStack)
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    // MARK: - Configure

    struct Model {
        let index: Int
        let title: String
        let spec: String
        let totalSeconds: TimeInterval
        let shares: [Double]
        let memberNames: [String]
        let memberSeconds: [TimeInterval]
        let isRelay: Bool
    }

    func configure(with model: Model) {
        isRelay = model.isRelay

        indexLabel.text = String(format: "%02d", model.index + 1)
        titleLabel.text = model.title
        specLabel.text = model.spec
        specLabel.isHidden = model.spec.isEmpty
        totalLabel.text = DurationFormatter.ms(model.totalSeconds)

        shareBar.update(shares: model.shares)

        slider.isHidden = model.isRelay
        ownerControl.isHidden = !model.isRelay

        if model.isRelay {
            configureOwnerControl(names: model.memberNames, shares: model.shares)
        } else {
            let share = model.shares.first ?? 0.5
            slider.setValue(Float(share), animated: false)
            lastNotifiedShare = share
        }

        rebuildBreakdown(model: model)
    }

    private func configureOwnerControl(names: [String], shares: [Double]) {
        if ownerControl.numberOfSegments != names.count {
            ownerControl.removeAllSegments()
            for (index, name) in names.enumerated() {
                ownerControl.insertSegment(withTitle: name, at: index, animated: false)
            }
        } else {
            for (index, name) in names.enumerated() {
                ownerControl.setTitle(name, forSegmentAt: index)
            }
        }
        let owner = shares.firstIndex { $0 >= 0.999 } ?? UISegmentedControl.noSegment
        ownerControl.selectedSegmentIndex = owner
    }

    private func rebuildBreakdown(model: Model) {
        breakdownStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (slot, share) in model.shares.enumerated() where share > 0 {
            let label = UILabel()
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = TeamSplitPalette.color(forSlot: slot)
            label.textAlignment = slot == 0 ? .left : (slot == model.shares.count - 1 ? .right : .center)
            let name = model.memberNames.indices.contains(slot) ? model.memberNames[slot] : "\(slot + 1)"
            let seconds = model.memberSeconds.indices.contains(slot) ? model.memberSeconds[slot] : 0
            label.text = "\(name) \(TeamSplitStrings.sharePercent(share)) · \(DurationFormatter.ms(seconds))"
            breakdownStack.addArrangedSubview(label)
        }

        breakdownStack.isHidden = breakdownStack.arrangedSubviews.isEmpty
    }

    // MARK: - Actions

    @objc private func sliderChanged() {
        let stepped = (Double(slider.value) / Self.shareStep).rounded() * Self.shareStep
        let clamped = min(max(stepped, 0), 1)
        slider.setValue(Float(clamped), animated: false)
        guard lastNotifiedShare.map({ abs($0 - clamped) > 0.0001 }) ?? true else { return }
        lastNotifiedShare = clamped
        onShareChanged?(clamped)
    }

    @objc private func ownerChanged() {
        guard ownerControl.selectedSegmentIndex != UISegmentedControl.noSegment else { return }
        onOwnerChanged?(ownerControl.selectedSegmentIndex)
    }
}
