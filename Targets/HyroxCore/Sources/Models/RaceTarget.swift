//
//  RaceTarget.swift
//  HyroxCore
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

/// 사용자가 준비 중인 실제 HYROX 대회 목표.
///
/// 레이스 준비 허브(다음 단계 UI)가 "D-30, 목표 1:25:00" 같은 화면을 그리는 근거이며,
/// 기록(`CompletedWorkout`)이나 템플릿(`WorkoutTemplate`)과 달리 운동 자체가 아니라
/// *일정*을 표현한다.
///
/// 날짜 계산은 전부 `Calendar` 를 주입받는다. 기기 시간대/달력 설정에 따라 D-day 가
/// 하루씩 어긋나는 문제를 테스트로 잡을 수 있어야 하기 때문이다.
public struct RaceTarget: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// 대회 이름 (예: "HYROX Seoul")
    public var eventName: String
    /// 개최 도시. 아직 모르면 nil.
    public var city: String?
    /// 대회 일시. 시각까지 알 수 없는 경우가 많아 D-day 계산은 "날짜" 단위로만 한다.
    public var date: Date
    /// 출전 예정 디비전. 미정이면 nil.
    public var division: HyroxDivision?
    /// 목표 완주 시간(초). 아직 목표를 정하지 않았으면 nil.
    public var goalDurationSeconds: TimeInterval?
    /// 자유 메모 (숙소, 동반 출전자, 준비물 등)
    public var note: String?
    public let createdAt: Date
    /// 마지막 수정 시각. 동기화 충돌 해소의 기준값으로 쓸 수 있도록 별도 보관한다.
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        eventName: String,
        city: String? = nil,
        date: Date,
        division: HyroxDivision? = nil,
        goalDurationSeconds: TimeInterval? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.eventName = eventName
        self.city = city
        self.date = date
        self.division = division
        self.goalDurationSeconds = goalDurationSeconds
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - 파생 값

    /// 대회까지 남은 일수. 대회 당일이면 `0`, 이미 지난 대회면 음수.
    ///
    /// 시/분/초는 무시하고 각 날짜의 자정을 기준으로 센다. 그래서 "오늘 아침에 끝난
    /// 대회"도 당일(`0`)로 계산되고, 이 규칙은 `isUpcoming(asOf:calendar:)` 와
    /// `PersistenceController.fetchUpcomingRaceTarget(now:calendar:)` 도 그대로 따른다.
    /// - Parameters:
    ///   - now: 기준 시각. 기본값은 현재 시각.
    ///   - calendar: 날짜 경계를 정하는 달력. 테스트에서는 고정 시간대 달력을 주입한다.
    public func daysRemaining(asOf now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let raceDay = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: raceDay).day ?? 0
    }

    /// 아직 치르지 않은 대회인지 여부. 대회 당일은 `true`.
    public func isUpcoming(asOf now: Date = Date(), calendar: Calendar = .current) -> Bool {
        daysRemaining(asOf: now, calendar: calendar) >= 0
    }
}
