//
//  LiveWorkoutState.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// 운동이 시작된 기기
public enum WorkoutOrigin: String, Codable, Sendable {
    case phone
    case watch
}

/// 워치 → 폰 HR 릴레이 (폰 운동 시 워치가 HR 센서 역할)
public struct HeartRateRelay: Codable, Sendable {
    public let bpm: Int
    public let timestamp: Date

    public init(bpm: Int, timestamp: Date = Date()) {
        self.bpm = bpm
        self.timestamp = timestamp
    }
}

/// 양방향 실시간 전송되는 운동 상태 스냅샷.
/// 매 0.5초마다 WCSession.sendMessage로 전송.
public struct LiveWorkoutState: Codable, Sendable {
    // MARK: - 세그먼트 정보
    public let segmentLabel: String
    public let segmentSubLabel: String?
    public let currentDisplayTitle: String
    public let nextDisplayTitle: String?
    public let segmentElapsedText: String
    public let totalElapsedText: String

    // MARK: - 데이터
    public let paceText: String
    public let distanceText: String
    public let heartRateText: String
    public let heartRateZoneRaw: Int?  // HeartRateZone.rawValue
    public let goalText: String
    public let goalDeltaText: String
    public let isOverGoal: Bool

    // MARK: - 스테이션
    public let stationNameText: String?
    public let stationTargetText: String?

    // MARK: - 상태
    public let accentKindRaw: String  // "run" / "roxZone" / "station"
    public let isPaused: Bool
    public let isFinished: Bool
    public let isLastSegment: Bool

    // MARK: - GPS
    public let gpsStrong: Bool
    public let gpsActive: Bool

    // MARK: - 메타
    public let templateName: String
    public let totalSegmentCount: Int
    public let currentSegmentIndex: Int
    public let origin: WorkoutOrigin

    // MARK: - 보간용 타임스탬프 (수신측 로컬 클록 보간으로 메시지 지연 흡수)
    /// 송신측이 이 스냅샷을 찍은 시각. 수신측은 `Date().timeIntervalSince(broadcastedAt)` 만큼 더해 표시한다.
    public let broadcastedAt: Date?
    /// 스냅샷 시점의 현재 세그먼트 경과 초.
    public let segmentElapsedSeconds: TimeInterval?
    /// 스냅샷 시점의 전체 경과 초.
    public let totalElapsedSeconds: TimeInterval?

    public init(
        segmentLabel: String, segmentSubLabel: String?,
        currentDisplayTitle: String, nextDisplayTitle: String?,
        segmentElapsedText: String, totalElapsedText: String,
        paceText: String, distanceText: String,
        heartRateText: String, heartRateZoneRaw: Int?,
        goalText: String, goalDeltaText: String, isOverGoal: Bool,
        stationNameText: String?, stationTargetText: String?,
        accentKindRaw: String, isPaused: Bool, isFinished: Bool, isLastSegment: Bool,
        gpsStrong: Bool, gpsActive: Bool,
        templateName: String, totalSegmentCount: Int, currentSegmentIndex: Int,
        origin: WorkoutOrigin = .watch,
        broadcastedAt: Date? = nil,
        segmentElapsedSeconds: TimeInterval? = nil,
        totalElapsedSeconds: TimeInterval? = nil
    ) {
        self.segmentLabel = segmentLabel
        self.segmentSubLabel = segmentSubLabel
        self.currentDisplayTitle = currentDisplayTitle
        self.nextDisplayTitle = nextDisplayTitle
        self.segmentElapsedText = segmentElapsedText
        self.totalElapsedText = totalElapsedText
        self.paceText = paceText
        self.distanceText = distanceText
        self.heartRateText = heartRateText
        self.heartRateZoneRaw = heartRateZoneRaw
        self.goalText = goalText
        self.goalDeltaText = goalDeltaText
        self.isOverGoal = isOverGoal
        self.stationNameText = stationNameText
        self.stationTargetText = stationTargetText
        self.accentKindRaw = accentKindRaw
        self.isPaused = isPaused
        self.isFinished = isFinished
        self.isLastSegment = isLastSegment
        self.gpsStrong = gpsStrong
        self.gpsActive = gpsActive
        self.templateName = templateName
        self.totalSegmentCount = totalSegmentCount
        self.currentSegmentIndex = currentSegmentIndex
        self.origin = origin
        self.broadcastedAt = broadcastedAt
        self.segmentElapsedSeconds = segmentElapsedSeconds
        self.totalElapsedSeconds = totalElapsedSeconds
    }
}

/// 양방향 원격 명령 (폰 ↔ 워치)
public enum WorkoutCommand: String, Codable, Sendable {
    case advance
    case pause
    case resume
    case end
}

/// WCSession 메시지 dict 키
public enum LiveSyncKeys {
    public static let liveState = "liveWorkoutState"
    public static let command = "workoutCommand"
    public static let workoutStarted = "workoutStarted"
    public static let workoutFinished = "workoutFinished"
    public static let templateData = "templateData"
    public static let workoutOrigin = "workoutOrigin"
    public static let heartRateRelay = "heartRateRelay"
    /// 템플릿 즉시 동기화 (reachable 시 sendMessage 경로). transferUserInfo 와 병행.
    public static let templateSync = "templateSync"
    /// 완료 워크아웃 즉시 동기화 (reachable 시 sendMessage 경로). transferFile 과 병행.
    public static let completedWorkoutData = "completedWorkoutData"
}
