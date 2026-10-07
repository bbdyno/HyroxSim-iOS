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
}

final class HomeViewController: UIViewController {

    weak var delegate: HomeViewControllerDelegate?
    private let viewModel: HomeViewModel

    /// Unified horizontal margin for all sections
    private let hMargin: CGFloat = CoursePageCell.horizontalInset

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var pagerCollectionView: UICollectionView!
    private let pageLabel = UILabel()
    private let lastRaceValueLabel = UILabel()
    private let goalValueLabel = UILabel()
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
        contentStack.setCustomSpacing(14, after: contentStack.arrangedSubviews.last!)

        // 내 대회 (D-day)
        contentStack.addArrangedSubview(inset(raceTargetContainer))
        contentStack.setCustomSpacing(20, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(makePager())
        contentStack.setCustomSpacing(18, after: pagerCollectionView)

        contentStack.addArrangedSubview(inset(makeHairline()))
        contentStack.setCustomSpacing(14, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(inset(makeStatsRow()))
        contentStack.setCustomSpacing(18, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(inset(makeStartButton()))
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
        pagerCollectionView.register(CoursePageCell.self, forCellWithReuseIdentifier: CoursePageCell.reuseId)
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
        delegate?.homeDidSelectTemplate(viewModel.trainingSessions[sender.tag].template)
    }

    private var pagerHeight: CGFloat {
        let stationCount = HyroxPresets.all.map { $0.courseStations.count }.max() ?? 8
        return CoursePageCell.height(stationCount: stationCount)
    }

    private func updateSelection() {
        let total = viewModel.presets.count
        pageLabel.text = total > 0 ? String(format: "%02d / %02d", currentPage + 1, total) : nil
        goalValueLabel.text = selectedPreset.map { DurationFormatter.hms($0.estimatedDurationSeconds) } ?? "—"
        lastRaceValueLabel.text = viewModel.mostRecentWorkout.map { DurationFormatter.hms($0.totalDuration) } ?? "—"
        historyCountLabel.text = "\(viewModel.recentWorkouts.count)"
    }

    // MARK: - Stats + Start

    private func makeStatsRow() -> UIView {
        lastRaceValueLabel.textColor = DesignTokens.Color.textPrimary
        goalValueLabel.textColor = DesignTokens.Color.textSecondary

        let lastRace = makeStatColumn(caption: "LAST RACE", valueLabel: lastRaceValueLabel)
        lastRace.isUserInteractionEnabled = true
        lastRace.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(recentTapped)))
        lastRace.isAccessibilityElement = true
        lastRace.accessibilityTraits = .button
        lastRace.accessibilityLabel = "Last race"

        let goal = makeStatColumn(caption: "GOAL", valueLabel: goalValueLabel)

        let row = UIStackView(arrangedSubviews: [lastRace, goal])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        return row
    }

    private func makeStatColumn(caption: String, valueLabel: UILabel) -> UIView {
        let captionLabel = UILabel()
        captionLabel.font = .systemFont(ofSize: 10, weight: .bold)
        captionLabel.textColor = DesignTokens.Color.textSecondary
        captionLabel.setTracked(caption, kern: 1.5)

        valueLabel.font = DesignTokens.Font.number(28)
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let column = UIStackView(arrangedSubviews: [captionLabel, valueLabel])
        column.axis = .vertical
        column.spacing = 4
        return column
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
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CoursePageCell.reuseId, for: indexPath) as! CoursePageCell
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
