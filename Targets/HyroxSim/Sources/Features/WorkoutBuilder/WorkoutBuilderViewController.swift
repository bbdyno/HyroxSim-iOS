//
//  WorkoutBuilderViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

@MainActor
protocol WorkoutBuilderViewControllerDelegate: AnyObject {
    func builderDidCancel()
    func builderDidRequestStart(template: WorkoutTemplate)
    func builderDidSaveTemplate(_ template: WorkoutTemplate)
}

final class WorkoutBuilderViewController: UIViewController {

    weak var delegate: WorkoutBuilderViewControllerDelegate?
    let viewModel: WorkoutBuilderViewModel

    private enum Section: Int, CaseIterable { case segments, addButtons }
    private enum Item: Hashable {
        case segment(UUID)
        case addRun, addRoxZone, addStation
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
        view.backgroundColor = DesignTokens.Color.background
        applyDarkNavBarAppearance()
        setupNav()
        setupCollectionView()
        setupDataSource()
        setupEmptyLabel()
        setupToolbar()
        applySnapshot()
    }

    // MARK: - Nav

    private func setupNav() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Start", style: .done, target: self, action: #selector(startTapped))
        navigationItem.rightBarButtonItem?.tintColor = DesignTokens.Color.accent
        updateStartButton()
    }

    private func updateStartButton() {
        navigationItem.rightBarButtonItem?.isEnabled = viewModel.canStart
    }

    @objc private func cancelTapped() {
        let alert = DarkAlertController(title: "Discard Changes?", message: nil)
        alert.addAction(.init(title: "Keep Editing", style: .cancel, handler: nil))
        alert.addAction(.init(title: "Discard", style: .destructive, handler: { [weak self] in
            self?.delegate?.builderDidCancel()
        }))
        present(alert, animated: true)
    }

    @objc private func startTapped() {
        guard let template = try? viewModel.makeTemplateForStart() else { return }
        delegate?.builderDidRequestStart(template: template)
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        navigationController?.isToolbarHidden = false
        applyDarkToolbarAppearance()

        let saveBtn = UIBarButtonItem(title: "Save as Template", style: .plain, target: self, action: #selector(saveTapped))
        saveBtn.tintColor = DesignTokens.Color.accent
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        let metaLabel = UILabel()
        metaLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        metaLabel.textColor = DesignTokens.Color.textSecondary
        metaLabel.text = metaSummary()
        let metaItem = UIBarButtonItem(customView: metaLabel)

        toolbarItems = [metaItem, flex, saveBtn]
    }

    private func metaSummary() -> String {
        let s = viewModel.stationCount
        let km = viewModel.totalRunDistanceMeters / 1000
        let m = Int(viewModel.estimatedDurationSeconds / 60)
        return "\(s) stations · \(String(format: "%.1f", km)) km · ~\(m) min"
    }

    @objc private func saveTapped() {
        guard viewModel.canSave else { return }
        let alert = DarkAlertController(title: "Save Template", message: "Enter a name")
        alert.addTextField { [weak self] tf in
            tf.text = self?.viewModel.name
        }
        alert.addAction(.init(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(.init(title: "Save", style: .normal, handler: { [weak self] in
            guard let self, let name = alert.textField?.text, !name.isEmpty else { return }
            self.viewModel.rename(to: name)
            guard let template = try? self.viewModel.saveAsTemplate() else { return }
            self.delegate?.builderDidSaveTemplate(template)
        }))
        present(alert, animated: true)
    }

    // MARK: - Collection View

    private func setupCollectionView() {
        var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
        listConfig.backgroundColor = DesignTokens.Color.background
        listConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self, let item = self.dataSource.itemIdentifier(for: indexPath), case .segment = item else { return nil }
            let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, done in
                self.viewModel.removeSegment(at: indexPath.row)
                self.applySnapshot()
                done(true)
            }
            return UISwipeActionsConfiguration(actions: [delete])
        }
        let layout = UICollectionViewCompositionalLayout.list(using: listConfig)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = DesignTokens.Color.background
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
        let segReg = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> { [weak self] cell, indexPath, _ in
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
                config.text = "\(num). \(name) — \(seg.stationTarget?.formatted ?? "")"
                if let w = seg.weightKg { config.secondaryText = "\(Int(w)) kg" + (seg.weightNote.map { " \($0)" } ?? "") }
                config.textProperties.color = DesignTokens.Color.stationAccent
            }
            config.textProperties.font = .systemFont(ofSize: 14, weight: .medium)
            config.secondaryTextProperties.color = DesignTokens.Color.textTertiary
            cell.contentConfiguration = config
            cell.accessories = [.reorder(displayed: .always)]

            var bg = UIBackgroundConfiguration.listPlainCell()
            bg.backgroundColor = DesignTokens.Color.background
            cell.backgroundConfiguration = bg
        }

        let addReg = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var config = UIListContentConfiguration.cell()
            switch item {
            case .addRun: config.text = "+ Add Run"; config.textProperties.color = DesignTokens.Color.runAccent
            case .addRoxZone: config.text = "+ Add ROX Zone"; config.textProperties.color = DesignTokens.Color.roxZoneAccent
            case .addStation: config.text = "+ Add Station"; config.textProperties.color = DesignTokens.Color.accent
            default: break
            }
            config.textProperties.font = .systemFont(ofSize: 15, weight: .bold)
            cell.contentConfiguration = config
            var bg = UIBackgroundConfiguration.listPlainCell()
            bg.backgroundColor = DesignTokens.Color.background
            cell.backgroundConfiguration = bg
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, ip, item in
            switch item {
            case .segment(let id): return cv.dequeueConfiguredReusableCell(using: segReg, for: ip, item: id)
            default: return cv.dequeueConfiguredReusableCell(using: addReg, for: ip, item: item)
            }
        }
        dataSource.reorderingHandlers.canReorderItem = { if case .segment = $0 { return true }; return false }
        dataSource.reorderingHandlers.didReorder = { [weak self] tx in
            guard let self else { return }
            let ids = tx.finalSnapshot.itemIdentifiers(inSection: .segments)
            var newSegs: [WorkoutSegment] = []
            for id in ids { if case .segment(let uuid) = id, let s = self.viewModel.segments.first(where: { $0.id == uuid }) { newSegs.append(s) } }
            while !self.viewModel.segments.isEmpty { self.viewModel.removeSegment(at: 0) }
            for s in newSegs { self.viewModel.addSegment(s) }
            self.updateMeta()
        }
    }

    private func setupEmptyLabel() {
        emptyLabel.text = "Tap a button below to add your first segment"
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = DesignTokens.Color.textTertiary
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
        if let l = toolbarItems?.first?.customView as? UILabel { l.text = metaSummary(); l.sizeToFit() }
    }
}

// MARK: - Delegate + Sheets

extension WorkoutBuilderViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .segment(let uuid):
            guard let idx = viewModel.segments.firstIndex(where: { $0.id == uuid }) else { return }
            let seg = viewModel.segments[idx]
            switch seg.type {
            case .run: presentEditRun(mode: .edit(existing: seg, index: idx))
            case .station: presentAddStation(mode: .edit(existing: seg, index: idx))
            case .roxZone: break
            }
        case .addRun: presentEditRun(mode: .create)
        case .addRoxZone: viewModel.addSegment(.roxZone()); applySnapshot()
        case .addStation: presentAddStation(mode: .create)
        }
    }

    private func presentAddStation(mode: AddStationMode) {
        let vc = AddStationSheetViewController(mode: mode); vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        if let s = nav.sheetPresentationController { s.detents = [.medium(), .large()] }
        present(nav, animated: true)
    }
    private func presentEditRun(mode: AddStationMode) {
        let vc = EditRunSheetViewController(mode: mode); vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        if let s = nav.sheetPresentationController { s.detents = [.medium()] }
        present(nav, animated: true)
    }
}

extension WorkoutBuilderViewController: AddStationSheetDelegate {
    func addStation(_ segment: WorkoutSegment, mode: AddStationMode) {
        dismiss(animated: true) { switch mode { case .create: self.viewModel.addSegment(segment); case .edit(_, let i): self.viewModel.updateSegment(at: i, segment) }; self.applySnapshot() }
    }
    func cancelAddStation() { dismiss(animated: true) }
}

extension WorkoutBuilderViewController: EditRunSheetDelegate {
    func editRunDidSave(distanceMeters: Double, mode: AddStationMode) {
        dismiss(animated: true) { let s = WorkoutSegment.run(distanceMeters: distanceMeters); switch mode { case .create: self.viewModel.addSegment(s); case .edit(_, let i): self.viewModel.updateSegment(at: i, s) }; self.applySnapshot() }
    }
    func editRunDidCancel() { dismiss(animated: true) }
}
