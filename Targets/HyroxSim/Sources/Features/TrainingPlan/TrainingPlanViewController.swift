//
//  TrainingPlanViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import UIKit

extension Notification.Name {
    /// 훈련 계획에서 세션을 골랐다. `object` 는 열어야 할 `WorkoutTemplate`.
    static let trainingPlanDidSelectTemplate = Notification.Name("TrainingPlan.didSelectTemplate")
}

/// 대회까지의 주간 훈련 계획. 이번 주가 맨 위에 있고, 세션을 누르면 그 운동의 상세로 간다.
final class TrainingPlanViewController: UIViewController {

    private let plan: TrainingPlan
    private let division: HyroxDivision
    private let eventName: String
    private let calendar: Calendar
    private let contentStack = UIStackView()

    private typealias L = HyroxSimStrings.Localizable.TrainingPlan

    init(plan: TrainingPlan, division: HyroxDivision, eventName: String, calendar: Calendar = .current) {
        self.plan = plan
        self.division = division
        self.eventName = eventName
        self.calendar = calendar
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.title
        view.backgroundColor = DesignTokens.Color.background
        view.accessibilityIdentifier = "trainingPlan.view"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped)
        )

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        contentStack.axis = .vertical
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32)
        ])
        buildContent()
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    private func buildContent() {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: plan.raceDate)
        ).day ?? 0

        let caption = UILabel()
        caption.font = DesignTokens.Font.wide(11, weight: .heavy)
        caption.textColor = DesignTokens.Color.textSecondary
        caption.numberOfLines = 0
        caption.setTracked(eventName.uppercased(), kern: 1.6)
        add(caption, spacing: 2)

        let countdown = UILabel()
        countdown.font = DesignTokens.Font.bigNumber(64)
        countdown.textColor = DesignTokens.Color.accent
        countdown.text = days == 0 ? L.raceToday : "D−\(days)"
        countdown.adjustsFontSizeToFitWidth = true
        countdown.minimumScaleFactor = 0.6
        countdown.accessibilityIdentifier = "trainingPlan.countdown"
        add(countdown, spacing: 6)

        let intro = UILabel()
        intro.font = .systemFont(ofSize: 13)
        intro.textColor = DesignTokens.Color.textSecondary
        intro.numberOfLines = 0
        intro.text = plan.isTruncated ? L.introTruncated(plan.weeks.count) : L.intro
        add(intro, spacing: 18)

        for week in plan.weeks {
            add(hairline(), spacing: 0)
            add(makeWeekHeader(week), spacing: 0)
            for item in week.items {
                add(makeItemRow(item, isCurrentWeek: week.index == 0), spacing: 0)
            }
            contentStack.setCustomSpacing(10, after: contentStack.arrangedSubviews.last!)
        }
        add(hairline(), spacing: 16)

        let footnote = UILabel()
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = DesignTokens.Color.textTertiary
        footnote.numberOfLines = 0
        footnote.text = L.footnote
        add(footnote, spacing: 0)
    }

    private func add(_ view: UIView, spacing: CGFloat) {
        contentStack.addArrangedSubview(view)
        contentStack.setCustomSpacing(spacing, after: view)
    }

    private func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = DesignTokens.Color.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func makeWeekHeader(_ week: TrainingPlanWeek) -> UIView {
        let isCurrent = week.index == 0
        let title = UILabel()
        title.font = DesignTokens.Font.wide(12, weight: .heavy)
        title.textColor = isCurrent ? DesignTokens.Color.accent : DesignTokens.Color.textPrimary
        let weekText = isCurrent
            ? L.thisWeek
            : L.weekOfFormat(week.startDate.formatted(.dateTime.month(.abbreviated).day()))
        title.setTracked(weekText.uppercased(), kern: 1.2)

        let phase = UILabel()
        phase.font = DesignTokens.Font.wide(10.5, weight: .heavy)
        phase.textColor = DesignTokens.Color.textSecondary
        phase.textAlignment = .right
        let remaining = week.weeksToRace == 0 ? L.raceWeekTag : L.weeksOutFormat(week.weeksToRace)
        phase.setTracked("\(Self.phaseName(week.phase)) · \(remaining)".uppercased(), kern: 1)
        phase.adjustsFontSizeToFitWidth = true
        phase.minimumScaleFactor = 0.7

        let row = UIStackView(arrangedSubviews: [title, phase])
        row.alignment = .firstBaseline
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 14, leading: 0, bottom: 6, trailing: 0)
        return row
    }

    private func makeItemRow(_ item: TrainingPlanItem, isCurrentWeek: Bool) -> UIView {
        let (name, detail) = Self.text(for: item)

        let marker = UIView()
        marker.backgroundColor = item == .race
            ? DesignTokens.Color.accent
            : (isCurrentWeek ? DesignTokens.Color.accent : DesignTokens.Color.track)
        marker.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = isCurrentWeek || item == .race
            ? DesignTokens.Color.textPrimary : DesignTokens.Color.textSecondary
        title.numberOfLines = 0
        title.text = name

        let subtitle = UILabel()
        subtitle.font = .systemFont(ofSize: 12.5)
        subtitle.textColor = DesignTokens.Color.textSecondary
        subtitle.numberOfLines = 0
        subtitle.text = detail
        subtitle.isHidden = !isCurrentWeek || detail == nil

        let text = UIStackView(arrangedSubviews: [title, subtitle])
        text.axis = .vertical
        text.spacing = 2
        text.isUserInteractionEnabled = false
        text.translatesAutoresizingMaskIntoConstraints = false

        let arrow = UIImageView(image: UIImage(systemName: "chevron.right"))
        arrow.tintColor = DesignTokens.Color.textTertiary
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.isHidden = item == .race

        let control = UIControl()
        control.addSubview(marker)
        control.addSubview(text)
        control.addSubview(arrow)
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            marker.widthAnchor.constraint(equalToConstant: 3),
            marker.topAnchor.constraint(equalTo: text.topAnchor, constant: 1),
            marker.bottomAnchor.constraint(equalTo: text.bottomAnchor, constant: -1),
            text.leadingAnchor.constraint(equalTo: marker.trailingAnchor, constant: 12),
            text.topAnchor.constraint(equalTo: control.topAnchor, constant: 8),
            text.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -8),
            text.trailingAnchor.constraint(lessThanOrEqualTo: arrow.leadingAnchor, constant: -10),
            arrow.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            arrow.centerYAnchor.constraint(equalTo: control.centerYAnchor)
        ])
        control.isAccessibilityElement = true
        control.accessibilityLabel = [name, detail].compactMap { $0 }.joined(separator: ". ")
        control.accessibilityTraits = item == .race ? .staticText : .button
        if let template = template(for: item) {
            control.addAction(UIAction { [weak self] _ in
                // 계획은 대회 편집 화면 위에 떠 있다. 닫고 나서 홈 쪽에서 운동 상세를 연다.
                self?.view.window?.rootViewController?.dismiss(animated: true) {
                    NotificationCenter.default.post(name: .trainingPlanDidSelectTemplate, object: template)
                }
            }, for: .touchUpInside)
        }
        return control
    }

    private func template(for item: TrainingPlanItem) -> WorkoutTemplate? {
        switch item {
        case .fullSimulation:
            return HyroxPresets.template(for: division)
        case .session(let kind):
            return HyroxPresets.trainingSession(
                kind, for: division, localizedName: TrainingSessionLocalization.name(for:)
            )
        case .race:
            return nil
        }
    }

    private static func text(for item: TrainingPlanItem) -> (String, String?) {
        switch item {
        case .fullSimulation: return (L.fullSimulation, L.fullSimulationDetail)
        case .session(let kind):
            return (TrainingSessionLocalization.name(for: kind), TrainingSessionLocalization.summary(for: kind))
        case .race: return (L.raceDay, nil)
        }
    }

    private static func phaseName(_ phase: TrainingPhase) -> String {
        switch phase {
        case .base: return L.Phase.base
        case .build: return L.Phase.build
        case .peak: return L.Phase.peak
        case .taper: return L.Phase.taper
        case .raceWeek: return L.Phase.raceWeek
        }
    }
}
