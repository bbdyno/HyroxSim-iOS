//
//  RacePaceCardViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import UIKit
import HyroxCore

/// 구간별 목표 시간표.
///
/// 대회장에서 실제로 보는 값은 "이 구간 목표"가 아니라 **"이 구간이 끝났을 때 시계가 얼마여야 하는가"**다.
/// 그래서 누적 목표 시각을 가장 크게, 구간 목표는 그 옆에 작게 둔다.
/// 표를 그대로 이미지로 구워 저장·공유할 수 있다 — 대회장에서는 앱보다 사진이 빠르다.
final class RacePaceCardViewController: UIViewController {

    private let card: RacePaceCard

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    init(card: RacePaceCard) {
        self.card = card
        super.init(nibName: nil, bundle: nil)
    }

    convenience init(context: RaceDayContext) {
        self.init(card: context.makePaceCard())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        title = RaceDayLocalization.PaceCard.title
        applyDarkNavBarAppearance()
        navigationItem.largeTitleDisplayMode = .never
        setupShareButton()
        setupScrollView()
        buildContent()
    }

    // MARK: - 레이아웃

    private func setupShareButton() {
        guard card.hasGoals else { return }
        let item = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareTapped)
        )
        item.tintColor = DesignTokens.Color.accent
        item.accessibilityLabel = RaceDayLocalization.PaceCard.share
        navigationItem.rightBarButtonItem = item
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = DesignTokens.Spacing.m
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let margin = DesignTokens.Spacing.l
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: margin),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -margin),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: margin),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -margin)
        ])
    }

    private func buildContent() {
        contentStack.addArrangedSubview(makeHeader())

        guard card.hasGoals else {
            contentStack.addArrangedSubview(makeEmptyState())
            return
        }

        contentStack.addArrangedSubview(makeColumnHeader())

        let rowsStack = UIStackView()
        rowsStack.axis = .vertical
        rowsStack.spacing = 2
        for row in card.rows {
            rowsStack.addArrangedSubview(RacePaceCardRowView(row: row))
        }
        contentStack.addArrangedSubview(rowsStack)
        contentStack.setCustomSpacing(DesignTokens.Spacing.l, after: rowsStack)

        contentStack.addArrangedSubview(makeFooter())
    }

    private func makeHeader() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4

        let titleLabel = UILabel()
        titleLabel.text = card.title.uppercased()
        titleLabel.font = .systemFont(ofSize: 26, weight: .black)
        titleLabel.textColor = DesignTokens.Color.accent
        titleLabel.numberOfLines = 2
        stack.addArrangedSubview(titleLabel)

        if let subtitle = card.subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            subtitleLabel.textColor = DesignTokens.Color.textSecondary
            subtitleLabel.numberOfLines = 2
            stack.addArrangedSubview(subtitleLabel)
        }

        if let total = card.totalGoalSeconds {
            let totalLabel = UILabel()
            totalLabel.text = DurationFormatter.hms(total)
            totalLabel.font = .monospacedDigitSystemFont(ofSize: 54, weight: .black)
            totalLabel.textColor = DesignTokens.Color.textPrimary
            totalLabel.adjustsFontSizeToFitWidth = true
            totalLabel.minimumScaleFactor = 0.6
            stack.setCustomSpacing(10, after: stack.arrangedSubviews.last ?? titleLabel)
            stack.addArrangedSubview(totalLabel)
        }

        if card.isScaledToRaceGoal {
            let noticeLabel = UILabel()
            noticeLabel.text = RaceDayLocalization.PaceCard.scaledNotice
            noticeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            noticeLabel.textColor = DesignTokens.Color.accent
            noticeLabel.numberOfLines = 0
            stack.addArrangedSubview(noticeLabel)
        }

        return stack
    }

    private func makeColumnHeader() -> UIView {
        let font = UIFont.systemFont(ofSize: 11, weight: .black)

        let segment = UILabel()
        segment.text = RaceDayLocalization.PaceCard.columnSegment
        segment.font = font
        segment.textColor = DesignTokens.Color.textTertiary

        let split = UILabel()
        split.text = RaceDayLocalization.PaceCard.columnSplit
        split.font = font
        split.textColor = DesignTokens.Color.textTertiary
        split.textAlignment = .right
        split.setContentHuggingPriority(.required, for: .horizontal)
        split.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let cumulative = UILabel()
        cumulative.text = RaceDayLocalization.PaceCard.columnCumulative
        cumulative.font = font
        cumulative.textColor = DesignTokens.Color.textTertiary
        cumulative.textAlignment = .right
        cumulative.setContentHuggingPriority(.required, for: .horizontal)
        cumulative.widthAnchor.constraint(equalToConstant: 104).isActive = true

        let row = UIStackView(arrangedSubviews: [segment, split, cumulative])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        return row
    }

    private func makeFooter() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10

        let hint = UILabel()
        hint.text = RaceDayLocalization.PaceCard.fastLaneHint
        hint.font = .systemFont(ofSize: 13, weight: .medium)
        hint.textColor = DesignTokens.Color.textSecondary
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)

        let shareButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = RaceDayLocalization.PaceCard.share
        config.baseBackgroundColor = DesignTokens.Color.accent
        config.baseForegroundColor = .black
        config.cornerStyle = .large
        config.image = UIImage(systemName: "square.and.arrow.up")
        config.imagePadding = 8
        shareButton.configuration = config
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        shareButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        stack.addArrangedSubview(shareButton)

        return stack
    }

    private func makeEmptyState() -> UIView {
        let container = UIView()
        container.backgroundColor = DesignTokens.Color.surface
        container.layer.cornerRadius = DesignTokens.Radius.card

        let titleLabel = UILabel()
        titleLabel.text = RaceDayLocalization.PaceCard.emptyTitle
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = DesignTokens.Color.textPrimary
        titleLabel.numberOfLines = 0

        let messageLabel = UILabel()
        messageLabel.text = RaceDayLocalization.PaceCard.emptyMessage
        messageLabel.font = .systemFont(ofSize: 14, weight: .medium)
        messageLabel.textColor = DesignTokens.Color.textSecondary
        messageLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.m),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.m),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DesignTokens.Spacing.m)
        ])
        return container
    }

    // MARK: - 공유

    @objc private func shareTapped(_ sender: Any) {
        guard let image = RacePaceCardRenderer.image(for: card) else {
            presentShareFailure()
            return
        }

        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        if activity.popoverPresentationController?.barButtonItem == nil,
           let button = sender as? UIView {
            activity.popoverPresentationController?.sourceView = button
            activity.popoverPresentationController?.sourceRect = button.bounds
        }
        present(activity, animated: true)
    }

    private func presentShareFailure() {
        let alert = DarkAlertController(
            title: RaceDayLocalization.PaceCard.shareFailed,
            message: RaceDayLocalization.PaceCard.emptyMessage
        )
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.ok, style: .normal, handler: nil))
        present(alert, animated: true)
    }
}

// MARK: - 표의 한 줄

/// 시스템 기본 셀 대신 쓰는 커스텀 행.
/// 누적 목표 시각을 가장 크게, 구간 목표와 페이스는 보조로 둔다.
private final class RacePaceCardRowView: UIView {

    init(row: RacePaceCard.Row) {
        super.init(frame: .zero)
        backgroundColor = UIColor.white.withAlphaComponent(0.04)
        layer.cornerRadius = 12

        let titleLabel = UILabel()
        titleLabel.text = row.title
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = row.kind == .run
            ? DesignTokens.Color.runAccent
            : DesignTokens.Color.stationAccent
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7

        let detailLabel = UILabel()
        detailLabel.text = Self.detailText(for: row)
        detailLabel.font = .systemFont(ofSize: 12, weight: .medium)
        detailLabel.textColor = DesignTokens.Color.textSecondary
        detailLabel.isHidden = detailLabel.text == nil

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        let splitLabel = UILabel()
        splitLabel.text = row.goalSeconds.map(DurationFormatter.ms) ?? "—"
        splitLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        splitLabel.textColor = DesignTokens.Color.textSecondary
        splitLabel.textAlignment = .right
        splitLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let cumulativeLabel = UILabel()
        cumulativeLabel.text = row.cumulativeSeconds.map(DurationFormatter.hms) ?? "—"
        cumulativeLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .black)
        cumulativeLabel.textColor = DesignTokens.Color.textPrimary
        cumulativeLabel.textAlignment = .right
        cumulativeLabel.adjustsFontSizeToFitWidth = true
        cumulativeLabel.minimumScaleFactor = 0.7
        cumulativeLabel.widthAnchor.constraint(equalToConstant: 104).isActive = true

        let contentRow = UIStackView(arrangedSubviews: [titleStack, splitLabel, cumulativeLabel])
        contentRow.axis = .horizontal
        contentRow.alignment = .center
        contentRow.spacing = 10
        contentRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentRow)

        NSLayoutConstraint.activate([
            contentRow.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            contentRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 거리·목표에 더해 런은 목표 페이스까지 보여준다.
    /// 4:00/km 이하면 Fast Lane 을 써야 해서 페이스는 대회장에서 실제로 쓰이는 정보다.
    private static func detailText(for row: RacePaceCard.Row) -> String? {
        var parts: [String] = []
        if let detail = row.detail { parts.append(detail) }
        if let pace = row.paceSecondsPerKm { parts.append(DurationFormatter.pace(pace)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
