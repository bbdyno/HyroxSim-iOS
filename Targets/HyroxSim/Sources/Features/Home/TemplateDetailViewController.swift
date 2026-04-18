//
//  TemplateDetailViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

@MainActor
protocol TemplateDetailViewControllerDelegate: AnyObject {
    func templateDetailDidTapStart(_ template: WorkoutTemplate)
}

final class TemplateDetailViewController: UIViewController {

    weak var delegate: TemplateDetailViewControllerDelegate?
    private var template: WorkoutTemplate
    private var preservedRoxSegments: [WorkoutSegment]
    private let onTemplateUpdated: ((WorkoutTemplate) -> Void)?
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let goalValueLabel = UILabel()
    private let goalHintLabel = UILabel()
    private let roxZoneSwitch = UISwitch()
    private let roxSubtitleLabel = UILabel()
    private let courseRowsStack = UIStackView()
    private let footerContainer = UIView()
    private let startButton = UIButton(type: .system)

    init(
        template: WorkoutTemplate,
        onTemplateUpdated: ((WorkoutTemplate) -> Void)? = nil
    ) {
        self.template = template
        self.preservedRoxSegments = template.segments.filter { $0.type == .roxZone }
        self.onTemplateUpdated = onTemplateUpdated
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        applyDarkNavBarAppearance()
        navigationItem.largeTitleDisplayMode = .never
        setupFooter()
        setupScrollView()
        buildContent()
        rebuildContent()
    }

    // MARK: - Layout

    private func setupScrollView() {
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerContainer.topAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        let m: CGFloat = 20
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: m),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: m),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -m),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -m)
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

        startButton.setTitle(NSLocalizedString("button.start_workout", comment: ""), for: .normal)
        startButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        startButton.setTitleColor(.black, for: .normal)
        startButton.backgroundColor = DesignTokens.Color.accent
        startButton.layer.cornerRadius = 24
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        footerContainer.addSubview(startButton)

        NSLayoutConstraint.activate([
            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            separator.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            startButton.topAnchor.constraint(equalTo: footerContainer.topAnchor, constant: 12),
            startButton.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            startButton.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            startButton.heightAnchor.constraint(equalToConstant: 48),
            startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    private func rebuildContent() {
        title = template.isBuiltIn ? (template.division?.shortName ?? template.name) : template.name
        titleLabel.text = template.isBuiltIn ? (template.division?.displayName ?? template.name) : template.name

        let stations = template.segments.filter { $0.type == .station }.count
        let runDist = template.segments.filter { $0.type == .run }.compactMap(\.distanceMeters).reduce(0, +)
        let mins = Int(template.estimatedDurationSeconds / 60)
        metaLabel.text = "\(stations) stations · \(DistanceFormatter.short(runDist)) run · ~\(mins) min"
        goalValueLabel.text = "Goal Total \(DurationFormatter.hms(template.estimatedDurationSeconds))"
        goalHintLabel.text = NSLocalizedString("button.edit_segment_targets", comment: "")

        roxZoneSwitch.isOn = template.usesRoxZone
        roxSubtitleLabel.text = template.usesRoxZone
            ? "Auto-inserts transition blocks between each run and station."
            : "Runs connect directly to stations."

        rebuildCourseRows()
    }

    private func buildContent() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        contentStack.addArrangedSubview(titleLabel)

        addSpacer(8)

        metaLabel.font = .systemFont(ofSize: 13, weight: .medium)
        metaLabel.textColor = DesignTokens.Color.textSecondary
        metaLabel.numberOfLines = 0
        contentStack.addArrangedSubview(metaLabel)

        addSpacer(16)
        contentStack.addArrangedSubview(makeGoalCard())
        addSpacer(12)

        let card = UIView()
        card.backgroundColor = DesignTokens.Color.surfaceElevated
        card.layer.cornerRadius = DesignTokens.Radius.card
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = "ROX ZONE"
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = DesignTokens.Color.roxZoneAccent

        roxSubtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        roxSubtitleLabel.textColor = DesignTokens.Color.textSecondary
        roxSubtitleLabel.numberOfLines = 0

        roxZoneSwitch.onTintColor = DesignTokens.Color.accent
        roxZoneSwitch.removeTarget(nil, action: nil, for: .valueChanged)
        roxZoneSwitch.addTarget(self, action: #selector(roxZoneToggleChanged), for: .valueChanged)

        let labels = UIStackView(arrangedSubviews: [titleLabel, roxSubtitleLabel])
        labels.axis = .vertical
        labels.spacing = 4

        let row = UIStackView(arrangedSubviews: [labels, roxZoneSwitch])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        contentStack.addArrangedSubview(card)
        addSpacer(20)

        let courseLabel = UILabel()
        courseLabel.text = "COURSE"
        courseLabel.font = .systemFont(ofSize: 12, weight: .bold)
        courseLabel.textColor = DesignTokens.Color.accent
        contentStack.addArrangedSubview(courseLabel)
        addSeparator(color: DesignTokens.Color.accent.withAlphaComponent(0.3))
        addSpacer(8)

        courseRowsStack.axis = .vertical
        courseRowsStack.spacing = 0
        contentStack.addArrangedSubview(courseRowsStack)
        addSpacer(24)
    }

    private func rebuildCourseRows() {
        courseRowsStack.arrangedSubviews.forEach {
            courseRowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        var stationIdx = 0
        for seg in template.segments {
            switch seg.type {
            case .run:
                addSegmentRow(
                    to: courseRowsStack,
                    num: nil,
                    title: "Running",
                    detail: DistanceFormatter.short(seg.distanceMeters ?? 0),
                    color: DesignTokens.Color.runAccent,
                    dimmed: false
                )
            case .roxZone:
                addSegmentRow(
                    to: courseRowsStack,
                    num: nil,
                    title: "Rox Zone",
                    detail: nil,
                    color: DesignTokens.Color.roxZoneAccent,
                    dimmed: true
                )
            case .station:
                stationIdx += 1
                let name = seg.stationKind?.displayName ?? "Station"
                var detail = seg.stationTarget?.formatted ?? ""
                if let w = seg.weightKg {
                    detail += " · \(Int(w))kg"
                    if let n = seg.weightNote { detail += " \(n)" }
                }
                addSegmentRow(
                    to: courseRowsStack,
                    num: String(format: "%02d", stationIdx),
                    title: name,
                    detail: detail,
                    color: DesignTokens.Color.accent,
                    dimmed: false
                )
            }
        }
    }

    @objc private func startTapped() {
        delegate?.templateDetailDidTapStart(template)
    }

    @objc private func editGoalsTapped() {
        let rootVC: UIViewController
        if template.division != nil,
           let pacePlanner = try? PaceReferenceLoader.loadPacePlanner() {
            let planner = PacePlannerViewController(template: template, planner: pacePlanner)
            planner.delegate = self
            rootVC = planner
        } else {
            let goalVC = WorkoutGoalSetupViewController(
                template: template,
                screenTitle: "Edit Goals",
                confirmButtonTitle: "Save Goals"
            )
            goalVC.delegate = self
            rootVC = goalVC
        }

        let nav = UINavigationController(rootViewController: rootVC)
        nav.applyDarkTheme()
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
        }
        present(nav, animated: true)
    }

    @objc private func roxZoneToggleChanged() {
        template = template.settingUsesRoxZone(
            roxZoneSwitch.isOn,
            preservedRoxSegments: preservedRoxSegments
        )
        if template.usesRoxZone {
            preservedRoxSegments = template.segments.filter { $0.type == .roxZone }
        }
        onTemplateUpdated?(template)
        rebuildContent()
    }

    // MARK: - Helpers

    private func makeGoalCard() -> UIView {
        let card = UIView()
        card.backgroundColor = DesignTokens.Color.surfaceElevated
        card.layer.cornerRadius = DesignTokens.Radius.card
        card.isUserInteractionEnabled = true

        let titleLabel = UILabel()
        titleLabel.text = "GOALS"
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = DesignTokens.Color.accent

        goalValueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        goalValueLabel.textColor = .white

        goalHintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        goalHintLabel.textColor = DesignTokens.Color.textSecondary

        let labels = UIStackView(arrangedSubviews: [titleLabel, goalValueLabel, goalHintLabel])
        labels.axis = .vertical
        labels.spacing = 4

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = DesignTokens.Color.textSecondary
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let row = UIStackView(arrangedSubviews: [labels, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(editGoalsTapped)))
        return card
    }

    private func addSegmentRow(
        to stackView: UIStackView,
        num: String?,
        title: String,
        detail: String?,
        color: UIColor,
        dimmed: Bool
    ) {
        let row = UIStackView()
        row.alignment = .center
        row.spacing = 10

        if let num {
            let badge = UIView()
            badge.backgroundColor = color
            badge.layer.cornerRadius = DesignTokens.Radius.badge
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.widthAnchor.constraint(equalToConstant: 28).isActive = true
            badge.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let lbl = UILabel()
            lbl.text = num
            lbl.font = .systemFont(ofSize: 10, weight: .black)
            lbl.textColor = .black
            lbl.textAlignment = .center
            lbl.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(lbl)
            NSLayoutConstraint.activate([lbl.centerXAnchor.constraint(equalTo: badge.centerXAnchor), lbl.centerYAnchor.constraint(equalTo: badge.centerYAnchor)])
            row.addArrangedSubview(badge)
        } else {
            let spacer = UIView()
            spacer.widthAnchor.constraint(equalToConstant: 28).isActive = true
            row.addArrangedSubview(spacer)
        }

        let alpha: CGFloat = dimmed ? 0.4 : 1.0
        let nameLabel = UILabel()
        nameLabel.text = title
        nameLabel.font = num != nil ? .systemFont(ofSize: 14, weight: .bold) : .systemFont(ofSize: 13, weight: .regular)
        nameLabel.textColor = UIColor.white.withAlphaComponent(alpha)
        row.addArrangedSubview(nameLabel)

        if let detail, !detail.isEmpty {
            let detailLabel = UILabel()
            detailLabel.text = detail
            detailLabel.font = .systemFont(ofSize: 12, weight: .medium)
            detailLabel.textColor = DesignTokens.Color.textTertiary
            detailLabel.textAlignment = .right
            row.addArrangedSubview(detailLabel)
            nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        let container = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5)
        ])
        stackView.addArrangedSubview(container)
    }

    private func addLabel(_ text: String, font: UIFont, color: UIColor) {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = color
        l.numberOfLines = 0
        contentStack.addArrangedSubview(l)
    }

    private func addSpacer(_ h: CGFloat) {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        contentStack.addArrangedSubview(v)
    }

    private func addSeparator(color: UIColor) {
        let v = UIView()
        v.backgroundColor = color
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        contentStack.addArrangedSubview(v)
    }
}

extension TemplateDetailViewController: WorkoutGoalSetupViewControllerDelegate {

    func goalSetupDidCancel() {
        dismiss(animated: true)
    }

    func goalSetupDidConfirm(template: WorkoutTemplate) {
        self.template = template
        preservedRoxSegments = template.segments.filter { $0.type == .roxZone }
        onTemplateUpdated?(template)
        dismiss(animated: true) {
            self.rebuildContent()
        }
    }
}

extension TemplateDetailViewController: PacePlannerViewControllerDelegate {

    func pacePlannerDidCancel() {
        dismiss(animated: true)
    }

    func pacePlannerDidConfirm(template: WorkoutTemplate) {
        self.template = template
        preservedRoxSegments = template.segments.filter { $0.type == .roxZone }
        onTemplateUpdated?(template)
        dismiss(animated: true) {
            self.rebuildContent()
        }
    }
}
