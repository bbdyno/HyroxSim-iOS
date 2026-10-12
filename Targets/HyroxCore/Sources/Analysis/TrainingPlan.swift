//
//  TrainingPlan.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 대회까지 남은 기간에서 한 주가 맡는 역할.
public enum TrainingPhase: String, Hashable, Sendable, CaseIterable {
    /// 9주 이상 남음. 스테이션 기술과 피로 상태 러닝의 기초.
    case base
    /// 4~8주. 절반 시뮬레이션으로 대회 볼륨에 익숙해진다.
    case build
    /// 2~3주. 풀 시뮬레이션으로 대회를 그대로 연습한다.
    case peak
    /// 1주. 양을 줄이고 날카로움만 유지한다.
    case taper
    /// 대회가 있는 주.
    case raceWeek

    public static func phase(weeksToRace: Int) -> TrainingPhase {
        switch weeksToRace {
        case ..<1: return .raceWeek
        case 1: return .taper
        case 2...3: return .peak
        case 4...8: return .build
        default: return .base
        }
    }
}

/// 계획에 들어가는 한 번의 훈련. 전부 앱에서 바로 시작할 수 있는 것들이다.
public enum TrainingPlanItem: Hashable, Sendable {
    /// 공식 코스 전체 (디비전 프리셋).
    case fullSimulation
    case session(TrainingSessionKind)
    /// 대회 당일.
    case race
}

public struct TrainingPlanWeek: Hashable, Sendable, Identifiable {
    /// 0 = 이번 주.
    public let index: Int
    /// 대회가 있는 주까지 남은 주 수. 0 = 대회 주.
    public let weeksToRace: Int
    /// 이 주의 첫날.
    public let startDate: Date
    public let phase: TrainingPhase
    public let items: [TrainingPlanItem]

    public var id: Int { index }
}

public struct TrainingPlan: Hashable, Sendable {
    public let raceDate: Date
    public let weeks: [TrainingPlanWeek]
    /// 계획에 다 담지 못할 만큼 대회가 멀어서 앞부분만 보여 주는지.
    public let isTruncated: Bool

    public var currentWeek: TrainingPlanWeek? { weeks.first }
}

/// 대회 날짜에서 거꾸로 세어 주간 계획을 만든다.
///
/// 규칙은 단순하고 고정이다. 주 3회, 단계마다 정해진 조합이고, 약점이 있으면 그 주의
/// 스테이션 훈련을 약점에 맞는 것으로 바꾼다. 풀 시뮬레이션은 대회 2~3주 전에만 넣는다 —
/// 대회 직전 주의 풀 시뮬레이션은 회복이 안 된 채 출전하게 만든다.
public enum TrainingPlanBuilder {

    /// 한 번에 보여 주는 최대 주 수.
    public static let maxWeeks = 16

    /// - Parameters:
    ///   - weaknesses: 약점 진단에서 손실이 큰 순. 없으면 기본 조합을 쓴다.
    /// - Returns: 대회가 이미 지났으면 nil.
    public static func build(
        raceDate: Date,
        today: Date = Date(),
        weaknesses: [WeaknessItem.Kind] = [],
        calendar: Calendar = .current
    ) -> TrainingPlan? {
        let startOfToday = calendar.startOfDay(for: today)
        let startOfRace = calendar.startOfDay(for: raceDate)
        guard startOfRace >= startOfToday else { return nil }

        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: startOfToday)?.start,
              let raceWeek = calendar.dateInterval(of: .weekOfYear, for: startOfRace)?.start else { return nil }
        let totalWeeks = (calendar.dateComponents([.weekOfYear], from: thisWeek, to: raceWeek).weekOfYear ?? 0)
        let weeksShown = min(totalWeeks, maxWeeks - 1)

        let wallBallsAreWeak = weaknesses.prefix(3).contains(.station(.wallBalls))
        let runningIsWeak = weaknesses.first == .running

        var weeks: [TrainingPlanWeek] = []
        for index in 0...weeksShown {
            let weeksToRace = totalWeeks - index
            let phase = TrainingPhase.phase(weeksToRace: weeksToRace)
            let start = calendar.date(byAdding: .weekOfYear, value: index, to: thisWeek) ?? thisWeek
            weeks.append(TrainingPlanWeek(
                index: index,
                weeksToRace: weeksToRace,
                startDate: start,
                phase: phase,
                items: items(
                    phase: phase, weeksToRace: weeksToRace,
                    wallBallsAreWeak: wallBallsAreWeak, runningIsWeak: runningIsWeak
                )
            ))
        }
        return TrainingPlan(raceDate: raceDate, weeks: weeks, isTruncated: totalWeeks > weeksShown)
    }

    private static func items(
        phase: TrainingPhase, weeksToRace: Int, wallBallsAreWeak: Bool, runningIsWeak: Bool
    ) -> [TrainingPlanItem] {
        // 스테이션 훈련 자리. 월볼이 약점이면 월볼 사다리로, 아니면 격주로 번갈아.
        let stationWork: TrainingPlanItem =
            (wallBallsAreWeak || weeksToRace % 2 == 0) ? .session(.wallBallLadder) : .session(.stationIntervals)
        // 전환 드릴 자리. 러닝이 가장 큰 약점이면 피로 상태 러닝을 한 번 더.
        let transition: TrainingPlanItem = runningIsWeak ? .session(.compromisedRun) : .session(.roxZoneDrill)

        switch phase {
        case .base:
            // 4주에 한 번은 체력 테스트로 현재 위치를 잰다.
            let third: TrainingPlanItem = weeksToRace % 4 == 0 ? .session(.pftBenchmark) : transition
            return [.session(.compromisedRun), .session(.stationIntervals), third]
        case .build:
            return [.session(.halfSimulation), .session(.compromisedRun), stationWork]
        case .peak:
            return weeksToRace == 3
                ? [.fullSimulation, .session(.compromisedRun), stationWork]
                : [.fullSimulation, .session(.roxZoneDrill)]
        case .taper:
            return [.session(.halfSimulation), .session(.roxZoneDrill)]
        case .raceWeek:
            return [.session(.roxZoneDrill), .race]
        }
    }
}
