//
//  WorkoutActivityAttributes.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

/// Live Activity / Dynamic Island 용 운동 상태.
/// 앱과 위젯 확장이 공유하는 타입.
public struct WorkoutActivityAttributes {

    /// 운동 시작 시 고정되는 정보
    public let templateName: String
    public let totalSegments: Int

    public init(templateName: String, totalSegments: Int) {
        self.templateName = templateName
        self.totalSegments = totalSegments
    }

    /// 실시간으로 갱신되는 상태
    public struct ContentState: Codable, Hashable {
        public let segmentLabel: String       // "RUN 3/8", "STATION 5/8"
        public let segmentSubLabel: String?   // "SkiErg", "→ Sled Push"
        public let segmentElapsed: String     // "03:42"
        public let totalElapsed: String       // "28:14"
        public let heartRate: String          // "162" or "—"
        public let accentKind: String         // "run" / "roxZone" / "station"
        public let isPaused: Bool
        public let isLastSegment: Bool

        public init(
            segmentLabel: String, segmentSubLabel: String?,
            segmentElapsed: String, totalElapsed: String,
            heartRate: String, accentKind: String,
            isPaused: Bool, isLastSegment: Bool
        ) {
            self.segmentLabel = segmentLabel
            self.segmentSubLabel = segmentSubLabel
            self.segmentElapsed = segmentElapsed
            self.totalElapsed = totalElapsed
            self.heartRate = heartRate
            self.accentKind = accentKind
            self.isPaused = isPaused
            self.isLastSegment = isLastSegment
        }
    }
}

#if canImport(ActivityKit)
extension WorkoutActivityAttributes: ActivityAttributes {}
#endif
