//
//  RaceDayChecklistViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import UIKit
import HyroxCore

/// 대회 당일 체크리스트.
///
/// 룰 항목은 전부 26/27 룰북 근거가 있고, 각 줄 아래에 그 근거를 한 줄로 붙인다.
/// "칩은 발목" 같은 문장은 외워서 되는 게 아니라 **대가를 알고 있어야** 지켜지기 때문에
/// 페널티(DNS·DQ·+0:15·+2:00)를 배지로 함께 보여준다.
///
/// 체크 상태는 대회 단위로 기기에 저장한다. 대회가 지나면 초기화를 권하고,
/// 언제든 직접 초기화할 수도 있다.
final class RaceDayChecklistViewController: UIViewController {

    private let context: RaceDayContext
    private let store: RaceDayChecklistStore
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let sections: [RaceDayChecklistCategory] = RaceDayChecklistCategory.allCases
    private var checkedIds: Set<String> = []

    init(context: RaceDayContext, store: RaceDayChecklistStore = RaceDayChecklistStore()) {
        self.context = context
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        title = RaceDayLocalization.Checklist.title
        applyDarkNavBarAppearance()
        navigationItem.largeTitleDisplayMode = .never
        setupResetButton()
        setupTableView()
        reloadState()
    }

    // MARK: - 레이아웃

    private func setupResetButton() {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "arrow.counterclockwise"),
            style: .plain,
            target: self,
            action: #selector(resetTapped)
        )
        item.tintColor = DesignTokens.Color.accent
        item.accessibilityLabel = RaceDayLocalization.Checklist.reset
        navigationItem.rightBarButtonItem = item
    }

    private func setupTableView() {
        tableView.backgroundColor = DesignTokens.Color.background
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(RaceDayChecklistCell.self, forCellReuseIdentifier: RaceDayChecklistCell.reuseIdentifier)
        tableView.register(
            RaceDayChecklistHeaderView.self,
            forHeaderFooterViewReuseIdentifier: RaceDayChecklistHeaderView.reuseIdentifier
        )
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: DesignTokens.Spacing.l, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - 상태

    private func reloadState() {
        checkedIds = store.checkedItemIds(raceKey: context.checklistRaceKey)
        tableView.tableHeaderView = makePastRaceBannerIfNeeded()
        tableView.reloadData()
    }

    /// 이미 지나간 대회면 초기화를 권하는 배너를 머리에 붙인다.
    /// 지난 대회의 체크가 남아 있으면 다음 대회 준비에서 착각을 부른다.
    private func makePastRaceBannerIfNeeded() -> UIView? {
        guard context.isPastRace() else { return nil }

        let label = UILabel()
        label.text = RaceDayLocalization.Checklist.pastRaceNotice
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = DesignTokens.Color.accent
        label.numberOfLines = 0

        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        container.layer.cornerRadius = DesignTokens.Radius.card
        container.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let wrapper = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 84))
        wrapper.backgroundColor = .clear
        wrapper.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: DesignTokens.Spacing.s),
            container.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: DesignTokens.Spacing.l),
            container.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -DesignTokens.Spacing.l),
            container.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -DesignTokens.Spacing.s),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        wrapper.layoutIfNeeded()
        return wrapper
    }

    @objc private func resetTapped() {
        let alert = DarkAlertController(
            title: RaceDayLocalization.Checklist.resetTitle,
            message: RaceDayLocalization.Checklist.resetMessage
        )
        alert.addAction(.init(
            title: HyroxSimStrings.Localizable.Button.cancel,
            style: .cancel,
            handler: nil
        ))
        alert.addAction(.init(
            title: RaceDayLocalization.Checklist.reset,
            style: .destructive,
            handler: { [weak self] in
                guard let self else { return }
                self.store.reset(raceKey: self.context.checklistRaceKey)
                self.reloadState()
            }
        ))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension RaceDayChecklistViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        RaceDayChecklist.items(in: sections[section]).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = RaceDayChecklist.items(in: sections[indexPath.section])[indexPath.row]
        let cell = tableView.dequeueReusableCell(
            withIdentifier: RaceDayChecklistCell.reuseIdentifier,
            for: indexPath
        )
        (cell as? RaceDayChecklistCell)?.configure(item: item, isChecked: checkedIds.contains(item.id))
        return cell
    }
}

// MARK: - UITableViewDelegate

extension RaceDayChecklistViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = RaceDayChecklist.items(in: sections[indexPath.section])[indexPath.row]
        let isChecked = store.toggle(itemId: item.id, raceKey: context.checklistRaceKey)
        if isChecked {
            checkedIds.insert(item.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            checkedIds.remove(item.id)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        // 진행 표시(3 / 8)는 헤더에 있어 함께 갱신한다.
        if let header = tableView.headerView(forSection: indexPath.section) as? RaceDayChecklistHeaderView {
            header.updateProgress(progressText(for: sections[indexPath.section]))
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let category = sections[section]
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RaceDayChecklistHeaderView.reuseIdentifier)
            as? RaceDayChecklistHeaderView ?? RaceDayChecklistHeaderView(reuseIdentifier: RaceDayChecklistHeaderView.reuseIdentifier)
        header.configure(
            title: RaceDayLocalization.sectionTitle(for: category),
            progress: progressText(for: category),
            footnote: category == .rule ? RaceDayLocalization.Checklist.ruleFooter : nil
        )
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        sections[section] == .rule ? 76 : 52
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        .leastNormalMagnitude
    }

    private func progressText(for category: RaceDayChecklistCategory) -> String {
        let items = RaceDayChecklist.items(in: category)
        let done = items.filter { checkedIds.contains($0.id) }.count
        return RaceDayLocalization.Checklist.progress(done: done, total: items.count)
    }
}

// MARK: - 섹션 헤더

/// 섹션 제목 + 진행 표시. 룰 섹션에는 근거 출처 한 줄이 더 붙는다.
private final class RaceDayChecklistHeaderView: UITableViewHeaderFooterView {

    static let reuseIdentifier = "RaceDayChecklistHeaderView"

    private let titleLabel = UILabel()
    private let progressLabel = UILabel()
    private let footnoteLabel = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, progress: String, footnote: String?) {
        titleLabel.text = title
        progressLabel.text = progress
        footnoteLabel.text = footnote
        footnoteLabel.isHidden = footnote == nil
    }

    func updateProgress(_ progress: String) {
        progressLabel.text = progress
    }

    private func setupViews() {
        let background = UIView()
        background.backgroundColor = DesignTokens.Color.background
        backgroundView = background

        titleLabel.font = .systemFont(ofSize: 12, weight: .black)
        titleLabel.textColor = DesignTokens.Color.accent

        progressLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        progressLabel.textColor = DesignTokens.Color.textSecondary
        progressLabel.textAlignment = .right
        progressLabel.setContentHuggingPriority(.required, for: .horizontal)

        footnoteLabel.font = .systemFont(ofSize: 11, weight: .medium)
        footnoteLabel.textColor = DesignTokens.Color.textTertiary
        footnoteLabel.numberOfLines = 0

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, progressLabel])
        titleRow.axis = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: [titleRow, footnoteLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DesignTokens.Spacing.m),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DesignTokens.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DesignTokens.Spacing.l),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DesignTokens.Spacing.s)
        ])
    }
}
