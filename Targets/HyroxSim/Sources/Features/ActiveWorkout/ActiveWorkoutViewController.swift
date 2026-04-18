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

    private let backgroundView = UIView()
    private let contentStack = UIStackView()
    private let gpsStatusView = UIStackView()
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
    private let totalTitleLabel = UILabel()
    private let totalValueLabel = UILabel()
    private let totalDeltaLabel = UILabel()
    private let goalDivider = UIView()
    private let totalGoalRow = UIStackView()
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

        setupGPSStatusView()

        headerLabel.font = .systemFont(ofSize: 24, weight: .black)
        headerLabel.textColor = .white
        headerLabel.textAlignment = .center
        headerLabel.numberOfLines = 2

        subHeaderLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        subHeaderLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        subHeaderLabel.textAlignment = .center
        subHeaderLabel.numberOfLines = 2
        subHeaderLabel.isHidden = true

        segmentMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 92, weight: .black)
        segmentMetric.captionLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        totalMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        totalMetric.captionLabel.textColor = UIColor.white.withAlphaComponent(0.55)

        infoPrimaryMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        infoSecondaryMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        heartMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)

        let topRow = UIStackView(arrangedSubviews: [gpsStatusView, UIView()])
        topRow.axis = .horizontal
        topRow.alignment = .center

        goalTitleLabel.font = .systemFont(ofSize: 11, weight: .black)
        goalTitleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        goalTitleLabel.text = "SEG"
        goalTitleLabel.setContentHuggingPriority(.required, for: .horizontal)

        goalValueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        goalValueLabel.textColor = UIColor.white.withAlphaComponent(0.9)

        goalDeltaLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .black)
        goalDeltaLabel.textAlignment = .right
        goalDeltaLabel.setContentHuggingPriority(.required, for: .horizontal)

        let segRow = UIStackView(arrangedSubviews: [goalTitleLabel, goalValueLabel, UIView(), goalDeltaLabel])
        segRow.axis = .horizontal
        segRow.alignment = .center
        segRow.spacing = 10

        totalTitleLabel.font = .systemFont(ofSize: 11, weight: .black)
        totalTitleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        totalTitleLabel.text = "TOTAL"
        totalTitleLabel.setContentHuggingPriority(.required, for: .horizontal)

        totalValueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        totalValueLabel.textColor = UIColor.white.withAlphaComponent(0.9)

        totalDeltaLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .black)
        totalDeltaLabel.textAlignment = .right
        totalDeltaLabel.setContentHuggingPriority(.required, for: .horizontal)

        totalGoalRow.addArrangedSubview(totalTitleLabel)
        totalGoalRow.addArrangedSubview(totalValueLabel)
        totalGoalRow.addArrangedSubview(UIView())
        totalGoalRow.addArrangedSubview(totalDeltaLabel)
        totalGoalRow.axis = .horizontal
        totalGoalRow.alignment = .center
        totalGoalRow.spacing = 10

        goalDivider.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        goalDivider.translatesAutoresizingMaskIntoConstraints = false
        goalDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let goalStack = UIStackView(arrangedSubviews: [segRow, goalDivider, totalGoalRow])
        goalStack.axis = .vertical
        goalStack.spacing = 8
        goalStack.translatesAutoresizingMaskIntoConstraints = false

        goalCard.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        goalCard.layer.cornerRadius = 18
        goalCard.layer.borderWidth = 1
        goalCard.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        goalCard.translatesAutoresizingMaskIntoConstraints = false
        goalCard.addSubview(goalStack)
        NSLayoutConstraint.activate([
            goalStack.topAnchor.constraint(equalTo: goalCard.topAnchor, constant: 12),
            goalStack.leadingAnchor.constraint(equalTo: goalCard.leadingAnchor, constant: 16),
            goalStack.trailingAnchor.constraint(equalTo: goalCard.trailingAnchor, constant: -16),
            goalStack.bottomAnchor.constraint(equalTo: goalCard.bottomAnchor, constant: -12)
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
        contentStack.setCustomSpacing(4, after: segmentMetric)
        contentStack.addArrangedSubview(totalMetric)
        contentStack.addArrangedSubview(goalCard)
        contentStack.addArrangedSubview(infoRow)
        contentStack.addArrangedSubview(heartMetric)
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        pauseOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        pauseOverlay.isHidden = true
        pauseOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pauseOverlay)
        NSLayoutConstraint.activate([
            pauseOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            pauseOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pauseOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pauseOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        pauseLabel.text = "PAUSED"
        pauseLabel.font = .systemFont(ofSize: 28, weight: .black)
        pauseLabel.textColor = UIColor.white.withAlphaComponent(0.86)
        pauseLabel.translatesAutoresizingMaskIntoConstraints = false
        pauseOverlay.addSubview(pauseLabel)
        NSLayoutConstraint.activate([
            pauseLabel.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            pauseLabel.centerYAnchor.constraint(equalTo: pauseOverlay.centerYAnchor)
        ])
    }

    private func setupButtons() {
        let margin: CGFloat = DesignTokens.Spacing.l
        let buttonSize: CGFloat = 54

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
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)

        endButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        endButton.backgroundColor = UIColor.red.withAlphaComponent(0.2)
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)

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

    private func setupCallbacks() {
        viewModel.goalAlertHandler = { [weak self] in
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            self?.flashGoalCard()
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
        headerLabel.text = viewModel.segmentLabel
        subHeaderLabel.text = viewModel.segmentSubLabel
        subHeaderLabel.isHidden = viewModel.segmentSubLabel == nil

        segmentMetric.setValue(viewModel.segmentElapsedText, caption: "CURRENT")
        totalMetric.setValue(viewModel.totalElapsedText, caption: "TOTAL")

        goalValueLabel.text = viewModel.goalText
        goalDeltaLabel.text = viewModel.goalDeltaText
        goalDeltaLabel.textColor = deltaColor(isOver: viewModel.isOverGoal, isPlaceholder: viewModel.goalText == "—")
        goalCard.backgroundColor = viewModel.isOverGoal
            ? UIColor.systemRed.withAlphaComponent(0.2)
            : UIColor.white.withAlphaComponent(0.08)
        goalCard.layer.borderColor = viewModel.isOverGoal
            ? UIColor.systemRed.withAlphaComponent(0.35).cgColor
            : UIColor.white.withAlphaComponent(0.08).cgColor

        let hasTotal = viewModel.totalGoalText != "—"
        totalGoalRow.isHidden = !hasTotal
        goalDivider.isHidden = !hasTotal
        totalValueLabel.text = viewModel.totalGoalText
        totalDeltaLabel.text = viewModel.totalDeltaText
        totalDeltaLabel.textColor = deltaColor(isOver: viewModel.isOverTotalGoal, isPlaceholder: !hasTotal)

        switch viewModel.accentKind {
        case .run, .roxZone:
            infoPrimaryMetric.setValue(viewModel.paceText, caption: "PACE")
            infoSecondaryMetric.setValue(viewModel.distanceText, caption: "DISTANCE")
            infoPrimaryMetric.setValueColor(.white)
            infoSecondaryMetric.setValueColor(accentColor(for: viewModel.accentKind))
        case .station:
            infoPrimaryMetric.setValue(viewModel.stationNameText ?? "—", caption: "STATION")
            infoSecondaryMetric.setValue(viewModel.stationTargetText ?? "—", caption: "TARGET")
            infoPrimaryMetric.setValueColor(accentColor(for: viewModel.accentKind))
            infoSecondaryMetric.setValueColor(.white)
        }

        heartMetric.setValue("\(viewModel.heartRateText) BPM", caption: "HEART")
        heartMetric.setValueColor(colorFor(zone: viewModel.heartRateZone))

        headerLabel.textColor = accentColor(for: viewModel.accentKind)
        backgroundView.backgroundColor = backgroundColor(
            for: viewModel.accentKind,
            isOverGoal: viewModel.isOverGoal
        )
        pauseOverlay.isHidden = !viewModel.isPaused
        pauseButton.setImage(
            UIImage(systemName: viewModel.isPaused ? "play.fill" : "pause.fill"),
            for: .normal
        )

        advanceControl.title = viewModel.isLastSegment ? "SLIDE TO FINISH" : "SLIDE TO NEXT"
        advanceControl.accentColor = viewModel.isLastSegment
            ? UIColor.systemGreen
            : accentColor(for: viewModel.accentKind)
        advanceControl.accessibilityLabel = advanceControl.title

        updateGPSStatus()

        if viewModel.isFinished {
            stopUITimer()
        }
    }

    private func flashGoalCard() {
        UIView.animate(withDuration: 0.12, animations: {
            self.goalCard.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
        }) { _ in
            UIView.animate(withDuration: 0.18) {
                self.goalCard.transform = .identity
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

    private func backgroundColor(
        for accent: ActiveWorkoutViewModel.AccentKind,
        isOverGoal: Bool
    ) -> UIColor {
        if isOverGoal {
            return UIColor(red: 0.36, green: 0.06, blue: 0.06, alpha: 1)
        }

        switch accent {
        case .run: return DesignTokens.Color.runBackground
        case .roxZone: return DesignTokens.Color.roxZoneBackground
        case .station: return DesignTokens.Color.stationBackground
        }
    }

    private func deltaColor(isOver: Bool, isPlaceholder: Bool) -> UIColor {
        if isPlaceholder { return UIColor.white.withAlphaComponent(0.8) }
        return isOver ? UIColor.systemRed : DesignTokens.Color.success
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
            bar.layer.cornerRadius = 1.5
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.widthAnchor.constraint(equalToConstant: 4).isActive = true
            bar.heightAnchor.constraint(equalToConstant: CGFloat(6 + index * 4)).isActive = true
            barsStack.addArrangedSubview(bar)
        }
        gpsStatusView.addArrangedSubview(barsStack)

        gpsLabel.font = .systemFont(ofSize: 10, weight: .bold)
        gpsLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        gpsStatusView.addArrangedSubview(gpsLabel)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        gpsStatusView.addArrangedSubview(spacer)

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
