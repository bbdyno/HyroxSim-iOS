//
//  WorkoutDisplaying.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/18/26.
//

import Foundation
import HyroxCore

enum WorkoutDisplayAccent: String, Sendable {
    case run, roxZone, station
}

/// 워치 운동 화면이 공통으로 필요로 하는 표시/제어 계약.
/// WatchActiveWorkoutModel (자체 엔진) 과 PhoneMirrorWorkoutModel (폰 상태 미러)
/// 이 모두 채택해 동일한 레이아웃 뷰를 재사용할 수 있도록 한다.
@MainActor
protocol WorkoutDisplaying: AnyObject {
    var segmentElapsedText: String { get }
    var totalElapsedText: String { get }
    var currentDisplayTitle: String { get }
    var nextDisplayTitle: String? { get }
    var paceText: String { get }
    var stationTargetText: String? { get }
    var heartRateText: String { get }
    var heartRateZone: HeartRateZone? { get }

    var goalText: String { get }
    var goalDeltaText: String { get }
    var isOverGoal: Bool { get }

    var totalGoalText: String { get }
    var totalDeltaText: String { get }
    var isOverTotalGoal: Bool { get }

    var accent: WorkoutDisplayAccent { get }
    var isPaused: Bool { get }
    var isLastSegment: Bool { get }
    var isConnected: Bool { get }

    func advance()
    func togglePause()
    func endWorkout()
}
