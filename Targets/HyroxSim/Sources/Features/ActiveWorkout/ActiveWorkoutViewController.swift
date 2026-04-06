//
//  ActiveWorkoutViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxKit

final class ActiveWorkoutViewController: UIViewController {

    private let viewModel: ActiveWorkoutViewModel
    private var uiTimer: Timer?

    // MARK: - Metrics
    private let headerLabel = UILabel()
    private let subHeaderLabel = UILabel()
    private let gpsStatusView = UIStackView()
    private let segmentMetric = MetricView()
    private let totalMetric = MetricView()
    private let paceMetric = MetricView()
    private let distanceMetric = MetricView()
    private let stationNameMetric = MetricView()
    private let stationTargetMetric = MetricView()
    private let heartMetric = MetricView()

    // MARK: - Buttons
    private let nextButton = UIButton(type: .system)
    private let pauseButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let endButton = UIButton(type: .system)

    // MARK: - Overlay
    private let pauseOverlay = UIView()

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
        setupGestures()
        setupButtons()
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

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = DesignTokens.Color.background

        // Header
        headerLabel.font = .systemFont(ofSize: 16, weight: .bold)
        headerLabel.textColor = DesignTokens.Color.accent
        headerLabel.textAlignment = .center

        subHeaderLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subHeaderLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        subHeaderLabel.textAlignment = .center
        subHeaderLabel.isHidden = true

        // GPS status bar (icon + 3 signal bars + label)
        setupGPSStatusView()

        // Segment time (biggest)
        segmentMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 64, weight: .bold)
        // Total time (smaller below)
        totalMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        totalMetric.valueLabel.textColor = UIColor.white.withAlphaComponent(0.6)

        // Row 2a: Pace + Distance
        let row2Run = UIStackView(arrangedSubviews: [paceMetric, distanceMetric])
        row2Run.distribution = .fillEqually
        row2Run.spacing = 16

        // Row 2b: Station
        let row2Station = UIStackView(arrangedSubviews: [stationNameMetric, stationTargetMetric])
        row2Station.distribution = .fillEqually
        row2Station.spacing = 16

        // Main vertical layout
        let mainStack = UIStackView(arrangedSubviews: [
            gpsStatusView,
            headerLabel, subHeaderLabel,
            segmentMetric, totalMetric,
            row2Run, row2Station,
            heartMetric
        ])
        mainStack.axis = .vertical
        mainStack.alignment = .fill
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        // Pause overlay
        pauseOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
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
    }

    private func setupButtons() {
        let smallSize: CGFloat = 50
        let margin: CGFloat = DesignTokens.Spacing.l

        // NEXT button — large, prominent, center bottom
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.setTitle("NEXT ▶", for: .normal)
        nextButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        nextButton.layer.cornerRadius = 28
        nextButton.layer.borderWidth = 2
        nextButton.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        view.addSubview(nextButton)
        NSLayoutConstraint.activate([
            nextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -margin),
            nextButton.widthAnchor.constraint(equalToConstant: 180),
            nextButton.heightAnchor.constraint(equalToConstant: 56)
        ])

        // Small corner buttons
        for btn in [pauseButton, undoButton, endButton] {
            btn.tintColor = .white
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.layer.cornerRadius = smallSize / 2
            btn.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            view.addSubview(btn)
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: smallSize),
                btn.heightAnchor.constraint(equalToConstant: smallSize)
            ])
        }

        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            pauseButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            pauseButton.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -DesignTokens.Spacing.m)
        ])

        endButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            endButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            endButton.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -DesignTokens.Spacing.m)
        ])

        undoButton.setImage(UIImage(systemName: "arrow.uturn.backward"), for: .normal)
        undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            undoButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            undoButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: margin)
        ])
    }

    private func setupGestures() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        view.addGestureRecognizer(longPress)
    }

    // MARK: - Actions

    @objc private func nextTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        viewModel.advance()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: view)
        for btn in [nextButton, pauseButton, undoButton, endButton] {
            if btn.frame.insetBy(dx: -10, dy: -10).contains(location) { return }
        }
        switch gesture.state {
        case .began:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .ended:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.advance()
        default: break
        }
    }

    @objc private func pauseTapped() {
        viewModel.togglePause()
    }

    @objc private func undoTapped() {
        let alert = DarkAlertController(title: "Go back to previous segment?", message: nil)
        alert.addAction(.init(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(.init(title: "Undo", style: .destructive, handler: { [weak self] in
            self?.viewModel.undo()
        }))
        present(alert, animated: true)
    }

    @objc private func endTapped() {
        let alert = DarkAlertController(title: "End workout?", message: "Your progress will be saved.")
        alert.addAction(.init(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(.init(title: "End", style: .destructive, handler: { [weak self] in
            self?.viewModel.endWorkout()
        }))
        present(alert, animated: true)
    }

    // MARK: - UI Timer

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

        segmentMetric.setValue(viewModel.segmentElapsedText, caption: "SEGMENT")
        totalMetric.setValue(viewModel.totalElapsedText, caption: "TOTAL")

        switch viewModel.accentKind {
        case .run, .roxZone:
            paceMetric.setValue(viewModel.paceText, caption: "PACE")
            distanceMetric.setValue(viewModel.distanceText, caption: "KM")
            paceMetric.superview?.isHidden = false
            stationNameMetric.superview?.isHidden = true
        case .station:
            stationNameMetric.setValue(viewModel.stationNameText ?? "—", caption: "STATION")
            stationTargetMetric.setValue(viewModel.stationTargetText ?? "—", caption: "TARGET")
            paceMetric.superview?.isHidden = true
            stationNameMetric.superview?.isHidden = false
        }

        heartMetric.setValue("\(viewModel.heartRateText) ♥", caption: "HEART")
        heartMetric.setValueColor(colorFor(zone: viewModel.heartRateZone))

        // Keep black background, tint header with accent color
        headerLabel.textColor = accentColor(for: viewModel.accentKind)
        pauseOverlay.isHidden = !viewModel.isPaused
        pauseButton.setImage(
            UIImage(systemName: viewModel.isPaused ? "play.fill" : "pause.fill"),
            for: .normal
        )

        // NEXT → FINISH on last segment
        let btnTitle = viewModel.isLastSegment ? "FINISH ✓" : "NEXT ▶"
        nextButton.setTitle(btnTitle, for: .normal)
        nextButton.backgroundColor = viewModel.isLastSegment
            ? DesignTokens.Color.accent.withAlphaComponent(0.4)
            : UIColor.white.withAlphaComponent(0.25)

        updateGPSStatus()

        if viewModel.isFinished {
            stopUITimer()
        }
    }

    private func accentColor(for accent: ActiveWorkoutViewModel.AccentKind) -> UIColor {
        switch accent {
        case .run: return DesignTokens.Color.runAccent
        case .roxZone: return DesignTokens.Color.roxZoneAccent
        case .station: return DesignTokens.Color.accent
        }
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
        for (i, bar) in gpsBars.enumerated() {
            bar.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            bar.layer.cornerRadius = 1.5
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.widthAnchor.constraint(equalToConstant: 4).isActive = true
            bar.heightAnchor.constraint(equalToConstant: CGFloat(6 + i * 4)).isActive = true
            barsStack.addArrangedSubview(bar)
        }
        gpsStatusView.addArrangedSubview(barsStack)

        gpsLabel.font = .systemFont(ofSize: 10, weight: .medium)
        gpsLabel.textColor = .gray
        gpsStatusView.addArrangedSubview(gpsLabel)

        // Push everything to the left
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        gpsStatusView.addArrangedSubview(spacer)

        gpsStatusView.heightAnchor.constraint(equalToConstant: 16).isActive = true
    }

    private func updateGPSStatus() {
        let status = viewModel.gpsStatus
        switch status {
        case .off:
            gpsIcon.tintColor = UIColor.white.withAlphaComponent(0.2)
            gpsLabel.text = "GPS OFF"
            gpsLabel.textColor = UIColor.white.withAlphaComponent(0.2)
            gpsBars.forEach { $0.backgroundColor = UIColor.white.withAlphaComponent(0.1) }
        case .searching:
            gpsIcon.tintColor = .gray
            gpsLabel.text = "Searching..."
            gpsLabel.textColor = .gray
            gpsBars.forEach { $0.backgroundColor = UIColor.white.withAlphaComponent(0.15) }
        case .weak:
            gpsIcon.tintColor = .systemOrange
            gpsLabel.text = "GPS Weak"
            gpsLabel.textColor = .systemOrange
            gpsBars[0].backgroundColor = .systemOrange
            gpsBars[1].backgroundColor = UIColor.white.withAlphaComponent(0.15)
            gpsBars[2].backgroundColor = UIColor.white.withAlphaComponent(0.15)
        case .fair:
            gpsIcon.tintColor = DesignTokens.Color.accent
            gpsLabel.text = "GPS Fair"
            gpsLabel.textColor = DesignTokens.Color.accent
            gpsBars[0].backgroundColor = DesignTokens.Color.accent
            gpsBars[1].backgroundColor = DesignTokens.Color.accent
            gpsBars[2].backgroundColor = UIColor.white.withAlphaComponent(0.15)
        case .strong:
            gpsIcon.tintColor = .systemGreen
            gpsLabel.text = "GPS Strong"
            gpsLabel.textColor = .systemGreen
            gpsBars.forEach { $0.backgroundColor = .systemGreen }
        }
    }
}
