//
//  PacePlannerViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/17/26.
//

import UIKit
import HyroxCore

@MainActor
protocol PacePlannerViewControllerDelegate: AnyObject {
    func pacePlannerDidCancel()
    func pacePlannerDidConfirm(template: WorkoutTemplate)
}

/// HYROX 페이스 플래너: 목표 완주 시간 → 버킷 보간 → 구간별 목표 분배.
final class PacePlannerViewController: UIViewController {

    weak var delegate: PacePlannerViewControllerDelegate?

    private var template: WorkoutTemplate
    private let planner: PacePlanner
    private let goalOverrideStore: TemplateGoalOverrideStore

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let timePicker = UIPickerView()
    private let pctLabel = UILabel()
    private let tierLabel = UILabel()
    private let rangeHintLabel = UILabel()
    private let warningLabel = UILabel()
    private let resultStack = UIStackView()
    private let footerContainer = UIView()
    private let applyButton = UIButton(type: .system)
    private let finetuneButton = UIButton(type: .system)

    /// 이 디비전의 버킷이 실제로 덮는 목표 시간 구간. 피커 범위와 경고의 기준이다.
    /// 데이터에 없는 디비전이면 nil.
    private let goalRange: PaceGoalRange?

    /// 데이터가 없을 때만 쓰는 피커 폴백 (0–4시간).
    private static let fallbackHourRange = 0...4

    /// 시(hour) 행은 데이터에서 뽑는다. 분·초는 열어 두고, 범위를 벗어난 조합은
    /// `warningLabel` + Apply 비활성화로 잡는다.
    private var pickerHourRange: ClosedRange<Int> {
        guard let goalRange else { return Self.fallbackHourRange }
        return (goalRange.minTotalS / 3600)...(goalRange.maxTotalS / 3600)
    }

    private var minSelectableSeconds: Int { pickerHourRange.lowerBound * 3600 }
    private var maxSelectableSeconds: Int { pickerHourRange.upperBound * 3600 + 59 * 60 + 59 }

    private var selectedHours = 1
    private var selectedMinutes = 20
    private var selectedSeconds = 0
    private var runMode: PacePlanner.RunMode = .adaptive
    private var plan: PacePlan?

    init(
        template: WorkoutTemplate,
        planner: PacePlanner,
        goalOverrideStore: TemplateGoalOverrideStore
    ) {
        self.template = template
        self.planner = planner
        self.goalOverrideStore = goalOverrideStore
        self.goalRange = template.division.flatMap { planner.goalRange(for: $0) }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = HyroxSimStrings.Localizable.Nav.pacePlanner
        view.backgroundColor = DesignTokens.Color.background
        applyDarkNavBarAppearance()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self, action: #selector(cancelTapped)
        )
        setupFooter()
        setupLayout()
        buildContent()
        setInitialPickerValues()
        performAnalysis()
    }

    // MARK: - Layout

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

        finetuneButton.setTitle(HyroxSimStrings.Localizable.Button.finetune, for: .normal)
        finetuneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        finetuneButton.setTitleColor(DesignTokens.Color.accent, for: .normal)
        finetuneButton.backgroundColor = DesignTokens.Color.surface
        finetuneButton.layer.cornerRadius = 24
        finetuneButton.layer.borderWidth = 1
        finetuneButton.layer.borderColor = DesignTokens.Color.accent.cgColor
        finetuneButton.translatesAutoresizingMaskIntoConstraints = false
        finetuneButton.addTarget(self, action: #selector(finetuneTapped), for: .touchUpInside)
        footerContainer.addSubview(finetuneButton)

        applyButton.setTitle(HyroxSimStrings.Localizable.Button.applyGoals, for: .normal)
        applyButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        applyButton.setTitleColor(.black, for: .normal)
        applyButton.setTitleColor(DesignTokens.Color.textSecondary, for: .disabled)
        applyButton.backgroundColor = DesignTokens.Color.accent
        applyButton.layer.cornerRadius = 24
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)
        footerContainer.addSubview(applyButton)

        NSLayoutConstraint.activate([
            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            separator.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            finetuneButton.topAnchor.constraint(equalTo: footerContainer.topAnchor, constant: 12),
            finetuneButton.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            finetuneButton.heightAnchor.constraint(equalToConstant: 48),

            applyButton.topAnchor.constraint(equalTo: finetuneButton.topAnchor),
            applyButton.leadingAnchor.constraint(equalTo: finetuneButton.trailingAnchor, constant: 12),
            applyButton.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            applyButton.heightAnchor.constraint(equalToConstant: 48),
            applyButton.widthAnchor.constraint(equalTo: finetuneButton.widthAnchor),
            applyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    // MARK: - Content

    private func buildContent() {
        // Division + athlete count
        let divLabel = UILabel()
        divLabel.text = template.division?.displayName ?? template.name
        divLabel.font = .systemFont(ofSize: 22, weight: .bold)
        divLabel.textColor = .white
        contentStack.addArrangedSubview(divLabel)

        if let division = template.division,
           let div = planner.data.divisions[division.rawValue] {
            let countLabel = UILabel()
            countLabel.text = "\(formatNumber(div.totalAthletes)) race results"
            countLabel.font = .systemFont(ofSize: 12, weight: .medium)
            countLabel.textColor = DesignTokens.Color.textTertiary
            contentStack.addArrangedSubview(countLabel)
        }

        // Goal time header
        let goalHeader = UILabel()
        goalHeader.text = "GOAL FINISH TIME"
        goalHeader.font = DesignTokens.Font.label
        goalHeader.textColor = DesignTokens.Color.accent
        contentStack.addArrangedSubview(goalHeader)

        // 이 화면이 계획할 수 있는 구간을 먼저 알려 준다 — 피커가 왜 거기서 멈추는지 설명.
        rangeHintLabel.font = .systemFont(ofSize: 11, weight: .medium)
        rangeHintLabel.textColor = DesignTokens.Color.textTertiary
        rangeHintLabel.numberOfLines = 0
        if let goalRange {
            rangeHintLabel.text = Self.L.dataRangeHint(
                DurationFormatter.hms(TimeInterval(goalRange.minTotalS)),
                DurationFormatter.hms(TimeInterval(goalRange.maxTotalS))
            )
        } else {
            rangeHintLabel.isHidden = true
        }
        contentStack.addArrangedSubview(rangeHintLabel)

        // Percentile display
        tierLabel.font = .systemFont(ofSize: 14, weight: .bold)
        tierLabel.textAlignment = .center
        contentStack.addArrangedSubview(tierLabel)

        pctLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        pctLabel.textColor = DesignTokens.Color.textSecondary
        pctLabel.textAlignment = .center
        contentStack.addArrangedSubview(pctLabel)

        // Time picker (h:m:s)
        timePicker.dataSource = self
        timePicker.delegate = self
        timePicker.translatesAutoresizingMaskIntoConstraints = false
        timePicker.heightAnchor.constraint(equalToConstant: 140).isActive = true
        contentStack.addArrangedSubview(timePicker)

        // 데이터 범위를 벗어났거나 분배가 목표에 못 맞은 경우의 경고
        warningLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        warningLabel.textColor = DesignTokens.Color.destructive
        warningLabel.numberOfLines = 0
        warningLabel.textAlignment = .center
        warningLabel.isHidden = true
        contentStack.addArrangedSubview(warningLabel)

        // Run mode toggle
        let modeRow = makeRunModeToggle()
        contentStack.addArrangedSubview(modeRow)

        // Result area
        resultStack.axis = .vertical
        resultStack.spacing = 6
        contentStack.addArrangedSubview(resultStack)
    }

    private func makeRunModeToggle() -> UIView {
        let container = UIView()

        let toggle = UISegmentedControl(items: [
            Self.L.modeEqual,
            Self.L.modeAdaptive
        ])
        toggle.selectedSegmentIndex = runMode == .equal ? 0 : 1
        toggle.addTarget(self, action: #selector(runModeChanged(_:)), for: .valueChanged)
        toggle.selectedSegmentTintColor = DesignTokens.Color.accent
        toggle.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 13, weight: .bold)], for: .selected)
        toggle.setTitleTextAttributes([.foregroundColor: DesignTokens.Color.textSecondary, .font: UIFont.systemFont(ofSize: 13, weight: .medium)], for: .normal)
        toggle.translatesAutoresizingMaskIntoConstraints = false

        let hint = UILabel()
        hint.text = Self.L.modeHint(runMode)
        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = DesignTokens.Color.textTertiary
        hint.tag = 100
        hint.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(toggle)
        container.addSubview(hint)
        toggle.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toggle.topAnchor.constraint(equalTo: container.topAnchor),
            toggle.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hint.leadingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: 10),
            hint.centerYAnchor.constraint(equalTo: toggle.centerYAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            container.heightAnchor.constraint(equalToConstant: 32)
        ])

        return container
    }

    private func setInitialPickerValues() {
        applyGoalSeconds(initialGoalSeconds())
    }

    /// 목표 시간을 피커가 표현할 수 있는 범위로 자른 뒤, 내부 상태와 피커 행을 함께 맞춘다.
    private func applyGoalSeconds(_ seconds: Int) {
        let clamped = min(max(minSelectableSeconds, seconds), maxSelectableSeconds)
        selectedHours = clamped / 3600
        selectedMinutes = (clamped % 3600) / 60
        selectedSeconds = clamped % 60

        timePicker.selectRow(selectedHours - pickerHourRange.lowerBound, inComponent: 0, animated: false)
        timePicker.selectRow(selectedMinutes, inComponent: 2, animated: false)
        timePicker.selectRow(selectedSeconds, inComponent: 4, animated: false)
    }

    private func initialGoalSeconds() -> Int {
        let currentSelection = selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds
        guard let division = template.division else { return currentSelection }

        if startsFromExistingGoals {
            let existingTotal = LocalizedDecimalFormatter.safeInt(template.estimatedDurationSeconds)
            if existingTotal > 0 { return existingTotal }
        }

        // 한 번도 목표를 정한 적이 없으면 이 디비전의 중앙값에서 출발한다.
        return planner.medianGoalSeconds(for: division) ?? currentSelection
    }

    /// 피커 시작값을 "이미 들어 있는 목표"로 둘지, 데이터 중앙값으로 둘지 판단한다.
    ///
    /// 프리셋 세그먼트는 만들어질 때부터 기본 목표(런 360초 / 스테이션 240초)를 들고 있어서
    /// 목표의 존재 여부로는 사용자가 정했는지 알 수 없다 — 그래서 모든 프리셋이 늘 1:27:30 에서
    /// 시작했다. 빌트인 프리셋은 `TemplateGoalOverrideStore` 에 저장된 override 가 유일한 근거다.
    /// 커스텀 템플릿은 override 저장소를 쓰지 않고 목표를 템플릿 자체에 들고 있으므로 그대로 쓴다.
    private var startsFromExistingGoals: Bool {
        guard template.isBuiltIn, let division = template.division else { return true }

        // 저장된 override 가 있을 때만 프리셋 원본과 다른 템플릿이 돌아온다.
        // 여기로 들어온 template 은 이미 override 가 적용된 상태일 수 있어 원본과 비교한다.
        let preset = HyroxPresets.template(for: division)
        return goalOverrideStore.resolvedTemplate(from: preset) != preset
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        delegate?.pacePlannerDidCancel()
    }

    @objc private func applyTapped() {
        guard let plan, plan.isApplicable else { return }
        applyPlanToTemplate(plan)
        delegate?.pacePlannerDidConfirm(template: template)
    }

    @objc private func finetuneTapped() {
        // 적용 가능한 플랜일 때만 템플릿에 쓴다. 데이터 범위를 벗어난 플랜은
        // 손으로 고치러 들어가는 길만 열어 두고 기존 목표는 건드리지 않는다.
        if let plan, plan.isApplicable {
            applyPlanToTemplate(plan)
        }

        let goalVC = WorkoutGoalSetupViewController(
            template: template,
            screenTitle: "Fine-tune Goals",
            confirmButtonTitle: "Save Goals"
        )
        goalVC.delegate = self
        navigationController?.pushViewController(goalVC, animated: true)
    }

    @objc private func runModeChanged(_ sender: UISegmentedControl) {
        runMode = sender.selectedSegmentIndex == 0 ? .equal : .adaptive
        // Update hint label
        if let hint = sender.superview?.viewWithTag(100) as? UILabel {
            hint.text = Self.L.modeHint(runMode)
        }
        performAnalysis()
    }

    // MARK: - Analysis

    private func performAnalysis() {
        guard let division = template.division else {
            updateGuardrails(for: nil, goalSeconds: 0)
            return
        }
        let goalS = selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds

        let computed = goalS > 0
            ? planner.computePlan(goalTotalS: goalS, division: division, mode: runMode)
            : nil
        plan = computed

        guard let computed else {
            // 목표 0 처럼 계획을 세울 수 없는 상태. 직전 결과를 남겨 두면 그 값이
            // 적용될 것처럼 보이므로 지운다.
            resultStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            tierLabel.text = nil
            pctLabel.text = nil
            updateGuardrails(for: nil, goalSeconds: goalS)
            return
        }

        updatePercentileDisplay(computed)
        buildResult(computed)
        updateGuardrails(for: computed, goalSeconds: goalS)
    }

    /// 경고 문구와 Apply 활성 여부를 한곳에서 정한다.
    private func updateGuardrails(for plan: PacePlan?, goalSeconds: Int) {
        let warning = warningText(for: plan, goalSeconds: goalSeconds)
        warningLabel.text = warning
        warningLabel.isHidden = warning == nil

        let canApply = plan?.isApplicable ?? false
        applyButton.isEnabled = canApply
        applyButton.backgroundColor = canApply
            ? DesignTokens.Color.accent
            : DesignTokens.Color.surfaceElevated
    }

    private func warningText(for plan: PacePlan?, goalSeconds: Int) -> String? {
        let range = plan?.goalRange ?? goalRange
        switch plan?.rangeStatus ?? range?.status(for: goalSeconds) {
        case .fasterThanData:
            guard let range else { return nil }
            return Self.L.warningTooFast(DurationFormatter.hms(TimeInterval(range.minTotalS)))
        case .slowerThanData:
            guard let range else { return nil }
            return Self.L.warningTooSlow(DurationFormatter.hms(TimeInterval(range.maxTotalS)))
        case .inRange, .none:
            // 범위 안인데도 보정 루프가 목표에 정확히 못 맞은 경우.
            guard let plan, plan.computedTotal != plan.goalTotalS else { return nil }
            return Self.L.warningUnbalanced
        }
    }

    private func updatePercentileDisplay(_ plan: PacePlan) {
        let pct = plan.percentile
        let tier = PacePlanner.tier(for: pct)
        let color = tierColor(pct)

        tierLabel.text = "\(DurationFormatter.hms(TimeInterval(plan.goalTotalS))) — \(tier)"
        tierLabel.textColor = color

        pctLabel.text = Self.L.percentileFormat(Float(pct))
    }

    private func buildResult(_ plan: PacePlan) {
        resultStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        addSeparator()

        // Breakdown
        let breakdownLabel = UILabel()
        breakdownLabel.font = .systemFont(ofSize: 12, weight: .medium)
        breakdownLabel.textColor = DesignTokens.Color.textTertiary
        breakdownLabel.textAlignment = .center
        breakdownLabel.text = "Run \(DurationFormatter.ms(TimeInterval(plan.runTotal))) + Station \(DurationFormatter.ms(TimeInterval(plan.stationTotal)))"
        resultStack.addArrangedSubview(breakdownLabel)

        addSeparator()

        // Runs + Stations interleaved (matching site: Run 1, Station 1, Run 2, Station 2, ...)
        for (i, station) in StationKind.standardOrder.enumerated() {
            guard i < plan.runTimes.count else { break }
            let runSec = plan.runTimes[i]
            let runPace = DurationFormatter.ms(TimeInterval(Int(Double(runSec) / 1.0875)))

            // Run row
            resultStack.addArrangedSubview(makeRow(
                title: "Run \(i + 1) + Roxzone",
                time: DurationFormatter.ms(TimeInterval(runSec)),
                subtitle: "\(runPace) /km",
                color: DesignTokens.Color.runAccent
            ))

            // Station row
            if let key = station.dataKey, let stnSec = plan.stationTimes[key] {
                let hasPace = station == .skiErg || station == .rowing
                let paceText = hasPace ? "\(DurationFormatter.ms(TimeInterval(stnSec / 2))) /500m" : nil
                resultStack.addArrangedSubview(makeRow(
                    title: station.displayName,
                    time: DurationFormatter.ms(TimeInterval(stnSec)),
                    subtitle: paceText,
                    color: DesignTokens.Color.stationAccent,
                    elevated: true
                ))
            }
        }

        addSeparator()

        // Total row
        let totalRow = UIView()
        let totalTitle = UILabel()
        totalTitle.text = "TOTAL"
        totalTitle.font = .systemFont(ofSize: 14, weight: .bold)
        totalTitle.textColor = .white

        let totalTime = UILabel()
        totalTime.text = DurationFormatter.hms(TimeInterval(plan.computedTotal))
        totalTime.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        totalTime.textColor = DesignTokens.Color.accent
        totalTime.textAlignment = .right

        let totalStack = UIStackView(arrangedSubviews: [totalTitle, totalTime])
        totalStack.axis = .horizontal
        totalStack.distribution = .fill
        totalStack.translatesAutoresizingMaskIntoConstraints = false

        totalRow.addSubview(totalStack)
        NSLayoutConstraint.activate([
            totalStack.topAnchor.constraint(equalTo: totalRow.topAnchor, constant: 8),
            totalStack.leadingAnchor.constraint(equalTo: totalRow.leadingAnchor),
            totalStack.trailingAnchor.constraint(equalTo: totalRow.trailingAnchor),
            totalStack.bottomAnchor.constraint(equalTo: totalRow.bottomAnchor, constant: -4)
        ])
        resultStack.addArrangedSubview(totalRow)
    }

    private func applyPlanToTemplate(_ plan: PacePlan) {
        // Plan's runTimes[i] = Run + Roxzone combined.
        // Run segment gets the full combined goal. Rox segment gets 0.
        // Delta calculation: goal(run+rox) - actual(run+rox) → 합산 기준.
        var runIndex = 0

        for i in template.segments.indices {
            let seg = template.segments[i]
            switch seg.type {
            case .run:
                if runIndex < plan.runTimes.count {
                    template.segments[i].goalDurationSeconds = TimeInterval(plan.runTimes[runIndex])
                    runIndex += 1
                }
            case .station:
                if let key = seg.stationKind?.dataKey, let secs = plan.stationTimes[key] {
                    template.segments[i].goalDurationSeconds = TimeInterval(secs)
                }
            case .roxZone:
                template.segments[i].goalDurationSeconds = 0
            }
        }
    }

    // MARK: - Helpers

    private func makeRow(title: String, time: String, subtitle: String?, color: UIColor, elevated: Bool = false) -> UIView {
        let container = UIView()
        container.backgroundColor = elevated ? DesignTokens.Color.surface : .clear
        container.layer.cornerRadius = 8

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = color

        let timeLabel = UILabel()
        timeLabel.text = time
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .right

        let right = UIStackView(arrangedSubviews: subtitle != nil ? [makePaceLabel(subtitle!), timeLabel] : [timeLabel])
        right.axis = .horizontal
        right.spacing = 8
        right.alignment = .center

        let row = UIStackView(arrangedSubviews: [titleLabel, right])
        row.axis = .horizontal
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: elevated ? 12 : 0),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: elevated ? -12 : 0),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -7)
        ])

        return container
    }

    private func makePaceLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = DesignTokens.Color.textTertiary
        return label
    }

    private func addSeparator() {
        let sep = UIView()
        sep.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        resultStack.addArrangedSubview(sep)
    }

    private func tierColor(_ pct: Double) -> UIColor {
        // HYROX 블랙+골드 테마에 맞춘 warm→cool 톤 (레퍼런스 사이트의 금/은/동/초록/파랑/보라/회색 팔레트와 의도적으로 차별화)
        if pct <= 1  { return UIColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1) } // apex — gold
        if pct <= 3  { return UIColor(red: 1.00, green: 0.65, blue: 0.15, alpha: 1) } // pro — amber
        if pct <= 5  { return UIColor(red: 1.00, green: 0.46, blue: 0.36, alpha: 1) } // expert — coral
        if pct <= 10 { return UIColor(red: 0.95, green: 0.35, blue: 0.55, alpha: 1) } // strong — salmon-pink
        if pct <= 25 { return UIColor(red: 0.30, green: 0.80, blue: 0.70, alpha: 1) } // solid — mint
        if pct <= 50 { return UIColor(red: 0.35, green: 0.72, blue: 0.92, alpha: 1) } // steady — cyan
        if pct <= 75 { return UIColor(red: 0.67, green: 0.60, blue: 0.90, alpha: 1) } // rising — lilac
        return UIColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1)                   // starter — neutral gray
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Localized strings

    fileprivate enum L {
        static var modeEqual: String { HyroxSimStrings.Localizable.PacePlanner.Mode.equal }
        static var modeAdaptive: String { HyroxSimStrings.Localizable.PacePlanner.Mode.adaptive }
        static var warningUnbalanced: String { HyroxSimStrings.Localizable.PacePlanner.Warning.unbalanced }

        static func dataRangeHint(_ fastest: String, _ slowest: String) -> String {
            HyroxSimStrings.Localizable.PacePlanner.DataRange.hint(fastest, slowest)
        }

        static func warningTooFast(_ fastest: String) -> String {
            HyroxSimStrings.Localizable.PacePlanner.Warning.tooFast(fastest)
        }

        static func warningTooSlow(_ slowest: String) -> String {
            HyroxSimStrings.Localizable.PacePlanner.Warning.tooSlow(slowest)
        }

        static func percentileFormat(_ percent: Float) -> String {
            HyroxSimStrings.Localizable.PacePlanner.Percentile.format(percent)
        }

        static func modeHint(_ mode: PacePlanner.RunMode) -> String {
            switch mode {
            case .adaptive: return HyroxSimStrings.Localizable.PacePlanner.Mode.Hint.adaptive
            case .equal: return HyroxSimStrings.Localizable.PacePlanner.Mode.Hint.equal
            }
        }
    }
}

// MARK: - UIPickerView (h:m:s)

extension PacePlannerViewController: UIPickerViewDataSource, UIPickerViewDelegate {

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 6 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch component {
        case 0: return pickerHourRange.count
        case 2: return 60
        case 4: return 60
        default: return 1
        }
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        switch component {
        case 0, 2, 4: return 44
        case 1, 3, 5: return 24
        default: return 44
        }
    }

    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let label = (view as? UILabel) ?? UILabel()
        label.textColor = .white

        switch component {
        case 0, 2, 4:
            label.textAlignment = .right
            label.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
            // 시 컴포넌트는 데이터 범위의 첫 시간부터 시작하므로 행 번호와 값이 다를 수 있다.
            label.text = String(format: "%02d", component == 0 ? pickerHourRange.lowerBound + row : row)
        case 1:
            label.textAlignment = .left
            label.font = .systemFont(ofSize: 16, weight: .medium)
            label.text = "h"
            label.textColor = DesignTokens.Color.textSecondary
        case 3:
            label.textAlignment = .left
            label.font = .systemFont(ofSize: 16, weight: .medium)
            label.text = "m"
            label.textColor = DesignTokens.Color.textSecondary
        case 5:
            label.textAlignment = .left
            label.font = .systemFont(ofSize: 16, weight: .medium)
            label.text = "s"
            label.textColor = DesignTokens.Color.textSecondary
        default:
            break
        }
        return label
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        switch component {
        case 0: selectedHours = pickerHourRange.lowerBound + row
        case 2: selectedMinutes = row
        case 4: selectedSeconds = row
        default: break
        }
        performAnalysis()
    }
}

// MARK: - WorkoutGoalSetupViewControllerDelegate (fine-tune)

extension PacePlannerViewController: WorkoutGoalSetupViewControllerDelegate {

    func goalSetupDidCancel() {
        navigationController?.popViewController(animated: true)
    }

    func goalSetupDidConfirm(template: WorkoutTemplate) {
        self.template = template
        delegate?.pacePlannerDidConfirm(template: template)
    }
}
