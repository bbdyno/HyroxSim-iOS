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
        /// 다음 구간 이름 ("Wall Balls"). 마지막 구간이면 nil.
        /// 대회장에서는 지금 뭘 하는지보다 다음에 뭐가 오는지가 더 중요해서 함께 내보낸다.
        public let nextSegmentLabel: String?
        /// 다음 구간의 목표 시간 ("04:10"). 목표가 없으면 nil.
        public let nextSegmentGoal: String?

        public init(
            segmentLabel: String, segmentSubLabel: String?,
            segmentElapsed: String, totalElapsed: String,
            heartRate: String, accentKind: String,
            isPaused: Bool, isLastSegment: Bool,
            nextSegmentLabel: String? = nil, nextSegmentGoal: String? = nil
        ) {
            self.segmentLabel = segmentLabel
            self.segmentSubLabel = segmentSubLabel
            self.segmentElapsed = segmentElapsed
            self.totalElapsed = totalElapsed
            self.heartRate = heartRate
            self.accentKind = accentKind
            self.isPaused = isPaused
            self.isLastSegment = isLastSegment
            self.nextSegmentLabel = nextSegmentLabel
            self.nextSegmentGoal = nextSegmentGoal
        }

        /// 잠금화면/다이내믹 아일랜드에 한 줄로 찍는 다음 목표.
        /// 마지막 구간이면 nil — 다음이 없다는 뜻이라 자리를 비워 둔다.
        public var nextTargetText: String? {
            guard let nextSegmentLabel else { return nil }
            guard let nextSegmentGoal else { return nextSegmentLabel }
            return "\(nextSegmentLabel) · \(nextSegmentGoal)"
        }
    }
}

#if canImport(ActivityKit)
extension WorkoutActivityAttributes: ActivityAttributes {}
#endif
