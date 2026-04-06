import UIKit
import HyroxKit

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

    init(viewModel: WorkoutSummaryViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Summary"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped))
        setupScrollView()
        buildContent()
    }

    @objc private func doneTapped() {
        delegate?.summaryDidTapDone()
    }

    @objc private func shareTapped() {
        delegate?.summaryDidTapShare(viewModel.workout)
    }

    // MARK: - Layout

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
        contentStack.spacing = DesignTokens.Spacing.l
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let margin = DesignTokens.Spacing.m
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: margin),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -margin)
        ])
    }

    private func buildContent() {
        // Header
        let totalLabel = makeCaption("TOTAL TIME")
        let totalValue = UILabel()
        totalValue.text = viewModel.totalTimeText
        totalValue.font = DesignTokens.Font.largeNumber
        totalValue.textAlignment = .center

        let titleLabel = UILabel()
        titleLabel.text = viewModel.titleText
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center

        let dateLabel = UILabel()
        dateLabel.text = viewModel.dateText
        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.textColor = .secondaryLabel
        dateLabel.textAlignment = .center

        contentStack.addArrangedSubview(totalLabel)
        contentStack.addArrangedSubview(totalValue)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(dateLabel)
        contentStack.addArrangedSubview(makeSeparator())

        // Summary 2x2
        contentStack.addArrangedSubview(makeCaption("SUMMARY"))
        let grid = makeSummaryGrid()
        contentStack.addArrangedSubview(grid)
        contentStack.addArrangedSubview(makeSeparator())

        // Run Paces
        if !viewModel.runPaces.isEmpty {
            contentStack.addArrangedSubview(makeCaption("PACE BY RUN"))
            let chart = BarChartView()
            chart.accentColor = DesignTokens.Color.runAccent
            chart.bars = viewModel.runPaces.map { item in
                BarChartView.Bar(
                    label: "Run \(item.index)",
                    value: item.secondsPerKm ?? 0,
                    display: item.durationText
                )
            }
            contentStack.addArrangedSubview(chart)
            contentStack.addArrangedSubview(makeSeparator())
        }

        // Stations
        if !viewModel.stationItems.isEmpty {
            contentStack.addArrangedSubview(makeCaption("STATIONS"))
            let chart = BarChartView()
            chart.accentColor = DesignTokens.Color.stationAccent
            chart.bars = viewModel.stationItems.map { item in
                BarChartView.Bar(label: item.name, value: item.durationSeconds, display: item.durationText)
            }
            contentStack.addArrangedSubview(chart)
            contentStack.addArrangedSubview(makeSeparator())
        }

        // HR Zones
        let zones = viewModel.heartRateZoneDistribution
        if !zones.isEmpty {
            contentStack.addArrangedSubview(makeCaption("HEART RATE ZONES"))
            let bar = StackedZoneBarView()
            bar.zones = zones.map { StackedZoneBarView.ZoneData(zone: $0.zone, ratio: $0.ratio, durationText: $0.durationText) }
            contentStack.addArrangedSubview(bar)
            contentStack.addArrangedSubview(makeSeparator())
        }

        // Breakdown
        contentStack.addArrangedSubview(makeCaption("SEGMENT BREAKDOWN"))
        for item in viewModel.breakdownItems {
            contentStack.addArrangedSubview(makeBreakdownRow(item))
        }
    }

    // MARK: - Helpers

    private func makeCaption(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .preferredFont(forTextStyle: .caption1)
        l.textColor = .secondaryLabel
        return l
    }

    private func makeSeparator() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return v
    }

    private func makeSummaryGrid() -> UIView {
        let row1 = UIStackView(arrangedSubviews: [
            makeMetricCell(viewModel.distanceText, caption: "Distance"),
            makeMetricCell(viewModel.averagePaceText, caption: "Avg Pace")
        ])
        row1.distribution = .fillEqually
        row1.spacing = DesignTokens.Spacing.m

        let row2 = UIStackView(arrangedSubviews: [
            makeMetricCell(viewModel.averageHeartRateText, caption: "Avg HR"),
            makeMetricCell(viewModel.maxHeartRateText, caption: "Max HR")
        ])
        row2.distribution = .fillEqually
        row2.spacing = DesignTokens.Spacing.m

        let grid = UIStackView(arrangedSubviews: [row1, row2])
        grid.axis = .vertical
        grid.spacing = DesignTokens.Spacing.s
        return grid
    }

    private func makeMetricCell(_ value: String, caption: String) -> UIView {
        let container = UIView()
        container.backgroundColor = DesignTokens.Color.cardBackground
        container.layer.cornerRadius = DesignTokens.Radius.card

        let vLabel = UILabel()
        vLabel.text = value
        vLabel.font = DesignTokens.Font.mediumNumber
        vLabel.textAlignment = .center

        let cLabel = UILabel()
        cLabel.text = caption
        cLabel.font = DesignTokens.Font.label
        cLabel.textColor = .secondaryLabel
        cLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [vLabel, cLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.m),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.s),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.s),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DesignTokens.Spacing.m)
        ])
        return container
    }

    private func makeBreakdownRow(_ item: WorkoutSummaryViewModel.BreakdownItem) -> UIView {
        let row = UIStackView()
        row.spacing = DesignTokens.Spacing.s
        row.alignment = .center

        let dot = UIView()
        dot.layer.cornerRadius = 4
        switch item.accent {
        case .run: dot.backgroundColor = DesignTokens.Color.runAccent
        case .roxZone: dot.backgroundColor = DesignTokens.Color.roxZoneAccent
        case .station: dot.backgroundColor = DesignTokens.Color.stationAccent
        }
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let indexLabel = UILabel()
        indexLabel.text = "\(item.index)."
        indexLabel.font = .preferredFont(forTextStyle: .body)
        indexLabel.textColor = .secondaryLabel
        indexLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = item.detail != nil ? "\(item.title) — \(item.detail!)" : item.title
        titleLabel.font = .preferredFont(forTextStyle: .body)

        let timeLabel = UILabel()
        timeLabel.text = item.durationText
        timeLabel.font = DesignTokens.Font.smallNumber
        timeLabel.textAlignment = .right

        row.addArrangedSubview(dot)
        row.addArrangedSubview(indexLabel)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(timeLabel)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return row
    }
}
