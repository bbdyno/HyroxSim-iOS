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

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var carouselCollectionView: UICollectionView!
    private let pageControl = UIPageControl()
    private var recentCard: UIView?

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationController?.navigationBar.prefersLargeTitles = true
        title = "HYROX"
        configureNavBar()
        setupScrollView()
        buildContent()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncUpdate), name: .syncDataUpdated, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
        carouselCollectionView?.reloadData()
        updateRecentCard()
    }

    @objc private func handleSyncUpdate() {
        viewModel.load()
        carouselCollectionView?.reloadData()
        updateRecentCard()
    }

    // MARK: - Nav Bar

    private func configureNavBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 34, weight: .black)
        ]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
    }

    // MARK: - Layout

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32)
        ])
    }

    private func buildContent() {
        // Recent workout (placeholder — filled on viewWillAppear)
        let recentContainer = UIView()
        recentContainer.tag = 100
        contentStack.addArrangedSubview(recentContainer)

        // Carousel
        contentStack.addArrangedSubview(makeSectionHeader("SELECT DIVISION"))
        contentStack.addArrangedSubview(makeCarousel())

        pageControl.numberOfPages = HyroxPresets.all.count
        pageControl.currentPageIndicatorTintColor = .white
        pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.25)
        pageControl.isUserInteractionEnabled = false
        contentStack.addArrangedSubview(pageControl)

        // Actions
        contentStack.addArrangedSubview(makeSectionHeader("MY WORKOUTS"))
        contentStack.addArrangedSubview(makeActionButton(title: "Create Custom Workout", icon: "plus.circle.fill", action: #selector(newWorkoutTapped)))
        contentStack.addArrangedSubview(makeActionButton(title: "Workout History", icon: "clock.arrow.circlepath", action: #selector(historyTapped)))
    }

    // MARK: - Carousel

    private func makeCarousel() -> UIView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: UIScreen.main.bounds.width - 48, height: 160)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)

        carouselCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        carouselCollectionView.translatesAutoresizingMaskIntoConstraints = false
        carouselCollectionView.backgroundColor = .clear
        carouselCollectionView.showsHorizontalScrollIndicator = false
        carouselCollectionView.decelerationRate = .fast
        carouselCollectionView.dataSource = self
        carouselCollectionView.delegate = self
        carouselCollectionView.register(PresetCardCell.self, forCellWithReuseIdentifier: PresetCardCell.reuseId)
        carouselCollectionView.heightAnchor.constraint(equalToConstant: 168).isActive = true
        return carouselCollectionView
    }

    // MARK: - Recent Card

    private func updateRecentCard() {
        guard let container = contentStack.arrangedSubviews.first(where: { $0.tag == 100 }) else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        guard let workout = viewModel.mostRecentWorkout else {
            container.isHidden = true
            return
        }
        container.isHidden = false

        let card = UIView()
        card.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        card.layer.cornerRadius = 16
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let badge = UILabel()
        badge.text = "RECENT"
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = UIColor.white.withAlphaComponent(0.4)

        let nameLabel = UILabel()
        nameLabel.text = workout.division?.shortName ?? workout.templateName
        nameLabel.font = .systemFont(ofSize: 17, weight: .bold)
        nameLabel.textColor = .white

        let timeLabel = UILabel()
        timeLabel.text = DurationFormatter.hms(workout.totalDuration)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        timeLabel.textColor = .white

        let dateLabel = UILabel()
        dateLabel.text = RelativeDateFormatter.short(workout.finishedAt)
        dateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        dateLabel.textColor = UIColor.white.withAlphaComponent(0.5)

        let stack = UIStackView(arrangedSubviews: [badge, nameLabel, timeLabel, dateLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = UIColor.white.withAlphaComponent(0.3)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(recentTapped))
        card.addGestureRecognizer(tap)
        card.isUserInteractionEnabled = true
    }

    @objc private func recentTapped() {
        guard let workout = viewModel.mostRecentWorkout else { return }
        delegate?.homeDidSelectRecent(workout)
    }

    // MARK: - Components

    private func makeSectionHeader(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = UIColor.white.withAlphaComponent(0.4)

        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeActionButton(title: String, icon: String, action: Selector) -> UIView {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePadding = 10
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.06)
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    // MARK: - Actions

    @objc private func newWorkoutTapped() { delegate?.homeDidTapNewWorkout() }
    @objc private func historyTapped() { delegate?.homeDidTapHistory() }
}

// MARK: - UICollectionViewDataSource & Delegate

extension HomeViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.presets.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PresetCardCell.reuseId, for: indexPath) as! PresetCardCell
        cell.configure(with: viewModel.presets[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.homeDidSelectTemplate(viewModel.presets[indexPath.item])
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView == carouselCollectionView else { return }
        let width = UIScreen.main.bounds.width - 48 + 12
        let page = Int(round(scrollView.contentOffset.x / width))
        pageControl.currentPage = min(max(page, 0), viewModel.presets.count - 1)
    }
}
