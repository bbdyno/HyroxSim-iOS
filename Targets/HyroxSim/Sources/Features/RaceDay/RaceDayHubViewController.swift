//
//  RaceDayHubViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import UIKit
import HyroxCore

/// 레이스 데이 허브 — 대회 당일에 쓰는 것들의 입구.
///
/// 지금 들어오는 경로는 운동 화면의 깃발 버튼이다(`RaceDayEntry`).
/// 코디네이터를 건드리지 않고도 어디서든 `RaceDayEntry.present(from:context:)` 한 줄로
/// 띄울 수 있게 만들어, 나중에 홈 화면에 진입점을 붙일 때 이 화면은 손대지 않아도 되도록 했다.
final class RaceDayHubViewController: UIViewController {

    private let context: RaceDayContext
    private let store: RaceDayChecklistStore
    private let contentStack = UIStackView()
    private let checklistRow = RaceDayMenuRowView()

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
        title = RaceDayLocalization.Hub.title
        applyDarkNavBarAppearance()
        navigationItem.largeTitleDisplayMode = .never
        setupCloseButton()
        setupContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateChecklistProgress()
    }

    // MARK: - 레이아웃

    private func setupCloseButton() {
        let item = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(closeTapped)
        )
        item.tintColor = DesignTokens.Color.accent
        navigationItem.leftBarButtonItem = item
    }

    private func setupContent() {
        contentStack.axis = .vertical
        contentStack.spacing = DesignTokens.Spacing.m
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        let margin = DesignTokens.Spacing.l
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: margin),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin)
        ])

        contentStack.addArrangedSubview(makeRaceHeader())

        let paceRow = RaceDayMenuRowView()
        paceRow.configure(
            symbolName: "list.number",
            title: RaceDayLocalization.Hub.paceCardTitle,
            subtitle: RaceDayLocalization.Hub.paceCardSubtitle
        )
        paceRow.addTarget(self, action: #selector(paceCardTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(paceRow)

        checklistRow.configure(
            symbolName: "checklist",
            title: RaceDayLocalization.Hub.checklistTitle,
            subtitle: RaceDayLocalization.Hub.checklistSubtitle
        )
        checklistRow.addTarget(self, action: #selector(checklistTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(checklistRow)
    }

    /// 대회 이름 · D-day · 목표. 등록된 대회가 없으면 템플릿 목표로 대신한다.
    private func makeRaceHeader() -> UIView {
        let container = UIView()
        container.backgroundColor = DesignTokens.Color.surface
        container.layer.cornerRadius = DesignTokens.Radius.card

        let titleLabel = UILabel()
        titleLabel.text = context.title.uppercased()
        titleLabel.font = .systemFont(ofSize: 22, weight: .black)
        titleLabel.textColor = DesignTokens.Color.accent
        titleLabel.numberOfLines = 2

        let subtitleLabel = UILabel()
        subtitleLabel.text = context.subtitle ?? RaceDayLocalization.Hub.noRace
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitleLabel.textColor = DesignTokens.Color.textSecondary
        subtitleLabel.numberOfLines = 2

        let metaStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        metaStack.axis = .vertical
        metaStack.spacing = 4

        let ddayLabel = UILabel()
        ddayLabel.font = .systemFont(ofSize: 15, weight: .black)
        ddayLabel.textColor = DesignTokens.Color.textPrimary
        ddayLabel.textAlignment = .right
        ddayLabel.text = ddayText()
        ddayLabel.isHidden = ddayLabel.text == nil
        ddayLabel.setContentHuggingPriority(.required, for: .horizontal)

        let goalLabel = UILabel()
        goalLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .black)
        goalLabel.textColor = DesignTokens.Color.textPrimary
        goalLabel.textAlignment = .right
        if let goal = context.goalSeconds {
            let formatted = DurationFormatter.hms(goal)
            goalLabel.text = formatted
            // 숫자만 읽어 주면 무슨 시간인지 알 수 없어 보이스오버에는 "목표 1:25:00" 로 읽힌다.
            goalLabel.accessibilityLabel = RaceDayLocalization.Hub.goal(formatted)
        } else {
            goalLabel.isHidden = true
        }
        goalLabel.setContentHuggingPriority(.required, for: .horizontal)

        let trailingStack = UIStackView(arrangedSubviews: [ddayLabel, goalLabel])
        trailingStack.axis = .vertical
        trailingStack.alignment = .trailing
        trailingStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [metaStack, trailingStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DesignTokens.Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.m),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.m),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.m),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DesignTokens.Spacing.m)
        ])

        return container
    }

    private func ddayText() -> String? {
        guard let days = context.daysRemaining() else { return nil }
        if days == 0 { return RaceDayLocalization.Hub.raceDay }
        if days < 0 { return RaceDayLocalization.Hub.pastRace }
        return RaceDayLocalization.Hub.daysRemaining(days)
    }

    private func updateChecklistProgress() {
        let checked = store.checkedItemIds(raceKey: context.checklistRaceKey)
        let total = RaceDayChecklist.all.count
        checklistRow.setTrailingText(
            RaceDayLocalization.Checklist.progress(done: checked.count, total: total)
        )
    }

    // MARK: - 이동

    @objc private func paceCardTapped() {
        navigationController?.pushViewController(
            RacePaceCardViewController(context: context),
            animated: true
        )
    }

    @objc private func checklistTapped() {
        navigationController?.pushViewController(
            RaceDayChecklistViewController(context: context, store: store),
            animated: true
        )
    }

    @objc private func closeTapped() {
        presentingViewController?.dismiss(animated: true)
    }
}

// MARK: - 진입점

/// 코디네이터를 고치지 않고 레이스 데이 화면을 띄우는 단일 통로.
enum RaceDayEntry {

    /// 허브를 담은 다크 테마 내비게이션 컨트롤러.
    static func makeHub(context: RaceDayContext) -> UINavigationController {
        let nav = UINavigationController(rootViewController: RaceDayHubViewController(context: context))
        nav.applyDarkTheme()
        nav.modalPresentationStyle = .formSheet
        return nav
    }

    /// 어느 화면에서든 한 줄로 띄운다.
    static func present(from presenter: UIViewController, context: RaceDayContext) {
        presenter.present(makeHub(context: context), animated: true)
    }
}

// MARK: - 메뉴 줄

/// 허브의 큰 버튼 한 줄. 시스템 기본 셀 대신 쓰는 커스텀 컨트롤.
private final class RaceDayMenuRowView: UIControl {

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let trailingLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1
        }
    }

    func configure(symbolName: String, title: String, subtitle: String) {
        iconView.image = UIImage(systemName: symbolName)
        titleLabel.text = title
        subtitleLabel.text = subtitle
        accessibilityLabel = title
        accessibilityHint = subtitle
    }

    func setTrailingText(_ text: String?) {
        trailingLabel.text = text
        trailingLabel.isHidden = text == nil
    }

    private func setupViews() {
        backgroundColor = DesignTokens.Color.surface
        layer.cornerRadius = DesignTokens.Radius.card
        isAccessibilityElement = true
        accessibilityTraits = .button

        iconView.tintColor = DesignTokens.Color.accent
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = DesignTokens.Color.textPrimary

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = DesignTokens.Color.textSecondary
        subtitleLabel.numberOfLines = 2

        trailingLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        trailingLabel.textColor = DesignTokens.Color.accent
        trailingLabel.isHidden = true
        trailingLabel.setContentHuggingPriority(.required, for: .horizontal)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = DesignTokens.Color.textTertiary
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [iconView, textStack, trailingLabel, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DesignTokens.Spacing.m
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 28),
            row.topAnchor.constraint(equalTo: topAnchor, constant: DesignTokens.Spacing.m),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.m),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.m),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DesignTokens.Spacing.m)
        ])
    }
}
