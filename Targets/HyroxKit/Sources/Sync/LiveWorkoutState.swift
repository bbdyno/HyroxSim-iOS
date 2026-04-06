//
//  LiveWorkoutState.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// 워치 → 폰으로 실시간 전송되는 운동 상태 스냅샷.
/// 매 1초마다 WCSession.sendMessage로 전송.
public struct LiveWorkoutState: Codable, Sendable {
    // MARK: - 세그먼트 정보
    public let segmentLabel: String
    public let segmentSubLabel: String?
    public let segmentElapsedText: String
    public let totalElapsedText: String

    // MARK: - 데이터
    public let paceText: String
    public let distanceText: String
    public let heartRateText: String
    public let heartRateZoneRaw: Int?  // HeartRateZone.rawValue

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

    public init(
        segmentLabel: String, segmentSubLabel: String?,
        segmentElapsedText: String, totalElapsedText: String,
        paceText: String, distanceText: String,
        heartRateText: String, heartRateZoneRaw: Int?,
        stationNameText: String?, stationTargetText: String?,
        accentKindRaw: String, isPaused: Bool, isFinished: Bool, isLastSegment: Bool,
        gpsStrong: Bool, gpsActive: Bool,
        templateName: String, totalSegmentCount: Int, currentSegmentIndex: Int
    ) {
        self.segmentLabel = segmentLabel
        self.segmentSubLabel = segmentSubLabel
        self.segmentElapsedText = segmentElapsedText
        self.totalElapsedText = totalElapsedText
        self.paceText = paceText
        self.distanceText = distanceText
        self.heartRateText = heartRateText
        self.heartRateZoneRaw = heartRateZoneRaw
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
    }
}

/// 폰 → 워치로 보내는 원격 명령
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
}
