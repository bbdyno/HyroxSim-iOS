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
    private(set) var totalGoalText: String = "—"
    private(set) var totalDeltaText: String = "—"
    private(set) var isOverTotalGoal: Bool = false
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

    // 보간용: 마지막 수신 스냅샷의 기준 시각 / elapsed / goal raw.
    private var lastBroadcastedAt: Date?
    private var lastSegmentElapsedSeconds: TimeInterval?
    private var lastTotalElapsedSeconds: TimeInterval?
    private var lastSegmentGoalSeconds: TimeInterval?
    private var lastSegmentGoalActualBaseSeconds: TimeInterval?
    private var lastTotalGoalSeconds: TimeInterval?
    private var lastTotalGoalSoFarSeconds: TimeInterval?

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
        paceText = state.paceText
        distanceText = state.distanceText
        stationNameText = state.stationNameText
        stationTargetText = state.stationTargetText
        accentKindRaw = state.accentKindRaw
        isPaused = state.isPaused
        isFinished = state.isFinished
        isLastSegment = state.isLastSegment
        gpsStrong = state.gpsStrong
        gpsActive = state.gpsActive

        // 보간용 기준값 저장. 타임스탬프/elapsed/goal raw 있으면 interpolate 가 타이머·델타 전부 재계산.
        // 없으면 폰이 보낸 포맷 문자열을 그대로 사용 (하위 호환).
        lastBroadcastedAt = state.broadcastedAt
        lastSegmentElapsedSeconds = state.segmentElapsedSeconds
        lastTotalElapsedSeconds = state.totalElapsedSeconds
        lastSegmentGoalSeconds = state.segmentGoalSeconds
        lastSegmentGoalActualBaseSeconds = state.segmentGoalActualBaseSeconds
        lastTotalGoalSeconds = state.totalGoalSeconds
        lastTotalGoalSoFarSeconds = state.totalGoalSoFarSeconds

        if state.broadcastedAt == nil {
            segmentElapsedText = state.segmentElapsedText
            totalElapsedText = state.totalElapsedText
            goalText = state.goalText
            goalDeltaText = state.goalDeltaText
            isOverGoal = state.isOverGoal
            totalGoalText = "—"
            totalDeltaText = "—"
            isOverTotalGoal = false
        } else {
            interpolate(at: Date())
        }

        // 폰의 HR 텍스트 사용, 워치 자체 HR이 더 최신이면 덮어씀
        if state.heartRateText != "—" {
            heartRateText = state.heartRateText
            heartRateZone = state.heartRateZoneRaw.flatMap { HeartRateZone(rawValue: $0) }
        }

        if isOverGoal, alertedGoalSegmentIndex != state.currentSegmentIndex {
            alertedGoalSegmentIndex = state.currentSegmentIndex
            goalAlertHandler?()
        }
    }

    /// TimelineView 매 틱에서 호출. 마지막 스냅샷 기준 시각으로부터의 경과를 더해
    /// 타이머·세그먼트 델타·전체 델타 모두 로컬 클록으로 재계산 — 메시지 지연·드랍에 무관하게 정확.
    func interpolate(at now: Date) {
        guard
            let broadcastedAt = lastBroadcastedAt,
            let segSec = lastSegmentElapsedSeconds,
            let totalSec = lastTotalElapsedSeconds
        else { return }
        let offset = isPaused ? 0 : max(0, now.timeIntervalSince(broadcastedAt))
        let segElapsed = segSec + offset
        let totalElapsed = totalSec + offset
        segmentElapsedText = DurationFormatter.ms(segElapsed)
        totalElapsedText = DurationFormatter.hms(totalElapsed)

        if let goalSec = lastSegmentGoalSeconds {
            let actualBase = lastSegmentGoalActualBaseSeconds ?? 0
            let delta = (actualBase + segElapsed) - goalSec
            goalText = DurationFormatter.ms(goalSec)
            goalDeltaText = DurationFormatter.signedMs(delta)
            isOverGoal = delta >= 0
        } else {
            goalText = "—"
            goalDeltaText = "—"
            isOverGoal = false
        }

        if let totalGoalSec = lastTotalGoalSeconds, let goalSoFar = lastTotalGoalSoFarSeconds {
            let delta = totalElapsed - goalSoFar
            totalGoalText = DurationFormatter.hms(totalGoalSec)
            totalDeltaText = DurationFormatter.signedMs(delta)
            isOverTotalGoal = delta >= 0
        } else {
            totalGoalText = "—"
            totalDeltaText = "—"
            isOverTotalGoal = false
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

    func advance() { sendAdvance() }
    func togglePause() { sendTogglePause() }
    func endWorkout() { sendEnd() }
}
