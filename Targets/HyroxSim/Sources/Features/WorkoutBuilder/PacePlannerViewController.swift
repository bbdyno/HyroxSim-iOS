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

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let timePicker = UIPickerView()
    private let pctLabel = UILabel()
    private let tierLabel = UILabel()
    private let resultStack = UIStackView()
    private let footerContainer = UIView()
    private let applyButton = UIButton(type: .system)
    private let finetuneButton = UIButton(type: .system)

    private var selectedHours = 1
    private var selectedMinutes = 20
    private var selectedSeconds = 0
    private var runMode: PacePlanner.RunMode = .adaptive
    private var plan: PacePlan?

    private let stationOrder: [(String, String)] = [
        ("skiErg", "SkiErg"),
        ("sledPush", "Sled Push"),
        ("sledPull", "Sled Pull"),
        ("burpeeBroadJumps", "Burpee Broad Jumps"),
        ("rowing", "Rowing"),
        ("farmersCarry", "Farmers Carry"),
        ("sandbagLunges", "Sandbag Lunges"),
        ("wallBalls", "Wall Balls")
    ]

    init(template: WorkoutTemplate, planner: PacePlanner) {
        self.template = template
        self.planner = planner
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pace Planner"
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

        finetuneButton.setTitle("Fine-tune", for: .normal)
        finetuneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        finetuneButton.setTitleColor(DesignTokens.Color.accent, for: .normal)
        finetuneButton.backgroundColor = DesignTokens.Color.surface
        finetuneButton.layer.cornerRadius = 24
        finetuneButton.layer.borderWidth = 1
        finetuneButton.layer.borderColor = DesignTokens.Color.accent.cgColor
        finetuneButton.translatesAutoresizingMaskIntoConstraints = false
        finetuneButton.addTarget(self, action: #selector(finetuneTapped), for: .touchUpInside)
        footerContainer.addSubview(finetuneButton)

        applyButton.setTitle("Apply Goals", for: .normal)
        applyButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        applyButton.setTitleColor(.black, for: .normal)
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
        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toggle.topAnchor.constraint(equalTo: container.topAnchor),
            toggle.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            toggle.widthAnchor.constraint(equalToConstant: 120),
            hint.leadingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: 10),
            hint.centerYAnchor.constraint(equalTo: toggle.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 32)
        ])

        return container
    }

    private func setInitialPickerValues() {
        guard let division = template.division,
              let div = planner.data.divisions[division.rawValue] else { return }

        // If template already has goals set, use the total as initial value
        let existingTotal = Int(template.estimatedDurationSeconds)
        let hasExistingGoals = template.segments.contains { $0.goalDurationSeconds != nil }

        var bestSec: Int
        if hasExistingGoals && existingTotal > 0 {
            bestSec = existingTotal
        } else {
            // Find 50th percentile time (matching site's setupTime)
            let bs = div.buckets
            bestSec = (bs.first!.loMin + bs.last!.hiMin) / 2 * 60
            for i in 0..<bs.count {
                let avg = (bs[i].pctRange[0] + bs[i].pctRange[1]) / 2
                if avg >= 50 {
                    if i == 0 {
                        bestSec = (bs[0].loMin + bs[0].hiMin) / 2 * 60
                    } else {
                        let prev = (bs[i - 1].pctRange[0] + bs[i - 1].pctRange[1]) / 2
                        let t = (50 - prev) / (avg - prev)
                        let prevMid = Double(bs[i - 1].loMin + bs[i - 1].hiMin) / 2
                        let curMid = Double(bs[i].loMin + bs[i].hiMin) / 2
                        bestSec = Int((prevMid + (curMid - prevMid) * t) * 60)
                    }
                    break
                }
            }
        }

        selectedHours = bestSec / 3600
        selectedMinutes = (bestSec % 3600) / 60
        selectedSeconds = bestSec % 60

        timePicker.selectRow(selectedHours, inComponent: 0, animated: false)
        timePicker.selectRow(selectedMinutes, inComponent: 2, animated: false)
        timePicker.selectRow(selectedSeconds, inComponent: 4, animated: false)
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        delegate?.pacePlannerDidCancel()
    }

    @objc private func applyTapped() {
        guard let plan else { return }
        applyPlanToTemplate(plan)
        delegate?.pacePlannerDidConfirm(template: template)
    }

    @objc private func finetuneTapped() {
        guard let plan else { return }
        applyPlanToTemplate(plan)

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
        guard let division = template.division else { return }
        let goalS = selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds
        guard goalS > 0 else { return }

        guard let p = planner.computePlan(goalTotalS: goalS, division: division, mode: runMode) else { return }
        plan = p

        updatePercentileDisplay(p)
        buildResult(p)
    }

    private func updatePercentileDisplay(_ plan: PacePlan) {
        let pct = plan.percentile
        let tier = PacePlanner.tier(for: pct)
        let color = tierColor(pct)

        tierLabel.text = "\(DurationFormatter.hms(TimeInterval(plan.goalTotalS))) — \(tier)"
        tierLabel.textColor = color

        pctLabel.text = String(format: Self.L.percentileFormat, pct)
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
        for i in 0..<8 {
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
            let (key, name) = stationOrder[i]
            if let stnSec = plan.stationTimes[key] {
                let hasPace = key == "skiErg" || key == "rowing"
                let paceText = hasPace ? "\(DurationFormatter.ms(TimeInterval(stnSec / 2))) /500m" : nil
                resultStack.addArrangedSubview(makeRow(
                    title: name,
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
                if let kind = seg.stationKind {
                    let key: String
                    switch kind {
                    case .skiErg: key = "skiErg"
                    case .sledPush: key = "sledPush"
                    case .sledPull: key = "sledPull"
                    case .burpeeBroadJumps: key = "burpeeBroadJumps"
                    case .rowing: key = "rowing"
                    case .farmersCarry: key = "farmersCarry"
                    case .sandbagLunges: key = "sandbagLunges"
                    case .wallBalls: key = "wallBalls"
                    case .custom: key = ""
                    }
                    if let secs = plan.stationTimes[key] {
                        template.segments[i].goalDurationSeconds = TimeInterval(secs)
                    }
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
        static var modeEqual: String {
            NSLocalizedString("pace_planner.mode.equal", comment: "Equal run-split mode label")
        }
        static var modeAdaptive: String {
            NSLocalizedString("pace_planner.mode.adaptive", comment: "Adaptive (data-based) run-split mode label")
        }
        static var percentileFormat: String {
            NSLocalizedString("pace_planner.percentile.format", comment: "Percentile display, e.g. 'Top 12.3%'")
        }

        static func modeHint(_ mode: PacePlanner.RunMode) -> String {
            switch mode {
            case .adaptive:
                return NSLocalizedString("pace_planner.mode.hint.adaptive", comment: "Hint for adaptive run-split")
            case .equal:
                return NSLocalizedString("pace_planner.mode.hint.equal", comment: "Hint for equal run-split")
            }
        }
    }
}

// MARK: - UIPickerView (h:m:s)

extension PacePlannerViewController: UIPickerViewDataSource, UIPickerViewDelegate {

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 6 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch component {
        case 0: return 3
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
            label.text = String(format: "%02d", row)
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
        case 0: selectedHours = row
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
