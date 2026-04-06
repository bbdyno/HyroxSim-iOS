import UIKit
import HyroxKit

/// Custom card for HYROX division presets. Black + yellow accent aesthetic.
final class PresetCardCell: UICollectionViewCell {

    static let reuseId = "PresetCardCell"

    private let containerView = UIView()
    private let badgeView = UIView()
    private let badgeLabel = UILabel()
    private let shortNameLabel = UILabel()
    private let divisionLabel = UILabel()
    private let detailLabel = UILabel()
    private let chevron = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = DesignTokens.Color.surface
        containerView.layer.cornerRadius = DesignTokens.Radius.card
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.white.withAlphaComponent(0.06).cgColor
        contentView.addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])

        // Yellow accent badge (like 01, 02... in the reference)
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.backgroundColor = DesignTokens.Color.accent
        badgeView.layer.cornerRadius = DesignTokens.Radius.badge
        containerView.addSubview(badgeView)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 12, weight: .black)
        badgeLabel.textColor = .black
        badgeLabel.textAlignment = .center
        badgeView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badgeView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            badgeView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            badgeView.widthAnchor.constraint(equalToConstant: 36),
            badgeView.heightAnchor.constraint(equalToConstant: 22),
            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor)
        ])

        // Short name
        shortNameLabel.translatesAutoresizingMaskIntoConstraints = false
        shortNameLabel.font = .systemFont(ofSize: 26, weight: .black)
        shortNameLabel.textColor = DesignTokens.Color.textPrimary
        containerView.addSubview(shortNameLabel)
        NSLayoutConstraint.activate([
            shortNameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            shortNameLabel.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 12)
        ])

        // Division full name
        divisionLabel.translatesAutoresizingMaskIntoConstraints = false
        divisionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        divisionLabel.textColor = DesignTokens.Color.textSecondary
        containerView.addSubview(divisionLabel)
        NSLayoutConstraint.activate([
            divisionLabel.topAnchor.constraint(equalTo: shortNameLabel.bottomAnchor, constant: 2),
            divisionLabel.leadingAnchor.constraint(equalTo: shortNameLabel.leadingAnchor)
        ])

        // Detail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        detailLabel.textColor = DesignTokens.Color.textTertiary
        containerView.addSubview(detailLabel)
        NSLayoutConstraint.activate([
            detailLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            detailLabel.leadingAnchor.constraint(equalTo: shortNameLabel.leadingAnchor)
        ])

        // Yellow line accent at left edge
        let leftBar = UIView()
        leftBar.translatesAutoresizingMaskIntoConstraints = false
        leftBar.backgroundColor = DesignTokens.Color.accent
        containerView.addSubview(leftBar)
        NSLayoutConstraint.activate([
            leftBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            leftBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            leftBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            leftBar.widthAnchor.constraint(equalToConstant: 3)
        ])

        // Chevron
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = DesignTokens.Color.textTertiary
        chevron.contentMode = .scaleAspectFit
        containerView.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    func configure(with template: WorkoutTemplate) {
        let division = template.division
        shortNameLabel.text = division?.shortName ?? template.name
        divisionLabel.text = division?.displayName ?? template.name

        let stations = template.segments.filter { $0.type == .station }.count
        let mins = Int(template.estimatedDurationSeconds / 60)
        detailLabel.text = "\(stations) stations  ·  ~\(mins) min"

        // Badge shows division category
        if let d = division {
            switch d {
            case .menOpenSingle, .menOpenDouble: badgeLabel.text = "OPEN"
            case .menProSingle, .menProDouble: badgeLabel.text = "PRO"
            case .womenOpenSingle, .womenOpenDouble: badgeLabel.text = "OPEN"
            case .womenProSingle, .womenProDouble: badgeLabel.text = "PRO"
            case .mixedDouble: badgeLabel.text = "MIX"
            }
        } else {
            badgeLabel.text = "—"
        }
    }
}
