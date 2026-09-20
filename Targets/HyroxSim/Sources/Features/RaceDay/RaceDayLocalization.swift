//
//  RaceDayLocalization.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import Foundation
import HyroxCore

/// 레이스 데이 문구를 앱 번들에서 읽는다.
///
/// 체크리스트 항목은 `HyroxCore` 가 *키* 만 들고 있어 SwiftGen 접근자를 쓸 수 없다.
/// 화면 문구까지 같은 경로로 읽어 두면 항목이 늘어나도 규칙이 하나로 유지된다.
/// 문구를 못 찾으면 영문 기본값으로 떨어진다. (같은 방식: `TrainingSessionLocalization`)
enum RaceDayLocalization {

    // MARK: - 원시 접근

    static func string(_ key: String, fallback: String) -> String {
        Bundle.module.localizedString(forKey: key, value: fallback, table: "Localizable")
    }

    static func format(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        String(format: string(key, fallback: fallback), locale: Locale.current, arguments: arguments)
    }

    // MARK: - 체크리스트 항목

    static func title(for item: RaceDayChecklistItem) -> String {
        string(item.titleLocalizationKey, fallback: item.defaultTitle)
    }

    static func evidence(for item: RaceDayChecklistItem) -> String? {
        guard let key = item.evidenceLocalizationKey, let fallback = item.defaultEvidence else {
            return nil
        }
        return string(key, fallback: fallback)
    }

    static func sectionTitle(for category: RaceDayChecklistCategory) -> String {
        switch category {
        case .rule: return string("race_day.checklist.section.rule", fallback: "RULES")
        case .gear: return string("race_day.checklist.section.gear", fallback: "GEAR")
        case .nutrition: return string("race_day.checklist.section.nutrition", fallback: "FUEL & WARM-UP")
        }
    }

    // MARK: - 화면 문구

    enum Hub {
        static var title: String { string("race_day.hub.title", fallback: "Race Day") }
        static var paceCardTitle: String {
            string("race_day.hub.pace_card.title", fallback: "Race pace card")
        }
        static var paceCardSubtitle: String {
            string("race_day.hub.pace_card.subtitle", fallback: "Splits and cumulative target times")
        }
        static var checklistTitle: String {
            string("race_day.hub.checklist.title", fallback: "Race day checklist")
        }
        static var checklistSubtitle: String {
            string("race_day.hub.checklist.subtitle", fallback: "Rules, gear, fuel and warm-up")
        }
        static var noRace: String {
            string("race_day.hub.no_race", fallback: "No race registered — using this workout's targets")
        }
        static func goal(_ value: String) -> String {
            format("race_day.hub.goal_format", fallback: "Goal %@", value)
        }
        static func daysRemaining(_ days: Int) -> String {
            format("race_day.hub.dday_format", fallback: "D-%d", days)
        }
        static var raceDay: String { string("race_day.hub.dday_today", fallback: "D-DAY") }
        static var pastRace: String {
            string("race_day.hub.past_race", fallback: "This race is over")
        }
    }

    enum PaceCard {
        static var title: String { string("race_day.pace_card.title", fallback: "Pace Card") }
        static var columnSegment: String {
            string("race_day.pace_card.column.segment", fallback: "SEGMENT")
        }
        static var columnSplit: String {
            string("race_day.pace_card.column.split", fallback: "SPLIT")
        }
        static var columnCumulative: String {
            string("race_day.pace_card.column.cumulative", fallback: "ELAPSED")
        }
        static var scaledNotice: String {
            string(
                "race_day.pace_card.scaled_notice",
                fallback: "Splits scaled to your race goal."
            )
        }
        static var fastLaneHint: String {
            string(
                "race_day.pace_card.fast_lane_hint",
                fallback: "Rulebook: runs at 4:00/km or faster belong in the Fast Lane."
            )
        }
        static var emptyTitle: String {
            string("race_day.pace_card.no_goal.title", fallback: "This workout has no target times")
        }
        static var emptyMessage: String {
            string(
                "race_day.pace_card.no_goal.message",
                fallback: "Set segment targets or a goal time and the pace card fills in."
            )
        }
        static var share: String {
            string("race_day.pace_card.share", fallback: "Save or share image")
        }
        static var shareFailed: String {
            string("race_day.pace_card.share_failed", fallback: "Couldn't build the image")
        }
    }

    enum Checklist {
        static var title: String { string("race_day.checklist.title", fallback: "Race Day Checklist") }
        static var ruleFooter: String {
            string(
                "race_day.checklist.section.rule.footer",
                fallback: "Straight from the HYROX 26/27 rulebook."
            )
        }
        static var reset: String { string("race_day.checklist.reset", fallback: "Reset checklist") }
        static var resetTitle: String {
            string("race_day.checklist.reset.title", fallback: "Reset checklist?")
        }
        static var resetMessage: String {
            string("race_day.checklist.reset.message", fallback: "Every item goes back to unchecked.")
        }
        static var pastRaceNotice: String {
            string(
                "race_day.checklist.past_race_notice",
                fallback: "That race is done. Reset the list for the next one."
            )
        }
        static func progress(done: Int, total: Int) -> String {
            format("race_day.checklist.progress_format", fallback: "%1$d / %2$d", done, total)
        }
    }

    enum Workout {
        static var addLap: String {
            string("race_day.workout.add_lap", fallback: "Add lap")
        }
        static var removeLap: String {
            string("race_day.workout.remove_lap", fallback: "Remove lap")
        }
        static var raceModeToggle: String {
            string("race_day.workout.race_mode", fallback: "Race mode")
        }
        static var openRaceDay: String {
            string("race_day.workout.open", fallback: "Race day")
        }
        static var lapHint: String {
            string("race_day.workout.lap_hint", fallback: "Count your own laps")
        }
    }
}
