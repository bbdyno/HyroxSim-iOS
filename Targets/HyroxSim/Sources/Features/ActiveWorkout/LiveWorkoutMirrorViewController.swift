//
//  LiveWorkoutMirrorViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxKit

/// 워치에서 진행 중인 운동을 폰에서 실시간으로 보여주는 미러 화면.
/// 워치의 LiveWorkoutState를 받아 표시하고, 원격 명령을 보낼 수 있다.
@MainActor
protocol LiveWorkoutMirrorDelegate: AnyObject {
    func mirrorDidClose()
    func mirrorSendCommand(_ command: WorkoutCommand)
}

final class LiveWorkoutMirrorViewController: UIViewController {

    weak var delegate: LiveWorkoutMirrorDelegate?

    private let headerLabel = UILabel()
    private let subHeaderLabel = UILabel()
    private let segmentMetric = MetricView()
    private let totalMetric = MetricView()
    private let paceMetric = MetricView()
    private let stationNameMetric = MetricView()
    private let stationTargetMetric = MetricView()
    private let heartMetric = MetricView()
    private let gpsLabel = UILabel()
    private let nextButton = UIButton(type: .system)
    private let pauseButton = UIButton(type: .system)
    private let endButton = UIButton(type: .system)
    private let watchBadge = UILabel()

    private var lastState: LiveWorkoutState?

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
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

    /// 워치에서 수신한 실시간 상태를 반영
    func updateState(_ state: LiveWorkoutState) {
        lastState = state

        headerLabel.text = state.segmentLabel
        subHeaderLabel.text = state.segmentSubLabel
        subHeaderLabel.isHidden = state.segmentSubLabel == nil

        segmentMetric.setValue(state.segmentElapsedText, caption: "SEGMENT")
        totalMetric.setValue(state.totalElapsedText, caption: "TOTAL")

        let isStation = state.accentKindRaw == "station"
        if isStation {
            stationNameMetric.setValue(state.stationNameText ?? "—", caption: "STATION")
            stationTargetMetric.setValue(state.stationTargetText ?? "—", caption: "TARGET")
        } else {
            paceMetric.setValue(state.paceText, caption: "PACE")
        }
        paceMetric.isHidden = isStation
        stationNameMetric.superview?.isHidden = !isStation

        heartMetric.setValue("\(state.heartRateText) ♥", caption: "HEART")
        if let zoneRaw = state.heartRateZoneRaw, let zone = HeartRateZone(rawValue: zoneRaw) {
            heartMetric.setValueColor(colorFor(zone: zone))
        } else {
            heartMetric.setValueColor(.white)
        }

        // Accent color on header
        switch state.accentKindRaw {
        case "run": headerLabel.textColor = DesignTokens.Color.runAccent
        case "roxZone": headerLabel.textColor = DesignTokens.Color.roxZoneAccent
        default: headerLabel.textColor = DesignTokens.Color.accent
        }

        // GPS
        if !state.gpsActive {
            gpsLabel.text = "📍 GPS OFF"
            gpsLabel.textColor = UIColor.white.withAlphaComponent(0.2)
        } else if state.gpsStrong {
            gpsLabel.text = "📍 GPS ●●●"
            gpsLabel.textColor = .systemGreen
        } else {
            gpsLabel.text = "📍 GPS ●○○"
            gpsLabel.textColor = .systemOrange
        }

        // Buttons
        nextButton.setTitle(state.isLastSegment ? "FINISH ✓" : "NEXT ▶", for: .normal)
        pauseButton.setImage(UIImage(systemName: state.isPaused ? "play.fill" : "pause.fill"), for: .normal)

        if state.isFinished {
            delegate?.mirrorDidClose()
        }
    }

    func showDisconnected() {
        headerLabel.text = "WATCH DISCONNECTED"
        headerLabel.textColor = .systemRed
    }

    // MARK: - UI

    private func setupUI() {
        // Watch badge
        watchBadge.text = "⌚ LIVE FROM APPLE WATCH"
        watchBadge.font = .systemFont(ofSize: 10, weight: .bold)
        watchBadge.textColor = DesignTokens.Color.accent
        watchBadge.textAlignment = .center

        gpsLabel.font = .systemFont(ofSize: 10, weight: .medium)
        gpsLabel.textColor = .gray
        gpsLabel.textAlignment = .center

        headerLabel.font = .systemFont(ofSize: 16, weight: .bold)
        headerLabel.textColor = DesignTokens.Color.accent
        headerLabel.textAlignment = .center

        subHeaderLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subHeaderLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        subHeaderLabel.textAlignment = .center
        subHeaderLabel.isHidden = true

        segmentMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 64, weight: .bold)
        totalMetric.valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        totalMetric.valueLabel.textColor = UIColor.white.withAlphaComponent(0.6)

        let row2Station = UIStackView(arrangedSubviews: [stationNameMetric, stationTargetMetric])
        row2Station.distribution = .fillEqually; row2Station.spacing = 16

        let mainStack = UIStackView(arrangedSubviews: [
            watchBadge, gpsLabel, headerLabel, subHeaderLabel,
            segmentMetric, totalMetric,
            paceMetric, row2Station, heartMetric
        ])
        mainStack.axis = .vertical
        mainStack.alignment = .fill
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    private func setupButtons() {
        let margin: CGFloat = 24

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

        let btnSize: CGFloat = 50
        for btn in [pauseButton, endButton] {
            btn.tintColor = .white
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.layer.cornerRadius = btnSize / 2
            btn.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            view.addSubview(btn)
            btn.widthAnchor.constraint(equalToConstant: btnSize).isActive = true
            btn.heightAnchor.constraint(equalToConstant: btnSize).isActive = true
        }

        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            pauseButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            pauseButton.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -16)
        ])

        endButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            endButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            endButton.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -16)
        ])
    }

    @objc private func nextTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        delegate?.mirrorSendCommand(.advance)
    }

    @objc private func pauseTapped() {
        let cmd: WorkoutCommand = (lastState?.isPaused == true) ? .resume : .pause
        delegate?.mirrorSendCommand(cmd)
    }

    @objc private func endTapped() {
        let alert = DarkAlertController(title: "워치 운동 종료?", message: "워치에서 진행 중인 운동이 종료됩니다.")
        alert.addAction(.init(title: "취소", style: .cancel, handler: nil))
        alert.addAction(.init(title: "종료", style: .destructive, handler: { [weak self] in
            self?.delegate?.mirrorSendCommand(.end)
        }))
        present(alert, animated: true)
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
