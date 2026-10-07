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
    /// 폰 상태가 오래 끊긴 상태. 미러에서 빠져나갈 수 있는 버튼 노출 조건.
    private(set) var isStale: Bool = false

    // 보간용: 마지막 수신 스냅샷의 기준 시각 / elapsed / goal raw.
    private var lastBroadcastedAt: Date?
    private var lastSegmentElapsedSeconds: TimeInterval?
    private var lastTotalElapsedSeconds: TimeInterval?
    private var lastSegmentGoalSeconds: TimeInterval?
    private var lastSegmentGoalActualBaseSeconds: TimeInterval?
    private var lastTotalGoalSeconds: TimeInterval?
    private var lastTotalGoalSoFarSeconds: TimeInterval?

    /// 폰 상태 무수신을 "끊김"으로 판단하는 기준. 폰이 종료 신호를 못 보낸 경우의 탈출 경로.
    private static let staleThreshold: TimeInterval = 45

    let templateName: String
    private let syncCoordinator: any SyncCoordinator
    private let maxHeartRate: Int
    private let createdAt = Date()
    private var workoutSession: WatchWorkoutSession?
    private var hrRelayTask: Task<Void, Never>?
    private var alertedGoalSegmentIndex: Int?
    var goalAlertHandler: (() -> Void)?
    /// 미러 종료 요청 — 폰 완료 상태 수신 또는 사용자가 직접 닫았을 때.
    var onFinished: (() -> Void)?

    init(templateName: String, syncCoordinator: any SyncCoordinator, maxHeartRate: Int = 190) {
        self.templateName = templateName
        self.syncCoordinator = syncCoordinator
        self.maxHeartRate = maxHeartRate
    }

    /// 폰에서 수신한 LiveWorkoutState 반영
    func updateState(_ state: LiveWorkoutState) {
        lastStateReceivedAt = Date()
        isStale = false
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

        // 폰이 보내는 종료 메시지를 놓쳐도 마지막 상태의 isFinished 로 미러를 닫는다.
        if state.isFinished {
            closeMirror()
        }
    }

    /// HR 릴레이 세션을 정리하고 미러 화면을 닫는다.
    func closeMirror() {
        stopHRSession()
        onFinished?()
    }

    /// TimelineView 매 틱에서 호출. 마지막 스냅샷 기준 시각으로부터의 경과를 더해
    /// 타이머·세그먼트 델타·전체 델타 모두 로컬 클록으로 재계산 — 메시지 지연·드랍에 무관하게 정확.
    func interpolate(at now: Date) {
        updateStaleness(at: now)
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

    /// 폰 상태가 일정 시간 이상 끊기면 사용자가 직접 미러를 닫을 수 있게 한다.
    /// 폰 앱 종료·블루투스 끊김이면 종료 메시지도 원격 명령도 도달하지 않기 때문.
    private func updateStaleness(at now: Date) {
        let last = lastStateReceivedAt ?? createdAt
        isStale = now.timeIntervalSince(last) > Self.staleThreshold
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
