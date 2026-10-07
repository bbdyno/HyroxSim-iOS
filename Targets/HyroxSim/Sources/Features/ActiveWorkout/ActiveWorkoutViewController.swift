//
//  ActiveWorkoutViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

final class ActiveWorkoutViewController: UIViewController {

    private let viewModel: ActiveWorkoutViewModel
    private var uiTimer: Timer?

    private let gpsStatusView = UIStackView()
    private let headerLabel = UILabel()
    private let titleLabel = UILabel()
    private let courseMapView = CourseMapView(style: .compact)
    private let segmentTimeLabel = UILabel()
    private let timeCaption = UILabel()
    private let contentStack = UIStackView()
    /// 작은 화면에서 랩 카운터가 하단 컨트롤과 겹치지 않도록 줄인 배치를 쓰는지.
    private var appliedCompactLayout: Bool?
    private let primaryStat = StatColumn()
    private let heartStat = StatColumn()
    private let totalStat = StatColumn()
    private let segmentGoalRow = GoalRow(caption: "SEGMENT GOAL")
    private let totalGoalRow = GoalRow(caption: "TOTAL GOAL")
    private let advanceControl = SlideActionControl()
    private let pauseButton = UIButton(type: .system)
    private let endButton = UIButton(type: .system)
    private let pauseOverlay = UIView()
    private let pauseLabel = UILabel()

    // MARK: - 레이스 데이

    private let raceModeButton = UIButton(type: .system)
    private let raceDayButton = UIButton(type: .system)
    private let lapCard = UIView()
    private let lapCaptionLabel = UILabel()
    private let lapCountLabel = UILabel()
    private let lapMinusButton = UIButton(type: .system)
    private let lapPlusButton = UIButton(type: .system)
    /// 레이스 모드 스타일을 매 틱마다 다시 적용하지 않도록 마지막 상태를 기억한다.
    private var appliedRaceMode: Bool?

    init(viewModel: ActiveWorkoutViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupButtons()
        setupCallbacks()
        Task { await viewModel.start() }
        startUITimer()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        // 레이스 데이 화면처럼 위에 올라온 모달에서 돌아왔을 때 화면이 멈춰 있지 않도록.
        startUITimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        stopUITimer()
    }

    override var prefersStatusBarHidden: Bool { true }

    private func setupUI() {
        view.backgroundColor = DesignTokens.Color.background

        setupGPSStatusView()

        headerLabel.font = DesignTokens.Font.wide(12, weight: .heavy)
        headerLabel.textColor = DesignTokens.Color.runAccent

        setupRaceControls()
        setupLapCard()

        let topRow = UIStackView(arrangedSubviews: [headerLabel, UIView(), gpsStatusView, raceDayButton, raceModeButton])
        topRow.spacing = 6
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 8

        titleLabel.font = DesignTokens.Font.wide(20, weight: .heavy)
        titleLabel.textColor = DesignTokens.Color.textPrimary
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.isHidden = true

        courseMapView.stations = viewModel.template.courseStations

        timeCaption.font = .systemFont(ofSize: 10, weight: .bold)
        timeCaption.textColor = DesignTokens.Color.textSecondary
        timeCaption.setTracked("SEGMENT TIME", kern: 1.5)

        segmentTimeLabel.font = DesignTokens.Font.number(104)
        segmentTimeLabel.textColor = DesignTokens.Color.textPrimary
        segmentTimeLabel.adjustsFontSizeToFitWidth = true
        segmentTimeLabel.minimumScaleFactor = 0.5

        let statsRow = UIStackView(arrangedSubviews: [primaryStat, heartStat, totalStat])
        statsRow.axis = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.spacing = 12

        [
            topRow, titleLabel, courseMapView, timeCaption, segmentTimeLabel,
            makeHairline(), statsRow, makeHairline(), segmentGoalRow, totalGoalRow
        ].forEach(contentStack.addArrangedSubview)
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 12
        contentStack.setCustomSpacing(14, after: topRow)
        contentStack.setCustomSpacing(18, after: titleLabel)
        contentStack.setCustomSpacing(22, after: courseMapView)
        contentStack.setCustomSpacing(-6, after: timeCaption)
        contentStack.setCustomSpacing(4, after: segmentTimeLabel)
        contentStack.setCustomSpacing(8, after: segmentGoalRow)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(lapCard)
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])

        pauseOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        pauseOverlay.isHidden = true
        pauseOverlay.isUserInteractionEnabled = false
        pauseOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pauseOverlay)
        NSLayoutConstraint.activate([
            pauseOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            pauseOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pauseOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pauseOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        pauseLabel.font = DesignTokens.Font.wide(28, weight: .heavy)
        pauseLabel.textColor = DesignTokens.Color.textPrimary
        pauseLabel.setTracked("PAUSED", kern: 4)
        pauseLabel.translatesAutoresizingMaskIntoConstraints = false
        pauseOverlay.addSubview(pauseLabel)
        NSLayoutConstraint.activate([
            pauseLabel.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            pauseLabel.centerYAnchor.constraint(equalTo: pauseOverlay.centerYAnchor)
        ])
    }

    private func makeHairline() -> UIView {
        let line = UIView()
        line.backgroundColor = DesignTokens.Color.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    // MARK: - 레이스 데이 컨트롤

    /// 상단의 레이스 모드 토글과 레이스 데이 진입 버튼.
    ///
    /// 레이스 데이 화면은 코디네이터를 거치지 않고 운동 화면에서 직접 띄운다.
    /// 대회장에서 페이스 카드·체크리스트를 다시 보려면 운동을 끝낼 필요가 없어야 하기 때문이다.
    private func setupRaceControls() {
        var raceConfig = UIButton.Configuration.plain()
        raceConfig.attributedTitle = Self.raceButtonTitle(isOn: false)
        raceConfig.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
        raceConfig.cornerStyle = .fixed
        raceConfig.background.cornerRadius = 0
        raceConfig.background.strokeWidth = 1
        raceConfig.background.strokeColor = UIColor.white.withAlphaComponent(0.25)
        raceModeButton.configuration = raceConfig
        raceModeButton.addTarget(self, action: #selector(raceModeTapped), for: .touchUpInside)
        raceModeButton.accessibilityLabel = RaceDayLocalization.Workout.raceModeToggle
        raceModeButton.setContentHuggingPriority(.required, for: .horizontal)
        // 좁은 화면에서 "RACE" 가 세로로 꺾이지 않게: 버튼은 줄어들지 않고 GPS 문구가 양보한다.
        raceModeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        raceModeButton.configuration?.titleLineBreakMode = .byClipping
        headerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        gpsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        gpsLabel.lineBreakMode = .byTruncatingTail

        var dayConfig = UIButton.Configuration.plain()
        dayConfig.image = UIImage(systemName: "flag.checkered")
        dayConfig.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
        raceDayButton.configuration = dayConfig
        raceDayButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        raceDayButton.addTarget(self, action: #selector(raceDayTapped), for: .touchUpInside)
        raceDayButton.accessibilityLabel = RaceDayLocalization.Workout.openRaceDay
        raceDayButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    /// 런 랩 카운터. 대회장 트랙은 랩을 선수가 직접 세야 해서 수동 증감만 제공한다.
    /// 기록에는 남지 않는 화면 보조 정보다.
    private func setupLapCard() {
        lapCaptionLabel.text = "LAP"
        lapCaptionLabel.font = .systemFont(ofSize: 11, weight: .black)
        lapCaptionLabel.textColor = UIColor.white.withAlphaComponent(0.55)

        let hintLabel = UILabel()
        hintLabel.text = RaceDayLocalization.Workout.lapHint
        hintLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.4)
        hintLabel.numberOfLines = 1
        hintLabel.adjustsFontSizeToFitWidth = true
        hintLabel.minimumScaleFactor = 0.7

        lapCountLabel.font = .monospacedDigitSystemFont(ofSize: 52, weight: .black)
        lapCountLabel.textColor = .white
        lapCountLabel.textAlignment = .center
        lapCountLabel.text = "0"
        lapCountLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        for (button, symbol, action) in [
            (lapMinusButton, "minus", #selector(lapMinusTapped)),
            (lapPlusButton, "plus", #selector(lapPlusTapped))
        ] {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
            )
            config.cornerStyle = .fixed
            config.background.cornerRadius = 0
            config.background.backgroundColor = UIColor.white.withAlphaComponent(0.1)
            button.configuration = config
            button.tintColor = .white
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 48).isActive = true
            button.heightAnchor.constraint(equalToConstant: 48).isActive = true
            button.addTarget(self, action: action, for: .touchUpInside)
        }
        lapMinusButton.accessibilityLabel = RaceDayLocalization.Workout.removeLap
        lapPlusButton.accessibilityLabel = RaceDayLocalization.Workout.addLap

        let captionStack = UIStackView(arrangedSubviews: [lapCaptionLabel, hintLabel])
        captionStack.axis = .vertical
        captionStack.alignment = .leading
        captionStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [captionStack, lapMinusButton, lapCountLabel, lapPlusButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        lapCard.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        lapCard.layer.borderWidth = 1
        lapCard.layer.borderColor = DesignTokens.Color.accentDim.cgColor
        lapCard.isHidden = true
        lapCard.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: lapCard.topAnchor, constant: 8),
            row.leadingAnchor.constraint(equalTo: lapCard.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: lapCard.trailingAnchor, constant: -10),
            row.bottomAnchor.constraint(equalTo: lapCard.bottomAnchor, constant: -8)
        ])
    }

    /// 켜짐/꺼짐에 따라 색만 바뀌는 "RACE" 라벨.
    private static func raceButtonTitle(isOn: Bool) -> AttributedString {
        var title = AttributedString("RACE")
        title.font = UIFont.systemFont(ofSize: 12, weight: .black)
        title.foregroundColor = isOn ? UIColor.black : UIColor.white.withAlphaComponent(0.6)
        return title
    }

    @objc private func raceModeTapped() {
        viewModel.toggleRaceMode()
        UISelectionFeedbackGenerator().selectionChanged()
        applyState()
    }

    @objc private func raceDayTapped() {
        RaceDayEntry.present(from: self, context: viewModel.makeRaceDayContext())
    }

    @objc private func lapPlusTapped() {
        viewModel.incrementLap()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        applyState()
    }

    @objc private func lapMinusTapped() {
        viewModel.decrementLap()
        UISelectionFeedbackGenerator().selectionChanged()
        applyState()
    }

    private func setupButtons() {
        let margin: CGFloat = DesignTokens.Spacing.l
        let buttonSize: CGFloat = 54

        advanceControl.translatesAutoresizingMaskIntoConstraints = false
        advanceControl.heightAnchor.constraint(equalToConstant: buttonSize).isActive = true
        advanceControl.addTarget(self, action: #selector(advanceTriggered), for: .primaryActionTriggered)

        for button in [pauseButton, endButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = .white
            button.backgroundColor = .clear
            button.layer.borderWidth = 1.5
            button.layer.borderColor = UIColor.white.cgColor
            button.widthAnchor.constraint(equalToConstant: buttonSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: buttonSize).isActive = true
        }

        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)

        endButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        endButton.tintColor = DesignTokens.Color.destructive
        endButton.layer.borderColor = DesignTokens.Color.destructive.cgColor
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)

        let controlRow = UIStackView(arrangedSubviews: [pauseButton, advanceControl, endButton])
        controlRow.axis = .horizontal
        controlRow.alignment = .center
        controlRow.spacing = 8
        controlRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlRow)
        view.bringSubviewToFront(controlRow)

        NSLayoutConstraint.activate([
            controlRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            controlRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            controlRow.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func setupCallbacks() {
        viewModel.goalAlertHandler = { [weak self] in
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            self?.flashGoalRow()
        }
    }

    @objc private func advanceTriggered() {
        viewModel.advance()
    }

    @objc private func pauseTapped() {
        viewModel.togglePause()
    }

    @objc private func endTapped() {
        let alert = DarkAlertController(
            title: HyroxSimStrings.Localizable.Alert.EndWorkout.title,
            message: HyroxSimStrings.Localizable.Alert.EndWorkout.message
        )
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.cancel, style: .cancel, handler: nil))
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.end, style: .destructive, handler: { [weak self] in
            self?.viewModel.endWorkout()
        }))
        present(alert, animated: true)
    }

    private func startUITimer() {
        guard uiTimer == nil, !viewModel.isFinished else { return }
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.applyState()
        }
    }

    private func stopUITimer() {
        uiTimer?.invalidate()
        uiTimer = nil
    }

    private func applyState() {
        let accent = accentColor(for: viewModel.accentKind)
        headerLabel.setTracked(viewModel.segmentLabel, kern: 3)
        headerLabel.textColor = accent
        titleLabel.text = viewModel.segmentSubLabel?.uppercased()
        titleLabel.isHidden = viewModel.segmentSubLabel == nil

        courseMapView.progress = CourseMapView.Progress(
            stationsReached: viewModel.courseStationsReached,
            fractionToNext: CGFloat(viewModel.courseFractionToNext)
        )

        segmentTimeLabel.text = viewModel.segmentElapsedText
        segmentTimeLabel.textColor = viewModel.isOverGoal
            ? DesignTokens.Color.overGoal
            : DesignTokens.Color.textPrimary

        applyRaceState()

        switch viewModel.accentKind {
        case .run, .roxZone:
            primaryStat.set(caption: "PACE", value: viewModel.paceText)
        case .station:
            primaryStat.set(caption: "TARGET", value: viewModel.stationTargetText ?? "—")
        }
        heartStat.set(caption: "HEART RATE", value: viewModel.heartRateText, color: colorFor(zone: viewModel.heartRateZone))
        totalStat.set(caption: "TOTAL", value: viewModel.totalElapsedText)

        segmentGoalRow.set(
            value: viewModel.goalText,
            delta: viewModel.goalDeltaText,
            deltaColor: deltaColor(isOver: viewModel.isOverGoal, isPlaceholder: viewModel.goalText == "—")
        )
        let hasTotal = viewModel.totalGoalText != "—"
        totalGoalRow.isHidden = !hasTotal
        totalGoalRow.set(
            value: viewModel.totalGoalText,
            delta: viewModel.totalDeltaText,
            deltaColor: deltaColor(isOver: viewModel.isOverTotalGoal, isPlaceholder: !hasTotal)
        )

        pauseOverlay.isHidden = !viewModel.isPaused
        pauseButton.setImage(
            UIImage(systemName: viewModel.isPaused ? "play.fill" : "pause.fill"),
            for: .normal
        )

        advanceControl.title = viewModel.isLastSegment ? "SLIDE TO FINISH" : "SLIDE TO NEXT"
        advanceControl.accentColor = viewModel.isLastSegment ? UIColor.systemGreen : accent
        advanceControl.accessibilityLabel = advanceControl.title

        updateGPSStatus()

        if viewModel.isFinished {
            stopUITimer()
        }
    }

    /// 레이스 모드 표시. 누적 델타를 키우고, 런 구간이면 랩 카운터를 연다.
    ///
    /// 대회에서 의미 있는 숫자는 "이 구간이 목표보다 빠른가"가 아니라
    /// **"지금까지 누적으로 앞서 있는가"** 다. 레이스 모드에서는 그 숫자를 가장 크게 둔다.
    private func applyRaceState() {
        let isRaceMode = viewModel.isRaceMode

        lapCountLabel.text = "\(viewModel.lapCount)"
        lapCard.isHidden = !(isRaceMode && viewModel.isLapCounterAvailable)
        lapMinusButton.isEnabled = viewModel.lapCount > 0
        lapMinusButton.alpha = viewModel.lapCount > 0 ? 1 : 0.35

        // 작은 화면 + 랩 카운터: 타이머를 줄이고 캡션을 접어 하단 컨트롤 위 공간을 만든다.
        let compact = view.bounds.height < 700 && !lapCard.isHidden
        if appliedCompactLayout != compact {
            appliedCompactLayout = compact
            segmentTimeLabel.font = DesignTokens.Font.number(compact ? 60 : 104)
            timeCaption.isHidden = compact
            contentStack.setCustomSpacing(compact ? 6 : 22, after: courseMapView)
        }

        guard appliedRaceMode != isRaceMode else { return }
        appliedRaceMode = isRaceMode

        totalGoalRow.setProminent(isRaceMode)
        segmentGoalRow.alpha = isRaceMode ? 0.7 : 1

        raceModeButton.tintColor = isRaceMode ? .black : UIColor.white.withAlphaComponent(0.6)
        raceModeButton.configuration?.background.backgroundColor = isRaceMode ? DesignTokens.Color.accent : .clear
        raceModeButton.configuration?.background.strokeColor = isRaceMode
            ? DesignTokens.Color.accent
            : UIColor.white.withAlphaComponent(0.25)
        raceModeButton.configuration?.attributedTitle = Self.raceButtonTitle(isOn: isRaceMode)
        raceModeButton.accessibilityValue = isRaceMode ? "1" : "0"
        raceModeButton.accessibilityTraits = isRaceMode ? [.button, .selected] : [.button]
    }

    private func flashGoalRow() {
        UIView.animate(withDuration: 0.12, animations: {
            self.segmentGoalRow.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
        }) { _ in
            UIView.animate(withDuration: 0.18) {
                self.segmentGoalRow.transform = .identity
            }
        }
    }

    private func accentColor(for accent: ActiveWorkoutViewModel.AccentKind) -> UIColor {
        switch accent {
        case .run: return DesignTokens.Color.runAccent
        case .roxZone: return DesignTokens.Color.roxZoneAccent
        case .station: return DesignTokens.Color.stationAccent
        }
    }

    private func deltaColor(isOver: Bool, isPlaceholder: Bool) -> UIColor {
        if isPlaceholder { return DesignTokens.Color.textSecondary }
        return isOver ? DesignTokens.Color.overGoal : DesignTokens.Color.accent
    }

    private func colorFor(zone: HeartRateZone?) -> UIColor {
        guard let zone else { return .white }
        switch zone {
        case .z1: return .lightGray
        case .z2: return .systemBlue
        case .z3: return .systemGreen
        case .z4: return .systemOrange
        case .z5: return .systemRed
        }
    }

    // MARK: - GPS Status

    private let gpsIcon = UIImageView()
    private let gpsBars: [UIView] = (0..<3).map { _ in UIView() }
    private let gpsLabel = UILabel()

    private func setupGPSStatusView() {
        gpsStatusView.axis = .horizontal
        gpsStatusView.alignment = .center
        gpsStatusView.spacing = 4

        gpsIcon.image = UIImage(systemName: "location.fill")
        gpsIcon.tintColor = .gray
        gpsIcon.contentMode = .scaleAspectFit
        gpsIcon.translatesAutoresizingMaskIntoConstraints = false
        gpsIcon.widthAnchor.constraint(equalToConstant: 12).isActive = true
        gpsIcon.heightAnchor.constraint(equalToConstant: 12).isActive = true
        gpsStatusView.addArrangedSubview(gpsIcon)

        let barsStack = UIStackView()
        barsStack.axis = .horizontal
        barsStack.alignment = .bottom
        barsStack.spacing = 2
        for (index, bar) in gpsBars.enumerated() {
            bar.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.widthAnchor.constraint(equalToConstant: 4).isActive = true
            bar.heightAnchor.constraint(equalToConstant: CGFloat(6 + index * 4)).isActive = true
            barsStack.addArrangedSubview(bar)
        }
        gpsStatusView.addArrangedSubview(barsStack)

        gpsLabel.font = .systemFont(ofSize: 10, weight: .bold)
        gpsLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        gpsStatusView.addArrangedSubview(gpsLabel)

        gpsStatusView.heightAnchor.constraint(equalToConstant: 18).isActive = true
    }

    private func updateGPSStatus() {
        switch viewModel.gpsStatus {
        case .off:
            gpsIcon.tintColor = UIColor.white.withAlphaComponent(0.2)
            gpsLabel.text = "GPS OFF"
            gpsLabel.textColor = UIColor.white.withAlphaComponent(0.22)
            gpsBars.forEach { $0.backgroundColor = UIColor.white.withAlphaComponent(0.1) }
        case .searching:
            gpsIcon.tintColor = .gray
            gpsLabel.text = "GPS SEARCHING"
            gpsLabel.textColor = .gray
            gpsBars.forEach { $0.backgroundColor = UIColor.white.withAlphaComponent(0.15) }
        case .weak:
            gpsIcon.tintColor = .systemOrange
            gpsLabel.text = "GPS WEAK"
            gpsLabel.textColor = .systemOrange
            gpsBars[0].backgroundColor = .systemOrange
            gpsBars[1].backgroundColor = UIColor.white.withAlphaComponent(0.15)
            gpsBars[2].backgroundColor = UIColor.white.withAlphaComponent(0.15)
        case .fair:
            gpsIcon.tintColor = DesignTokens.Color.accent
            gpsLabel.text = "GPS FAIR"
            gpsLabel.textColor = DesignTokens.Color.accent
            gpsBars[0].backgroundColor = DesignTokens.Color.accent
            gpsBars[1].backgroundColor = DesignTokens.Color.accent
            gpsBars[2].backgroundColor = UIColor.white.withAlphaComponent(0.15)
        case .strong:
            gpsIcon.tintColor = .systemGreen
            gpsLabel.text = "GPS STRONG"
            gpsLabel.textColor = .systemGreen
            gpsBars.forEach { $0.backgroundColor = .systemGreen }
        }
    }
}

// MARK: - Components

/// Caption above a left-aligned value.
private final class StatColumn: UIStackView {

    private let captionLabel = UILabel()
    private let valueLabel = UILabel()

    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 4

        captionLabel.font = .systemFont(ofSize: 10, weight: .bold)
        captionLabel.textColor = DesignTokens.Color.textSecondary

        valueLabel.font = DesignTokens.Font.number(24, weight: .bold)
        valueLabel.textColor = DesignTokens.Color.textPrimary
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.5

        addArrangedSubview(captionLabel)
        addArrangedSubview(valueLabel)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    func set(caption: String, value: String, color: UIColor = DesignTokens.Color.textPrimary) {
        captionLabel.setTracked(caption, kern: 1)
        valueLabel.text = value
        valueLabel.textColor = color
    }
}

/// "CAPTION  goal ........ delta" line.
private final class GoalRow: UIStackView {

    private let valueLabel = UILabel()
    private let deltaLabel = UILabel()
    private lazy var minHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: 0)

    init(caption: String) {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .lastBaseline
        spacing = 10
        minHeight.isActive = true

        let captionLabel = UILabel()
        captionLabel.font = .systemFont(ofSize: 10, weight: .bold)
        captionLabel.textColor = DesignTokens.Color.textSecondary
        captionLabel.setTracked(caption, kern: 1.5)
        captionLabel.setContentHuggingPriority(.required, for: .horizontal)

        valueLabel.font = DesignTokens.Font.number(15, weight: .bold)
        valueLabel.textColor = DesignTokens.Color.textPrimary

        deltaLabel.font = DesignTokens.Font.number(20)
        deltaLabel.textAlignment = .right
        deltaLabel.setContentHuggingPriority(.required, for: .horizontal)

        addArrangedSubview(captionLabel)
        addArrangedSubview(valueLabel)
        addArrangedSubview(deltaLabel)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    /// Race mode: the cumulative delta becomes the largest number on the row.
    func setProminent(_ isProminent: Bool) {
        deltaLabel.font = DesignTokens.Font.number(isProminent ? 36 : 20)
        // 큰 숫자가 윗줄(구간 목표)과 겹치지 않도록 줄 높이를 확보한다.
        minHeight.constant = isProminent ? 46 : 0
    }

    func set(value: String, delta: String, deltaColor: UIColor) {
        valueLabel.text = value
        deltaLabel.text = delta
        deltaLabel.textColor = deltaColor
    }
}
