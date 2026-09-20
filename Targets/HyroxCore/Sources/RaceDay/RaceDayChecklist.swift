//
//  RaceDayChecklist.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

/// 체크리스트 항목의 분류. 화면에서 섹션을 나누고 시각적으로 구분하는 기준이다.
public enum RaceDayChecklistCategory: String, Codable, CaseIterable, Hashable, Sendable {
    /// 공식 룰북에 근거가 있는 항목. 어기면 시간 페널티나 실격으로 이어진다.
    case rule
    /// 챙겨야 하는 장비.
    case gear
    /// 웨이브 시각 기준의 식사·수분·워밍업.
    case nutrition
}

/// 대회 당일 체크리스트의 한 항목.
///
/// `HyroxCore` 는 문자열 리소스를 갖지 않으므로 여기서는 *키* 와 영문 기본값만 노출하고,
/// 실제 문구는 앱 타겟(`HyroxSim`)의 `Localizable.strings` 가 갖는다.
/// (같은 방식: `TrainingSessionKind`)
public struct RaceDayChecklistItem: Identifiable, Hashable, Sendable {
    /// 저장에 쓰는 안정적인 키. 문구가 바뀌어도 체크 상태가 유지되도록 절대 바꾸지 않는다.
    public let id: String
    public let category: RaceDayChecklistCategory
    /// 지역화 문구가 없을 때 쓰는 영문 제목.
    public let defaultTitle: String
    /// 룰북 근거 한 줄. 룰 항목에만 있다.
    public let defaultEvidence: String?
    /// 위반 시 대가를 나타내는 짧은 배지 ("DNS", "DQ", "+0:15"). 숫자·약어라 지역화하지 않는다.
    public let penaltyBadge: String?

    public init(
        id: String,
        category: RaceDayChecklistCategory,
        defaultTitle: String,
        defaultEvidence: String? = nil,
        penaltyBadge: String? = nil
    ) {
        self.id = id
        self.category = category
        self.defaultTitle = defaultTitle
        self.defaultEvidence = defaultEvidence
        self.penaltyBadge = penaltyBadge
    }

    /// `Localizable.strings` 의 제목 키.
    public var titleLocalizationKey: String { "race_day.checklist.\(id).title" }

    /// `Localizable.strings` 의 근거 문구 키. 근거가 없는 항목은 nil.
    public var evidenceLocalizationKey: String? {
        defaultEvidence == nil ? nil : "race_day.checklist.\(id).evidence"
    }
}

/// 대회 당일 체크리스트 카탈로그.
///
/// 룰 항목의 근거는 HYROX 26/27 시즌 룰북에서 확인한 내용이다. 표현은 줄였지만
/// "무엇을 어기면 무엇을 잃는지"는 그대로 남겨 대회장에서 판단할 수 있게 했다.
public enum RaceDayChecklist {

    /// 룰북 근거가 있는 항목 (8개). 순서는 대회 흐름 순 — 등록 → 출발 → 코스 → 스테이션.
    public static let rules: [RaceDayChecklistItem] = [
        RaceDayChecklistItem(
            id: "chip_ankle",
            category: .rule,
            defaultTitle: "Timing chip strapped to your ankle",
            defaultEvidence: "Rulebook: the chip is worn on the ankle. No chip at the start means DNS.",
            penaltyBadge: "DNS"
        ),
        RaceDayChecklistItem(
            id: "assigned_wave",
            category: .rule,
            defaultTitle: "Start only in your assigned wave",
            defaultEvidence: "Rulebook: starting in a wave you were not assigned to is a disqualification.",
            penaltyBadge: "DQ"
        ),
        RaceDayChecklistItem(
            id: "count_laps",
            category: .rule,
            defaultTitle: "Count your own run laps",
            defaultEvidence: "Rulebook: lap counting is the athlete's job. A missed run lap costs 3, 5 or 7 minutes, or the race.",
            penaltyBadge: "+3:00~"
        ),
        RaceDayChecklistItem(
            id: "finish_every_station",
            category: .rule,
            defaultTitle: "Finish every station in full",
            defaultEvidence: "Rulebook: an unfinished station is a disqualification, not a time penalty.",
            penaltyBadge: "DQ"
        ),
        RaceDayChecklistItem(
            id: "sandbag_shoulder",
            category: .rule,
            defaultTitle: "Keep the sandbag on your shoulders",
            defaultEvidence: "Rulebook: every time the sandbag drops off the shoulders costs 15 seconds.",
            penaltyBadge: "+0:15"
        ),
        RaceDayChecklistItem(
            id: "event_chalk_only",
            category: .rule,
            defaultTitle: "Use the chalk provided at the venue",
            defaultEvidence: "Rulebook: only event-supplied chalk is allowed. Your own chalk costs 2 minutes.",
            penaltyBadge: "+2:00"
        ),
        RaceDayChecklistItem(
            id: "no_pouring_drinks",
            category: .rule,
            defaultTitle: "Never pour a drink over your body",
            defaultEvidence: "Rulebook: pouring any drink over yourself costs 2 minutes.",
            penaltyBadge: "+2:00"
        ),
        RaceDayChecklistItem(
            id: "fast_lane",
            category: .rule,
            defaultTitle: "Move to the Fast Lane under 4:00/km",
            defaultEvidence: "Rulebook: runs at 4:00/km or faster belong in the Fast Lane.",
            penaltyBadge: "FAST LANE"
        )
    ]

    /// 장비 항목. 룰 항목과 달리 근거 줄이 없고, 화면에서도 다른 스타일로 그린다.
    public static let gear: [RaceDayChecklistItem] = [
        RaceDayChecklistItem(id: "bib_front", category: .gear, defaultTitle: "Bib pinned on the front, fully visible"),
        RaceDayChecklistItem(id: "shoes_laced", category: .gear, defaultTitle: "Race shoes on, laces double-knotted"),
        RaceDayChecklistItem(id: "grips_ready", category: .gear, defaultTitle: "Gloves or grips packed for sled and carry"),
        RaceDayChecklistItem(id: "bag_drop", category: .gear, defaultTitle: "Change of clothes and towel in bag drop"),
        RaceDayChecklistItem(id: "devices_charged", category: .gear, defaultTitle: "Watch and phone charged, race template loaded")
    ]

    /// 영양·워밍업 항목. 기준 시각은 전부 배정된 웨이브 시각이다.
    public static let nutrition: [RaceDayChecklistItem] = [
        RaceDayChecklistItem(id: "main_meal", category: .nutrition, defaultTitle: "Main meal 3 hours before your wave"),
        RaceDayChecklistItem(id: "light_carbs", category: .nutrition, defaultTitle: "Light carbs 60 minutes before"),
        RaceDayChecklistItem(id: "hydration", category: .nutrition, defaultTitle: "500 ml of water across the last 2 hours"),
        RaceDayChecklistItem(id: "caffeine", category: .nutrition, defaultTitle: "Caffeine timed 45 minutes before the start"),
        RaceDayChecklistItem(id: "warm_up", category: .nutrition, defaultTitle: "Warm-up starts 30 minutes before your wave")
    ]

    /// 전체 항목 — 룰 → 장비 → 영양 순.
    public static let all: [RaceDayChecklistItem] = rules + gear + nutrition

    /// 저장된 체크 상태를 거를 때 쓰는 유효 ID 집합.
    public static let allIds: Set<String> = Set(all.map(\.id))

    public static func items(in category: RaceDayChecklistCategory) -> [RaceDayChecklistItem] {
        switch category {
        case .rule: return rules
        case .gear: return gear
        case .nutrition: return nutrition
        }
    }
}
