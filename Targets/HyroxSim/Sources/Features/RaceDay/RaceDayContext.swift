//
//  RaceDayContext.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import Foundation
import HyroxCore

/// 레이스 데이 화면들이 공유하는 맥락.
///
/// 페이스 카드는 "어떤 코스를, 어떤 목표로" 뛰는지 알아야 하고, 체크리스트는
/// "어느 대회의" 체크 상태인지 알아야 한다. 둘 다 이 한 덩어리에서 나온다.
///
/// 등록된 대회가 없어도 동작한다 — 그때는 템플릿 목표가 곧 대회 목표다.
public struct RaceDayContext {

    public let template: WorkoutTemplate
    /// 등록된 가장 가까운 대회. 없으면 nil.
    public let raceTarget: RaceTarget?

    public init(template: WorkoutTemplate, raceTarget: RaceTarget?) {
        self.template = template
        self.raceTarget = raceTarget
    }

    /// 체크리스트 저장 키. 대회별로 체크 상태를 분리한다.
    public var checklistRaceKey: String {
        RaceDayChecklistStore.raceKey(for: raceTarget)
    }

    /// 카드 제목 — 대회 이름이 있으면 그쪽이 우선.
    public var title: String {
        raceTarget?.eventName ?? template.name
    }

    /// 카드 부제 — 디비전과 대회 날짜.
    public var subtitle: String? {
        var parts: [String] = []
        if let division = raceTarget?.division ?? template.division {
            parts.append(division.displayName)
        }
        if let date = raceTarget?.date {
            parts.append(Self.dateFormatter.string(from: date))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 대회까지 남은 일수. 등록된 대회가 없으면 nil.
    public func daysRemaining(asOf now: Date = Date()) -> Int? {
        raceTarget?.daysRemaining(asOf: now)
    }

    /// 이미 지나간 대회인지. 체크리스트 초기화를 권하는 근거가 된다.
    public func isPastRace(asOf now: Date = Date()) -> Bool {
        guard let raceTarget else { return false }
        return !raceTarget.isUpcoming(asOf: now)
    }

    /// 목표 완주 시간 — 대회 목표가 있으면 그 값, 없으면 템플릿 구간 목표의 합.
    public var goalSeconds: TimeInterval? {
        if let raceGoal = raceTarget?.goalDurationSeconds, raceGoal > 0 {
            return raceGoal
        }
        let templateGoal = template.segments.compactMap(\.goalDurationSeconds).reduce(0, +)
        return templateGoal > 0 ? templateGoal : nil
    }

    /// 이 맥락으로 만든 페이스 카드.
    /// 대회 목표가 따로 있으면 템플릿 구간 목표를 그 시간에 맞춰 비율 조정한다.
    public func makePaceCard() -> RacePaceCard {
        RacePaceCard.make(
            template: template,
            title: title,
            subtitle: subtitle,
            raceGoalSeconds: raceTarget?.goalDurationSeconds
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
