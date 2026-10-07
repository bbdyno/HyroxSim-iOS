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
}

final class WorkoutSummaryViewController: UIViewController {

    private enum Layout {
        static let badgeWidth: CGFloat = 30
        static let timeWidth: CGFloat = 68
        static let deltaWidth: CGFloat = 52
        static let chevronWidth: CGFloat = 12
        static let rowSpacing: CGFloat = 8
    }

    weak var delegate: WorkoutSummaryViewControllerDelegate?

    private let viewModel: WorkoutSummaryViewModel
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var expandedRunGroups: Set<String> = []
    private var detailContainers: [String: UIView] = [:]
    private var chevronViews: [String: UIImageView] = [:]

    init(viewModel: WorkoutSummaryViewModel) {
        self.viewModel = viewModel
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

    @objc private func doneTapped() {
        delegate?.summaryDidTapDone()
    }

    @objc private func shareTapped() {
        guard let shareImage = makeShareImage() else { return }

        let activityViewController = UIActivityViewController(
            activityItems: [shareImage],
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

        let margin: CGFloat = 24
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
        addCourseMap()
        addSpacer(14)
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
        addSpacer(12)
    }

    private func addHeader() {
        let captionLabel = UILabel()
        captionLabel.font = DesignTokens.Font.wide(11, weight: .bold)
        captionLabel.textColor = DesignTokens.Color.textSecondary
        captionLabel.setTracked("FINISH · \(viewModel.titleText.uppercased())", kern: 3)
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.7

        let totalLabel = UILabel()
        totalLabel.text = viewModel.totalTimeText
        totalLabel.font = DesignTokens.Font.number(72)
        totalLabel.textColor = DesignTokens.Color.textPrimary
        totalLabel.adjustsFontSizeToFitWidth = true
        totalLabel.minimumScaleFactor = 0.5

        let hasGoal = viewModel.totalGoalText != "—"

        let goalLabel = UILabel()
        goalLabel.font = .systemFont(ofSize: 12, weight: .bold)
        goalLabel.textColor = DesignTokens.Color.textSecondary
        goalLabel.setTracked(
            hasGoal
                ? HyroxSimStrings.Localizable.Summary.goalFormat(viewModel.totalGoalText).uppercased()
                : viewModel.dateText.uppercased(),
            kern: 1
        )

        let deltaLabel = UILabel()
        deltaLabel.text = viewModel.totalDelta.text
        deltaLabel.font = DesignTokens.Font.number(16)
        deltaLabel.textColor = color(for: viewModel.totalDelta.tone)
        deltaLabel.textAlignment = .right
        deltaLabel.isHidden = !hasGoal
        deltaLabel.setContentHuggingPriority(.required, for: .horizontal)

        let goalRow = UIStackView(arrangedSubviews: [goalLabel, deltaLabel])
        goalRow.axis = .horizontal
        goalRow.alignment = .firstBaseline

        let dateLabel = UILabel()
        dateLabel.text = viewModel.dateText
        dateLabel.font = .systemFont(ofSize: 11, weight: .medium)
        dateLabel.textColor = DesignTokens.Color.textTertiary
        dateLabel.isHidden = !hasGoal

        let stack = UIStackView(arrangedSubviews: [captionLabel, totalLabel, goalRow, dateLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.setCustomSpacing(4, after: goalRow)
        contentStack.addArrangedSubview(stack)
    }

    /// Course with each station marked ahead/behind its goal, plus the costliest station.
    private func addCourseMap() {
        let stations = viewModel.sections.compactMap(\.station)
        guard !stations.isEmpty else { return }

        let mapView = CourseMapView(style: .regular)
        mapView.stations = stations.map { station in
            let isBehind = station.delta.tone == .behind
            return CourseMapView.Station(
                label: station.delta.tone == .neutral ? nil : station.delta.text,
                color: isBehind ? DesignTokens.Color.overGoal : DesignTokens.Color.accent,
                labelColor: isBehind ? DesignTokens.Color.overGoal : DesignTokens.Color.textPrimary
            )
        }
        addSpacer(20)
        contentStack.addArrangedSubview(mapView)

        let worst = stations
            .filter { ($0.delta.seconds ?? 0) > 0 }
            .max { ($0.delta.seconds ?? 0) < ($1.delta.seconds ?? 0) }
        guard let worst else { return }

        let captionLabel = UILabel()
        captionLabel.font = .systemFont(ofSize: 10, weight: .bold)
        captionLabel.textColor = DesignTokens.Color.textSecondary
        captionLabel.setTracked("BIGGEST LOSS", kern: 1.5)

        let nameLabel = makeLabel(
            String(format: "%02d  %@", worst.index, worst.title.uppercased()),
            font: .systemFont(ofSize: 18, weight: .heavy),
            color: DesignTokens.Color.textPrimary
        )
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7

        let lossLabel = makeLabel(
            worst.delta.text,
            font: DesignTokens.Font.number(18),
            color: DesignTokens.Color.overGoal
        )
        lossLabel.textAlignment = .right
        lossLabel.setContentHuggingPriority(.required, for: .horizontal)
        lossLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let lossRow = UIStackView(arrangedSubviews: [nameLabel, lossLabel])
        lossRow.axis = .horizontal
        lossRow.alignment = .firstBaseline
        lossRow.spacing = 12

        let stack = UIStackView(arrangedSubviews: [captionLabel, lossRow])
        stack.axis = .vertical
        stack.spacing = 6

        addSpacer(8)
        addSeparator()
        addSpacer(12)
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

        let splitLabel = makeLabel(columns[0].uppercased(), font: .systemFont(ofSize: 10, weight: .bold), color: DesignTokens.Color.textSecondary)
        row.addArrangedSubview(splitLabel)

        let timeLabel = makeLabel(columns[1].uppercased(), font: .systemFont(ofSize: 10, weight: .bold), color: DesignTokens.Color.textSecondary)
        timeLabel.textAlignment = .right
        timeLabel.widthAnchor.constraint(equalToConstant: Layout.timeWidth).isActive = true
        row.addArrangedSubview(timeLabel)

        let deltaLabel = makeLabel(columns[2].uppercased(), font: .systemFont(ofSize: 10, weight: .bold), color: DesignTokens.Color.textSecondary)
        deltaLabel.textAlignment = .right
        deltaLabel.widthAnchor.constraint(equalToConstant: Layout.deltaWidth).isActive = true
        row.addArrangedSubview(deltaLabel)

        let trailingSpacer = UIView()
        trailingSpacer.translatesAutoresizingMaskIntoConstraints = false
        trailingSpacer.widthAnchor.constraint(equalToConstant: Layout.chevronWidth).isActive = true
        row.addArrangedSubview(trailingSpacer)

        contentStack.addArrangedSubview(row)
        addSeparator()
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
            return DesignTokens.Color.accent
        case .behind:
            return DesignTokens.Color.overGoal
        case .neutral:
            return DesignTokens.Color.textSecondary
        }
    }

    private func makeShareImage() -> UIImage? {
        view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = view.window?.screen.scale ?? UIScreen.main.scale

        let contentHeight = max(scrollView.contentSize.height, contentStack.frame.maxY)
        let imageSize = CGSize(width: scrollView.bounds.width, height: contentHeight)
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        return renderer.image { _ in
            DesignTokens.Color.background.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: imageSize)).fill()

            let drawRect = CGRect(origin: contentStack.frame.origin, size: contentStack.bounds.size)
            contentStack.drawHierarchy(in: drawRect, afterScreenUpdates: true)
        }
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
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
