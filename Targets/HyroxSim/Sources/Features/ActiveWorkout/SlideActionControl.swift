//
//  SlideActionControl.swift
//  HyroxSim
//
//  Created by bbdyno on 4/12/26.
//

import UIKit

final class SlideActionControl: UIControl {

    var title: String = "SLIDE TO NEXT" {
        didSet {
            titleLabel.text = title
            accessibilityLabel = title
        }
    }

    var accentColor: UIColor = DesignTokens.Color.accent {
        didSet { updateAppearance() }
    }

    private let trackView = UIView()
    private let fillView = UIView()
    private let titleLabel = UILabel()
    private let thumbView = UIView()
    private let thumbImageView = UIImageView(
        image: UIImage(systemName: "arrow.right", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
    )

    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private var thumbLeadingConstraint: NSLayoutConstraint!
    private var fillWidthConstraint: NSLayoutConstraint!
    private var thumbWidthConstraint: NSLayoutConstraint!
    private var startOffset: CGFloat = 0
    private var currentOffset: CGFloat = 0

    private let thumbPadding: CGFloat = 6
    private var thumbDiameter: CGFloat { max(52, bounds.height - thumbPadding * 2) }
    private var horizontalInset: CGFloat { max(6, (bounds.height - thumbDiameter) / 2 + 2) }
    private var maxTravel: CGFloat { max(0, bounds.width - horizontalInset * 2 - thumbDiameter) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        trackView.layer.cornerRadius = bounds.height / 2
        fillView.layer.cornerRadius = bounds.height / 2
        thumbView.layer.cornerRadius = thumbDiameter / 2
        thumbWidthConstraint.constant = thumbDiameter
        applyOffset(currentOffset, animated: false)
    }

    func reset(animated: Bool = true) {
        currentOffset = 0
        applyOffset(0, animated: animated)
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        accessibilityTraits.insert(.button)
        accessibilityLabel = title

        trackView.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        trackView.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        trackView.layer.borderWidth = 1
        trackView.clipsToBounds = false
        trackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackView)

        fillView.backgroundColor = accentColor.withAlphaComponent(0.32)
        fillView.clipsToBounds = true
        fillView.translatesAutoresizingMaskIntoConstraints = false
        trackView.addSubview(fillView)

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .black)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        trackView.addSubview(titleLabel)

        thumbView.backgroundColor = accentColor
        thumbView.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        thumbView.layer.borderWidth = 1.5
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        trackView.addSubview(thumbView)

        thumbImageView.tintColor = .white
        thumbImageView.contentMode = .scaleAspectFit
        thumbImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.addSubview(thumbImageView)

        thumbLeadingConstraint = thumbView.leadingAnchor.constraint(
            equalTo: trackView.leadingAnchor,
            constant: 8
        )
        fillWidthConstraint = fillView.widthAnchor.constraint(equalToConstant: 0)
        thumbWidthConstraint = thumbView.widthAnchor.constraint(equalToConstant: 52)

        NSLayoutConstraint.activate([
            trackView.topAnchor.constraint(equalTo: topAnchor),
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            fillView.topAnchor.constraint(equalTo: trackView.topAnchor),
            fillView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
            fillView.bottomAnchor.constraint(equalTo: trackView.bottomAnchor),
            fillWidthConstraint,

            titleLabel.centerXAnchor.constraint(equalTo: trackView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: thumbView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trackView.trailingAnchor, constant: -20),

            thumbLeadingConstraint,
            thumbView.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
            thumbView.heightAnchor.constraint(equalTo: thumbView.widthAnchor),
            thumbWidthConstraint,

            thumbImageView.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor, constant: 20),
            thumbImageView.centerYAnchor.constraint(equalTo: thumbView.centerYAnchor),
            thumbImageView.widthAnchor.constraint(equalToConstant: 22),
            thumbImageView.heightAnchor.constraint(equalToConstant: 22)
        ])

        addGestureRecognizer(panGesture)
        updateAppearance()
    }

    private func updateAppearance() {
        fillView.backgroundColor = accentColor.withAlphaComponent(0.32)
        thumbView.backgroundColor = accentColor
    }

    private func applyOffset(_ offset: CGFloat, animated: Bool) {
        let clamped = min(max(0, offset), maxTravel)
        let progress = maxTravel > 0 ? clamped / maxTravel : 0
        let updates = {
            self.thumbLeadingConstraint.constant = self.horizontalInset + clamped
            let thumbTrailing = self.horizontalInset + clamped + self.thumbDiameter
            self.fillWidthConstraint.constant = thumbTrailing + progress * self.horizontalInset
            self.titleLabel.alpha = max(0.18, 1 - (progress * 1.15))
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.2) {
                updates()
            }
        } else {
            updates()
        }
    }

    private func completeSlide() {
        currentOffset = maxTravel
        applyOffset(currentOffset, animated: true)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        sendActions(for: .primaryActionTriggered)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.reset()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            startOffset = currentOffset
        case .changed:
            let proposed = startOffset + gesture.translation(in: self).x
            currentOffset = min(max(0, proposed), maxTravel)
            applyOffset(currentOffset, animated: false)
        case .ended, .cancelled, .failed:
            if maxTravel > 0, currentOffset / maxTravel >= 0.82 {
                completeSlide()
            } else {
                reset()
            }
        default:
            break
        }
    }
}
