//
//  SeasonReport.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 한 해의 훈련과 대회를 요약한 값.
public struct SeasonReport: Hashable, Sendable {

    public struct BestRace: Hashable, Sendable {
        public let name: String
        public let date: Date
        public let seconds: Double
        /// 실제 대회 기록이면 `true`, 앱에서 한 풀 시뮬레이션이면 `false`.
        public let isOfficial: Bool
    }

    public let year: Int
    /// 앱에서 완료한 운동 수.
    public let sessionCount: Int
    /// 그중 공식 코스를 끝까지 달린 횟수.
    public let fullSimulationCount: Int
    /// 보관함에 넣은 실제 대회 수.
    public let raceCount: Int
    /// 일시정지를 뺀 운동 시간 합(초).
    public let activeSeconds: Double
    /// 계획 거리 기준 러닝 합(미터).
    public let runningMeters: Double
    /// 수행한 스테이션 수.
    public let stationCount: Int
    /// 운동을 한 날이 있는 주의 수.
    public let activeWeeks: Int
    /// 연속으로 운동한 주의 최장 길이.
    public let longestWeekStreak: Int
    /// 운동이 가장 많았던 달(1...12). 운동이 없으면 nil.
    public let busiestMonth: Int?
    /// 그해 가장 빠른 완주 기록 (대회 + 풀 시뮬레이션).
    public let best: BestRace?
    /// 그해 첫 완주 기록 대비 가장 빠른 기록이 얼마나 줄었는지(초). 완주가 2번 미만이면 nil.
    public let improvementSeconds: Double?

    public var isEmpty: Bool { sessionCount == 0 && raceCount == 0 }
}

public enum SeasonReportBuilder {

    /// 기록이 있는 해 목록 (최근이 앞).
    public static func years(
        workouts: [CompletedWorkout], races: [RaceResult], calendar: Calendar = .current
    ) -> [Int] {
        let all = workouts.map(\.finishedAt) + races.map(\.date)
        return Array(Set(all.map { calendar.component(.year, from: $0) })).sorted(by: >)
    }

    public static func build(
        year: Int,
        workouts: [CompletedWorkout],
        races: [RaceResult],
        calendar: Calendar = .current
    ) -> SeasonReport {
        let sessions = workouts.filter { calendar.component(.year, from: $0.finishedAt) == year }
        let yearRaces = races.filter { calendar.component(.year, from: $0.date) == year }
        let simulations = sessions.filter(\.isStandardHyroxCourse)

        let running = sessions.reduce(0.0) { sum, workout in
            sum + workout.runSegments.reduce(0.0) { $0 + ($1.plannedDistanceMeters ?? 0) }
        }

        // 주 단위 꾸준함.
        var weekStarts = Set<Date>()
        for workout in sessions {
            if let start = calendar.dateInterval(of: .weekOfYear, for: workout.finishedAt)?.start {
                weekStarts.insert(start)
            }
        }
        var longest = 0, current = 0
        var previous: Date?
        for week in weekStarts.sorted() {
            if let previous, let next = calendar.date(byAdding: .weekOfYear, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: week) {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = week
        }

        var perMonth: [Int: Int] = [:]
        for workout in sessions { perMonth[calendar.component(.month, from: workout.finishedAt), default: 0] += 1 }
        // 같은 횟수면 이른 달.
        let busiest = perMonth.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key

        // 완주 기록: 대회와 풀 시뮬레이션을 날짜순으로.
        var finishes: [SeasonReport.BestRace] = simulations.map {
            .init(name: $0.templateName, date: $0.finishedAt, seconds: $0.totalActiveDuration, isOfficial: false)
        }
        finishes += yearRaces.map {
            .init(name: $0.eventName, date: $0.date, seconds: Double($0.totalSeconds), isOfficial: true)
        }
        finishes = finishes.filter { $0.seconds > 0 }.sorted { $0.date < $1.date }
        let best = finishes.min { $0.seconds < $1.seconds }
        var improvement: Double?
        if finishes.count >= 2, let first = finishes.first, let best, first.seconds > best.seconds {
            improvement = first.seconds - best.seconds
        }

        return SeasonReport(
            year: year,
            sessionCount: sessions.count,
            fullSimulationCount: simulations.count,
            raceCount: yearRaces.count,
            activeSeconds: sessions.reduce(0) { $0 + $1.totalActiveDuration },
            runningMeters: running,
            stationCount: sessions.reduce(0) { $0 + $1.stationSegments.count },
            activeWeeks: weekStarts.count,
            longestWeekStreak: longest,
            busiestMonth: busiest,
            best: best,
            improvementSeconds: improvement
        )
    }
}
