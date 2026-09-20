//
//  TeamSplitPlannerViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import UIKit
import HyroxCore

/// 더블스·릴레이 분담 계획 화면.
///
/// 계산은 전부 `TeamSplitCalculator`(순수 함수)가 한다. 이 화면은 값을 보여 주고,
/// 슬라이더·세그먼트로 만든 새 계획을 다시 계산기에 넣는 일만 한다.
final class TeamSplitPlannerViewController: UIViewController {

    // MARK: - 상태

    private var plan: TeamSplitPlan {
        didSet { refresh() }
    }

    /// 사용자가 고른 디비전. 포맷을 바꿀 때 기준이 된다.
    private let baseDivision: HyroxDivision
    private let raceTargetId: UUID?
    private let paceData: (any PaceDataProviding)?
    private let store: TeamSplitPlanStore

    /// 목표 시간 조절 단위·한계. 팀 목표는 분 단위면 충분하다.
    private static let goalStepSeconds: TimeInterval = 60
    private static let goalRangeSeconds: ClosedRange<TimeInterval> = (30 * 60)...(3 * 60 * 60)
    /// 이 비중을 넘으면 "한쪽으로 쏠렸다" 고 알린다.
    private static let imbalanceWarningShare: Double = 0.6

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let formatControl = UISegmentedControl()
    private let entryLabel = UILabel()
    private let ruleLabel = UILabel()
    private let goalValueLabel = UILabel()
    private let summaryStack = UIStackView()
    private let memberStack = UIStackView()
    private let stationStack = UIStackView()
    private let warningLabel = UILabel()
    private let noteLabel = UILabel()
    private let resetButton = UIButton(type: .system)
    private var stationRows: [TeamSplitStationRowView] = []

    // MARK: - Init

    init(
        division: HyroxDivision,
        goalSeconds: TimeInterval,
        raceTargetId: UUID?,
        paceData: (any PaceDataProviding)? = nil,
        store: TeamSplitPlanStore? = nil
    ) {
        // 기본 인자 자리에서 만들면 nonisolated 컨텍스트라 @MainActor 초기화가 막힌다.
        self.baseDivision = division
        self.raceTargetId = raceTargetId
        let store = store ?? TeamSplitPlanStore()
        self.store = store

        // 화면마다 표를 새로 읽지 않는다 — 번들 스냅샷은 한 번 디코드되면 캐시된다.
        if let paceData {
            self.paceData = paceData
        } else {
            self.paceData = try? PaceReferenceLoader.loadBundledPaceData()
        }

        // 지난번에 릴레이로 짜 두었으면 릴레이로 다시 연다. 포맷까지 기억하지 않으면
        // 릴레이 계획은 화면을 닫는 순간 사라진다.
        let stored = store.plan(raceTargetId: raceTargetId)
        let entry: TeamEntry = stored?.entry.format == .relay
            ? .relay(RelayDivision(matching: division))
            : .doubles(division.doublesCounterpart)

        let dataset = try? self.paceData?.dataset(for: entry.referenceDivision)
        // 목표가 없으면 이 디비전의 중앙값에서 시작한다 — 0 에서 시작하면 아무것도 못 보여 준다.
        let fallbackGoal = TimeInterval(dataset?.goalSeconds(atPercentile: 50) ?? 5_400)
        let resolvedGoal = goalSeconds > 0 ? goalSeconds : fallbackGoal

        if let stored, stored.entry.format == entry.format {
            // 저장된 분담은 그대로 쓰되 디비전은 지금 고른 값을 따른다(무게가 바뀌었을 수 있다).
            self.plan = TeamSplitPlan(
                entry: entry,
                goalTotalSeconds: stored.goalTotalSeconds > 0 ? stored.goalTotalSeconds : resolvedGoal,
                memberNames: stored.memberNames,
                stationShares: stored.stationShares
            )
        } else {
            self.plan = .balanced(entry: entry, goalTotalSeconds: resolvedGoal)
        }

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = TeamSplitStrings.title
        view.backgroundColor = DesignTokens.Color.background
        applyDarkNavBarAppearance()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        setupLayout()
        buildContent()
        refresh()
    }

    // MARK: - Layout

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32)
        ])
    }

    private func buildContent() {
        buildFormatControl()

        entryLabel.font = .systemFont(ofSize: 20, weight: .bold)
        entryLabel.textColor = .white
        entryLabel.numberOfLines = 0
        contentStack.addArrangedSubview(entryLabel)

        ruleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        ruleLabel.textColor = DesignTokens.Color.textSecondary
        ruleLabel.numberOfLines = 0
        contentStack.addArrangedSubview(ruleLabel)

        contentStack.addArrangedSubview(makeSectionHeader(TeamSplitStrings.sectionGoal))
        contentStack.addArrangedSubview(makeGoalCard())

        summaryStack.axis = .vertical
        summaryStack.spacing = 8
        summaryStack.isLayoutMarginsRelativeArrangement = true
        summaryStack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        summaryStack.backgroundColor = DesignTokens.Color.surface
        summaryStack.layer.cornerRadius = DesignTokens.Radius.card
        contentStack.addArrangedSubview(summaryStack)

        warningLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        warningLabel.textColor = DesignTokens.Color.roxZoneAccent
        warningLabel.numberOfLines = 0
        contentStack.addArrangedSubview(warningLabel)

        contentStack.addArrangedSubview(makeSectionHeader(TeamSplitStrings.sectionWorkload))
        memberStack.axis = .vertical
        memberStack.spacing = 10
        contentStack.addArrangedSubview(memberStack)

        contentStack.addArrangedSubview(makeSectionHeader(TeamSplitStrings.sectionStations))
        stationStack.axis = .vertical
        stationStack.spacing = 10
        contentStack.addArrangedSubview(stationStack)

        for index in 0..<TeamSplitPlan.stationCount {
            let row = TeamSplitStationRowView()
            row.onShareChanged = { [weak self] share in
                guard let self else { return }
                self.plan = self.plan.settingShare(share, stationAt: index, slot: 0)
            }
            row.onOwnerChanged = { [weak self] slot in
                guard let self else { return }
                self.plan = self.plan.assigning(stationAt: index, to: slot)
            }
            stationRows.append(row)
            stationStack.addArrangedSubview(row)
        }

        resetButton.setTitle(TeamSplitStrings.resetButton, for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        resetButton.setTitleColor(DesignTokens.Color.accent, for: .normal)
        resetButton.setTitleColor(DesignTokens.Color.textTertiary, for: .disabled)
        resetButton.backgroundColor = DesignTokens.Color.surface
        resetButton.layer.cornerRadius = DesignTokens.Radius.card
        resetButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(resetButton)

        noteLabel.font = .systemFont(ofSize: 11, weight: .medium)
        noteLabel.textColor = DesignTokens.Color.textTertiary
        noteLabel.numberOfLines = 0
        contentStack.addArrangedSubview(noteLabel)
    }

    private func buildFormatControl() {
        for (index, format) in TeamFormat.allCases.enumerated() {
            formatControl.insertSegment(withTitle: TeamSplitStrings.formatName(format), at: index, animated: false)
        }
        formatControl.selectedSegmentIndex = TeamFormat.allCases.firstIndex(of: plan.entry.format) ?? 0
        formatControl.selectedSegmentTintColor = DesignTokens.Color.accent
        formatControl.backgroundColor = DesignTokens.Color.surface
        formatControl.setTitleTextAttributes(
            [.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 13, weight: .bold)],
            for: .selected
        )
        formatControl.setTitleTextAttributes(
            [.foregroundColor: DesignTokens.Color.textSecondary, .font: UIFont.systemFont(ofSize: 13, weight: .medium)],
            for: .normal
        )
        formatControl.addTarget(self, action: #selector(formatChanged), for: .valueChanged)
        contentStack.addArrangedSubview(formatControl)
    }

    private func makeGoalCard() -> UIView {
        goalValueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        goalValueLabel.textColor = .white
        goalValueLabel.textAlignment = .center

        let minusButton = makeStepperButton(symbol: "minus", action: #selector(goalDownTapped))
        let plusButton = makeStepperButton(symbol: "plus", action: #selector(goalUpTapped))

        let stack = UIStackView(arrangedSubviews: [minusButton, goalValueLabel, plusButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = DesignTokens.Color.surface
        container.layer.cornerRadius = DesignTokens.Radius.card
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeStepperButton(symbol: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: symbol)
        config.cornerStyle = .capsule
        config.baseBackgroundColor = DesignTokens.Color.surfaceElevated
        config.baseForegroundColor = DesignTokens.Color.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        button.configuration = config
        button.addTarget(self, action: action, for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func makeSectionHeader(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = DesignTokens.Font.label
        label.textColor = DesignTokens.Color.accent

        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])
        return container
    }

    // MARK: - 갱신

    private func refresh() {
        entryLabel.text = plan.entry.displayName
        ruleLabel.text = TeamSplitStrings.ruleNote(plan.entry.format)
        goalValueLabel.text = DurationFormatter.hms(plan.goalTotalSeconds)
        resetButton.isEnabled = !plan.isBalanced

        guard let dataset = try? paceData?.dataset(for: plan.entry.referenceDivision) else {
            showUnavailableState()
            return
        }

        let reference = TeamSplitReference.make(
            entry: plan.entry,
            dataset: dataset,
            goalSeconds: Int(plan.goalTotalSeconds.rounded())
        )
        let result = TeamSplitCalculator.result(for: plan, reference: reference)

        updateSummary(result)
        updateMembers(result)
        updateStations(result)
        updateWarning(result)

        noteLabel.text = reference.isEstimated
            ? TeamSplitStrings.estimatedNote(division: reference.division.displayName)
            : TeamSplitStrings.referenceNote(division: reference.division.displayName)

        store.save(plan, raceTargetId: raceTargetId)
    }

    private func showUnavailableState() {
        summaryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        memberStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stationStack.isHidden = true
        warningLabel.isHidden = true
        noteLabel.text = TeamSplitStrings.referenceNote(division: plan.entry.referenceDivision.displayName)
    }

    private func updateSummary(_ result: TeamSplitResult) {
        summaryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        summaryStack.addArrangedSubview(makeSummaryRow(
            title: TeamSplitStrings.projectedFinish,
            value: DurationFormatter.hms(result.projectedTotalSeconds),
            emphasised: true
        ))

        if plan.entry.format.splitsRunning {
            let perAthlete = result.members.map(\.runSeconds).max() ?? 0
            summaryStack.addArrangedSubview(makeSummaryRow(
                title: TeamSplitStrings.runPerAthlete,
                value: DurationFormatter.ms(perAthlete)
            ))
        } else {
            summaryStack.addArrangedSubview(makeSummaryRow(
                title: TeamSplitStrings.sharedRun,
                value: DurationFormatter.ms(result.sharedRunRoxSeconds)
            ))
        }

        summaryStack.addArrangedSubview(makeSummaryRow(
            title: TeamSplitStrings.loadGap,
            value: result.imbalanceSeconds < 1
                ? TeamSplitStrings.evenSplit
                : DurationFormatter.ms(result.imbalanceSeconds)
        ))
    }

    private func makeSummaryRow(title: String, value: String, emphasised: Bool = false) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = DesignTokens.Color.textSecondary

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = emphasised
            ? .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
            : .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.textColor = emphasised ? DesignTokens.Color.accent : .white
        valueLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        return row
    }

    private func updateMembers(_ result: TeamSplitResult) {
        memberStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let teamStationSeconds = result.teamStationSeconds

        for member in result.members {
            memberStack.addArrangedSubview(
                makeMemberCard(member, teamStationSeconds: teamStationSeconds)
            )
        }
    }

    private func makeMemberCard(_ member: TeamMemberLoad, teamStationSeconds: TimeInterval) -> UIView {
        let nameLabel = UILabel()
        nameLabel.text = member.name
        nameLabel.font = .systemFont(ofSize: 16, weight: .bold)
        nameLabel.textColor = TeamSplitPalette.color(forSlot: member.slot)

        let totalLabel = UILabel()
        totalLabel.text = DurationFormatter.ms(member.totalSeconds)
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        totalLabel.textColor = .white
        totalLabel.textAlignment = .right

        let header = UIStackView(arrangedSubviews: [nameLabel, totalLabel])
        header.axis = .horizontal
        header.alignment = .firstBaseline

        let share = teamStationSeconds > 0 ? member.stationSeconds / teamStationSeconds : 0
        let bar = TeamSplitShareBarView()
        // 이 사람의 몫만 자기 색으로 칠하고 나머지는 빈칸으로 둔다.
        var shares = Array(repeating: 0.0, count: member.slot + 1)
        shares[member.slot] = share
        bar.update(shares: shares)

        var parts = ["\(TeamSplitStrings.memberStations) \(DurationFormatter.ms(member.stationSeconds))"]
        if member.runSeconds > 0 {
            parts.append("\(TeamSplitStrings.memberRunning) \(DurationFormatter.ms(member.runSeconds))")
        }
        parts.append("\(TeamSplitStrings.memberRest) \(DurationFormatter.ms(member.restSeconds))")

        let detailLabel = UILabel()
        detailLabel.text = parts.joined(separator: " · ")
        detailLabel.font = .systemFont(ofSize: 11, weight: .medium)
        detailLabel.textColor = DesignTokens.Color.textTertiary
        detailLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [header, bar, detailLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.backgroundColor = DesignTokens.Color.surface
        stack.layer.cornerRadius = DesignTokens.Radius.card
        return stack
    }

    private func updateStations(_ result: TeamSplitResult) {
        stationStack.isHidden = false
        let specs = HyroxDivisionSpec.stations(for: plan.entry.weightDivision(forSlot: 0))
        let isRelay = plan.entry.format.splitsRunning

        for (index, station) in StationKind.standardOrder.enumerated() {
            guard stationRows.indices.contains(index) else { continue }
            let shares = (0..<plan.memberCount).map { plan.share(stationAt: index, slot: $0) }
            let total = result.reference.seconds(for: station)

            stationRows[index].configure(with: .init(
                index: index,
                title: station.displayName,
                spec: specText(for: specs.first { $0.kind == station }),
                totalSeconds: total,
                shares: shares,
                memberNames: (0..<plan.memberCount).map { plan.name(forSlot: $0) },
                memberSeconds: shares.map { $0 * total },
                isRelay: isRelay
            ))
        }
    }

    private func specText(for spec: HyroxStationSpec?) -> String {
        guard let spec else { return "" }
        var text = spec.target.formatted
        if let weight = spec.weightKg {
            text += " · \(LocalizedDecimalFormatter.safeInt(weight))kg"
            if let note = spec.weightNote { text += " \(note)" }
        }
        return text
    }

    private func updateWarning(_ result: TeamSplitResult) {
        // 릴레이는 한 사람이 두 구간을 통째로 맡는 게 정상이라, 쏠림 경고는 더블스에만 건다.
        guard !plan.entry.format.splitsRunning,
              result.peakStationShare > Self.imbalanceWarningShare else {
            warningLabel.isHidden = true
            return
        }
        warningLabel.isHidden = false
        warningLabel.text = TeamSplitStrings.imbalanceWarning(
            percent: Int((result.peakStationShare * 100).rounded())
        )
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func goalUpTapped() {
        adjustGoal(by: Self.goalStepSeconds)
    }

    @objc private func goalDownTapped() {
        adjustGoal(by: -Self.goalStepSeconds)
    }

    private func adjustGoal(by delta: TimeInterval) {
        let next = plan.goalTotalSeconds + delta
        let clamped = min(max(next, Self.goalRangeSeconds.lowerBound), Self.goalRangeSeconds.upperBound)
        guard clamped != plan.goalTotalSeconds else { return }
        plan = plan.settingGoalTotalSeconds(clamped)
    }

    @objc private func formatChanged() {
        let format = TeamFormat.allCases.indices.contains(formatControl.selectedSegmentIndex)
            ? TeamFormat.allCases[formatControl.selectedSegmentIndex]
            : plan.entry.format
        guard format != plan.entry.format else { return }

        let entry: TeamEntry
        switch format {
        case .doubles: entry = .doubles(baseDivision.doublesCounterpart)
        case .relay: entry = .relay(RelayDivision(matching: baseDivision))
        }
        // 팀원 수가 달라지므로 분담은 기본값으로 다시 시작한다.
        plan = .balanced(entry: entry, goalTotalSeconds: plan.goalTotalSeconds)
    }

    @objc private func resetTapped() {
        plan = plan.resettingToBalanced()
    }
}
