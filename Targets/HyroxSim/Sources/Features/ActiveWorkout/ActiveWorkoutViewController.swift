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

        let topRow = UIStackView(arrangedSubviews: [headerLabel, UIView(), gpsStatusView])
        topRow.axis = .horizontal
        topRow.alignment = .center

        titleLabel.font = DesignTokens.Font.wide(20, weight: .heavy)
        titleLabel.textColor = DesignTokens.Color.textPrimary
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.isHidden = true

        courseMapView.stations = viewModel.template.courseStations

        let timeCaption = UILabel()
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

        let contentStack = UIStackView(arrangedSubviews: [
            topRow, titleLabel, courseMapView, timeCaption, segmentTimeLabel,
            makeHairline(), statsRow, makeHairline(), segmentGoalRow, totalGoalRow
        ])
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

    init(caption: String) {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .firstBaseline
        spacing = 10

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

    func set(value: String, delta: String, deltaColor: UIColor) {
        valueLabel.text = value
        deltaLabel.text = delta
        deltaLabel.textColor = deltaColor
    }
}
