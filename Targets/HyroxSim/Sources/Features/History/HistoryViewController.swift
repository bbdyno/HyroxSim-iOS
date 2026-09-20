//
//  HistoryViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

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
        title = HyroxSimStrings.Localizable.Nav.history
        view.backgroundColor = DesignTokens.Color.background
        applyDarkNavBarAppearance()
        setupTableView()
        setupEmptyLabel()

        // 워치·가민에서 기록이 도착하거나 삭제가 전파되면 화면이 바로 따라간다.
        viewModel.onWorkoutsChanged = { [weak self] in
            self?.reloadFromViewModel()
        }
        viewModel.startObserving()
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
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(HistoryCardCell.self, forCellReuseIdentifier: HistoryCardCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel.text = HyroxSimStrings.Localizable.History.empty
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = DesignTokens.Color.textTertiary
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !viewModel.workouts.isEmpty
        tableView.isHidden = viewModel.workouts.isEmpty
    }

    private func reloadFromViewModel() {
        tableView.reloadData()
        updateEmptyState()
    }

    private func presentDeleteFailure() {
        let alert = DarkAlertController(
            title: HyroxSimStrings.Localizable.Alert.DeleteWorkoutFailed.title,
            message: HyroxSimStrings.Localizable.Alert.DeleteWorkoutFailed.message
        )
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.ok, style: .normal, handler: nil))
        present(alert, animated: true)
    }
}

// MARK: - DataSource

extension HistoryViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.workouts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: HistoryCardCell.reuseId, for: indexPath) as! HistoryCardCell
        cell.configure(with: viewModel.workouts[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, done in
            guard let self else { return }
            do {
                try self.viewModel.delete(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .automatic)
                self.updateEmptyState()
                done(true)
            } catch {
                // 저장에 실패했으면 행을 지우면 안 된다. 스와이프를 되돌리고
                // 사용자에게 알린다 — 예전에는 `try?` 라 행만 사라졌다가
                // 다음에 화면에 들어오면 되살아났다.
                done(false)
                self.reloadFromViewModel()
                self.presentDeleteFailure()
            }
        }
        delete.image = UIImage(systemName: "trash.fill")
        delete.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - Delegate

extension HistoryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        delegate?.historyDidSelect(viewModel.workouts[indexPath.row])
    }
}

// MARK: - Custom Cell

private final class HistoryCardCell: UITableViewCell {

    static let reuseId = "HistoryCardCell"

    private let cardView = UIView()
    private let divisionLabel = UILabel()
    private let timeLabel = UILabel()
    private let dateLabel = UILabel()
    private let stationsLabel = UILabel()
    private let chevron = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        cardView.backgroundColor = DesignTokens.Color.surface
        cardView.layer.cornerRadius = 14
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])

        divisionLabel.font = .systemFont(ofSize: 15, weight: .bold)
        divisionLabel.textColor = .white

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        timeLabel.textColor = DesignTokens.Color.accent

        dateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        dateLabel.textColor = DesignTokens.Color.textTertiary

        stationsLabel.font = .systemFont(ofSize: 12, weight: .medium)
        stationsLabel.textColor = DesignTokens.Color.textSecondary

        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = DesignTokens.Color.textTertiary
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [divisionLabel, timeLabel, stationsLabel, dateLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let hStack = UIStackView(arrangedSubviews: [textStack, chevron])
        hStack.alignment = .center
        hStack.spacing = 12
        hStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            hStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            hStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            hStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14)
        ])
    }

    func configure(with workout: CompletedWorkout) {
        divisionLabel.text = workout.templateName
        timeLabel.text = DurationFormatter.hms(workout.totalDuration)
        stationsLabel.text = "\(workout.stationSegments.count) stations · \(workout.segments.count) segments"
        dateLabel.text = RelativeDateFormatter.short(workout.finishedAt)
    }
}
