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

final class WorkoutSummaryViewController: UIViewController {

    weak var delegate: WorkoutSummaryViewControllerDelegate?

    private let viewModel: WorkoutSummaryViewModel
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var expandedRunGroups: Set<String> = []

    init(viewModel: WorkoutSummaryViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Summary"
        view.backgroundColor = DesignTokens.Color.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareTapped)
        )
        applyDarkNavigationStyle()
        setupScrollView()
        rebuildContent()
    }

    @objc private func doneTapped() {
        delegate?.summaryDidTapDone()
    }

    @objc private func shareTapped() {
        delegate?.summaryDidTapShare(viewModel.workout)
    }

    private func applyDarkNavigationStyle() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = DesignTokens.Color.background
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
    }

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
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20)
        ])
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        addHeader()
        addMetricStrip()

        for section in viewModel.sections {
            if let runGroup = section.runGroup {
                let isExpandable = runGroup.detailItems.count > 1
                let isExpanded = expandedRunGroups.contains(runGroup.id)
                contentStack.addArrangedSubview(
                    makeMainRow(
                        badgeText: "R\(String(format: "%02d", runGroup.index))",
                        badgeTint: DesignTokens.Color.runAccent,
                        title: runGroup.title,
                        subtitle: runGroup.subtitle,
                        duration: runGroup.durationText,
                        delta: runGroup.delta,
                        showsChevron: isExpandable,
                        expanded: isExpanded,
                        tapTag: isExpandable ? runGroup.id : nil
                    )
                )

                if isExpanded {
                    for detail in runGroup.detailItems {
                        contentStack.addArrangedSubview(makeDetailRow(detail))
                    }
                }
            }

            if let station = section.station {
                contentStack.addArrangedSubview(
                    makeMainRow(
                        badgeText: String(format: "%02d", station.index),
                        badgeTint: DesignTokens.Color.stationAccent,
                        title: station.title,
                        subtitle: station.subtitle,
                        duration: station.durationText,
                        delta: station.delta,
                        showsChevron: false,
                        expanded: false,
                        tapTag: nil
                    )
                )
            }
        }
    }

    private func addHeader() {
        let totalLabel = UILabel()
        totalLabel.text = viewModel.totalTimeText
        totalLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 42, weight: .black)
        totalLabel.textColor = .white
        totalLabel.textAlignment = .center

        let deltaLabel = UILabel()
        deltaLabel.text = viewModel.totalDelta.text
        deltaLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .black)
        deltaLabel.textColor = color(for: viewModel.totalDelta.tone)
        deltaLabel.textAlignment = .center

        let goalLabel = UILabel()
        goalLabel.text = "Goal \(viewModel.totalGoalText)"
        goalLabel.font = .systemFont(ofSize: 12, weight: .bold)
        goalLabel.textColor = DesignTokens.Color.textSecondary
        goalLabel.textAlignment = .center

        let titleLabel = UILabel()
        titleLabel.text = viewModel.titleText
        titleLabel.font = .systemFont(ofSize: 15, weight: .black)
        titleLabel.textColor = DesignTokens.Color.accent
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        let dateLabel = UILabel()
        dateLabel.text = viewModel.dateText
        dateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        dateLabel.textColor = DesignTokens.Color.textSecondary
        dateLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [totalLabel, deltaLabel, goalLabel, titleLabel, dateLabel])
        stack.axis = .vertical
        stack.spacing = 4
        contentStack.addArrangedSubview(stack)
    }

    private func addMetricStrip() {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually

        for metric in viewModel.headerMetrics {
            row.addArrangedSubview(makeMetricCard(title: metric.title, value: metric.value))
        }

        contentStack.addArrangedSubview(row)
    }

    private func makeMetricCard(title: String, value: String) -> UIView {
        let container = UIView()
        container.backgroundColor = DesignTokens.Color.surface
        container.layer.cornerRadius = 14

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 10, weight: .black)
        titleLabel.textColor = DesignTokens.Color.textSecondary
        titleLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [valueLabel, titleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        return container
    }

    private func makeMainRow(
        badgeText: String,
        badgeTint: UIColor,
        title: String,
        subtitle: String?,
        duration: String,
        delta: WorkoutSummaryViewModel.GoalDelta,
        showsChevron: Bool,
        expanded: Bool,
        tapTag: String?
    ) -> UIView {
        let container = UIView()
        container.backgroundColor = DesignTokens.Color.surface
        container.layer.cornerRadius = 16

        if let tapTag {
            container.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(runGroupTapped(_:)))
            container.addGestureRecognizer(tap)
            container.accessibilityIdentifier = tapTag
        }

        let badge = UILabel()
        badge.text = badgeText
        badge.font = .systemFont(ofSize: 10, weight: .black)
        badge.textColor = .black
        badge.textAlignment = .center
        badge.backgroundColor = badgeTint
        badge.layer.cornerRadius = 10
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 42).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .black)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = DesignTokens.Color.textSecondary
        subtitleLabel.numberOfLines = 1
        subtitleLabel.isHidden = subtitle == nil

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        let durationLabel = UILabel()
        durationLabel.text = duration
        durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .right

        let deltaLabel = UILabel()
        deltaLabel.text = delta.text
        deltaLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .black)
        deltaLabel.textColor = color(for: delta.tone)
        deltaLabel.textAlignment = .right

        let trailingStack = UIStackView(arrangedSubviews: [durationLabel, deltaLabel])
        trailingStack.axis = .vertical
        trailingStack.spacing = 2
        trailingStack.alignment = .trailing

        let row = UIStackView(arrangedSubviews: [badge, titleStack, trailingStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        let trailingConstraint: NSLayoutConstraint
        if showsChevron {
            trailingConstraint = row.trailingAnchor.constraint(
                equalTo: container.trailingAnchor,
                constant: -34
            )
        } else {
            trailingConstraint = row.trailingAnchor.constraint(
                equalTo: container.trailingAnchor,
                constant: -12
            )
        }

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            trailingConstraint,
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        if showsChevron {
            let chevron = UILabel()
            chevron.text = expanded ? "▾" : "▸"
            chevron.font = .systemFont(ofSize: 15, weight: .black)
            chevron.textColor = DesignTokens.Color.textSecondary
            chevron.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(chevron)
            NSLayoutConstraint.activate([
                chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                chevron.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12)
            ])
        }

        return container
    }

    private func makeDetailRow(_ detail: WorkoutSummaryViewModel.DetailItem) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(0.04)
        container.layer.cornerRadius = 14

        let accent = accentColor(for: detail.accent)

        let dot = UIView()
        dot.backgroundColor = accent
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = detail.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = accent

        let subtitleLabel = UILabel()
        subtitleLabel.text = detail.subtitle
        subtitleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        subtitleLabel.textColor = DesignTokens.Color.textSecondary
        subtitleLabel.isHidden = detail.subtitle == nil

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        let durationLabel = UILabel()
        durationLabel.text = detail.durationText
        durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .right

        let deltaLabel = UILabel()
        deltaLabel.text = detail.delta.text
        deltaLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        deltaLabel.textColor = color(for: detail.delta.tone)
        deltaLabel.textAlignment = .right

        let trailingStack = UIStackView(arrangedSubviews: [durationLabel, deltaLabel])
        trailingStack.axis = .vertical
        trailingStack.spacing = 2
        trailingStack.alignment = .trailing

        let row = UIStackView(arrangedSubviews: [dot, titleStack, trailingStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        return container
    }

    @objc private func runGroupTapped(_ gesture: UITapGestureRecognizer) {
        guard
            let id = gesture.view?.accessibilityIdentifier,
            !id.isEmpty
        else { return }

        if expandedRunGroups.contains(id) {
            expandedRunGroups.remove(id)
        } else {
            expandedRunGroups.insert(id)
        }
        rebuildContent()
    }

    private func color(for tone: WorkoutSummaryViewModel.DeltaTone) -> UIColor {
        switch tone {
        case .ahead: return DesignTokens.Color.success
        case .behind: return .systemRed
        case .neutral: return UIColor.white.withAlphaComponent(0.78)
        }
    }

    private func accentColor(for accent: WorkoutSummaryViewModel.DetailItem.Accent) -> UIColor {
        switch accent {
        case .run: return DesignTokens.Color.runAccent
        case .roxZone: return DesignTokens.Color.roxZoneAccent
        case .station: return DesignTokens.Color.stationAccent
        }
    }
}
