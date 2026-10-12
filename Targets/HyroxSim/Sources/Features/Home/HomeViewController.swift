//
//  HomeViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

@MainActor
protocol HomeViewControllerDelegate: AnyObject {
    func homeDidSelectTemplate(_ template: WorkoutTemplate)
    func homeDidTapStart(_ template: WorkoutTemplate)
    func homeDidRequestDeleteTemplate(_ template: WorkoutTemplate)
    func homeDidTapNewWorkout()
    func homeDidTapHistory()
    /// 진척 추적 화면.
    func homeDidTapProgress()
    /// 대회 당일 도구 — 페이스 카드와 룰북 체크리스트.
    func homeDidTapRaceDay()
    func homeDidSelectRecent(_ workout: CompletedWorkout)
    /// 내 대회 카드 탭 — 등록된 대회가 있으면 그 대회를, 없으면 새 대회 작성 화면을 연다.
    func homeDidTapRaceTarget(_ target: RaceTarget?)
    /// 훈련 세션 탭. `index` 는 목록에서의 순서 — 무료 범위 판단에 쓴다.
    func homeDidSelectTrainingSession(_ template: WorkoutTemplate, at index: Int)
}

final class HomeViewController: UIViewController {

    weak var delegate: HomeViewControllerDelegate?
    private let viewModel: HomeViewModel

    /// Unified horizontal margin for all sections
    private let hMargin: CGFloat = DivisionPageCell.horizontalInset

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var pagerCollectionView: UICollectionView!
    private let pageLabel = UILabel()
    private let lastRaceLabel = UILabel()
    private let lastRaceDeltaLabel = UILabel()
    private let goalValueLabel = UILabel()
    private let stripView = SegmentStripView()
    private let planStack = UIStackView()
    /// 홈 표에 미리 보여줄 구간 수. 나머지는 상세 화면에서 본다.
    private let planPreviewCount = 5
    private let historyCountLabel = UILabel()
    private let savedTemplatesStack = UIStackView()
    private var currentPage = 0
    private let raceTargetContainer = UIView()
    private let trainingSessionsStack = UIStackView()
    private var progressRow: UIView?

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        navigationItem.title = "HYROX"
        setupScrollView()
        buildContent()
        // 페이스 플래너/워치에서 목표가 바뀌면 프리셋 카드의 예상 시간도 같이 갱신한다.
        viewModel.onDataChanged = { [weak self] in self?.refreshSections() }
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncUpdate), name: .syncDataUpdated, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reload()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Only restore the bar when another screen is pushed; a full-screen modal
        // (active workout) would otherwise flash the large title over the home screen.
        if let nav = navigationController, nav.topViewController !== self {
            nav.setNavigationBarHidden(false, animated: animated)
        }
    }

    @objc private func handleSyncUpdate() {
        reload()
    }

    private func reload() {
        viewModel.load()
        refreshSections()
    }

    /// 이미 불러온 뷰모델 상태를 화면에 다시 그린다.
    private func refreshSections() {
        pagerCollectionView.reloadData()
        currentPage = min(currentPage, max(viewModel.presets.count - 1, 0))
        updateSelection()
        rebuildRaceTargetCard()
        rebuildTrainingSessions()
        rebuildSavedTemplates()
        refreshProgressRow()
    }

    private var selectedPreset: WorkoutTemplate? {
        viewModel.presets.indices.contains(currentPage) ? viewModel.presets[currentPage] : nil
    }

    // MARK: - Scroll View

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32)
        ])
    }

    // MARK: - Build Content

    private func buildContent() {
        let header = makeHeaderRow()
        contentStack.addArrangedSubview(inset(header))
        contentStack.setCustomSpacing(18, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(makePager())
        contentStack.setCustomSpacing(10, after: pagerCollectionView)

        contentStack.addArrangedSubview(inset(makeHairline()))
        contentStack.setCustomSpacing(14, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(inset(makeGoalBlock()))
        contentStack.setCustomSpacing(16, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(inset(makeHairline()))
        contentStack.setCustomSpacing(10, after: contentStack.arrangedSubviews.last!)

        planStack.axis = .vertical
        contentStack.addArrangedSubview(inset(planStack))
        contentStack.setCustomSpacing(14, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(inset(makeStartButton()))
        contentStack.setCustomSpacing(20, after: contentStack.arrangedSubviews.last!)

        // 내 대회 (D-day). 시작 버튼이 작은 화면에서도 첫 화면에 보이도록 그 아래에 둔다.
        contentStack.addArrangedSubview(inset(raceTargetContainer))
        contentStack.setCustomSpacing(20, after: contentStack.arrangedSubviews.last!)

        historyCountLabel.font = DesignTokens.Font.number(13, weight: .bold)
        historyCountLabel.textColor = DesignTokens.Color.textSecondary

        let plusLabel = UILabel()
        plusLabel.text = "+"
        plusLabel.font = .systemFont(ofSize: 17, weight: .bold)
        plusLabel.textColor = DesignTokens.Color.textPrimary

        contentStack.addArrangedSubview(inset(makeHairline()))
        contentStack.addArrangedSubview(inset(makeLinkRow(
            title: HyroxSimStrings.Localizable.Home.Action.createCustom,
            accessory: plusLabel,
            action: #selector(newWorkoutTapped)
        )))
        contentStack.addArrangedSubview(inset(makeLinkRow(
            title: HyroxSimStrings.Localizable.Home.Action.history,
            accessory: historyCountLabel,
            action: #selector(historyTapped)
        )))

        let progress = makeLinkRow(
            title: HyroxSimStrings.Localizable.Home.Action.progress,
            accessory: makeRowArrow(),
            action: #selector(progressTapped)
        )
        progress.isHidden = true
        progressRow = progress
        contentStack.addArrangedSubview(inset(progress))
        contentStack.addArrangedSubview(inset(makeLinkRow(
            title: HyroxSimStrings.Localizable.Home.Action.raceDay,
            accessory: makeRowArrow(),
            action: #selector(raceDayTapped)
        )))

        // 훈련 세션
        trainingSessionsStack.axis = .vertical
        trainingSessionsStack.isHidden = true
        contentStack.addArrangedSubview(inset(trainingSessionsStack))

        savedTemplatesStack.axis = .vertical
        savedTemplatesStack.isHidden = true
        contentStack.addArrangedSubview(inset(savedTemplatesStack))
    }

    /// 기록이 하나도 없으면 진척 화면은 빈 안내밖에 못 한다 — 그때는 줄을 감춘다.
    private func refreshProgressRow() {
        progressRow?.isHidden = !viewModel.showsProgressEntry
    }

    private func makeHeaderRow() -> UIView {
        let brandLabel = UILabel()
        brandLabel.font = DesignTokens.Font.wide(11, weight: .bold)
        brandLabel.textColor = DesignTokens.Color.textSecondary
        brandLabel.setTracked("HYROX SIM", kern: 4)

        pageLabel.font = DesignTokens.Font.number(11, weight: .semibold)
        pageLabel.textColor = DesignTokens.Color.textSecondary
        pageLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [brandLabel, pageLabel])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    // MARK: - Pager

    private func makePager() -> UIView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0

        pagerCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        pagerCollectionView.translatesAutoresizingMaskIntoConstraints = false
        pagerCollectionView.backgroundColor = .clear
        pagerCollectionView.showsHorizontalScrollIndicator = false
        pagerCollectionView.isPagingEnabled = true
        pagerCollectionView.dataSource = self
        pagerCollectionView.delegate = self
        pagerCollectionView.register(DivisionPageCell.self, forCellWithReuseIdentifier: DivisionPageCell.reuseId)
        pagerCollectionView.heightAnchor.constraint(equalToConstant: pagerHeight).isActive = true
        return pagerCollectionView
    }

    // MARK: - Race Target Card

    private func rebuildRaceTargetCard() {
        raceTargetContainer.subviews.forEach { $0.removeFromSuperview() }

        let card = RaceTargetCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        if let countdown = viewModel.raceCountdown {
            card.configure(with: countdown)
        } else {
            card.configureEmpty()
        }
        card.addTarget(self, action: #selector(raceTargetTapped), for: .touchUpInside)
        raceTargetContainer.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: raceTargetContainer.topAnchor),
            card.leadingAnchor.constraint(equalTo: raceTargetContainer.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: raceTargetContainer.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: raceTargetContainer.bottomAnchor)
        ])
    }

    @objc private func raceTargetTapped() {
        delegate?.homeDidTapRaceTarget(viewModel.raceCountdown?.target)
    }

    // MARK: - Training Sessions

    private func rebuildTrainingSessions() {
        trainingSessionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        trainingSessionsStack.isHidden = viewModel.trainingSessions.isEmpty
        guard !viewModel.trainingSessions.isEmpty else { return }

        trainingSessionsStack.addArrangedSubview(makeSectionCaption(
            HyroxSimStrings.Localizable.Home.Section.trainingSessions
        ))
        trainingSessionsStack.addArrangedSubview(makeHairline())

        for (index, item) in viewModel.trainingSessions.enumerated() {
            let card = TrainingSessionCardView()
            card.configure(with: item)
            card.tag = index
            card.addTarget(self, action: #selector(trainingSessionTapped(_:)), for: .touchUpInside)
            trainingSessionsStack.addArrangedSubview(card)
        }
    }

    @objc private func trainingSessionTapped(_ sender: UIControl) {
        guard sender.tag < viewModel.trainingSessions.count else { return }
        delegate?.homeDidSelectTrainingSession(viewModel.trainingSessions[sender.tag].template, at: sender.tag)
    }

    private var pagerHeight: CGFloat { DivisionPageCell.height }

    private func updateSelection() {
        let total = viewModel.presets.count
        pageLabel.text = total > 0 ? String(format: "%02d / %02d", currentPage + 1, total) : nil
        historyCountLabel.text = "\(viewModel.recentWorkouts.count)"

        let preset = selectedPreset
        goalValueLabel.text = preset.map { DurationFormatter.hms($0.estimatedDurationSeconds) } ?? "—"
        let blocks = preset?.planBlocks ?? []
        rebuildPlanRows(blocks)

        // 지난 기록이 지금 고른 디비전의 것일 때만 띠에 색을 입힌다. 다른 코스의 기록이면 계획만 보여준다.
        let recent = viewModel.mostRecentWorkout
        if let recent {
            lastRaceLabel.setTracked("LAST RACE  \(DurationFormatter.hms(recent.totalDuration))", kern: 1)
        } else {
            lastRaceLabel.setTracked("NO RACE YET", kern: 1)
        }
        if let recent, let division = preset?.division, recent.division == division {
            let summary = WorkoutSummaryViewModel(workout: recent)
            stripView.cells = SegmentStripView.cells(for: recent)
            let hasGoal = summary.totalGoalText != "—"
            lastRaceDeltaLabel.isHidden = !hasGoal
            lastRaceDeltaLabel.text = summary.totalDelta.text
            lastRaceDeltaLabel.textColor = summary.totalDelta.tone == .behind
                ? DesignTokens.Color.overGoal
                : DesignTokens.Color.accent
        } else {
            stripView.cells = Array(repeating: .upcoming, count: blocks.count)
            lastRaceDeltaLabel.isHidden = true
        }
    }

    // MARK: - Goal + Plan

    private func makeGoalBlock() -> UIView {
        let caption = makeCaptionLabel("GOAL")

        let editButton = UIButton(type: .system)
        editButton.setAttributedTitle(NSAttributedString(
            string: "EDIT PLAN →",
            attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: DesignTokens.Color.accent,
                .kern: 1
            ]
        ), for: .normal)
        editButton.addTarget(self, action: #selector(editPlanTapped), for: .touchUpInside)
        editButton.accessibilityLabel = HyroxSimStrings.Localizable.Button.editSegmentTargets

        let captionRow = UIStackView(arrangedSubviews: [caption, UIView(), editButton])
        captionRow.axis = .horizontal
        captionRow.alignment = .center

        goalValueLabel.font = DesignTokens.Font.number(56)
        goalValueLabel.textColor = DesignTokens.Color.textPrimary
        goalValueLabel.adjustsFontSizeToFitWidth = true
        goalValueLabel.minimumScaleFactor = 0.6

        lastRaceLabel.font = .systemFont(ofSize: 10, weight: .bold)
        lastRaceLabel.textColor = DesignTokens.Color.textSecondary
        lastRaceDeltaLabel.font = DesignTokens.Font.number(12)
        lastRaceDeltaLabel.textAlignment = .right

        let lastRow = UIStackView(arrangedSubviews: [lastRaceLabel, UIView(), lastRaceDeltaLabel])
        lastRow.axis = .horizontal
        lastRow.alignment = .center
        lastRow.isUserInteractionEnabled = true
        lastRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(recentTapped)))
        lastRow.isAccessibilityElement = true
        lastRow.accessibilityTraits = .button
        lastRow.accessibilityLabel = "Last race"

        let stack = UIStackView(arrangedSubviews: [captionRow, goalValueLabel, stripView, lastRow])
        stack.axis = .vertical
        stack.spacing = 2
        stack.setCustomSpacing(6, after: goalValueLabel)
        stack.setCustomSpacing(8, after: stripView)
        return stack
    }

    private func makeCaptionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = DesignTokens.Color.textSecondary
        label.setTracked(text, kern: 1.5)
        return label
    }

    /// 구간별 목표 표. 앞의 몇 줄만 보여주고 나머지는 상세 화면으로 넘긴다.
    private func rebuildPlanRows(_ blocks: [PlanBlock]) {
        planStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !blocks.isEmpty else { return }

        planStack.addArrangedSubview(makePlanRow(tag: "#", title: "SEGMENT", value: "TARGET", isHeader: true, isStation: false))
        for block in blocks.prefix(planPreviewCount) {
            planStack.addArrangedSubview(makePlanRow(
                tag: block.tag,
                title: block.title,
                value: DurationFormatter.ms(block.goalSeconds),
                isHeader: false,
                isStation: block.isStation
            ))
        }

        let remaining = blocks.count - planPreviewCount
        if remaining > 0 {
            let more = UIButton(type: .system)
            more.setAttributedTitle(NSAttributedString(
                string: "+ \(remaining) MORE",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: DesignTokens.Color.textSecondary,
                    .kern: 1.5
                ]
            ), for: .normal)
            more.addTarget(self, action: #selector(editPlanTapped), for: .touchUpInside)
            more.heightAnchor.constraint(equalToConstant: 30).isActive = true
            planStack.addArrangedSubview(more)
        }
    }

    private func makePlanRow(tag: String, title: String, value: String, isHeader: Bool, isStation: Bool) -> UIView {
        let captionFont = UIFont.systemFont(ofSize: 10, weight: .bold)
        let secondary = DesignTokens.Color.textSecondary

        let tagLabel = UILabel()
        tagLabel.text = tag
        tagLabel.font = isHeader ? captionFont : DesignTokens.Font.number(10, weight: .bold)
        tagLabel.textColor = isStation ? DesignTokens.Color.accent : secondary
        tagLabel.widthAnchor.constraint(equalToConstant: 26).isActive = true

        let titleLabel = UILabel()
        titleLabel.font = isHeader ? captionFont : .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = isHeader ? secondary : DesignTokens.Color.textPrimary
        if isHeader { titleLabel.setTracked(title, kern: 1) } else { titleLabel.text = title }
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75

        let valueLabel = UILabel()
        valueLabel.font = isHeader ? captionFont : DesignTokens.Font.number(13, weight: .semibold)
        valueLabel.textColor = isHeader ? secondary : DesignTokens.Color.textPrimary
        valueLabel.textAlignment = .right
        if isHeader { valueLabel.setTracked(value, kern: 1) } else { valueLabel.text = value }
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [tagLabel, titleLabel, valueLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: isHeader ? 22 : 28).isActive = true
        return row
    }

    private func makeStartButton() -> UIView {
        let button = UIButton(type: .system)
        button.backgroundColor = DesignTokens.Color.accent
        button.setAttributedTitle(NSAttributedString(
            string: HyroxSimStrings.Localizable.Button.startWorkout.uppercased(),
            attributes: [
                .font: DesignTokens.Font.wide(16, weight: .heavy),
                .foregroundColor: UIColor.black,
                .kern: 1.2
            ]
        ), for: .normal)
        button.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
        return button
    }

    // MARK: - Saved templates

    private func rebuildSavedTemplates() {
        savedTemplatesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        savedTemplatesStack.isHidden = viewModel.customTemplates.isEmpty
        guard !viewModel.customTemplates.isEmpty else { return }

        let header = UILabel()
        header.font = .systemFont(ofSize: 10, weight: .bold)
        header.textColor = DesignTokens.Color.textSecondary
        header.setTracked("SAVED TEMPLATES", kern: 1.5)
        let headerContainer = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 28),
            header.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            header.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -10)
        ])
        savedTemplatesStack.addArrangedSubview(headerContainer)
        savedTemplatesStack.addArrangedSubview(makeHairline())

        for (index, template) in viewModel.customTemplates.enumerated() {
            savedTemplatesStack.addArrangedSubview(makeCustomTemplateRow(template: template, index: index))
        }
    }

    // MARK: - Components

    private func inset(_ content: UIView) -> UIView {
        let container = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hMargin),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hMargin),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeRowArrow() -> UIView {
        let label = UILabel()
        label.text = "→"
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.textColor = DesignTokens.Color.textSecondary
        return label
    }

    private func makeSectionCaption(_ text: String) -> UIView {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = DesignTokens.Color.textSecondary
        label.setTracked(text.uppercased(), kern: 1.5)
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        return container
    }

    private func makeHairline() -> UIView {
        let line = UIView()
        line.backgroundColor = DesignTokens.Color.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    /// Full-width text row with a hairline underneath.
    private func makeRow(title: String, subtitle: String?, accessory: UIView?) -> UIButton {
        let button = UIButton(type: .custom)

        let titleLabel = UILabel()
        titleLabel.text = title.uppercased()
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = DesignTokens.Color.textPrimary
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75

        let textStack = UIStackView(arrangedSubviews: [titleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        if let subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
            subtitleLabel.textColor = DesignTokens.Color.textSecondary
            textStack.addArrangedSubview(subtitleLabel)
        }

        let row = UIStackView(arrangedSubviews: [textStack])
        if let accessory {
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(accessory)
        }
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(row)

        let line = makeHairline()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.isUserInteractionEnabled = false
        button.addSubview(line)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 50 : 58),
            row.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            line.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        button.accessibilityLabel = title
        return button
    }

    private func makeLinkRow(title: String, accessory: UIView, action: Selector) -> UIView {
        let button = makeRow(title: title, subtitle: nil, accessory: accessory)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeCustomTemplateRow(template: WorkoutTemplate, index: Int) -> UIView {
        let button = makeRow(title: template.name, subtitle: customTemplateSummary(for: template), accessory: nil)
        button.tag = index
        button.addTarget(self, action: #selector(customTemplateTapped(_:)), for: .touchUpInside)
        button.addInteraction(UIContextMenuInteraction(delegate: self))
        return button
    }

    private func confirmDeleteCustomTemplate(_ template: WorkoutTemplate) {
        let alert = DarkAlertController(
            title: HyroxSimStrings.Localizable.Alert.DeleteTemplate.title,
            message: HyroxSimStrings.Localizable.Alert.DeleteTemplate.message(template.name)
        )
        alert.addAction(.init(
            title: HyroxSimStrings.Localizable.Button.cancel,
            style: .cancel,
            handler: nil
        ))
        alert.addAction(.init(
            title: HyroxSimStrings.Localizable.Button.delete,
            style: .destructive,
            handler: { [weak self] in
                self?.delegate?.homeDidRequestDeleteTemplate(template)
            }
        ))
        present(alert, animated: true)
    }

    private func customTemplateSummary(for template: WorkoutTemplate) -> String {
        let stations = template.segments.filter { $0.type == .station }.count
        let mins = Int(template.estimatedDurationSeconds / 60)
        let roxLabel = template.usesRoxZone ? "ROX ON" : "ROX OFF"
        return "\(roxLabel)  ·  \(stations) stations  ·  ~\(mins) min"
    }

    // MARK: - Actions

    @objc private func editPlanTapped() {
        guard let preset = selectedPreset else { return }
        delegate?.homeDidSelectTemplate(preset)
    }

    @objc private func startTapped() {
        guard let preset = selectedPreset else { return }
        delegate?.homeDidTapStart(preset)
    }

    @objc private func recentTapped() {
        guard let workout = viewModel.mostRecentWorkout else { return }
        delegate?.homeDidSelectRecent(workout)
    }

    @objc private func newWorkoutTapped() { delegate?.homeDidTapNewWorkout() }
    @objc private func historyTapped() { delegate?.homeDidTapHistory() }
    @objc private func progressTapped() { delegate?.homeDidTapProgress() }
    @objc private func customTemplateTapped(_ sender: UIButton) {
        guard sender.tag < viewModel.customTemplates.count else { return }
        delegate?.homeDidSelectTemplate(viewModel.customTemplates[sender.tag])
    }

    @objc private func raceDayTapped() { delegate?.homeDidTapRaceDay() }
}

// MARK: - UIContextMenuInteractionDelegate

extension HomeViewController: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        // 길게 누른 행에 대응하는 템플릿을 그 시점의 viewModel snapshot에서 캡처.
        // 메뉴가 떠 있는 동안 customTemplates가 갱신되어 인덱스가 어긋나도
        // 캡처된 값으로 동작하므로 안전.
        guard
            let button = interaction.view as? UIButton,
            button.tag >= 0,
            button.tag < viewModel.customTemplates.count
        else { return nil }
        let template = viewModel.customTemplates[button.tag]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let delete = UIAction(
                title: HyroxSimStrings.Localizable.Button.delete,
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.confirmDeleteCustomTemplate(template)
            }
            return UIMenu(title: template.name, children: [delete])
        }
    }
}

// MARK: - UICollectionViewDataSource

extension HomeViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.presets.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DivisionPageCell.reuseId, for: indexPath) as! DivisionPageCell
        cell.configure(with: viewModel.presets[indexPath.item])
        return cell
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension HomeViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: collectionView.bounds.width, height: collectionView.bounds.height)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.homeDidSelectTemplate(viewModel.presets[indexPath.item])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == pagerCollectionView, scrollView.bounds.width > 0 else { return }
        let page = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
        let clamped = max(0, min(page, viewModel.presets.count - 1))
        guard clamped != currentPage else { return }
        currentPage = clamped
        updateSelection()
    }
}
