import UIKit
import HyroxKit

@MainActor
protocol WorkoutBuilderViewControllerDelegate: AnyObject {
    func builderDidCancel()
    func builderDidRequestStart(template: WorkoutTemplate)
    func builderDidSaveTemplate(_ template: WorkoutTemplate)
}

final class WorkoutBuilderViewController: UIViewController {

    weak var delegate: WorkoutBuilderViewControllerDelegate?
    let viewModel: WorkoutBuilderViewModel

    private enum Section: Int, CaseIterable {
        case segments
        case addButtons
    }

    private enum Item: Hashable {
        case segment(UUID)
        case addRun
        case addRoxZone
        case addStation
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let emptyLabel = UILabel()

    init(viewModel: WorkoutBuilderViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.name
        view.backgroundColor = .systemBackground
        setupNav()
        setupCollectionView()
        setupDataSource()
        setupEmptyLabel()
        setupToolbar()
        applySnapshot()
    }

    // MARK: - Nav

    private func setupNav() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Start", style: .done, target: self, action: #selector(startTapped)
        )
        updateStartButton()
    }

    private func updateStartButton() {
        navigationItem.rightBarButtonItem?.isEnabled = viewModel.canStart
    }

    @objc private func cancelTapped() {
        // First version: always confirm on cancel
        let alert = UIAlertController(title: "Discard Changes?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            self?.delegate?.builderDidCancel()
        })
        alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func startTapped() {
        guard let template = try? viewModel.makeTemplateForStart() else { return }
        delegate?.builderDidRequestStart(template: template)
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        navigationController?.isToolbarHidden = false
        let saveBtn = UIBarButtonItem(title: "Save as Template", style: .plain, target: self, action: #selector(saveTapped))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        let metaLabel = UILabel()
        metaLabel.font = .preferredFont(forTextStyle: .caption1)
        metaLabel.textColor = .secondaryLabel
        metaLabel.text = metaSummary()
        let metaItem = UIBarButtonItem(customView: metaLabel)

        toolbarItems = [metaItem, flex, saveBtn]
    }

    private func metaSummary() -> String {
        let stations = viewModel.stationCount
        let km = viewModel.totalRunDistanceMeters / 1000
        let mins = Int(viewModel.estimatedDurationSeconds / 60)
        return "\(stations) stations · \(String(format: "%.1f", km)) km · ~\(mins) min"
    }

    @objc private func saveTapped() {
        guard viewModel.canSave else { return }

        let alert = UIAlertController(title: "Save Template", message: "Enter a name", preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            tf.text = self?.viewModel.name
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self, let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            self.viewModel.rename(to: name)
            guard let template = try? self.viewModel.saveAsTemplate() else { return }
            self.delegate?.builderDidSaveTemplate(template)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Collection View

    private func setupCollectionView() {
        var listConfig = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self, let item = self.dataSource.itemIdentifier(for: indexPath),
                  case .segment = item else { return nil }
            let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                self.viewModel.removeSegment(at: indexPath.row)
                self.applySnapshot()
                completion(true)
            }
            return UISwipeActionsConfiguration(actions: [delete])
        }
        let layout = UICollectionViewCompositionalLayout.list(using: listConfig)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupDataSource() {
        let segmentReg = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> { [weak self] cell, indexPath, segId in
            guard let self else { return }
            let idx = indexPath.row
            guard idx < self.viewModel.segments.count else { return }
            let seg = self.viewModel.segments[idx]

            var config = UIListContentConfiguration.subtitleCell()
            let num = idx + 1
            switch seg.type {
            case .run:
                config.text = "\(num). RUN — \(DistanceFormatter.short(seg.distanceMeters ?? 0))"
                config.textProperties.color = DesignTokens.Color.runAccent
            case .roxZone:
                config.text = "\(num). ROX ZONE"
                config.textProperties.color = DesignTokens.Color.roxZoneAccent
            case .station:
                let name = seg.stationKind?.displayName ?? "Station"
                let target = seg.stationTarget?.formatted ?? ""
                config.text = "\(num). \(name) — \(target)"
                if let w = seg.weightKg {
                    config.secondaryText = "\(Int(w)) kg" + (seg.weightNote.map { " \($0)" } ?? "")
                }
                config.textProperties.color = DesignTokens.Color.stationAccent
            }
            config.textProperties.font = .preferredFont(forTextStyle: .body)
            config.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = config
            cell.accessories = [.reorder(displayed: .always)]
        }

        let addBtnReg = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var config = UIListContentConfiguration.cell()
            switch item {
            case .addRun:
                config.text = "+ Add Run"
                config.textProperties.color = DesignTokens.Color.runAccent
            case .addRoxZone:
                config.text = "+ Add ROX Zone"
                config.textProperties.color = DesignTokens.Color.roxZoneAccent
            case .addStation:
                config.text = "+ Add Station"
                config.textProperties.color = DesignTokens.Color.stationAccent
            default: break
            }
            config.textProperties.font = .preferredFont(forTextStyle: .headline)
            cell.contentConfiguration = config
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .segment(let id):
                return cv.dequeueConfiguredReusableCell(using: segmentReg, for: indexPath, item: id)
            case .addRun, .addRoxZone, .addStation:
                return cv.dequeueConfiguredReusableCell(using: addBtnReg, for: indexPath, item: item)
            }
        }

        dataSource.reorderingHandlers.canReorderItem = { item in
            if case .segment = item { return true }
            return false
        }

        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            guard let self else { return }
            // Rebuild segments array from the new snapshot order
            let ids = transaction.finalSnapshot.itemIdentifiers(inSection: .segments)
            var newSegments: [WorkoutSegment] = []
            for id in ids {
                if case .segment(let uuid) = id,
                   let seg = self.viewModel.segments.first(where: { $0.id == uuid }) {
                    newSegments.append(seg)
                }
            }
            // Replace all segments with reordered version
            while !self.viewModel.segments.isEmpty {
                self.viewModel.removeSegment(at: 0)
            }
            for seg in newSegments {
                self.viewModel.addSegment(seg)
            }
            self.updateMeta()
        }
    }

    private func setupEmptyLabel() {
        emptyLabel.text = "Tap a button below to add your first segment"
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50)
        ])
    }

    func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.segments, .addButtons])
        snapshot.appendItems(viewModel.segments.map { .segment($0.id) }, toSection: .segments)
        snapshot.appendItems([.addRun, .addRoxZone, .addStation], toSection: .addButtons)
        dataSource.apply(snapshot, animatingDifferences: true)

        emptyLabel.isHidden = !viewModel.isEmpty
        updateStartButton()
        updateMeta()
    }

    private func updateMeta() {
        if let metaLabel = toolbarItems?.first?.customView as? UILabel {
            metaLabel.text = metaSummary()
            metaLabel.sizeToFit()
        }
    }
}

// MARK: - UICollectionViewDelegate

extension WorkoutBuilderViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case .segment(let uuid):
            guard let idx = viewModel.segments.firstIndex(where: { $0.id == uuid }) else { return }
            let seg = viewModel.segments[idx]
            switch seg.type {
            case .run:
                presentEditRun(mode: .edit(existing: seg, index: idx))
            case .station:
                presentAddStation(mode: .edit(existing: seg, index: idx))
            case .roxZone:
                break // Nothing to edit
            }
        case .addRun:
            presentEditRun(mode: .create)
        case .addRoxZone:
            viewModel.addSegment(.roxZone())
            applySnapshot()
        case .addStation:
            presentAddStation(mode: .create)
        }
    }

    private func presentAddStation(mode: AddStationMode) {
        let vc = AddStationSheetViewController(mode: mode)
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(nav, animated: true)
    }

    private func presentEditRun(mode: AddStationMode) {
        let vc = EditRunSheetViewController(mode: mode)
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium()]
        }
        present(nav, animated: true)
    }
}

// MARK: - AddStationSheetDelegate

extension WorkoutBuilderViewController: AddStationSheetDelegate {

    func addStation(_ segment: WorkoutSegment, mode: AddStationMode) {
        dismiss(animated: true) {
            switch mode {
            case .create:
                self.viewModel.addSegment(segment)
            case .edit(_, let index):
                self.viewModel.updateSegment(at: index, segment)
            }
            self.applySnapshot()
        }
    }

    func cancelAddStation() {
        dismiss(animated: true)
    }
}

// MARK: - EditRunSheetDelegate

extension WorkoutBuilderViewController: EditRunSheetDelegate {

    func editRunDidSave(distanceMeters: Double, mode: AddStationMode) {
        dismiss(animated: true) {
            let segment = WorkoutSegment.run(distanceMeters: distanceMeters)
            switch mode {
            case .create:
                self.viewModel.addSegment(segment)
            case .edit(_, let index):
                self.viewModel.updateSegment(at: index, segment)
            }
            self.applySnapshot()
        }
    }

    func editRunDidCancel() {
        dismiss(animated: true)
    }
}
