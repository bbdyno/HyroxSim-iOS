//
//  PFTBenchmarkViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import UIKit
import HyroxCore

/// PFT 벤치마크 화면.
///
/// 공식 PFT 프로토콜을 보여 주고, 완료 시간(기록에서 읽거나 직접 입력)을 받아
/// 추천 디비전과 예상 완주 범위를 낸다. 해석은 전부 `PFTBenchmarkEvaluator`(순수 함수)가 하고,
/// 이 화면은 값을 넣고 받은 결과를 그리는 일만 한다.
final class PFTBenchmarkViewController: UIViewController {

    // MARK: - 상태

    private let record: CompletedWorkout?
    private let recordSeconds: Int?
    private let recordStepSeconds: [PFTStep: TimeInterval]
    private let paceData: (any PaceDataProviding)?

    private var projectionDivision: HyroxDivision
    private var selectedMinutes: Int
    private var selectedSeconds: Int

    private var totalSeconds: Int { selectedMinutes * 60 + selectedSeconds }

    /// 기록에서 읽은 시간을 그대로 쓰고 있는지 여부.
    /// 사용자가 시간을 손으로 바꾸면 구간 기록과 총 시간이 어긋나므로 구간 비교를 내린다.
    private var usesRecordSplits: Bool {
        guard let recordSeconds else { return false }
        return recordSeconds == totalSeconds
    }

    private static let maximumMinutes = 99

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let summaryLabel = UILabel()
    private let protocolStack = UIStackView()
    private let sourceLabel = UILabel()
    private let timePicker = UIPickerView()
    private let divisionChipStack = UIStackView()
    private let resultStack = UIStackView()
    private let splitStack = UIStackView()
    private let noteLabel = UILabel()

    // MARK: - Init

    init(
        record: CompletedWorkout?,
        defaultDivision: HyroxDivision?,
        paceData: (any PaceDataProviding)? = nil
    ) {
        self.record = record
        let seconds = record.flatMap { PFTBenchmark.totalSeconds(of: $0) }
        self.recordSeconds = seconds.map { LocalizedDecimalFormatter.safeInt($0) }
        self.recordStepSeconds = record.map { PFTBenchmark.stepSeconds(of: $0) } ?? [:]
        self.projectionDivision = defaultDivision ?? .menOpenSingle

        if let paceData {
            self.paceData = paceData
        } else {
            self.paceData = try? PaceReferenceLoader.loadBundledPaceData()
        }

        // 기록이 없으면 템플릿 기본 목표 합계(21:45)에서 시작한다 — 보도된 기준 구간 한가운데다.
        let start = self.recordSeconds
            ?? LocalizedDecimalFormatter.safeInt(HyroxPresets.pftBenchmark().estimatedDurationSeconds)
        self.selectedMinutes = min(Self.maximumMinutes, start / 60)
        self.selectedSeconds = start % 60

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = BenchmarkStrings.title
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
        timePicker.selectRow(selectedMinutes, inComponent: 0, animated: false)
        timePicker.selectRow(selectedSeconds, inComponent: 2, animated: false)
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
        contentStack.spacing = 10
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
        summaryLabel.text = BenchmarkStrings.templateSummary
        summaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        summaryLabel.textColor = DesignTokens.Color.textSecondary
        summaryLabel.numberOfLines = 0
        contentStack.addArrangedSubview(summaryLabel)

        contentStack.addArrangedSubview(makeSectionHeader(BenchmarkStrings.sectionProtocol))
        protocolStack.axis = .vertical
        protocolStack.spacing = 0
        protocolStack.backgroundColor = DesignTokens.Color.surface
        protocolStack.layer.cornerRadius = DesignTokens.Radius.card
        protocolStack.isLayoutMarginsRelativeArrangement = true
        protocolStack.layoutMargins = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        contentStack.addArrangedSubview(protocolStack)

        contentStack.addArrangedSubview(makeSectionHeader(BenchmarkStrings.sectionTime))
        sourceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sourceLabel.textColor = DesignTokens.Color.textTertiary
        sourceLabel.numberOfLines = 0
        contentStack.addArrangedSubview(sourceLabel)

        timePicker.dataSource = self
        timePicker.delegate = self
        timePicker.translatesAutoresizingMaskIntoConstraints = false
        timePicker.heightAnchor.constraint(equalToConstant: 130).isActive = true
        contentStack.addArrangedSubview(timePicker)

        contentStack.addArrangedSubview(makeSectionHeader(BenchmarkStrings.sectionDivision))
        contentStack.addArrangedSubview(makeDivisionChips())

        contentStack.addArrangedSubview(makeSectionHeader(BenchmarkStrings.sectionResult))
        resultStack.axis = .vertical
        resultStack.spacing = 10
        contentStack.addArrangedSubview(resultStack)

        noteLabel.font = .systemFont(ofSize: 11, weight: .medium)
        noteLabel.textColor = DesignTokens.Color.textTertiary
        noteLabel.numberOfLines = 0
        contentStack.addArrangedSubview(noteLabel)

        contentStack.addArrangedSubview(makeSectionHeader(BenchmarkStrings.sectionSplits))
        splitStack.axis = .vertical
        splitStack.spacing = 6
        contentStack.addArrangedSubview(splitStack)

        contentStack.addArrangedSubview(makeSectionHeader(BenchmarkStrings.sectionNext))
        contentStack.addArrangedSubview(makeNextStepCard())
    }

    private func makeDivisionChips() -> UIView {
        divisionChipStack.axis = .horizontal
        divisionChipStack.spacing = 8
        divisionChipStack.translatesAutoresizingMaskIntoConstraints = false

        for (index, division) in HyroxDivision.allCases.enumerated() {
            let chip = UIButton(type: .system)
            var config = UIButton.Configuration.filled()
            config.title = division.shortName
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            chip.configuration = config
            chip.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            chip.tag = index
            chip.addTarget(self, action: #selector(divisionChipTapped(_:)), for: .touchUpInside)
            divisionChipStack.addArrangedSubview(chip)
        }

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(divisionChipStack)
        NSLayoutConstraint.activate([
            divisionChipStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            divisionChipStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            divisionChipStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            divisionChipStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            divisionChipStack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 38)
        ])
        return scroll
    }

    private func makeNextStepCard() -> UIView {
        let label = UILabel()
        label.text = BenchmarkStrings.nextStepBody
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = DesignTokens.Color.textSecondary
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = DesignTokens.Color.surface
        container.layer.cornerRadius = DesignTokens.Radius.card
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
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
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])
        return container
    }

    // MARK: - 갱신

    private func refresh() {
        updateDivisionChips()
        updateProtocolRows()
        updateSource()

        guard let dataset = try? paceData?.dataset(for: projectionDivision) else {
            showUnavailableState()
            return
        }

        let result = PFTBenchmarkEvaluator.evaluate(
            totalSeconds: TimeInterval(totalSeconds),
            projectionDivision: projectionDivision,
            dataset: dataset,
            stepSeconds: usesRecordSplits ? recordStepSeconds : [:]
        )

        updateResult(result)
        updateSplits(result)

        var notes = [BenchmarkStrings.noteSource]
        if result.isOutsideReportedBand { notes.append(BenchmarkStrings.noteOutsideBand) }
        noteLabel.text = notes.joined(separator: "\n")
    }

    private func showUnavailableState() {
        resultStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        splitStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        noteLabel.text = BenchmarkStrings.unavailable
    }

    private func updateProtocolRows() {
        protocolStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let template = HyroxPresets.pftBenchmark(
            for: projectionDivision,
            name: BenchmarkStrings.templateName,
            stepName: BenchmarkStrings.stepName
        )

        for (index, step) in PFTStep.allCases.enumerated() {
            let segment = template.segments.indices.contains(index) ? template.segments[index] : nil
            protocolStack.addArrangedSubview(
                makeProtocolRow(index: index, step: step, segment: segment)
            )
        }
    }

    private func makeProtocolRow(index: Int, step: PFTStep, segment: WorkoutSegment?) -> UIView {
        let indexLabel = UILabel()
        indexLabel.text = String(format: "%02d", index + 1)
        indexLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        indexLabel.textColor = DesignTokens.Color.textTertiary
        indexLabel.setContentHuggingPriority(.required, for: .horizontal)

        let nameLabel = UILabel()
        nameLabel.text = BenchmarkStrings.stepName(step)
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = step.segmentType == .run
            ? DesignTokens.Color.runAccent
            : DesignTokens.Color.textPrimary

        var detail = step.target.formatted
        if let weight = segment?.weightKg {
            detail += " · \(LocalizedDecimalFormatter.safeInt(weight))kg"
        }
        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        detailLabel.textColor = DesignTokens.Color.textSecondary
        detailLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [indexLabel, nameLabel, detailLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return row
    }

    private func updateSource() {
        if let record, usesRecordSplits {
            sourceLabel.text = BenchmarkStrings.recordSource(Self.dateFormatter.string(from: record.finishedAt))
        } else if record != nil {
            sourceLabel.text = BenchmarkStrings.recordEdited
        } else {
            sourceLabel.text = BenchmarkStrings.recordNone
        }
    }

    private func updateResult(_ result: PFTBenchmarkResult) {
        resultStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        resultStack.addArrangedSubview(makeRecommendationCard(result))
        resultStack.addArrangedSubview(makeProjectionCard(result))
    }

    private func makeRecommendationCard(_ result: PFTBenchmarkResult) -> UIView {
        let badge = UILabel()
        badge.text = " \(BenchmarkStrings.recommendation(result.recommended)) "
        badge.font = .systemFont(ofSize: 22, weight: .black)
        badge.textColor = .black
        badge.backgroundColor = DesignTokens.Color.accent
        badge.layer.cornerRadius = DesignTokens.Radius.badge
        badge.layer.masksToBounds = true
        badge.setContentHuggingPriority(.required, for: .horizontal)

        let headline = UILabel()
        headline.text = BenchmarkStrings.recommendationHeadline(
            result.recommended.division(matching: projectionDivision).displayName
        )
        headline.font = .systemFont(ofSize: 13, weight: .medium)
        headline.textColor = DesignTokens.Color.textSecondary
        headline.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [badge, headline])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.backgroundColor = DesignTokens.Color.surface
        stack.layer.cornerRadius = DesignTokens.Radius.card
        return stack
    }

    private func makeProjectionCard(_ result: PFTBenchmarkResult) -> UIView {
        let title = UILabel()
        title.text = BenchmarkStrings.projectionTitle
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = DesignTokens.Color.textSecondary

        let value = UILabel()
        value.text = BenchmarkStrings.projectionRange(
            DurationFormatter.hms(TimeInterval(result.projectedFinishRange.lowerBound)),
            DurationFormatter.hms(TimeInterval(result.projectedFinishRange.upperBound))
        )
        value.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        value.textColor = DesignTokens.Color.accent
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.7

        let detail = UILabel()
        detail.text = [
            BenchmarkStrings.projectionBasis(projectionDivision.displayName),
            BenchmarkStrings.projectionPercentile(
                Int(result.projectedPercentileRange.lowerBound.rounded()),
                Int(result.projectedPercentileRange.upperBound.rounded())
            )
        ].joined(separator: " · ")
        detail.font = .systemFont(ofSize: 11, weight: .medium)
        detail.textColor = DesignTokens.Color.textTertiary
        detail.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [title, value, detail])
        stack.axis = .vertical
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.backgroundColor = DesignTokens.Color.surface
        stack.layer.cornerRadius = DesignTokens.Radius.card
        return stack
    }

    private func updateSplits(_ result: PFTBenchmarkResult) {
        splitStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !result.stepComparisons.isEmpty else {
            let empty = UILabel()
            empty.text = BenchmarkStrings.splitsEmpty
            empty.font = .systemFont(ofSize: 12, weight: .medium)
            empty.textColor = DesignTokens.Color.textTertiary
            empty.numberOfLines = 0
            splitStack.addArrangedSubview(empty)
            return
        }

        for comparison in result.stepComparisons {
            splitStack.addArrangedSubview(makeSplitRow(comparison))
        }
    }

    private func makeSplitRow(_ comparison: PFTStepComparison) -> UIView {
        let nameLabel = UILabel()
        nameLabel.text = comparison.isApproximate
            ? "\(BenchmarkStrings.stepName(comparison.step)) (\(BenchmarkStrings.splitsApproximate))"
            : BenchmarkStrings.stepName(comparison.step)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .white

        let timeLabel = UILabel()
        timeLabel.text = DurationFormatter.ms(comparison.seconds)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textColor = DesignTokens.Color.textSecondary
        timeLabel.textAlignment = .right

        let percentileLabel = UILabel()
        percentileLabel.text = BenchmarkStrings.splitPercentile(comparison.percentile)
        percentileLabel.font = .systemFont(ofSize: 12, weight: .bold)
        percentileLabel.textColor = DesignTokens.Color.accent
        percentileLabel.textAlignment = .right
        percentileLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [nameLabel, timeLabel, percentileLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        row.backgroundColor = DesignTokens.Color.surface
        row.layer.cornerRadius = 10
        return row
    }

    private func updateDivisionChips() {
        for (index, chip) in divisionChipStack.arrangedSubviews.enumerated() {
            guard let button = chip as? UIButton, var config = button.configuration,
                  HyroxDivision.allCases.indices.contains(index) else { continue }
            let isSelected = HyroxDivision.allCases[index] == projectionDivision
            config.baseBackgroundColor = isSelected ? DesignTokens.Color.accent : DesignTokens.Color.surface
            config.baseForegroundColor = isSelected ? .black : DesignTokens.Color.textSecondary
            button.configuration = config
        }
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func divisionChipTapped(_ sender: UIButton) {
        guard HyroxDivision.allCases.indices.contains(sender.tag) else { return }
        projectionDivision = HyroxDivision.allCases[sender.tag]
        refresh()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - UIPickerView (mm:ss)

extension PFTBenchmarkViewController: UIPickerViewDataSource, UIPickerViewDelegate {

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 4 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch component {
        case 0: return Self.maximumMinutes + 1
        case 2: return 60
        default: return 1
        }
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        switch component {
        case 0, 2: return 52
        default: return 30
        }
    }

    func pickerView(
        _ pickerView: UIPickerView,
        viewForRow row: Int,
        forComponent component: Int,
        reusing view: UIView?
    ) -> UIView {
        let label = (view as? UILabel) ?? UILabel()
        switch component {
        case 0, 2:
            label.textAlignment = .right
            label.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
            label.textColor = .white
            label.text = String(format: "%02d", row)
        default:
            label.textAlignment = .left
            label.font = .systemFont(ofSize: 16, weight: .medium)
            label.textColor = DesignTokens.Color.textSecondary
            label.text = component == 1 ? "m" : "s"
        }
        return label
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        switch component {
        case 0: selectedMinutes = row
        case 2: selectedSeconds = row
        default: break
        }
        refresh()
    }
}
