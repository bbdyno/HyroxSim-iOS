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
        view.backgroundColor = .systemBackground
        setupTableView()
        setupEmptyLabel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
        tableView.reloadData()
        updateEmptyState()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
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
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: DesignTokens.Spacing.xl)
        ])
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !viewModel.workouts.isEmpty
        tableView.isHidden = viewModel.workouts.isEmpty
    }
}

// MARK: - UITableViewDataSource

extension HistoryViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.workouts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WorkoutCell", for: indexPath)
        let workout = viewModel.workouts[indexPath.row]

        var config = UIListContentConfiguration.subtitleCell()
        config.text = workout.templateName
        config.textProperties.font = .preferredFont(forTextStyle: .headline)

        let duration = DurationFormatter.hms(workout.totalDuration)
        let date = RelativeDateFormatter.short(workout.finishedAt)
        config.secondaryText = "\(duration) · \(date)"
        config.secondaryTextProperties.font = DesignTokens.Font.smallNumber
        config.secondaryTextProperties.color = .secondaryLabel

        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
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

// MARK: - UITableViewDelegate

extension HistoryViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let workout = viewModel.workouts[indexPath.row]
        delegate?.historyDidSelect(workout)
    }
}
