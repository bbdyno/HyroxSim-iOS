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

    // MARK: - 레이스 데이

    /// 랩 카운터 페이지를 붙일 수 있는 모델인지.
    /// 폰 미러는 폰이 세는 값을 받아 쓰지 않으므로 false 로 둔다.
    var supportsLapCounter: Bool { get }
    /// 현재 구간에서 선수가 직접 센 바퀴 수.
    var lapCount: Int { get }
    /// 랩을 셀 수 있는 구간(런)인지.
    var isLapCounterAvailable: Bool { get }

    func incrementLap()
    func decrementLap()
    /// 크라운 회전처럼 값이 통째로 오는 입력용.
    func setLapCount(_ value: Int)

    func advance()
    func togglePause()
    func endWorkout()
}

/// 랩 카운터는 워치 자체 운동에서만 의미가 있어 기본 구현을 "없음"으로 둔다.
/// 미러 모델은 이 기본값을 그대로 쓴다.
extension WorkoutDisplaying {
    var supportsLapCounter: Bool { false }
    var lapCount: Int { 0 }
    var isLapCounterAvailable: Bool { false }

    func incrementLap() {}
    func decrementLap() {}
    func setLapCount(_ value: Int) {}
}
