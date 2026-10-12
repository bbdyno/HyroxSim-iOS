//
//  VoiceCue.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 구간이 바뀔 때 말로 알려 줄 내용. 문장은 앱이 언어별로 만든다.
public struct VoiceCue: Hashable, Sendable {

    public enum Pace: Hashable, Sendable {
        /// 목표보다 이만큼(초) 빨랐다.
        case ahead(seconds: Int)
        /// 목표보다 이만큼(초) 느렸다.
        case behind(seconds: Int)
        case onGoal
    }

    /// 방금 끝난 구간의 종류. 록스존은 따로 말하지 않는다.
    public let finishedType: SegmentType
    public let finishedStation: StationKind?
    /// 방금 끝난 구간의 기록(초, 반올림).
    public let finishedSeconds: Int
    /// 목표가 있었으면 그 대비.
    public let pace: Pace?
    /// 다음 구간. 운동이 끝났으면 nil.
    public let nextType: SegmentType?
    public let nextStation: StationKind?

    public init(
        finishedType: SegmentType, finishedStation: StationKind?, finishedSeconds: Int, pace: Pace?,
        nextType: SegmentType?, nextStation: StationKind?
    ) {
        self.finishedType = finishedType
        self.finishedStation = finishedStation
        self.finishedSeconds = finishedSeconds
        self.pace = pace
        self.nextType = nextType
        self.nextStation = nextStation
    }

    /// 목표와 이 정도 차이는 "목표대로" 라고 말한다.
    public static let onGoalToleranceSeconds = 2

    /// - Returns: 말할 것이 없으면 nil — 록스존에서 록스존으로 넘어갈 일은 없지만,
    ///   록스존이 끝날 때는 다음 구간만 알려 주면 되므로 기록은 0 으로 둔다.
    public static func make(
        finished: WorkoutSegment,
        finishedSeconds: TimeInterval,
        next: WorkoutSegment?
    ) -> VoiceCue {
        var pace: Pace?
        if let goal = finished.goalDurationSeconds, goal > 0, finished.type != .roxZone {
            let delta = Int((finishedSeconds - goal).rounded())
            if abs(delta) <= onGoalToleranceSeconds {
                pace = .onGoal
            } else {
                pace = delta < 0 ? .ahead(seconds: -delta) : .behind(seconds: delta)
            }
        }
        return VoiceCue(
            finishedType: finished.type,
            finishedStation: finished.stationKind,
            finishedSeconds: max(0, Int(finishedSeconds.rounded())),
            pace: pace,
            nextType: next?.type,
            nextStation: next?.stationKind
        )
    }
}
