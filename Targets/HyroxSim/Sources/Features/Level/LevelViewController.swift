//
//  LevelViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import UIKit

/// 내 수준 판정 + 약점 진단. 공식 코스를 완주한 기록 하나를 실제 대회 기록과 비교한다.
final class LevelViewController: UIViewController {

    enum Links {
        static let fitBoost = URL(string: "https://apps.apple.com/app/id6805938033")!
    }

    private var viewModel: LevelViewModel
    private let defaults: UserDefaults
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let margin: CGFloat = 20

    private typealias L = HyroxSimStrings.Localizable.Level

    init(viewModel: LevelViewModel, defaults: UserDefaults = .standard) {
        self.viewModel = viewModel
        self.defaults = defaults
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.title
        view.backgroundColor = DesignTokens.Color.background
        view.accessibilityIdentifier = "level.view"
        navigationItem.largeTitleDisplayMode = .never
        if presentingViewController != nil, navigationController?.viewControllers.first === self {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close, target: self, action: #selector(closeTapped)
            )
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        contentStack.axis = .vertical
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32)
        ])
        rebuild()
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    // MARK: - Content

    private func rebuild() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        add(caption(viewModel.caption, color: DesignTokens.Color.textSecondary), spacing: 6)

        let top = UILabel()
        top.font = DesignTokens.Font.wide(13, weight: .heavy)
        top.textColor = DesignTokens.Color.accent
        top.setTracked(L.topCaption.uppercased(), kern: 2)
        add(top, spacing: 0)

        let big = UILabel()
        big.font = DesignTokens.Font.bigNumber(92)
        big.textColor = DesignTokens.Color.accent
        big.text = viewModel.headlineValue
        big.adjustsFontSizeToFitWidth = true
        big.minimumScaleFactor = 0.5
        big.accessibilityIdentifier = "level.headline"
        add(big, spacing: 2)

        if let population = viewModel.populationText {
            let label = UILabel()
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = DesignTokens.Color.textSecondary
            label.numberOfLines = 0
            label.text = population
            add(label, spacing: 14)
        }

        add(DistributionBar(position: viewModel.markerPosition, fastLabel: L.barFast, slowLabel: L.barSlow), spacing: 18)

        add(hairline(), spacing: 0)
        add(makeAgeGroupRow(), spacing: 0)
        add(hairline(), spacing: 0)
        if let title = viewModel.milestoneTitle, let gap = viewModel.milestoneGap {
            add(makeValueRow(title: title, subtitle: viewModel.milestoneTarget, value: gap, id: "level.milestone"), spacing: 0)
            add(hairline(), spacing: 0)
        }

        addPredictionSection()

        let rows = viewModel.rows
        if !rows.isEmpty {
            contentStack.setCustomSpacing(26, after: contentStack.arrangedSubviews.last!)
            add(caption(L.weaknessCaption.uppercased(), color: DesignTokens.Color.accent), spacing: 4)
            let explain = UILabel()
            explain.font = .systemFont(ofSize: 12.5)
            explain.textColor = DesignTokens.Color.textSecondary
            explain.numberOfLines = 0
            explain.text = L.weaknessExplain
            add(explain, spacing: 10)
            add(makeTableHeader(), spacing: 0)
            add(hairline(), spacing: 0)
            for row in rows {
                add(makeWeaknessRow(row), spacing: 0)
                add(hairline(), spacing: 0)
            }
            if let recoverable = viewModel.recoverableText {
                let label = UILabel()
                label.font = .systemFont(ofSize: 13, weight: .semibold)
                label.textColor = DesignTokens.Color.textPrimary
                label.numberOfLines = 0
                label.text = recoverable
                label.accessibilityIdentifier = "level.recoverable"
                contentStack.setCustomSpacing(12, after: contentStack.arrangedSubviews.last!)
                add(label, spacing: 0)
            }
            if viewModel.suggestsStrengthWork {
                contentStack.setCustomSpacing(22, after: contentStack.arrangedSubviews.last!)
                add(makeFitBoostRow(), spacing: 0)
            }
        }

        addCoachSection()

        let footnote = UILabel()
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = DesignTokens.Color.textTertiary
        footnote.numberOfLines = 0
        footnote.text = viewModel.footnote
        contentStack.setCustomSpacing(22, after: contentStack.arrangedSubviews.last!)
        add(footnote, spacing: 0)
    }

    // MARK: - 코치

    private var coachTask: Task<Void, Never>?

    /// 정해진 문장을 바로 보여 주고, 기기 내 모델을 쓸 수 있으면 한 문단으로 바꿔 쓴다.
    private func addCoachSection() {
        coachTask?.cancel()
        guard PremiumAccess.gate().allows(.aiCoach) else { return }
        let lines = CoachWriter.lines(for: viewModel.coachInsights)
        guard !lines.isEmpty else { return }

        contentStack.setCustomSpacing(26, after: contentStack.arrangedSubviews.last!)
        add(caption(L.Coach.caption.uppercased(), color: DesignTokens.Color.accent), spacing: 8)

        let body = UILabel()
        body.font = .systemFont(ofSize: 15)
        body.textColor = DesignTokens.Color.textPrimary
        body.numberOfLines = 0
        body.accessibilityIdentifier = "level.coach"
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 8
        func set(_ text: String) {
            body.attributedText = NSAttributedString(string: text, attributes: [.paragraphStyle: paragraph])
        }
        set(lines.joined(separator: "\n"))
        add(body, spacing: 8)

        let source = UILabel()
        source.font = .systemFont(ofSize: 11)
        source.textColor = DesignTokens.Color.textTertiary
        source.numberOfLines = 0
        source.text = L.Coach.sourceRules
        source.accessibilityIdentifier = "level.coachSource"
        add(source, spacing: 0)

        guard CoachWriter.isOnDeviceModelAvailable else { return }
        let language = Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"
        coachTask = Task { [weak body, weak source] in
            guard let rewritten = await CoachWriter.rewrite(lines: lines, languageName: language),
                  !Task.isCancelled else { return }
            if let body {
                body.attributedText = NSAttributedString(string: rewritten, attributes: [.paragraphStyle: paragraph])
            }
            source?.text = HyroxSimStrings.Localizable.Level.Coach.sourceModel
        }
    }

    private func addPredictionSection() {
        guard let time = viewModel.predictionTime else { return }
        contentStack.setCustomSpacing(26, after: contentStack.arrangedSubviews.last!)
        add(caption(L.Prediction.caption.uppercased(), color: DesignTokens.Color.accent), spacing: 2)

        let big = UILabel()
        big.font = DesignTokens.Font.bigNumber(56)
        big.textColor = DesignTokens.Color.textPrimary
        big.text = time
        big.adjustsFontSizeToFitWidth = true
        big.minimumScaleFactor = 0.6
        big.accessibilityIdentifier = "level.prediction"
        add(big, spacing: 2)

        if let basis = viewModel.predictionBasis {
            let label = UILabel()
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = DesignTokens.Color.textSecondary
            label.numberOfLines = 0
            label.text = basis
            add(label, spacing: 10)
        }
        for note in viewModel.predictionNotes {
            let label = UILabel()
            label.font = .systemFont(ofSize: 13.5, weight: .semibold)
            label.numberOfLines = 0
            label.text = note.text
            switch note.tone {
            case .gained: label.textColor = DesignTokens.Color.accent
            case .lost: label.textColor = DesignTokens.Color.overGoal
            case .even: label.textColor = DesignTokens.Color.textSecondary
            }
            add(label, spacing: 4)
        }
        contentStack.setCustomSpacing(14, after: contentStack.arrangedSubviews.last!)
        add(hairline(), spacing: 0)
    }

    private func add(_ view: UIView, spacing: CGFloat) {
        contentStack.addArrangedSubview(view)
        contentStack.setCustomSpacing(spacing, after: view)
    }

    private func caption(_ text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = DesignTokens.Font.wide(11, weight: .heavy)
        label.textColor = color
        label.numberOfLines = 0
        label.setTracked(text, kern: 1.6)
        return label
    }

    private func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = DesignTokens.Color.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func makeValueRow(title: String, subtitle: String?, value: String, id: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = DesignTokens.Color.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.text = title

        let subtitleLabel = UILabel()
        subtitleLabel.font = DesignTokens.Font.number(12, weight: .medium)
        subtitleLabel.textColor = DesignTokens.Color.textSecondary
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil

        let valueLabel = UILabel()
        valueLabel.font = DesignTokens.Font.bigNumber(28)
        valueLabel.textColor = DesignTokens.Color.accent
        valueLabel.text = value
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [text, valueLabel])
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 14, leading: 0, bottom: 14, trailing: 0)
        row.accessibilityIdentifier = id
        return row
    }

    private func makeAgeGroupRow() -> UIView {
        var config = UIButton.Configuration.plain()
        config.title = viewModel.ageGroupTitle
        config.image = UIImage(systemName: "chevron.up.chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        config.baseForegroundColor = DesignTokens.Color.textPrimary
        config.contentInsets = .init(top: 6, leading: 10, bottom: 6, trailing: 10)
        config.background.backgroundColor = DesignTokens.Color.surfaceElevated
        config.background.cornerRadius = 0
        let button = UIButton(configuration: config)
        button.accessibilityIdentifier = "level.ageGroup"
        button.showsMenuAsPrimaryAction = true
        var actions = viewModel.ageGroupOptions.map { label in
            UIAction(title: label, state: label == viewModel.ageGroup ? .on : .off) { [weak self] _ in
                self?.selectAgeGroup(label)
            }
        }
        if viewModel.ageGroup != nil {
            actions.append(UIAction(title: L.ageGroupClear, attributes: .destructive) { [weak self] _ in
                self?.selectAgeGroup(nil)
            })
        }
        button.menu = UIMenu(children: actions)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = DesignTokens.Color.textPrimary
        titleLabel.text = L.ageGroup
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let valueLabel = UILabel()
        valueLabel.font = DesignTokens.Font.bigNumber(22)
        valueLabel.textColor = viewModel.assessment?.ageGroup == nil
            ? DesignTokens.Color.textTertiary : DesignTokens.Color.accent
        valueLabel.text = viewModel.ageGroupValue
        valueLabel.textAlignment = .right
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        valueLabel.accessibilityIdentifier = "level.ageGroupValue"
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [titleLabel, button, valueLabel])
        row.alignment = .center
        row.spacing = 10
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 12, leading: 0, bottom: 12, trailing: 0)
        return row
    }

    private func selectAgeGroup(_ label: String?) {
        viewModel.selectAgeGroup(label)
        defaults.set(label, forKey: LevelViewModel.ageGroupKey)
        rebuild()
    }

    // MARK: - Weakness table

    private static let columnWidths: (time: CGFloat, delta: CGFloat, level: CGFloat) = (58, 64, 52)

    private func makeTableHeader() -> UIView {
        func head(_ text: String, alignment: NSTextAlignment = .right) -> UILabel {
            let label = UILabel()
            label.font = DesignTokens.Font.wide(9.5, weight: .heavy)
            label.textColor = DesignTokens.Color.textTertiary
            label.textAlignment = alignment
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            label.setTracked(text.uppercased(), kern: 1)
            return label
        }
        let name = head(L.columnSegment, alignment: .left)
        let time = head(L.columnTime)
        let delta = head(L.columnDelta)
        let level = head(L.columnLevel)
        return tableRow(name: name, time: time, delta: delta, level: level, vertical: 6)
    }

    private func makeWeaknessRow(_ row: LevelViewModel.Row) -> UIView {
        let color: UIColor
        switch row.tone {
        case .lost: color = DesignTokens.Color.overGoal
        case .gained: color = DesignTokens.Color.accent
        case .even: color = DesignTokens.Color.textSecondary
        }
        let name = UILabel()
        name.font = DesignTokens.Font.wide(13, weight: .bold)
        name.textColor = DesignTokens.Color.textPrimary
        name.text = row.title
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.7

        func number(_ text: String, color: UIColor, weight: UIFont.Weight) -> UILabel {
            let label = UILabel()
            label.font = DesignTokens.Font.number(14, weight: weight)
            label.textColor = color
            label.textAlignment = .right
            label.text = text
            return label
        }
        let view = tableRow(
            name: name,
            time: number(row.time, color: DesignTokens.Color.textSecondary, weight: .medium),
            delta: number(row.delta, color: color, weight: .heavy),
            level: number(row.level, color: color, weight: .medium),
            vertical: 11
        )
        view.isAccessibilityElement = true
        view.accessibilityLabel = "\(row.title), \(row.time), \(row.delta), \(row.level)"
        return view
    }

    private func tableRow(name: UIView, time: UIView, delta: UIView, level: UIView, vertical: CGFloat) -> UIView {
        time.widthAnchor.constraint(equalToConstant: Self.columnWidths.time).isActive = true
        delta.widthAnchor.constraint(equalToConstant: Self.columnWidths.delta).isActive = true
        level.widthAnchor.constraint(equalToConstant: Self.columnWidths.level).isActive = true
        let row = UIStackView(arrangedSubviews: [name, time, delta, level])
        row.alignment = .center
        row.spacing = 6
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: vertical, leading: 0, bottom: vertical, trailing: 0)
        return row
    }

    // MARK: - FitBoost

    private func makeFitBoostRow() -> UIView {
        let title = UILabel()
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = DesignTokens.Color.textPrimary
        title.numberOfLines = 0
        title.text = L.fitboostTitle
        let detail = UILabel()
        detail.font = .systemFont(ofSize: 12.5)
        detail.textColor = DesignTokens.Color.textSecondary
        detail.numberOfLines = 0
        detail.text = L.fitboostDetail
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 3
        text.isUserInteractionEnabled = false

        let arrow = UIImageView(image: UIImage(systemName: "arrow.up.right"))
        arrow.tintColor = DesignTokens.Color.accent
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        arrow.isUserInteractionEnabled = false

        let row = UIStackView(arrangedSubviews: [text, arrow])
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 14, leading: 14, bottom: 14, trailing: 14)
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false

        let control = UIControl()
        control.layer.borderWidth = 1
        control.layer.borderColor = DesignTokens.Color.hairline.cgColor
        control.accessibilityIdentifier = "level.fitboost"
        control.isAccessibilityElement = true
        control.accessibilityTraits = .link
        control.accessibilityLabel = "\(L.fitboostTitle). \(L.fitboostDetail)"
        control.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: control.topAnchor),
            row.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: control.bottomAnchor)
        ])
        control.addAction(UIAction { _ in UIApplication.shared.open(Links.fitBoost) }, for: .touchUpInside)
        return control
    }
}

// MARK: - Distribution bar

/// 전체 참가자 분포에서 내 위치를 한 줄로 보여 준다. 왼쪽이 빠른 쪽.
private final class DistributionBar: UIView {

    private let position: Double
    private let track = UIView()
    private let fill = UIView()
    private let marker = UIView()

    init(position: Double, fastLabel: String, slowLabel: String) {
        self.position = position
        super.init(frame: .zero)
        track.backgroundColor = DesignTokens.Color.track
        fill.backgroundColor = DesignTokens.Color.accentDim
        marker.backgroundColor = DesignTokens.Color.accent
        [track, fill, marker].forEach(addSubview)

        func edge(_ text: String, alignment: NSTextAlignment) -> UILabel {
            let label = UILabel()
            label.font = DesignTokens.Font.wide(9.5, weight: .heavy)
            label.textColor = DesignTokens.Color.textTertiary
            label.textAlignment = alignment
            label.setTracked(text.uppercased(), kern: 1)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            return label
        }
        let fast = edge(fastLabel, alignment: .left)
        let slow = edge(slowLabel, alignment: .right)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            fast.leadingAnchor.constraint(equalTo: leadingAnchor),
            fast.bottomAnchor.constraint(equalTo: bottomAnchor),
            slow.trailingAnchor.constraint(equalTo: trailingAnchor),
            slow.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let trackHeight: CGFloat = 10
        let y: CGFloat = 8
        track.frame = CGRect(x: 0, y: y, width: bounds.width, height: trackHeight)
        let x = bounds.width * CGFloat(position)
        // 나보다 느린 쪽(오른쪽)을 채운다 — 채워진 만큼이 내가 앞선 사람들이다.
        fill.frame = CGRect(x: x, y: y, width: max(0, bounds.width - x), height: trackHeight)
        let markerWidth: CGFloat = 4
        marker.frame = CGRect(
            x: min(max(0, x - markerWidth / 2), bounds.width - markerWidth),
            y: y - 6, width: markerWidth, height: trackHeight + 12
        )
    }
}
