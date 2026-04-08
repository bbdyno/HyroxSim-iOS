//
//  WorkoutSummaryViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

@MainActor
protocol WorkoutSummaryViewControllerDelegate: AnyObject {
    func summaryDidTapDone()
    func summaryDidTapShare(_ workout: CompletedWorkout)
}

/// Workout summary screen — black + yellow accent, matching HYROX results aesthetic.
final class WorkoutSummaryViewController: UIViewController {

    weak var delegate: WorkoutSummaryViewControllerDelegate?
    private let viewModel: WorkoutSummaryViewModel
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let accent = DesignTokens.Color.accent
    private let bg = DesignTokens.Color.background
    private let surface = DesignTokens.Color.surface

    init(viewModel: WorkoutSummaryViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Summary"
        view.backgroundColor = bg
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped))

        // Style nav bar for dark theme
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bg
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance

        setupScrollView()
        buildContent()
    }

    @objc private func doneTapped() { delegate?.summaryDidTapDone() }
    @objc private func shareTapped() { delegate?.summaryDidTapShare(viewModel.workout) }

    // MARK: - Layout

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        let margin: CGFloat = 20
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: margin),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -margin)
        ])
    }

    private func buildContent() {
        // Header
        addSpacer(16)
        addCenteredLabel(viewModel.totalTimeText, font: DesignTokens.Font.largeNumber, color: .white)
        addSpacer(4)
        addCenteredLabel("TOTAL TIME", font: DesignTokens.Font.label, color: DesignTokens.Color.textTertiary)
        addSpacer(12)
        addCenteredLabel(viewModel.titleText, font: .systemFont(ofSize: 16, weight: .bold), color: accent)
        addCenteredLabel(viewModel.dateText, font: .systemFont(ofSize: 12, weight: .medium), color: DesignTokens.Color.textTertiary)
        addSpacer(24)
        addSeparator()

        // Summary table header (yellow)
        addSpacer(16)
        addTableHeader(["Split", "Time", "Place"])
        addSpacer(8)

        // Segment breakdown — HYROX results style
        let segments = viewModel.workout.segments
        var stationIndex = 0
        for (i, record) in segments.enumerated() {
            switch record.type {
            case .run:
                let runNum = segments[0...i].filter { $0.type == .run }.count
                addSegmentRow(badge: nil, name: "Running \(runNum)", time: DurationFormatter.hms(record.activeDuration), isBold: false)
            case .roxZone:
                // ROX Zone rows are subtle
                addSegmentRow(badge: nil, name: "Rox Zone", time: DurationFormatter.hms(record.activeDuration), isBold: false, dimmed: true)
            case .station:
                stationIndex += 1
                let displayName = viewModel.workout.resolvedStationDisplayName(for: record) ?? "Station"
                addSegmentRow(
                    badge: String(format: "%02d", stationIndex),
                    name: displayName,
                    time: DurationFormatter.hms(record.activeDuration),
                    isBold: true
                )
            }
        }

        // Summary totals (like the reference bottom section)
        addSpacer(12)
        addSeparator()
        addSpacer(8)
        addSummaryRow("Roxzone Time", viewModel.totalRoxZoneTimeText, highlighted: true)
        addSummaryRow("Run Total", viewModel.totalRunTimeText, highlighted: true)
        addSpacer(4)
        addSummaryRow("Avg Pace", viewModel.averagePaceText, highlighted: false)
        addSummaryRow("Avg HR", viewModel.averageHeartRateText, highlighted: false)
        addSummaryRow("Max HR", viewModel.maxHeartRateText, highlighted: false)
        addSpacer(20)
    }

    // MARK: - Row Builders

    private func addTableHeader(_ columns: [String]) {
        let row = UIStackView()
        row.distribution = .fillProportionally

        let col1 = makeLabel(columns[0], font: .systemFont(ofSize: 13, weight: .bold), color: accent)
        col1.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        row.addArrangedSubview(col1)

        let col2 = makeLabel(columns[1], font: .systemFont(ofSize: 13, weight: .bold), color: accent)
        col2.textAlignment = .center
        row.addArrangedSubview(col2)

        if columns.count > 2 {
            let col3 = makeLabel(columns[2], font: .systemFont(ofSize: 13, weight: .bold), color: accent)
            col3.textAlignment = .right
            col3.widthAnchor.constraint(equalToConstant: 50).isActive = true
            row.addArrangedSubview(col3)
        }

        contentStack.addArrangedSubview(row)
        addSeparator(color: accent.withAlphaComponent(0.3))
    }

    private func addSegmentRow(badge: String?, name: String, time: String, isBold: Bool, dimmed: Bool = false) {
        let row = UIStackView()
        row.alignment = .center
        row.spacing = 8

        // Badge
        if let badge {
            let bv = UIView()
            bv.backgroundColor = accent
            bv.layer.cornerRadius = DesignTokens.Radius.badge
            bv.translatesAutoresizingMaskIntoConstraints = false
            bv.widthAnchor.constraint(equalToConstant: 30).isActive = true
            bv.heightAnchor.constraint(equalToConstant: 20).isActive = true

            let bl = UILabel()
            bl.text = badge
            bl.font = .systemFont(ofSize: 11, weight: .black)
            bl.textColor = .black
            bl.textAlignment = .center
            bl.translatesAutoresizingMaskIntoConstraints = false
            bv.addSubview(bl)
            NSLayoutConstraint.activate([
                bl.centerXAnchor.constraint(equalTo: bv.centerXAnchor),
                bl.centerYAnchor.constraint(equalTo: bv.centerYAnchor)
            ])
            row.addArrangedSubview(bv)
        } else {
            let spacer = UIView()
            spacer.widthAnchor.constraint(equalToConstant: 30).isActive = true
            row.addArrangedSubview(spacer)
        }

        let alpha: CGFloat = dimmed ? 0.4 : 1.0
        let nameLabel = makeLabel(name,
            font: isBold ? .systemFont(ofSize: 15, weight: .bold) : .systemFont(ofSize: 14, weight: .regular),
            color: DesignTokens.Color.textPrimary.withAlphaComponent(alpha))
        row.addArrangedSubview(nameLabel)

        let timeLabel = makeLabel(time,
            font: .monospacedDigitSystemFont(ofSize: 14, weight: .medium),
            color: DesignTokens.Color.textPrimary.withAlphaComponent(alpha))
        timeLabel.textAlignment = .right
        timeLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
        row.addArrangedSubview(timeLabel)

        let container = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        contentStack.addArrangedSubview(container)
    }

    private func addSummaryRow(_ label: String, _ value: String, highlighted: Bool) {
        let row = UIStackView()
        row.distribution = .fill

        let lbl = makeLabel(label,
            font: .systemFont(ofSize: 14, weight: highlighted ? .bold : .medium),
            color: highlighted ? accent : DesignTokens.Color.textSecondary)
        row.addArrangedSubview(lbl)

        let val = makeLabel(value,
            font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            color: highlighted ? accent : DesignTokens.Color.textPrimary)
        val.textAlignment = .right
        row.addArrangedSubview(val)

        let container = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        contentStack.addArrangedSubview(container)
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = color
        return l
    }

    private func addCenteredLabel(_ text: String, font: UIFont, color: UIColor) {
        let l = makeLabel(text, font: font, color: color)
        l.textAlignment = .center
        contentStack.addArrangedSubview(l)
    }

    private func addSpacer(_ height: CGFloat) {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        contentStack.addArrangedSubview(v)
    }

    private func addSeparator(color: UIColor = UIColor.white.withAlphaComponent(0.1)) {
        let v = UIView()
        v.backgroundColor = color
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        contentStack.addArrangedSubview(v)
    }
}
