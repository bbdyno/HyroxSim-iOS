//
//  LiveWorkoutMirrorViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

@MainActor
protocol LiveWorkoutMirrorDelegate: AnyObject {
    func mirrorDidClose()
    func mirrorSendCommand(_ command: WorkoutCommand)
}

final class LiveWorkoutMirrorViewController: UIViewController {

    weak var delegate: LiveWorkoutMirrorDelegate?

    private let backgroundView = UIView()
    private let contentStack = UIStackView()
    private let watchBadge = UILabel()
    private let gpsLabel = UILabel()
    private let headerLabel = UILabel()
    private let subHeaderLabel = UILabel()
    private let segmentMetric = MetricView()
    private let totalMetric = MetricView()
    private let infoPrimaryMetric = MetricView()
    private let infoSecondaryMetric = MetricView()
    private let heartMetric = MetricView()
    private let goalCard = UIView()
    private let goalTitleLabel = UILabel()
    private let goalValueLabel = UILabel()
    private let goalDeltaLabel = UILabel()
    private let advanceControl = SlideActionControl()
    private let pauseButton = UIButton(type: .system)
    private let endButton = UIButton(type: .system)

    private var lastState: LiveWorkoutState?
    private var isConnected = true
    private var alertedGoalSegmentIndex: Int?

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupButtons()
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func updateState(_ state: LiveWorkoutState) {
        loadViewIfNeeded()

        if state.isOverGoal, alertedGoalSegmentIndex != state.currentSegmentIndex {
            alertedGoalSegmentIndex = state.currentSegmentIndex
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        lastState = state

        watchBadge.text = isConnected ? "⌚ LIVE FROM APPLE WATCH" : "⌚ WATCH DISCONNECTED"
        watchBadge.textColor = isConnected ? DesignTokens.Color.accent : .systemRed

        gpsLabel.text = gpsText(for: state)
        gpsLabel.textColor = gpsColor(for: state)

        headerLabel.text = state.segmentLabel
        subHeaderLabel.text = state.segmentSubLabel
        subHeaderLabel.isHidden = state.segmentSubLabel == nil

        segmentMetric.setValue(state.segmentElapsedText, caption: "CURRENT")
        totalMetric.setValue(state.totalElapsedText, caption: "TOTAL")

        goalValueLabel.text = state.goalText
        goalDeltaLabel.text = state.goalDeltaText
        goalDeltaLabel.textColor = state.isOverGoal ? .systemRed : DesignTokens.Color.success
        goalCard.backgroundColor = state.isOverGoal
            ? UIColor.systemRed.withAlphaComponent(0.2)
            : UIColor.white.withAlphaComponent(0.08)
        goalCard.layer.borderColor = state.isOverGoal
            ? UIColor.systemRed.withAlphaComponent(0.35).cgColor
            : UIColor.white.withAlphaComponent(0.08).cgColor

        if state.accentKindRaw == "station" {
            infoPrimaryMetric.setValue(state.stationNameText ?? "—", caption: "STATION")
            infoSecondaryMetric.setValue(state.stationTargetText ?? "—", caption: "TARGET")
            infoPrimaryMetric.setValueColor(accentColor(for: state))
            infoSecondaryMetric.setValueColor(.white)
        } else {
            infoPrimaryMetric.setValue(state.paceText, caption: "PACE")
            infoSecondaryMetric.setValue(state.distanceText, caption: "DISTANCE")
            infoPrimaryMetric.setValueColor(.white)
            infoSecondaryMetric.setValueColor(accentColor(for: state))
        }

        heartMetric.setValue("\(state.heartRateText) BPM", caption: "HEART")
        if let zoneRaw = state.heartRateZoneRaw, let zone = HeartRateZone(rawValue: zoneRaw) {
            heartMetric.setValueColor(colorFor(zone: zone))
        } else {
            heartMetric.setValueColor(.white)
        }

        headerLabel.textColor = accentColor(for: state)
        backgroundView.backgroundColor = backgroundColor(for: state)
        pauseButton.setImage(
            UIImage(systemName: state.isPaused ? "play.fill" : "pause.fill"),
            for: .normal
        )
        advanceControl.title = state.isLastSegment ? "SLIDE TO FINISH" : "SLIDE TO NEXT"
        advanceControl.accentColor = state.isLastSegment ? .systemGreen : accentColor(for: state)
        advanceControl.accessibilityLabel = advanceControl.title

        setControlsEnabled(isConnected)

        if state.isFinished {
            delegate?.mirrorDidClose()
        }
    }

    func showDisconnected() {
        loadViewIfNeeded()
        isConnected = false
        watchBadge.text = "⌚ WATCH DISCONNECTED"
        watchBadge.textColor = .systemRed
        setControlsEnabled(false)
    }

    func showReconnected() {
        loadViewIfNeeded()
        isConnected = true
        watchBadge.text = "⌚ LIVE FROM APPLE WATCH"
        watchBadge.textColor = DesignTokens.Color.accent
        setControlsEnabled(true)
        if let lastState {
            updateState(lastState)
        }
    }

    private func setupUI() {
        view.backgroundColor = .black

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = DesignTokens.Color.runBackground
        view.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        watchBadge.font = .systemFont(ofSize: 10, weight: .black)
        watchBadge.textColor = DesignTokens.Color.accent
        watchBadge.textAlignment = .center
        watchBadge.text = "⌚ LIVE FROM APPLE WATCH"
        watchBadge.accessibilityIdentifier = "liveMirror.watchBadge"

        gpsLabel.font = .systemFont(ofSize: 11, weight: .bold)
        gpsLabel.textAlignment = .center
        gpsLabel.textColor = UIColor.white.withAlphaComponent(0.7)

        headerLabel.font = .systemFont(ofSize: 24, weight: .black)
        headerLabel.textAlignment = .center
        headerLabel.textColor = .white
        headerLabel.numberOfLines = 2
        headerLabel.accessibilityIdentifier = "liveMirror.headerLabel"

        subHeaderLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        subHeaderLabel.textAlignment = .center
        subHeaderLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        subHeaderLabel.numberOfLines = 2
        subHeaderLabel.isHidden = true

        segmentMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 92, weight: .black)
        totalMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        totalMetric.widthAnchor.constraint(equalToConstant: 132).isActive = true
        infoPrimaryMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        infoSecondaryMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        heartMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)

        let topMeta = UIStackView(arrangedSubviews: [watchBadge, gpsLabel])
        topMeta.axis = .vertical
        topMeta.spacing = 4

        let topRow = UIStackView(arrangedSubviews: [topMeta, totalMetric])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 16

        goalTitleLabel.text = "GOAL"
        goalTitleLabel.font = .systemFont(ofSize: 11, weight: .black)
        goalTitleLabel.textColor = UIColor.white.withAlphaComponent(0.55)

        goalValueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        goalValueLabel.textColor = .white

        goalDeltaLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .black)
        goalDeltaLabel.textAlignment = .right

        let goalTextStack = UIStackView(arrangedSubviews: [goalTitleLabel, goalValueLabel])
        goalTextStack.axis = .vertical
        goalTextStack.spacing = 2

        let goalStack = UIStackView(arrangedSubviews: [goalTextStack, goalDeltaLabel])
        goalStack.axis = .horizontal
        goalStack.alignment = .center
        goalStack.spacing = 12
        goalStack.translatesAutoresizingMaskIntoConstraints = false

        goalCard.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        goalCard.layer.cornerRadius = 18
        goalCard.layer.borderWidth = 1
        goalCard.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        goalCard.translatesAutoresizingMaskIntoConstraints = false
        goalCard.addSubview(goalStack)
        NSLayoutConstraint.activate([
            goalStack.topAnchor.constraint(equalTo: goalCard.topAnchor, constant: 14),
            goalStack.leadingAnchor.constraint(equalTo: goalCard.leadingAnchor, constant: 16),
            goalStack.trailingAnchor.constraint(equalTo: goalCard.trailingAnchor, constant: -16),
            goalStack.bottomAnchor.constraint(equalTo: goalCard.bottomAnchor, constant: -14)
        ])

        let infoRow = UIStackView(arrangedSubviews: [infoPrimaryMetric, infoSecondaryMetric])
        infoRow.axis = .horizontal
        infoRow.alignment = .fill
        infoRow.distribution = .fillEqually
        infoRow.spacing = 12

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(topRow)
        contentStack.addArrangedSubview(headerLabel)
        contentStack.addArrangedSubview(subHeaderLabel)
        contentStack.addArrangedSubview(segmentMetric)
        contentStack.addArrangedSubview(goalCard)
        contentStack.addArrangedSubview(infoRow)
        contentStack.addArrangedSubview(heartMetric)
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    private func setupButtons() {
        let buttonSize: CGFloat = 54
        let margin: CGFloat = 24

        advanceControl.translatesAutoresizingMaskIntoConstraints = false
        advanceControl.heightAnchor.constraint(equalToConstant: 68).isActive = true
        advanceControl.addTarget(self, action: #selector(advanceTriggered), for: .primaryActionTriggered)

        for button in [pauseButton, endButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = .white
            button.backgroundColor = UIColor.black.withAlphaComponent(0.25)
            button.layer.cornerRadius = buttonSize / 2
            button.widthAnchor.constraint(equalToConstant: buttonSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: buttonSize).isActive = true
        }

        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseButton.accessibilityIdentifier = "liveMirror.pauseButton"
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)

        endButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        endButton.backgroundColor = UIColor.red.withAlphaComponent(0.2)
        endButton.accessibilityIdentifier = "liveMirror.endButton"
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)

        advanceControl.accessibilityIdentifier = "liveMirror.nextButton"

        let controlRow = UIStackView(arrangedSubviews: [pauseButton, advanceControl, endButton])
        controlRow.axis = .horizontal
        controlRow.alignment = .center
        controlRow.spacing = 14
        controlRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlRow)

        NSLayoutConstraint.activate([
            controlRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            controlRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            controlRow.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func setControlsEnabled(_ enabled: Bool) {
        [pauseButton, endButton, advanceControl].forEach {
            $0.isEnabled = enabled
            $0.isUserInteractionEnabled = enabled
        }
        advanceControl.accessibilityTraits = enabled ? [.button] : [.button, .notEnabled]
        let alpha: CGFloat = enabled ? 1 : 0.45
        pauseButton.alpha = alpha
        endButton.alpha = alpha
        advanceControl.alpha = alpha
    }

    @objc private func advanceTriggered() {
        delegate?.mirrorSendCommand(.advance)
    }

    @objc private func pauseTapped() {
        let command: WorkoutCommand = lastState?.isPaused == true ? .resume : .pause
        delegate?.mirrorSendCommand(command)
    }

    @objc private func endTapped() {
        let alert = DarkAlertController(
            title: HyroxSimStrings.Localizable.Alert.EndWatchWorkout.title,
            message: HyroxSimStrings.Localizable.Alert.EndWatchWorkout.message
        )
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.cancel, style: .cancel, handler: nil))
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.end, style: .destructive, handler: { [weak self] in
            self?.delegate?.mirrorSendCommand(.end)
        }))
        present(alert, animated: true)
    }

    private func accentColor(for state: LiveWorkoutState) -> UIColor {
        switch state.accentKindRaw {
        case "run": return DesignTokens.Color.runAccent
        case "roxZone": return DesignTokens.Color.roxZoneAccent
        default: return DesignTokens.Color.stationAccent
        }
    }

    private func backgroundColor(for state: LiveWorkoutState) -> UIColor {
        if state.isOverGoal {
            return UIColor(red: 0.36, green: 0.06, blue: 0.06, alpha: 1)
        }

        switch state.accentKindRaw {
        case "run": return DesignTokens.Color.runBackground
        case "roxZone": return DesignTokens.Color.roxZoneBackground
        default: return DesignTokens.Color.stationBackground
        }
    }

    private func gpsText(for state: LiveWorkoutState) -> String {
        if !state.gpsActive { return "GPS OFF" }
        return state.gpsStrong ? "GPS STRONG" : "GPS SEARCHING"
    }

    private func gpsColor(for state: LiveWorkoutState) -> UIColor {
        if !state.gpsActive { return UIColor.white.withAlphaComponent(0.22) }
        return state.gpsStrong ? .systemGreen : .systemOrange
    }

    private func colorFor(zone: HeartRateZone) -> UIColor {
        switch zone {
        case .z1: return .lightGray
        case .z2: return .systemBlue
        case .z3: return .systemGreen
        case .z4: return .systemOrange
        case .z5: return .systemRed
        }
    }
}
