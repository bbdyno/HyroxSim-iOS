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
        case addRun, addStation
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let emptyLabel = UILabel()
    private let headerStack = UIStackView()
    private let summaryCard = UIView()
    private let summaryLabel = UILabel()
    private let goalCard = UIView()
    private let goalValueLabel = UILabel()
    private let goalHintLabel = UILabel()
    private let roxCard = UIView()
    private let roxZoneSwitch = UISwitch()
    private var startButtonItem: UIBarButtonItem!
    private var saveButtonItem: UIBarButtonItem!

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
        setupHeader()
        setupCollectionView()
        setupDataSource()
        setupEmptyLabel()
        applySnapshot()
    }

    // MARK: - Nav

    private func setupNav() {
        navigationController?.isToolbarHidden = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        saveButtonItem = UIBarButtonItem(title: "Save", style: .plain, target: self, action: #selector(saveTapped))
        saveButtonItem.tintColor = DesignTokens.Color.textSecondary
        startButtonItem = UIBarButtonItem(title: "Start", style: .done, target: self, action: #selector(startTapped))
        startButtonItem.tintColor = DesignTokens.Color.accent
        navigationItem.rightBarButtonItems = [startButtonItem, saveButtonItem]
        updateStartButton()
        saveButtonItem.isEnabled = viewModel.canSave
    }

    private func updateStartButton() {
        startButtonItem?.isEnabled = viewModel.canStart
    }

    @objc private func cancelTapped() {
        let alert = DarkAlertController(
            title: HyroxSimStrings.Localizable.Alert.DiscardChanges.title,
            message: nil
        )
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.keepEditing, style: .cancel, handler: nil))
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.discard, style: .destructive, handler: { [weak self] in
            self?.delegate?.builderDidCancel()
        }))
        present(alert, animated: true)
    }

    @objc private func startTapped() {
        guard let template = try? viewModel.makeTemplateForStart() else { return }
        delegate?.builderDidRequestStart(template: template)
    }

    // MARK: - Header

    private func setupHeader() {
        headerStack.axis = .vertical
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        summaryCard.backgroundColor = DesignTokens.Color.surface
        summaryCard.layer.cornerRadius = DesignTokens.Radius.card
        summaryCard.layer.borderWidth = 1
        summaryCard.layer.borderColor = UIColor.white.withAlphaComponent(0.06).cgColor

        let summaryTitleLabel = UILabel()
        summaryTitleLabel.text = "BUILDER"
        summaryTitleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        summaryTitleLabel.textColor = DesignTokens.Color.textTertiary

        summaryLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        summaryLabel.textColor = .white
        summaryLabel.numberOfLines = 0

        let summaryStack = UIStackView(arrangedSubviews: [summaryTitleLabel, summaryLabel])
        summaryStack.axis = .vertical
        summaryStack.spacing = 6
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.addSubview(summaryStack)
        NSLayoutConstraint.activate([
            summaryStack.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: 14),
            summaryStack.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 16),
            summaryStack.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -16),
            summaryStack.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -14)
        ])

        goalCard.backgroundColor = DesignTokens.Color.surfaceElevated
        goalCard.layer.cornerRadius = DesignTokens.Radius.card
        goalCard.isUserInteractionEnabled = true

        let goalTitleLabel = UILabel()
        goalTitleLabel.text = "GOALS"
        goalTitleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        goalTitleLabel.textColor = DesignTokens.Color.accent

        goalValueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        goalValueLabel.textColor = .white

        goalHintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        goalHintLabel.textColor = DesignTokens.Color.textSecondary

        let goalLabels = UIStackView(arrangedSubviews: [goalTitleLabel, goalValueLabel, goalHintLabel])
        goalLabels.axis = .vertical
        goalLabels.spacing = 4

        let goalChevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        goalChevron.tintColor = DesignTokens.Color.textSecondary
        goalChevron.translatesAutoresizingMaskIntoConstraints = false
        goalChevron.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let goalStack = UIStackView(arrangedSubviews: [goalLabels, goalChevron])
        goalStack.axis = .horizontal
        goalStack.alignment = .center
        goalStack.spacing = 12
        goalStack.translatesAutoresizingMaskIntoConstraints = false
        goalCard.addSubview(goalStack)
        NSLayoutConstraint.activate([
            goalStack.topAnchor.constraint(equalTo: goalCard.topAnchor, constant: 14),
            goalStack.leadingAnchor.constraint(equalTo: goalCard.leadingAnchor, constant: 16),
            goalStack.trailingAnchor.constraint(equalTo: goalCard.trailingAnchor, constant: -16),
            goalStack.bottomAnchor.constraint(equalTo: goalCard.bottomAnchor, constant: -14)
        ])
        goalCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(goalsTapped)))

        roxCard.backgroundColor = DesignTokens.Color.surfaceElevated
        roxCard.layer.cornerRadius = DesignTokens.Radius.card

        let roxTitleLabel = UILabel()
        roxTitleLabel.text = "ROX ZONE"
        roxTitleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        roxTitleLabel.textColor = DesignTokens.Color.roxZoneAccent

        let roxSubtitleLabel = UILabel()
        roxSubtitleLabel.tag = 101
        roxSubtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        roxSubtitleLabel.textColor = DesignTokens.Color.textSecondary
        roxSubtitleLabel.numberOfLines = 0

        roxZoneSwitch.isOn = viewModel.usesRoxZone
        roxZoneSwitch.onTintColor = DesignTokens.Color.accent
        roxZoneSwitch.addTarget(self, action: #selector(roxZoneToggleChanged), for: .valueChanged)

        let roxLabels = UIStackView(arrangedSubviews: [roxTitleLabel, roxSubtitleLabel])
        roxLabels.axis = .vertical
        roxLabels.spacing = 4

        let roxStack = UIStackView(arrangedSubviews: [roxLabels, roxZoneSwitch])
        roxStack.axis = .horizontal
        roxStack.alignment = .center
        roxStack.spacing = 12
        roxStack.translatesAutoresizingMaskIntoConstraints = false
        roxCard.addSubview(roxStack)
        NSLayoutConstraint.activate([
            roxStack.topAnchor.constraint(equalTo: roxCard.topAnchor, constant: 14),
            roxStack.leadingAnchor.constraint(equalTo: roxCard.leadingAnchor, constant: 16),
            roxStack.trailingAnchor.constraint(equalTo: roxCard.trailingAnchor, constant: -16),
            roxStack.bottomAnchor.constraint(equalTo: roxCard.bottomAnchor, constant: -14)
        ])

        headerStack.addArrangedSubview(summaryCard)
        headerStack.addArrangedSubview(goalCard)
        headerStack.addArrangedSubview(roxCard)
    }

    private func metaSummary() -> String {
        let s = viewModel.stationCount
        let km = viewModel.totalRunDistanceMeters / 1000
        let m = Int(viewModel.estimatedDurationSeconds / 60)
        return "\(s) stations · \(String(format: "%.1f", km)) km · ~\(m) min"
    }

    @objc private func saveTapped() {
        guard viewModel.canSave else { return }
        let alert = DarkAlertController(
            title: HyroxSimStrings.Localizable.Alert.SaveTemplate.title,
            message: HyroxSimStrings.Localizable.Alert.SaveTemplate.message
        )
        alert.addTextField { [weak self] tf in
            tf.text = self?.viewModel.name
        }
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.cancel, style: .cancel, handler: nil))
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.save, style: .normal, handler: { [weak self] in
            guard let self, let name = alert.textField?.text, !name.isEmpty else { return }
            self.viewModel.rename(to: name)
            guard let template = try? self.viewModel.saveAsTemplate() else { return }
            self.delegate?.builderDidSaveTemplate(template)
        }))
        present(alert, animated: true)
    }

    @objc private func roxZoneToggleChanged() {
        viewModel.setUsesRoxZone(roxZoneSwitch.isOn)
        updateMeta()
    }

    @objc private func goalsTapped() {
        guard let template = try? viewModel.makeTemplateForStart() else { return }

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
            collectionView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
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
        emptyLabel.text = HyroxSimStrings.Localizable.Builder.empty
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = DesignTokens.Color.textTertiary
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor, constant: -20)
        ])
    }

    func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.segments, .addButtons])
        snapshot.appendItems(viewModel.segments.map { .segment($0.id) }, toSection: .segments)
        snapshot.appendItems([.addRun, .addStation], toSection: .addButtons)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyLabel.isHidden = !viewModel.isEmpty
        updateStartButton()
        updateMeta()
    }

    private func updateMeta() {
        summaryLabel.text = metaSummary()
        goalValueLabel.text = HyroxSimStrings.Localizable.Workout.goalTotalFormat(DurationFormatter.hms(viewModel.estimatedDurationSeconds))
        goalHintLabel.text = viewModel.segments.isEmpty ? "Add segments first" : "Edit segment targets"
        goalCard.alpha = viewModel.segments.isEmpty ? 0.45 : 1
        goalCard.isUserInteractionEnabled = !viewModel.segments.isEmpty
        if let subtitleLabel = roxCard.viewWithTag(101) as? UILabel {
            subtitleLabel.text = viewModel.usesRoxZone
                ? "Transitions are inserted automatically between runs and stations."
                : "Runs connect directly to stations without transition blocks."
        }
        saveButtonItem?.isEnabled = viewModel.canSave
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

extension WorkoutBuilderViewController: WorkoutGoalSetupViewControllerDelegate {

    func goalSetupDidCancel() {
        dismiss(animated: true)
    }

    func goalSetupDidConfirm(template: WorkoutTemplate) {
        viewModel.applyGoalTemplate(template)
        dismiss(animated: true) {
            self.applySnapshot()
        }
    }
}

extension WorkoutBuilderViewController: PacePlannerViewControllerDelegate {

    func pacePlannerDidCancel() {
        dismiss(animated: true)
    }

    func pacePlannerDidConfirm(template: WorkoutTemplate) {
        viewModel.applyGoalTemplate(template)
        dismiss(animated: true) {
            self.applySnapshot()
        }
    }
}
