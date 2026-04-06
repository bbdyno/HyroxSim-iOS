import UIKit
import HyroxKit

@MainActor
protocol BuilderEntrySheetDelegate: AnyObject {
    func builderEntryDidSelectPreset(_ template: WorkoutTemplate)
    func builderEntryDidSelectScratch()
}

final class BuilderEntrySheetViewController: UIViewController {

    weak var delegate: BuilderEntrySheetDelegate?

    private var tableView: UITableView!
    private let presets = HyroxPresets.all

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Workout"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        setupTableView()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
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

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Start from Preset" : nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? presets.count : 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        if indexPath.section == 0 {
            var config = UIListContentConfiguration.cell()
            config.text = presets[indexPath.row].name
            config.textProperties.font = .preferredFont(forTextStyle: .body)
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
        } else {
            var config = UIListContentConfiguration.cell()
            config.text = "Start from Scratch"
            config.textProperties.font = .preferredFont(forTextStyle: .headline)
            config.textProperties.color = .systemBlue
            config.image = UIImage(systemName: "plus.circle.fill")
            config.imageProperties.tintColor = .systemBlue
            cell.contentConfiguration = config
            cell.accessoryType = .none
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
