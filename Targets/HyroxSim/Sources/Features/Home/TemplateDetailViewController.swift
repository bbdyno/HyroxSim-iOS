//
//  TemplateDetailViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxKit

@MainActor
protocol TemplateDetailViewControllerDelegate: AnyObject {
    func templateDetailDidTapStart(_ template: WorkoutTemplate)
}

final class TemplateDetailViewController: UIViewController {

    weak var delegate: TemplateDetailViewControllerDelegate?
    private let template: WorkoutTemplate
    private var tableView: UITableView!

    init(template: WorkoutTemplate) {
        self.template = template
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = template.division?.shortName ?? template.name
        view.backgroundColor = .systemBackground
        setupTableView()
        setupFooter()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupFooter() {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 80))
        let startButton = UIButton(type: .system)
        startButton.setTitle("Start Workout", for: .normal)
        startButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        startButton.setTitleColor(.white, for: .normal)
        startButton.backgroundColor = .systemGreen
        startButton.layer.cornerRadius = 24
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        footer.addSubview(startButton)

        NSLayoutConstraint.activate([
            startButton.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            startButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            startButton.widthAnchor.constraint(equalToConstant: 240),
            startButton.heightAnchor.constraint(equalToConstant: 48)
        ])
        tableView.tableFooterView = footer
    }

    @objc private func startTapped() {
        delegate?.templateDetailDidTapStart(template)
    }

    // MARK: - Helpers

    private var stationCount: Int {
        template.segments.filter { $0.type == .station }.count
    }

    private var runDistance: Double {
        template.segments.filter { $0.type == .run }.compactMap(\.distanceMeters).reduce(0, +)
    }
}

// MARK: - UITableViewDataSource

extension TemplateDetailViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Overview" : "Course (\(template.segments.count) segments)"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 3 : template.segments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.selectionStyle = .none

        if indexPath.section == 0 {
            var config = UIListContentConfiguration.valueCell()
            switch indexPath.row {
            case 0:
                config.text = "Division"
                config.secondaryText = template.division?.displayName ?? "Custom"
            case 1:
                config.text = "Stations"
                config.secondaryText = "\(stationCount) stations · \(DistanceFormatter.short(runDistance)) run"
            default:
                config.text = "Est. Duration"
                config.secondaryText = "~\(Int(template.estimatedDurationSeconds / 60)) min"
            }
            cell.contentConfiguration = config
        } else {
            let seg = template.segments[indexPath.row]
            var config = UIListContentConfiguration.subtitleCell()
            let num = indexPath.row + 1

            switch seg.type {
            case .run:
                config.text = "\(num). RUN"
                config.secondaryText = DistanceFormatter.short(seg.distanceMeters ?? 0)
                config.textProperties.color = DesignTokens.Color.runAccent
            case .roxZone:
                config.text = "\(num). ROX ZONE"
                config.textProperties.color = DesignTokens.Color.roxZoneAccent
            case .station:
                let name = seg.stationKind?.displayName ?? "Station"
                config.text = "\(num). \(name)"
                var detail = seg.stationTarget?.formatted ?? ""
                if let w = seg.weightKg {
                    detail += " · \(Int(w)) kg"
                    if let note = seg.weightNote { detail += " \(note)" }
                }
                config.secondaryText = detail
                config.textProperties.color = DesignTokens.Color.stationAccent
            }
            config.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = config
        }

        return cell
    }
}
