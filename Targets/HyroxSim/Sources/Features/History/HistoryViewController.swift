//
//  HistoryViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxKit

@MainActor
protocol HistoryViewControllerDelegate: AnyObject {
    func historyDidSelect(_ workout: CompletedWorkout)
}

final class HistoryViewController: UIViewController {

    weak var delegate: HistoryViewControllerDelegate?
    private let viewModel: HistoryViewModel
    private var tableView: UITableView!
    private let emptyLabel = UILabel()

    init(viewModel: HistoryViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        view.backgroundColor = DesignTokens.Color.background
        applyDarkNavBarAppearance()
        setupTableView()
        setupEmptyLabel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
        tableView.reloadData()
        updateEmptyState()
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = DesignTokens.Color.background
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "WorkoutCell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel.text = "No workouts yet.\nComplete your first HYROX!"
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = DesignTokens.Color.textTertiary
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40)
        ])
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !viewModel.workouts.isEmpty
        tableView.isHidden = viewModel.workouts.isEmpty
    }
}

extension HistoryViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.workouts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WorkoutCell", for: indexPath)
        let workout = viewModel.workouts[indexPath.row]
        cell.backgroundColor = DesignTokens.Color.background
        cell.selectedBackgroundView = {
            let v = UIView()
            v.backgroundColor = DesignTokens.Color.surface
            return v
        }()

        var config = UIListContentConfiguration.subtitleCell()
        config.text = workout.division?.shortName ?? workout.templateName
        config.textProperties.font = .systemFont(ofSize: 16, weight: .bold)
        config.textProperties.color = .white

        let duration = DurationFormatter.hms(workout.totalDuration)
        let date = RelativeDateFormatter.short(workout.finishedAt)
        config.secondaryText = "\(duration)  ·  \(date)"
        config.secondaryTextProperties.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        config.secondaryTextProperties.color = DesignTokens.Color.textSecondary

        cell.contentConfiguration = config

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = DesignTokens.Color.textTertiary
        cell.accessoryView = chevron
        return cell
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            viewModel.delete(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            updateEmptyState()
        }
    }
}

extension HistoryViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        delegate?.historyDidSelect(viewModel.workouts[indexPath.row])
    }
}
