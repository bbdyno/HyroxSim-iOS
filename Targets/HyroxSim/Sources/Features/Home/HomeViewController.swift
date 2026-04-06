import UIKit
import HyroxKit

@MainActor
protocol HomeViewControllerDelegate: AnyObject {
    func homeDidSelectTemplate(_ template: WorkoutTemplate)
    func homeDidTapNewWorkout()
    func homeDidTapHistory()
    func homeDidSelectRecent(_ workout: CompletedWorkout)
}

final class HomeViewController: UIViewController {

    weak var delegate: HomeViewControllerDelegate?
    private let viewModel: HomeViewModel

    private enum Section: Int, CaseIterable {
        case recent
        case presets
        case custom
        case actions
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, AnyHashable>!

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "HYROX"
        view.backgroundColor = .systemBackground
        setupCollectionView()
        setupDataSource()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncUpdate), name: .syncDataUpdated, object: nil)
    }

    @objc private func handleSyncUpdate() {
        viewModel.load()
        applySnapshot()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
        applySnapshot()
    }

    // MARK: - Collection View Setup

    private func setupCollectionView() {
        let layout = createLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            guard let section = Section(rawValue: sectionIndex) else { return nil }
            switch section {
            case .recent:
                return Self.fullWidthSection(estimatedHeight: 80)
            case .presets:
                return Self.fullWidthSection(estimatedHeight: 72)
            case .custom:
                return Self.fullWidthSection(estimatedHeight: 60)
            case .actions:
                return Self.fullWidthSection(estimatedHeight: 50)
            }
        }
    }

    private static func fullWidthSection(estimatedHeight: CGFloat) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(estimatedHeight))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(estimatedHeight))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: DesignTokens.Spacing.s, leading: DesignTokens.Spacing.m, bottom: DesignTokens.Spacing.s, trailing: DesignTokens.Spacing.m)
        section.interGroupSpacing = DesignTokens.Spacing.s
        return section
    }

    // MARK: - Data Source

    private func setupDataSource() {
        let presetReg = UICollectionView.CellRegistration<UICollectionViewListCell, PresetItem> { cell, _, item in
            var config = UIListContentConfiguration.subtitleCell()
            config.text = item.template.name
            config.secondaryText = "8 stations · ~\(Int(item.template.estimatedDurationSeconds / 60)) min"
            config.textProperties.font = .preferredFont(forTextStyle: .headline)
            config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            config.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = config
            cell.accessories = [.disclosureIndicator()]
            var bg = UIBackgroundConfiguration.listGroupedCell()
            bg.cornerRadius = DesignTokens.Radius.card
            bg.backgroundColor = DesignTokens.Color.cardBackground
            cell.backgroundConfiguration = bg
        }

        let recentReg = UICollectionView.CellRegistration<UICollectionViewListCell, RecentItem> { cell, _, item in
            var config = UIListContentConfiguration.subtitleCell()
            config.text = item.workout.templateName
            config.secondaryText = DurationFormatter.hms(item.workout.totalDuration) + " · " + RelativeDateFormatter.short(item.workout.finishedAt)
            config.textProperties.font = .preferredFont(forTextStyle: .headline)
            config.secondaryTextProperties.font = DesignTokens.Font.smallNumber
            cell.contentConfiguration = config
            cell.accessories = [.disclosureIndicator()]
            var bg = UIBackgroundConfiguration.listGroupedCell()
            bg.cornerRadius = DesignTokens.Radius.card
            bg.backgroundColor = DesignTokens.Color.cardBackground
            cell.backgroundConfiguration = bg
        }

        let customReg = UICollectionView.CellRegistration<UICollectionViewListCell, CustomItem> { cell, _, item in
            var config = UIListContentConfiguration.cell()
            config.text = item.template.name
            config.textProperties.font = .preferredFont(forTextStyle: .body)
            cell.contentConfiguration = config
            cell.accessories = [.disclosureIndicator()]
        }

        let actionReg = UICollectionView.CellRegistration<UICollectionViewListCell, ActionItem> { cell, _, item in
            var config = UIListContentConfiguration.cell()
            config.text = item.title
            config.textProperties.font = .preferredFont(forTextStyle: .body)
            config.textProperties.color = .systemBlue
            config.image = UIImage(systemName: item.icon)
            cell.contentConfiguration = config
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case let preset as PresetItem:
                return cv.dequeueConfiguredReusableCell(using: presetReg, for: indexPath, item: preset)
            case let recent as RecentItem:
                return cv.dequeueConfiguredReusableCell(using: recentReg, for: indexPath, item: recent)
            case let custom as CustomItem:
                return cv.dequeueConfiguredReusableCell(using: customReg, for: indexPath, item: custom)
            case let action as ActionItem:
                return cv.dequeueConfiguredReusableCell(using: actionReg, for: indexPath, item: action)
            default:
                return nil
            }
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, AnyHashable>()

        if let recent = viewModel.mostRecentWorkout {
            snapshot.appendSections([.recent])
            snapshot.appendItems([RecentItem(workout: recent)], toSection: .recent)
        }

        snapshot.appendSections([.presets])
        snapshot.appendItems(viewModel.presets.map { PresetItem(template: $0) }, toSection: .presets)

        if !viewModel.customTemplates.isEmpty {
            snapshot.appendSections([.custom])
            snapshot.appendItems(viewModel.customTemplates.map { CustomItem(template: $0) }, toSection: .custom)
        }

        snapshot.appendSections([.actions])
        var actions: [ActionItem] = [
            ActionItem(id: "new", title: "New Workout", icon: "plus.circle"),
            ActionItem(id: "history", title: "View All History", icon: "clock.arrow.circlepath")
        ]
        snapshot.appendItems(actions, toSection: .actions)

        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

// MARK: - UICollectionViewDelegate

extension HomeViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case let preset as PresetItem:
            delegate?.homeDidSelectTemplate(preset.template)
        case let recent as RecentItem:
            delegate?.homeDidSelectRecent(recent.workout)
        case let custom as CustomItem:
            delegate?.homeDidSelectTemplate(custom.template)
        case let action as ActionItem:
            if action.id == "new" { delegate?.homeDidTapNewWorkout() }
            else if action.id == "history" { delegate?.homeDidTapHistory() }
        default:
            break
        }
    }
}

// MARK: - Item Types

private struct PresetItem: Hashable {
    let template: WorkoutTemplate
    func hash(into hasher: inout Hasher) { hasher.combine(template.id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.template.id == rhs.template.id }
}

private struct RecentItem: Hashable {
    let workout: CompletedWorkout
    func hash(into hasher: inout Hasher) { hasher.combine(workout.id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.workout.id == rhs.workout.id }
}

private struct CustomItem: Hashable {
    let template: WorkoutTemplate
    func hash(into hasher: inout Hasher) { hasher.combine(template.id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.template.id == rhs.template.id }
}

private struct ActionItem: Hashable {
    let id: String
    let title: String
    let icon: String
}
