//
//  HomeViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

@MainActor
protocol HomeViewControllerDelegate: AnyObject {
    func homeDidSelectTemplate(_ template: WorkoutTemplate)
    func homeDidTapNewWorkout()
    func homeDidTapHistory()
    func homeDidTapGarminPairing()
    func homeDidSelectRecent(_ workout: CompletedWorkout)
}

final class HomeViewController: UIViewController {

    weak var delegate: HomeViewControllerDelegate?
    private let viewModel: HomeViewModel

    /// Unified horizontal margin for all sections
    private let hMargin: CGFloat = 20

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var carouselCollectionView: UICollectionView!
    private let pageControl = UIPageControl()
    private enum Tags {
        static let recentContainer = 100
        static let customTemplatesHeader = 101
        static let customTemplatesContainer = 102
    }

    private var cardWidth: CGFloat { view.bounds.width - hMargin * 2 }
    private let cardSpacing: CGFloat = 10

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        title = "HYROX"
        setupScrollView()
        buildContent()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncUpdate), name: .syncDataUpdated, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
        carouselCollectionView?.reloadData()
        rebuildRecentCard()
        rebuildCustomTemplates()
    }

    @objc private func handleSyncUpdate() {
        viewModel.load()
        carouselCollectionView?.reloadData()
        rebuildRecentCard()
        rebuildCustomTemplates()
    }

    // MARK: - Scroll View

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
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40)
        ])
    }

    // MARK: - Build Content

    private func buildContent() {
        // Recent workout placeholder
        let recentContainer = UIView()
        recentContainer.tag = Tags.recentContainer
        contentStack.addArrangedSubview(recentContainer)

        // Carousel
        contentStack.addArrangedSubview(makeSectionHeader("SELECT DIVISION"))
        contentStack.addArrangedSubview(makeCarousel())

        pageControl.numberOfPages = HyroxPresets.all.count
        pageControl.currentPageIndicatorTintColor = .white
        pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.2)
        pageControl.isUserInteractionEnabled = false
        contentStack.addArrangedSubview(pageControl)

        let customHeader = makeSectionHeader("SAVED TEMPLATES")
        customHeader.tag = Tags.customTemplatesHeader
        customHeader.isHidden = true
        contentStack.addArrangedSubview(customHeader)

        let customContainer = UIView()
        customContainer.tag = Tags.customTemplatesContainer
        customContainer.isHidden = true
        contentStack.addArrangedSubview(customContainer)

        // Actions
        contentStack.addArrangedSubview(makeSectionHeader("MY WORKOUTS"))
        contentStack.addArrangedSubview(makeActionRow(title: HyroxSimStrings.Localizable.Home.Action.createCustom, icon: "plus.circle.fill", action: #selector(newWorkoutTapped)))
        contentStack.addArrangedSubview(makeActionRow(title: HyroxSimStrings.Localizable.Home.Action.history, icon: "clock.arrow.circlepath", action: #selector(historyTapped)))

        // Settings
        contentStack.addArrangedSubview(makeSectionHeader(HyroxSimStrings.Localizable.Home.Section.settings))
        contentStack.addArrangedSubview(makeActionRow(title: HyroxSimStrings.Localizable.Home.Action.garminPairing, icon: "applewatch.radiowaves.left.and.right", action: #selector(garminPairingTapped)))
    }

    // MARK: - Carousel (paging snap)

    private func makeCarousel() -> UIView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = cardSpacing
        layout.sectionInset = UIEdgeInsets(top: 0, left: hMargin, bottom: 0, right: hMargin)

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

    private func rebuildRecentCard() {
        guard let container = contentStack.arrangedSubviews.first(where: { $0.tag == Tags.recentContainer }) else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        guard let workout = viewModel.mostRecentWorkout else {
            container.isHidden = true
            return
        }
        container.isHidden = false

        let card = UIView()
        card.backgroundColor = DesignTokens.Color.surface
        card.layer.cornerRadius = DesignTokens.Radius.card
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hMargin),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hMargin),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let badge = UILabel()
        badge.text = "RECENT"
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = DesignTokens.Color.textTertiary

        let nameLabel = UILabel()
        nameLabel.text = workout.templateName
        nameLabel.font = .systemFont(ofSize: 17, weight: .bold)
        nameLabel.textColor = .white

        let timeLabel = UILabel()
        timeLabel.text = DurationFormatter.hms(workout.totalDuration)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        timeLabel.textColor = .white

        let dateLabel = UILabel()
        dateLabel.text = RelativeDateFormatter.short(workout.finishedAt)
        dateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        dateLabel.textColor = DesignTokens.Color.textTertiary

        let stack = UIStackView(arrangedSubviews: [badge, nameLabel, timeLabel, dateLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = DesignTokens.Color.textTertiary
        chevron.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(chevron)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])

        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(recentTapped)))
        card.isUserInteractionEnabled = true
    }

    private func rebuildCustomTemplates() {
        guard
            let header = contentStack.arrangedSubviews.first(where: { $0.tag == Tags.customTemplatesHeader }),
            let container = contentStack.arrangedSubviews.first(where: { $0.tag == Tags.customTemplatesContainer })
        else { return }

        container.subviews.forEach { $0.removeFromSuperview() }

        guard !viewModel.customTemplates.isEmpty else {
            header.isHidden = true
            container.isHidden = true
            return
        }

        header.isHidden = false
        container.isHidden = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        for (index, template) in viewModel.customTemplates.enumerated() {
            stack.addArrangedSubview(makeCustomTemplateRow(template: template, index: index))
        }
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
        label.textColor = DesignTokens.Color.textTertiary
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hMargin),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeActionRow(title: String, icon: String, action: Selector) -> UIView {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePadding = 10
        config.baseForegroundColor = .white
        config.baseBackgroundColor = DesignTokens.Color.surface
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
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hMargin),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hMargin),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeCustomTemplateRow(template: WorkoutTemplate, index: Int) -> UIView {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = template.name
        config.subtitle = customTemplateSummary(for: template)
        config.image = UIImage(systemName: template.usesRoxZone ? "square.stack.3d.forward.dottedline.fill" : "figure.run")
        config.imagePadding = 10
        config.baseForegroundColor = .white
        config.baseBackgroundColor = DesignTokens.Color.surface
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.tag = index
        button.addTarget(self, action: #selector(customTemplateTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hMargin),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hMargin),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func customTemplateSummary(for template: WorkoutTemplate) -> String {
        let stations = template.segments.filter { $0.type == .station }.count
        let mins = Int(template.estimatedDurationSeconds / 60)
        let roxLabel = template.usesRoxZone ? "ROX ON" : "ROX OFF"
        return "\(roxLabel)  ·  \(stations) stations  ·  ~\(mins) min"
    }

    // MARK: - Actions

    @objc private func newWorkoutTapped() { delegate?.homeDidTapNewWorkout() }
    @objc private func historyTapped() { delegate?.homeDidTapHistory() }
    @objc private func garminPairingTapped() { delegate?.homeDidTapGarminPairing() }
    @objc private func customTemplateTapped(_ sender: UIButton) {
        guard sender.tag < viewModel.customTemplates.count else { return }
        delegate?.homeDidSelectTemplate(viewModel.customTemplates[sender.tag])
    }
}

// MARK: - UICollectionViewDataSource

extension HomeViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.presets.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PresetCardCell.reuseId, for: indexPath) as! PresetCardCell
        cell.configure(with: viewModel.presets[indexPath.item])
        return cell
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension HomeViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: cardWidth, height: 160)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.homeDidSelectTemplate(viewModel.presets[indexPath.item])
    }

    // Snap-to-card paging
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scrollView == carouselCollectionView else { return }
        let pageWidth = cardWidth + cardSpacing
        let currentOffset = scrollView.contentOffset.x
        let targetOffset = targetContentOffset.pointee.x

        var newPage: Int
        if velocity.x > 0.3 {
            newPage = Int(ceil(currentOffset / pageWidth))
        } else if velocity.x < -0.3 {
            newPage = Int(floor(currentOffset / pageWidth))
        } else {
            newPage = Int(round(targetOffset / pageWidth))
        }

        newPage = max(0, min(newPage, viewModel.presets.count - 1))
        targetContentOffset.pointee.x = CGFloat(newPage) * pageWidth
        pageControl.currentPage = newPage
    }
}
