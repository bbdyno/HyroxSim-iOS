//
//  WorkoutGoalSetupViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/12/26.
//

import UIKit
import HyroxCore

@MainActor
protocol WorkoutGoalSetupViewControllerDelegate: AnyObject {
    func goalSetupDidCancel()
    func goalSetupDidConfirm(template: WorkoutTemplate)
}

final class WorkoutGoalSetupViewController: UIViewController {

    weak var delegate: WorkoutGoalSetupViewControllerDelegate?

    private var template: WorkoutTemplate
    private let screenTitle: String
    private let confirmButtonTitle: String
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let totalGoalLabel = UILabel()
    private var goalFields: [Int: UITextField] = [:]
    private let footerContainer = UIView()
    private let startButton = UIButton(type: .system)

    init(
        template: WorkoutTemplate,
        screenTitle: String = "Set Goals",
        confirmButtonTitle: String = "Start Workout"
    ) {
        self.template = template
        self.screenTitle = screenTitle
        self.confirmButtonTitle = confirmButtonTitle
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = screenTitle
        view.backgroundColor = DesignTokens.Color.background
        applyDarkNavBarAppearance()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        setupFooter()
        setupLayout()
        buildContent()
        updateTotalGoal()
    }

    @objc private func cancelTapped() {
        delegate?.goalSetupDidCancel()
    }

    @objc private func startTapped() {
        applyGoals()
        delegate?.goalSetupDidConfirm(template: template)
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerContainer.topAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24)
        ])
    }

    private func setupFooter() {
        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.backgroundColor = DesignTokens.Color.background
        view.addSubview(footerContainer)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        footerContainer.addSubview(separator)

        startButton.setTitle(confirmButtonTitle, for: .normal)
        startButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        startButton.setTitleColor(.black, for: .normal)
        startButton.backgroundColor = DesignTokens.Color.accent
        startButton.layer.cornerRadius = 24
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        footerContainer.addSubview(startButton)

        NSLayoutConstraint.activate([
            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            separator.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            startButton.topAnchor.constraint(equalTo: footerContainer.topAnchor, constant: 12),
            startButton.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            startButton.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            startButton.heightAnchor.constraint(equalToConstant: 48),
            startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    private func buildContent() {
        let titleLabel = UILabel()
        titleLabel.text = template.isBuiltIn ? (template.division?.displayName ?? template.name) : template.name
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        contentStack.addArrangedSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = HyroxSimStrings.Localizable.GoalSetup.subtitle
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = DesignTokens.Color.textSecondary
        subtitleLabel.numberOfLines = 0
        contentStack.addArrangedSubview(subtitleLabel)

        totalGoalLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        totalGoalLabel.textColor = DesignTokens.Color.accent
        contentStack.addArrangedSubview(totalGoalLabel)

        addSeparator()

        for index in template.segments.indices {
            let record = template.segments[index]
            let row = makeGoalRow(for: record, index: index)
            contentStack.addArrangedSubview(row)
        }
    }

    private func makeGoalRow(for segment: WorkoutSegment, index: Int) -> UIView {
        let container = UIView()

        let titleLabel = UILabel()
        titleLabel.text = rowTitle(for: segment, at: index)
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = accentColor(for: segment.type)

        let detailLabel = UILabel()
        detailLabel.text = rowDetail(for: segment)
        detailLabel.font = .systemFont(ofSize: 11, weight: .medium)
        detailLabel.textColor = DesignTokens.Color.textTertiary

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 2

        let field = UITextField()
        field.tag = index
        field.text = DurationFormatter.ms(segment.goalDurationSeconds ?? defaultGoal(for: segment))
        field.keyboardType = .numbersAndPunctuation
        field.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        field.textAlignment = .center
        field.textColor = .white
        field.backgroundColor = DesignTokens.Color.surface
        field.layer.cornerRadius = 10
        field.heightAnchor.constraint(equalToConstant: 42).isActive = true
        field.widthAnchor.constraint(equalToConstant: 88).isActive = true
        field.addTarget(self, action: #selector(goalFieldChanged(_:)), for: .editingChanged)
        goalFields[index] = field

        let row = UIStackView(arrangedSubviews: [labels, field])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        let separator = UIView()
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        return container
    }

    @objc private func goalFieldChanged(_ sender: UITextField) {
        updateTotalGoal()
    }

    private func applyGoals() {
        for index in template.segments.indices {
            let current = template.segments[index]
            let parsed = parsedDuration(for: goalFields[index]?.text)
            template.segments[index] = WorkoutSegment(
                id: current.id,
                type: current.type,
                distanceMeters: current.distanceMeters,
                goalDurationSeconds: parsed ?? current.goalDurationSeconds ?? defaultGoal(for: current),
                stationKind: current.stationKind,
                stationTarget: current.stationTarget,
                weightKg: current.weightKg,
                weightNote: current.weightNote
            )
        }
    }

    private func updateTotalGoal() {
        let total = template.segments.indices.reduce(0.0) { partial, index in
            partial + (parsedDuration(for: goalFields[index]?.text) ?? template.segments[index].goalDurationSeconds ?? defaultGoal(for: template.segments[index]))
        }
        totalGoalLabel.text = HyroxSimStrings.Localizable.Workout.goalTotalFormat(DurationFormatter.hms(total))
    }

    private func rowTitle(for segment: WorkoutSegment, at index: Int) -> String {
        switch segment.type {
        case .run:
            let runIndex = template.segments[0...index].filter { $0.type == .run }.count
            return "RUN \(runIndex)"
        case .roxZone:
            let roxIndex = template.segments[0...index].filter { $0.type == .roxZone }.count
            return "ROX ZONE \(roxIndex)"
        case .station:
            return segment.stationKind?.displayName ?? "Station"
        }
    }

    private func rowDetail(for segment: WorkoutSegment) -> String {
        switch segment.type {
        case .run:
            return DistanceFormatter.short(segment.distanceMeters ?? 0)
        case .roxZone:
            return template.usesRoxZone ? "Transition" : ""
        case .station:
            return segment.stationTarget?.formatted ?? ""
        }
    }

    private func accentColor(for type: SegmentType) -> UIColor {
        switch type {
        case .run: return DesignTokens.Color.runAccent
        case .roxZone: return DesignTokens.Color.roxZoneAccent
        case .station: return DesignTokens.Color.stationAccent
        }
    }

    private func defaultGoal(for segment: WorkoutSegment) -> TimeInterval {
        segment.goalDurationSeconds ?? WorkoutSegment.defaultGoalDurationSeconds(
            for: segment.type,
            distanceMeters: segment.distanceMeters
        )
    }

    private func parsedDuration(for text: String?) -> TimeInterval? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ":")
        if parts.count == 2,
           let minutes = Double(parts[0]),
           let seconds = Double(parts[1]) {
            return max(0, minutes * 60 + seconds)
        }
        if let seconds = Double(trimmed) {
            return max(0, seconds)
        }
        return nil
    }

    private func addSeparator() {
        let separator = UIView()
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        contentStack.addArrangedSubview(separator)
    }
}
