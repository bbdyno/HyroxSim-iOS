//
//  BuilderEntrySheetViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

@MainActor
protocol BuilderEntrySheetDelegate: AnyObject {
    func builderEntryDidSelectPreset(_ template: WorkoutTemplate)
    func builderEntryDidSelectScratch()
}

final class BuilderEntrySheetViewController: UIViewController {

    weak var delegate: BuilderEntrySheetDelegate?
    private var tableView: UITableView!
    private let presets = HyroxPresets.all

    init() { super.init(nibName: nil, bundle: nil) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Workout"
        view.backgroundColor = DesignTokens.Color.background
        applyDarkNavBarAppearance()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        setupTableView()
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = DesignTokens.Color.background
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

extension BuilderEntrySheetViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 0 else { return nil }
        let label = UILabel()
        label.text = "  START FROM PRESET"
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = DesignTokens.Color.accent
        let container = UIView()
        container.backgroundColor = DesignTokens.Color.background
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 0 ? 36 : 16
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? presets.count : 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.backgroundColor = DesignTokens.Color.background
        cell.selectedBackgroundView = { let v = UIView(); v.backgroundColor = DesignTokens.Color.surface; return v }()

        if indexPath.section == 0 {
            var config = UIListContentConfiguration.cell()
            config.text = presets[indexPath.row].division?.shortName ?? presets[indexPath.row].name
            config.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
            config.textProperties.color = .white
            cell.contentConfiguration = config
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = DesignTokens.Color.textTertiary
            cell.accessoryView = chevron
        } else {
            var config = UIListContentConfiguration.cell()
            config.text = "Start from Scratch"
            config.textProperties.font = .systemFont(ofSize: 16, weight: .bold)
            config.textProperties.color = DesignTokens.Color.accent
            config.image = UIImage(systemName: "plus.circle.fill")
            config.imageProperties.tintColor = DesignTokens.Color.accent
            cell.contentConfiguration = config
            cell.accessoryView = nil
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            delegate?.builderEntryDidSelectPreset(presets[indexPath.row])
        } else {
            delegate?.builderEntryDidSelectScratch()
        }
    }
}
