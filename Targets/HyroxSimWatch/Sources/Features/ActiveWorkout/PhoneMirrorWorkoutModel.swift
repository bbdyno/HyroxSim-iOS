//
//  PhoneMirrorWorkoutModel.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/8/26.
//

import Foundation
import Observation
import HyroxCore

/// 폰에서 시작된 운동을 워치에서 미러링하는 모델.
/// 폰의 LiveWorkoutState를 수신하여 표시하고, 워치의 HR 센서를 폰에 릴레이한다.
@Observable
@MainActor
final class PhoneMirrorWorkoutModel {

    // MARK: - UI State (폰 LiveWorkoutState에서 받음)
    private(set) var segmentLabel: String = ""
    private(set) var segmentSubLabel: String?
    private(set) var currentDisplayTitle: String = ""
    private(set) var nextDisplayTitle: String?
    private(set) var segmentElapsedText: String = "00:00"
    private(set) var totalElapsedText: String = "0:00:00"
    private(set) var paceText: String = "—"
    private(set) var distanceText: String = "0 m"
    private(set) var heartRateText: String = "—"
    private(set) var heartRateZone: HeartRateZone?
    private(set) var goalText: String = "—"
    private(set) var goalDeltaText: String = "—"
    private(set) var isOverGoal: Bool = false
    private(set) var stationNameText: String?
    private(set) var stationTargetText: String?
    private(set) var accentKindRaw: String = "run"
    private(set) var isPaused: Bool = false
    private(set) var isFinished: Bool = false
    private(set) var isLastSegment: Bool = false
    private(set) var gpsStrong: Bool = false
    private(set) var gpsActive: Bool = true
    private(set) var isConnected: Bool = true
    private(set) var lastStateReceivedAt: Date?

    let templateName: String
    private let syncCoordinator: any SyncCoordinator
    private let maxHeartRate: Int
    private var workoutSession: WatchWorkoutSession?
    private var hrRelayTask: Task<Void, Never>?
    private var alertedGoalSegmentIndex: Int?
    var goalAlertHandler: (() -> Void)?

    init(templateName: String, syncCoordinator: any SyncCoordinator, maxHeartRate: Int = 190) {
        self.templateName = templateName
        self.syncCoordinator = syncCoordinator
        self.maxHeartRate = maxHeartRate
    }

    /// 폰에서 수신한 LiveWorkoutState 반영
    func updateState(_ state: LiveWorkoutState) {
        lastStateReceivedAt = Date()
        segmentLabel = state.segmentLabel
        segmentSubLabel = state.segmentSubLabel
        currentDisplayTitle = state.currentDisplayTitle
        nextDisplayTitle = state.nextDisplayTitle
        segmentElapsedText = state.segmentElapsedText
        totalElapsedText = state.totalElapsedText
        paceText = state.paceText
        distanceText = state.distanceText
        goalText = state.goalText
        goalDeltaText = state.goalDeltaText
        isOverGoal = state.isOverGoal
        stationNameText = state.stationNameText
        stationTargetText = state.stationTargetText
        accentKindRaw = state.accentKindRaw
        isPaused = state.isPaused
        isFinished = state.isFinished
        isLastSegment = state.isLastSegment
        gpsStrong = state.gpsStrong
        gpsActive = state.gpsActive

        // 폰의 HR 텍스트 사용, 워치 자체 HR이 더 최신이면 덮어씀
        if state.heartRateText != "—" {
            heartRateText = state.heartRateText
            heartRateZone = state.heartRateZoneRaw.flatMap { HeartRateZone(rawValue: $0) }
        }

        if state.isOverGoal, alertedGoalSegmentIndex != state.currentSegmentIndex {
            alertedGoalSegmentIndex = state.currentSegmentIndex
            goalAlertHandler?()
        }
    }

    // MARK: - HR Session (워치 HR → 폰 릴레이)

    func startHRSession() async {
        let session = WatchWorkoutSession()
        self.workoutSession = session
        do {
            try await session.start()
            hrRelayTask = Task { [weak self] in
                for await sample in session.samples {
                    guard !Task.isCancelled else { break }
                    let relay = HeartRateRelay(bpm: sample.bpm, timestamp: sample.timestamp)
                    await MainActor.run {
                        self?.syncCoordinator.sendHeartRateRelay(relay)
                        // 워치 자체 HR 업데이트
                        self?.heartRateText = "\(sample.bpm)"
                        self?.heartRateZone = HeartRateZone.zone(
                            forHeartRate: sample.bpm, maxHeartRate: self?.maxHeartRate ?? 190
                        )
                    }
                }
            }
        } catch {
            print("[PhoneMirror] HR session start failed: \(error)")
        }
    }

    func stopHRSession() {
        hrRelayTask?.cancel()
        hrRelayTask = nil
        workoutSession?.stop()
        workoutSession = nil
    }

    // MARK: - Remote Commands (워치 → 폰)

    func sendAdvance() { syncCoordinator.sendCommand(.advance) }
    func sendTogglePause() { syncCoordinator.sendCommand(isPaused ? .resume : .pause) }
    func sendEnd() { syncCoordinator.sendCommand(.end) }

    func setConnected(_ connected: Bool) { isConnected = connected }
}

// MARK: - WorkoutDisplaying

extension PhoneMirrorWorkoutModel: WorkoutDisplaying {
    var accent: WorkoutDisplayAccent {
        WorkoutDisplayAccent(rawValue: accentKindRaw) ?? .run
    }

    // 폰에서 totalGoal 델타는 아직 전송 안 함 — 생략 표시.
    var totalGoalText: String { "—" }
    var totalDeltaText: String { "—" }
    var isOverTotalGoal: Bool { false }

    func advance() { sendAdvance() }
    func togglePause() { sendTogglePause() }
    func endWorkout() { sendEnd() }
}
