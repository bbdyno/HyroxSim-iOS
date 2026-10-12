//
//  SeasonReportViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import UIKit

/// 한 해의 훈련과 대회를 숫자 몇 개로 정리해 보여 준다. 그대로 이미지로 공유할 수 있다.
final class SeasonReportViewController: UIViewController {

    private let workouts: [CompletedWorkout]
    private let races: [RaceResult]
    private let years: [Int]
    private var year: Int
    private let calendar: Calendar
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let yearButton = UIButton(type: .system)

    private typealias L = HyroxSimStrings.Localizable.Season

    init(workouts: [CompletedWorkout], races: [RaceResult], calendar: Calendar = .current) {
        self.workouts = workouts
        self.races = races
        self.calendar = calendar
        let available = SeasonReportBuilder.years(workouts: workouts, races: races, calendar: calendar)
        let thisYear = calendar.component(.year, from: Date())
        self.years = available.isEmpty ? [thisYear] : available
        self.year = self.years.first ?? thisYear
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.title
        view.backgroundColor = DesignTokens.Color.background
        view.accessibilityIdentifier = "seasonReport.view"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped)),
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped))
        ]

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        stack.axis = .vertical
        stack.backgroundColor = DesignTokens.Color.background
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 16, leading: 20, bottom: 28, trailing: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor)
        ])
        rebuild()
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    /// 화면에 보이는 요약을 그대로 이미지로 내보낸다.
    @objc private func shareTapped() {
        stack.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: stack.bounds).image { _ in
            stack.drawHierarchy(in: stack.bounds, afterScreenUpdates: true)
        }
        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
        present(activity, animated: true)
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let report = SeasonReportBuilder.build(year: year, workouts: workouts, races: races, calendar: calendar)

        let brand = label("HYROX SIM", font: DesignTokens.Font.wide(11, weight: .heavy),
                          color: DesignTokens.Color.textSecondary, kern: 2)
        add(brand, spacing: 2)

        var config = UIButton.Configuration.plain()
        var title = AttributedString("\(year)")
        title.font = DesignTokens.Font.bigNumber(72)
        config.attributedTitle = title
        config.baseForegroundColor = DesignTokens.Color.accent
        config.contentInsets = .zero
        if years.count > 1 {
            config.image = UIImage(systemName: "chevron.up.chevron.down")
            config.imagePlacement = .trailing
            config.imagePadding = 10
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        }
        yearButton.configuration = config
        yearButton.contentHorizontalAlignment = .leading
        yearButton.showsMenuAsPrimaryAction = years.count > 1
        yearButton.accessibilityIdentifier = "seasonReport.year"
        yearButton.menu = UIMenu(children: years.map { option in
            UIAction(title: "\(option)", state: option == year ? .on : .off) { [weak self] _ in
                self?.year = option
                self?.rebuild()
            }
        })
        add(yearButton, spacing: 4)
        add(label(L.subtitle, font: .systemFont(ofSize: 13, weight: .medium),
                  color: DesignTokens.Color.textSecondary), spacing: 20)

        guard !report.isEmpty else {
            add(hairline(), spacing: 24)
            let empty = label(L.empty, font: .systemFont(ofSize: 15), color: DesignTokens.Color.textSecondary)
            empty.accessibilityIdentifier = "seasonReport.empty"
            add(empty, spacing: 0)
            return
        }

        if let best = report.best {
            add(hairline(), spacing: 16)
            add(label(L.best.uppercased(), font: DesignTokens.Font.wide(11, weight: .heavy),
                      color: DesignTokens.Color.accent, kern: 1.6), spacing: 0)
            let time = label(DurationFormatter.hms(best.seconds), font: DesignTokens.Font.bigNumber(64), color: .white)
            time.adjustsFontSizeToFitWidth = true
            time.minimumScaleFactor = 0.6
            time.accessibilityIdentifier = "seasonReport.best"
            add(time, spacing: 2)
            let when = best.date.formatted(.dateTime.month(.abbreviated).day())
            let kind = best.isOfficial ? L.bestOfficial : L.bestSimulation
            add(label("\(best.name) · \(when) · \(kind)", font: .systemFont(ofSize: 13, weight: .medium),
                      color: DesignTokens.Color.textSecondary), spacing: 6)
            if let improvement = report.improvementSeconds {
                add(label(L.improvementFormat(DurationFormatter.ms(improvement)),
                          font: .systemFont(ofSize: 14, weight: .semibold), color: DesignTokens.Color.accent), spacing: 0)
            }
            stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
        }

        add(hairline(), spacing: 0)
        let hours = report.activeSeconds / 3600
        let rows: [(String, String)] = [
            (L.sessions, "\(report.sessionCount)"),
            (L.simulations, "\(report.fullSimulationCount)"),
            (L.races, "\(report.raceCount)"),
            (L.hours, hours >= 10 ? String(format: "%.0f", hours) : String(format: "%.1f", hours)),
            (L.runningKm, String(format: "%.0f", report.runningMeters / 1000)),
            (L.stations, "\(report.stationCount)"),
            (L.activeWeeks, "\(report.activeWeeks)"),
            (L.streak, "\(report.longestWeekStreak)")
        ]
        for pair in stride(from: 0, to: rows.count, by: 2) {
            let left = makeStat(title: rows[pair].0, value: rows[pair].1)
            let right = pair + 1 < rows.count ? makeStat(title: rows[pair + 1].0, value: rows[pair + 1].1) : UIView()
            let row = UIStackView(arrangedSubviews: [left, right])
            row.distribution = .fillEqually
            row.spacing = 16
            add(row, spacing: 0)
            add(hairline(), spacing: 0)
        }
        if let month = report.busiestMonth,
           let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
            stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)
            add(label(L.busiestFormat(date.formatted(.dateTime.month(.wide))),
                      font: .systemFont(ofSize: 13, weight: .medium), color: DesignTokens.Color.textSecondary), spacing: 0)
        }
    }

    private func add(_ view: UIView, spacing: CGFloat) {
        stack.addArrangedSubview(view)
        stack.setCustomSpacing(spacing, after: view)
    }

    private func label(_ text: String, font: UIFont, color: UIColor, kern: CGFloat = 0) -> UILabel {
        let label = UILabel()
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        if kern > 0 { label.setTracked(text, kern: kern) } else { label.text = text }
        return label
    }

    private func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = DesignTokens.Color.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func makeStat(title: String, value: String) -> UIView {
        let number = label(value, font: DesignTokens.Font.bigNumber(40), color: .white)
        number.adjustsFontSizeToFitWidth = true
        number.minimumScaleFactor = 0.6
        number.numberOfLines = 1
        let caption = label(title.uppercased(), font: DesignTokens.Font.wide(10, weight: .heavy),
                            color: DesignTokens.Color.textSecondary, kern: 1.2)
        let column = UIStackView(arrangedSubviews: [number, caption])
        column.axis = .vertical
        column.spacing = 2
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = .init(top: 14, leading: 0, bottom: 14, trailing: 0)
        column.isAccessibilityElement = true
        column.accessibilityLabel = "\(title) \(value)"
        return column
    }
}
