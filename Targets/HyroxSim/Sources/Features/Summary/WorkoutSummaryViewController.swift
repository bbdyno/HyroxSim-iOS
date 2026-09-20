//
//  WorkoutSummaryViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import StoreKit
import UIKit
import HyroxCore

@MainActor
protocol WorkoutSummaryViewControllerDelegate: AnyObject {
    func summaryDidTapDone()
}

final class WorkoutSummaryViewController: UIViewController {

    private enum Layout {
        static let badgeWidth: CGFloat = 30
        static let timeWidth: CGFloat = 82
        static let deltaWidth: CGFloat = 58
        static let chevronWidth: CGFloat = 12
        static let rowSpacing: CGFloat = 8
    }

    weak var delegate: WorkoutSummaryViewControllerDelegate?

    private let viewModel: WorkoutSummaryViewModel
    private let reviewGate: ReviewRequestGate
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var expandedRunGroups: Set<String> = []
    private var detailContainers: [String: UIView] = [:]
    private var chevronViews: [String: UIImageView] = [:]

    init(viewModel: WorkoutSummaryViewModel, reviewGate: ReviewRequestGate? = nil) {
        self.viewModel = viewModel
        self.reviewGate = reviewGate ?? ReviewRequestGate()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = HyroxSimStrings.Localizable.Nav.summary
        view.backgroundColor = DesignTokens.Color.background
        navigationItem.largeTitleDisplayMode = .never
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestReviewIfEarned()
    }

    @objc private func doneTapped() {
        delegate?.summaryDidTapDone()
    }

    /// 방금 끝난 운동이 조건을 만족할 때만 스토어 리뷰 시트를 띄운다.
    ///
    /// 조건 판단은 `ReviewRequestGate` 가 한다. 시트를 실제로 띄울 수 없으면(씬이 없으면)
    /// 아무 기록도 남기지 않아서, 다음 기회에 다시 판단된다.
    private func requestReviewIfEarned() {
        guard let scene = view.window?.windowScene else { return }
        guard reviewGate.evaluate(viewModel.workout) else { return }

        SKStoreReviewController.requestReview(in: scene)
        reviewGate.markRequested()
    }

    @objc private func shareTapped() {
        let shareImage = SummaryShareCardRenderer(content: viewModel.shareCardContent).makeImage()

        let activityViewController = UIActivityViewController(
            activityItems: [shareImage, viewModel.shareText],
            applicationActivities: nil
        )
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
            popover.sourceView = view
        }
        present(activityViewController, animated: true)
    }

    private func applyDarkNavigationStyle() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = DesignTokens.Color.background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
    }

    private func setupScrollView() {
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
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

        let margin: CGFloat = 10
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: margin),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: margin),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -margin),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -margin)
        ])
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        detailContainers.removeAll()
        chevronViews.removeAll()

        buildContent()
    }

    private func buildContent() {
        addSpacer(2)
        addHeader()
        addSpacer(10)
        addGapCard()
        addSeparator()
        addSpacer(10)
        addTableHeader(["Split", "Time", "Delta"])
        addSpacer(4)

        for section in viewModel.sections {
            if let runGroup = section.runGroup {
                let isExpandable = runGroup.detailItems.count > 1
                let isExpanded = expandedRunGroups.contains(runGroup.id)
                addRunGroupSection(runGroup, expandable: isExpandable, expanded: isExpanded)
            }

            if let station = section.station {
                addStationRow(station)
            }
        }

        addSpacer(12)
        addSeparator()
        addSpacer(6)
        addSummaryRow("Roxzone Time", viewModel.totalRoxZoneTimeText, highlighted: true)
        addSummaryRow("Run Total", viewModel.totalRunTimeText, highlighted: true)
        addSpacer(2)
        addSummaryRow("Avg Pace", viewModel.averagePaceText)
        addHeartRateRow()
        addHeartRateZonesSection()
        addSpacer(12)
    }

    // MARK: - 격차 분석 카드

    private func addGapCard() {
        let card = viewModel.gapCard
        guard card.isVisible else { return }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6

        let titleLabel = makeLabel(
            card.title.uppercased(),
            font: .systemFont(ofSize: 12, weight: .black),
            color: DesignTokens.Color.accent
        )
        stack.addArrangedSubview(titleLabel)

        if let subtitle = card.subtitle {
            stack.addArrangedSubview(
                makeLabel(subtitle, font: .systemFont(ofSize: 11, weight: .medium), color: DesignTokens.Color.textTertiary)
            )
        }

        if let message = card.message {
            let messageLabel = makeLabel(
                message,
                font: .systemFont(ofSize: 13, weight: card.status == .gaps ? .bold : .medium),
                color: card.status == .gaps ? DesignTokens.Color.textPrimary : DesignTokens.Color.textSecondary
            )
            messageLabel.numberOfLines = 0
            stack.addArrangedSubview(messageLabel)
        }

        if !card.rows.isEmpty {
            stack.addArrangedSubview(makeSpacerView(4))
            for row in card.rows {
                stack.addArrangedSubview(makeGapRow(row))
            }
        }

        if let remainderText = card.remainderText {
            stack.addArrangedSubview(
                makeLabel(remainderText, font: .systemFont(ofSize: 11, weight: .medium), color: DesignTokens.Color.textTertiary)
            )
        }

        let container = UIView()
        container.backgroundColor = DesignTokens.Color.cardBackground
        container.layer.cornerRadius = DesignTokens.Radius.card
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])

        contentStack.addArrangedSubview(container)
        addSpacer(10)
    }

    private func makeGapRow(_ row: WorkoutSummaryViewModel.GapRow) -> UIView {
        let titleLabel = makeLabel(row.title, font: .systemFont(ofSize: 13, weight: .semibold), color: DesignTokens.Color.textPrimary)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let deltaLabel = makeLabel(
            row.deltaText,
            font: .monospacedDigitSystemFont(ofSize: 14, weight: .black),
            color: accentColor(for: row.accent)
        )
        deltaLabel.textAlignment = .right
        deltaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let headerRow = UIStackView(arrangedSubviews: [titleLabel, deltaLabel])
        headerRow.axis = .horizontal
        headerRow.alignment = .firstBaseline
        headerRow.spacing = Layout.rowSpacing

        let shareLabel = makeLabel(row.shareText, font: .systemFont(ofSize: 10, weight: .medium), color: DesignTokens.Color.textTertiary)

        let stack = UIStackView(arrangedSubviews: [headerRow, makeGapBar(ratio: row.barRatio, accent: row.accent), shareLabel])
        stack.axis = .vertical
        stack.spacing = 4

        let container = UIView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5)
        ])
        return container
    }

    private func makeGapBar(ratio: Double, accent: WorkoutSummaryViewModel.AccentKind) -> UIView {
        let track = UIView()
        track.backgroundColor = DesignTokens.Color.surfaceElevated
        track.layer.cornerRadius = 3
        track.translatesAutoresizingMaskIntoConstraints = false
        track.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let fill = UIView()
        fill.backgroundColor = accentColor(for: accent)
        fill.layer.cornerRadius = 3
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        // multiplier 는 0 이 될 수 없다. 아주 작은 격차도 막대가 보이도록 최소 폭을 준다.
        let clamped = ratio.isFinite ? min(1, max(0.04, ratio)) : 0.04
        NSLayoutConstraint.activate([
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: CGFloat(clamped))
        ])
        return track
    }

    private func accentColor(for accent: WorkoutSummaryViewModel.AccentKind) -> UIColor {
        switch accent {
        case .run:
            return DesignTokens.Color.runAccent
        case .roxZone:
            return DesignTokens.Color.roxZoneAccent
        case .station:
            return DesignTokens.Color.stationAccent
        }
    }

    // MARK: - 심박 존

    /// 최대 심박을 알 때만 존 분포를 그린다. 뷰모델이 빈 배열을 주면 섹션 자체를 만들지 않는다.
    private func addHeartRateZonesSection() {
        let zones = viewModel.heartRateZoneDistribution.filter { $0.ratio > 0 }
        guard !zones.isEmpty else { return }

        addSpacer(10)
        contentStack.addArrangedSubview(
            makeLabel(
                HyroxSimStrings.Localizable.Summary.Zones.title.uppercased(),
                font: .systemFont(ofSize: 12, weight: .black),
                color: DesignTokens.Color.accent
            )
        )
        addSpacer(6)

        let barView = StackedZoneBarView()
        barView.zones = zones.map {
            StackedZoneBarView.ZoneData(
                zone: $0.zone,
                ratio: $0.ratio,
                durationText: $0.durationText
            )
        }
        contentStack.addArrangedSubview(barView)
    }

    private func makeSpacerView(_ height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }

    private func addHeader() {
        let totalLabel = UILabel()
        totalLabel.text = viewModel.totalTimeText
        totalLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .black)
        totalLabel.textColor = .white
        totalLabel.textAlignment = .center

        let deltaLabel = UILabel()
        deltaLabel.text = viewModel.totalDelta.text
        deltaLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .black)
        deltaLabel.textColor = color(for: viewModel.totalDelta.tone)
        deltaLabel.textAlignment = .center
        deltaLabel.isHidden = viewModel.totalGoalText == "—"

        let goalLabel = UILabel()
        goalLabel.text = HyroxSimStrings.Localizable.Summary.goalFormat(viewModel.totalGoalText)
        goalLabel.font = .systemFont(ofSize: 10, weight: .bold)
        goalLabel.textColor = DesignTokens.Color.textSecondary
        goalLabel.textAlignment = .center
        goalLabel.isHidden = viewModel.totalGoalText == "—"

        let titleLabel = UILabel()
        titleLabel.text = viewModel.titleText
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = DesignTokens.Color.accent
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8

        let dateLabel = UILabel()
        dateLabel.text = viewModel.dateText
        dateLabel.font = .systemFont(ofSize: 10, weight: .medium)
        dateLabel.textColor = DesignTokens.Color.textTertiary
        dateLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [totalLabel, deltaLabel, goalLabel, titleLabel, dateLabel])
        stack.axis = .vertical
        stack.spacing = 1
        contentStack.addArrangedSubview(stack)
    }

    private func addTableHeader(_ columns: [String]) {
        let row = UIStackView()
        row.alignment = .center
        row.spacing = Layout.rowSpacing

        let leadSpacer = UIView()
        leadSpacer.translatesAutoresizingMaskIntoConstraints = false
        leadSpacer.widthAnchor.constraint(equalToConstant: Layout.badgeWidth).isActive = true
        row.addArrangedSubview(leadSpacer)

        let splitLabel = makeLabel(columns[0], font: .systemFont(ofSize: 13, weight: .bold), color: DesignTokens.Color.accent)
        row.addArrangedSubview(splitLabel)

        let timeLabel = makeLabel(columns[1], font: .systemFont(ofSize: 13, weight: .bold), color: DesignTokens.Color.accent)
        timeLabel.textAlignment = .right
        timeLabel.widthAnchor.constraint(equalToConstant: Layout.timeWidth).isActive = true
        row.addArrangedSubview(timeLabel)

        let deltaLabel = makeLabel(columns[2], font: .systemFont(ofSize: 13, weight: .bold), color: DesignTokens.Color.accent)
        deltaLabel.textAlignment = .right
        deltaLabel.widthAnchor.constraint(equalToConstant: Layout.deltaWidth).isActive = true
        row.addArrangedSubview(deltaLabel)

        let trailingSpacer = UIView()
        trailingSpacer.translatesAutoresizingMaskIntoConstraints = false
        trailingSpacer.widthAnchor.constraint(equalToConstant: Layout.chevronWidth).isActive = true
        row.addArrangedSubview(trailingSpacer)

        contentStack.addArrangedSubview(row)
        addSeparator(color: DesignTokens.Color.accentDim)
    }

    private func addRunGroupRow(
        _ runGroup: WorkoutSummaryViewModel.RunGroupItem,
        expandable: Bool,
        expanded: Bool
    ) -> UIView {
        let row = UIStackView()
        row.alignment = .center
        row.spacing = Layout.rowSpacing

        let leadSpacer = UIView()
        leadSpacer.translatesAutoresizingMaskIntoConstraints = false
        leadSpacer.widthAnchor.constraint(equalToConstant: Layout.badgeWidth).isActive = true
        leadSpacer.heightAnchor.constraint(equalToConstant: 18).isActive = true
        row.addArrangedSubview(leadSpacer)

        let titleLabel = makeLabel(
            runGroupDisplayTitle(runGroup),
            font: .systemFont(ofSize: 14, weight: .semibold),
            color: DesignTokens.Color.textPrimary
        )
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(titleLabel)

        let timeLabel = makeLabel(
            runGroup.durationText,
            font: .monospacedDigitSystemFont(ofSize: 14, weight: .medium),
            color: DesignTokens.Color.textPrimary
        )
        timeLabel.textAlignment = .right
        timeLabel.widthAnchor.constraint(equalToConstant: Layout.timeWidth).isActive = true
        row.addArrangedSubview(timeLabel)

        let deltaLabel = makeLabel(
            runGroup.delta.text,
            font: .monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            color: color(for: runGroup.delta.tone)
        )
        deltaLabel.textAlignment = .right
        deltaLabel.widthAnchor.constraint(equalToConstant: Layout.deltaWidth).isActive = true
        row.addArrangedSubview(deltaLabel)

        if expandable {
            let chevron = UIImageView(image: UIImage(systemName: expanded ? "chevron.down" : "chevron.right"))
            chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            chevron.tintColor = DesignTokens.Color.textSecondary
            chevron.contentMode = .scaleAspectFit
            chevron.translatesAutoresizingMaskIntoConstraints = false
            chevron.widthAnchor.constraint(equalToConstant: Layout.chevronWidth).isActive = true
            row.addArrangedSubview(chevron)
            chevronViews[runGroup.id] = chevron
        } else {
            let spacer = UIView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.widthAnchor.constraint(equalToConstant: Layout.chevronWidth).isActive = true
            row.addArrangedSubview(spacer)
        }

        let container = UIView()
        container.isUserInteractionEnabled = expandable
        container.accessibilityIdentifier = runGroup.id
        if expandable {
            let tap = UITapGestureRecognizer(target: self, action: #selector(runGroupTapped(_:)))
            container.addGestureRecognizer(tap)
        }

        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5)
        ])
        return container
    }

    private func addRunGroupSection(
        _ runGroup: WorkoutSummaryViewModel.RunGroupItem,
        expandable: Bool,
        expanded: Bool
    ) {
        let sectionStack = UIStackView()
        sectionStack.axis = .vertical
        sectionStack.spacing = 0

        let mainRow = addRunGroupRow(runGroup, expandable: expandable, expanded: expanded)
        sectionStack.addArrangedSubview(mainRow)

        let detailsContainer = UIStackView()
        detailsContainer.axis = .vertical
        detailsContainer.spacing = 0
        detailsContainer.isHidden = !expanded

        for detail in runGroup.detailItems {
            detailsContainer.addArrangedSubview(makeDetailRow(detail))
        }

        if expandable {
            detailContainers[runGroup.id] = detailsContainer
            sectionStack.addArrangedSubview(detailsContainer)
        }

        contentStack.addArrangedSubview(sectionStack)
    }

    private func makeDetailRow(_ detail: WorkoutSummaryViewModel.DetailItem) -> UIView {
        let row = UIStackView()
        row.alignment = .center
        row.spacing = Layout.rowSpacing

        let leadSpacer = UIView()
        leadSpacer.translatesAutoresizingMaskIntoConstraints = false
        leadSpacer.widthAnchor.constraint(equalToConstant: Layout.badgeWidth).isActive = true
        row.addArrangedSubview(leadSpacer)

        let titleLabel = makeLabel(detail.title, font: .systemFont(ofSize: 13, weight: .medium), color: detailTitleColor(for: detail.accent))
        row.addArrangedSubview(titleLabel)

        let timeLabel = makeLabel(
            detail.durationText,
            font: .monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            color: DesignTokens.Color.textPrimary
        )
        timeLabel.textAlignment = .right
        timeLabel.widthAnchor.constraint(equalToConstant: Layout.timeWidth).isActive = true
        row.addArrangedSubview(timeLabel)

        let deltaLabel = makeLabel(
            detail.delta.text,
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            color: color(for: detail.delta.tone)
        )
        deltaLabel.textAlignment = .right
        deltaLabel.widthAnchor.constraint(equalToConstant: Layout.deltaWidth).isActive = true
        row.addArrangedSubview(deltaLabel)

        let chevronSpacer = UIView()
        chevronSpacer.translatesAutoresizingMaskIntoConstraints = false
        chevronSpacer.widthAnchor.constraint(equalToConstant: Layout.chevronWidth).isActive = true
        row.addArrangedSubview(chevronSpacer)

        let container = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3)
        ])
        return container
    }

    private func addStationRow(_ station: WorkoutSummaryViewModel.SectionStationItem) {
        let row = UIStackView()
        row.alignment = .center
        row.spacing = Layout.rowSpacing

        row.addArrangedSubview(makeBadge(text: String(format: "%02d", station.index)))

        let titleLabel = makeLabel(station.title, font: .systemFont(ofSize: 15, weight: .bold), color: DesignTokens.Color.textPrimary)
        row.addArrangedSubview(titleLabel)

        let timeLabel = makeLabel(
            station.durationText,
            font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            color: DesignTokens.Color.textPrimary
        )
        timeLabel.textAlignment = .right
        timeLabel.widthAnchor.constraint(equalToConstant: Layout.timeWidth).isActive = true
        row.addArrangedSubview(timeLabel)

        let deltaLabel = makeLabel(
            station.delta.text,
            font: .monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            color: color(for: station.delta.tone)
        )
        deltaLabel.textAlignment = .right
        deltaLabel.widthAnchor.constraint(equalToConstant: Layout.deltaWidth).isActive = true
        row.addArrangedSubview(deltaLabel)

        let chevronSpacer = UIView()
        chevronSpacer.translatesAutoresizingMaskIntoConstraints = false
        chevronSpacer.widthAnchor.constraint(equalToConstant: Layout.chevronWidth).isActive = true
        row.addArrangedSubview(chevronSpacer)

        let container = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5)
        ])
        contentStack.addArrangedSubview(container)
    }

    private func addSummaryRow(_ label: String, _ value: String, highlighted: Bool = false) {
        let row = UIStackView()
        row.distribution = .fill

        let labelColor = highlighted ? DesignTokens.Color.accent : DesignTokens.Color.textSecondary
        let valueColor = highlighted ? DesignTokens.Color.accent : DesignTokens.Color.textPrimary

        let labelView = makeLabel(
            label,
            font: .systemFont(ofSize: 13, weight: highlighted ? .bold : .medium),
            color: labelColor
        )
        row.addArrangedSubview(labelView)

        let valueView = makeLabel(
            value,
            font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            color: valueColor
        )
        valueView.textAlignment = .right
        row.addArrangedSubview(valueView)

        let container = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3)
        ])
        contentStack.addArrangedSubview(container)
    }

    private func addHeartRateRow() {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually

        row.addArrangedSubview(
            makeHeartMetricCell(
                symbolName: "heart",
                title: "Avg HR",
                value: viewModel.averageHeartRateText
            )
        )
        row.addArrangedSubview(
            makeHeartMetricCell(
                symbolName: "heart.fill",
                title: "Max HR",
                value: viewModel.maxHeartRateText
            )
        )

        contentStack.addArrangedSubview(row)
    }

    private func makeHeartMetricCell(symbolName: String, title: String, value: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbolName))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        icon.tintColor = DesignTokens.Color.accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 12).isActive = true

        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 13, weight: .medium), color: DesignTokens.Color.textSecondary)

        let leading = UIStackView(arrangedSubviews: [icon, titleLabel])
        leading.axis = .horizontal
        leading.spacing = 6
        leading.alignment = .center

        let valueLabel = makeLabel(
            value,
            font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            color: DesignTokens.Color.textPrimary
        )
        valueLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [leading, valueLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill

        let container = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3)
        ])
        return container
    }

    private func makeBadge(text: String) -> UIView {
        let container = UIView()
        container.backgroundColor = DesignTokens.Color.accent
        container.layer.cornerRadius = 4
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 30).isActive = true
        container.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 10, weight: .black)
        label.textColor = .black
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func runGroupDisplayTitle(_ runGroup: WorkoutSummaryViewModel.RunGroupItem) -> String {
        let hasRox = runGroup.detailItems.contains { $0.accent == .roxZone }
        return hasRox ? "Running \(runGroup.index) + Rox Zone" : "Running \(runGroup.index)"
    }

    private func detailTitleColor(for accent: WorkoutSummaryViewModel.DetailItem.Accent) -> UIColor {
        switch accent {
        case .run:
            return DesignTokens.Color.textSecondary
        case .roxZone:
            return DesignTokens.Color.textSecondary
        case .station:
            return DesignTokens.Color.textPrimary
        }
    }

    @objc private func runGroupTapped(_ gesture: UITapGestureRecognizer) {
        guard
            let id = gesture.view?.accessibilityIdentifier,
            !id.isEmpty,
            let detailContainer = detailContainers[id]
        else { return }

        let willExpand = !expandedRunGroups.contains(id)
        if willExpand {
            expandedRunGroups.insert(id)
        } else {
            expandedRunGroups.remove(id)
        }

        chevronViews[id]?.image = UIImage(
            systemName: willExpand ? "chevron.down" : "chevron.right"
        )
        chevronViews[id]?.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 11,
            weight: .bold
        )

        if willExpand {
            detailContainer.alpha = 0
        }

        view.layoutIfNeeded()
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut]) {
            detailContainer.isHidden = !willExpand
            detailContainer.alpha = willExpand ? 1 : 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            if !willExpand {
                detailContainer.alpha = 1
            }
        }
    }

    private func color(for tone: WorkoutSummaryViewModel.DeltaTone) -> UIColor {
        switch tone {
        case .ahead:
            return DesignTokens.Color.success
        case .behind:
            return .systemRed
        case .neutral:
            return DesignTokens.Color.textSecondary
        }
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        return label
    }

    private func addSpacer(_ height: CGFloat) {
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        contentStack.addArrangedSubview(spacer)
    }

    private func addSeparator(color: UIColor = UIColor.white.withAlphaComponent(0.1)) {
        let separator = UIView()
        separator.backgroundColor = color
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        contentStack.addArrangedSubview(separator)
    }
}
