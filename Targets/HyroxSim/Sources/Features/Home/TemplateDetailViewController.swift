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
    private let template: WorkoutTemplate
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    init(template: WorkoutTemplate) {
        self.template = template
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = template.division?.shortName ?? template.name
        view.backgroundColor = DesignTokens.Color.background
        applyDarkNavBarAppearance()
        setupScrollView()
        buildContent()
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
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        let m: CGFloat = 20
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: m),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -m)
        ])
    }

    private func buildContent() {
        let accent = DesignTokens.Color.accent

        // Header
        addLabel(template.division?.displayName ?? template.name, font: .systemFont(ofSize: 22, weight: .bold), color: .white)
        addSpacer(8)

        let stations = template.segments.filter { $0.type == .station }.count
        let runDist = template.segments.filter { $0.type == .run }.compactMap(\.distanceMeters).reduce(0, +)
        let mins = Int(template.estimatedDurationSeconds / 60)
        addLabel("\(stations) stations · \(DistanceFormatter.short(runDist)) run · ~\(mins) min", font: .systemFont(ofSize: 13, weight: .medium), color: DesignTokens.Color.textSecondary)
        addSpacer(20)

        // Course header
        addLabel("COURSE", font: .systemFont(ofSize: 12, weight: .bold), color: accent)
        addSeparator(color: accent.withAlphaComponent(0.3))
        addSpacer(8)

        // Segments
        var stationIdx = 0
        for (_, seg) in template.segments.enumerated() {
            switch seg.type {
            case .run:
                addSegmentRow(num: nil, title: "Running", detail: DistanceFormatter.short(seg.distanceMeters ?? 0), color: DesignTokens.Color.runAccent, dimmed: false)
            case .roxZone:
                addSegmentRow(num: nil, title: "Rox Zone", detail: nil, color: DesignTokens.Color.roxZoneAccent, dimmed: true)
            case .station:
                stationIdx += 1
                let name = seg.stationKind?.displayName ?? "Station"
                var detail = seg.stationTarget?.formatted ?? ""
                if let w = seg.weightKg {
                    detail += " · \(Int(w))kg"
                    if let n = seg.weightNote { detail += " \(n)" }
                }
                addSegmentRow(num: String(format: "%02d", stationIdx), title: name, detail: detail, color: accent, dimmed: false)
            }
        }

        addSpacer(24)

        // Start button
        let startBtn = UIButton(type: .system)
        startBtn.setTitle("Start Workout", for: .normal)
        startBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        startBtn.setTitleColor(.black, for: .normal)
        startBtn.backgroundColor = accent
        startBtn.layer.cornerRadius = 24
        startBtn.heightAnchor.constraint(equalToConstant: 48).isActive = true
        startBtn.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(startBtn)
        addSpacer(20)
    }

    @objc private func startTapped() {
        delegate?.templateDetailDidTapStart(template)
    }

    // MARK: - Helpers

    private func addSegmentRow(num: String?, title: String, detail: String?, color: UIColor, dimmed: Bool) {
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
        contentStack.addArrangedSubview(container)
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
