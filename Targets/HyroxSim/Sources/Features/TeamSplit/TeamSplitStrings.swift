//
//  TeamSplitStrings.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import Foundation
import HyroxCore

/// 분담 플래너 문구.
///
/// SwiftGen 접근자 대신 번들을 직접 조회한다 — 팀원 수·포맷에 따라 키가 갈리는 문구가 있어
/// 어차피 동적 조회가 필요하고, 한 화면의 문구를 두 가지 방식으로 읽으면 어느 쪽이 최신인지
/// 알기 어려워진다(`TrainingSessionLocalization` 과 같은 방식).
enum TeamSplitStrings {

    static var title: String { localized("team_split.title", "Split Plan") }

    // MARK: 대회 화면 진입 (키 이름공간은 `race_target.*` — 문구가 그 화면에 있기 때문)

    static var planningSection: String { localized("race_target.section.planning", "PLANNING") }
    static var entryTitle: String { localized("race_target.action.team_split", "Split plan") }
    static var entrySubtitle: String {
        localized("race_target.action.team_split.subtitle", "Divide the stations with your partner")
    }

    static var sectionGoal: String { localized("team_split.section.goal", "TEAM GOAL") }
    static var sectionWorkload: String { localized("team_split.section.workload", "WORKLOAD") }
    static var sectionStations: String { localized("team_split.section.stations", "STATION SPLIT") }

    static func formatName(_ format: TeamFormat) -> String {
        switch format {
        case .doubles: return localized("team_split.format.doubles", "Doubles · 2")
        case .relay: return localized("team_split.format.relay", "Relay · 4")
        }
    }

    static func ruleNote(_ format: TeamFormat) -> String {
        switch format {
        case .doubles:
            return localized(
                "team_split.rule.doubles",
                "Stations are split freely, but both partners run every lap together. Running ahead costs a 1-minute penalty, and more than three breaks means disqualification — so running time is shared, not divided."
            )
        case .relay:
            return localized(
                "team_split.rule.relay",
                "Each athlete covers 2 × (1 km + one station), so the running is divided with the stations. Weights follow each athlete's own Open division."
            )
        }
    }

    static var projectedFinish: String { localized("team_split.summary.projected", "Projected finish") }
    static var sharedRun: String { localized("team_split.summary.shared_run", "Run together") }
    static var runPerAthlete: String { localized("team_split.summary.run_per_athlete", "Running each") }
    static var loadGap: String { localized("team_split.summary.load_gap", "Load gap") }
    static var evenSplit: String { localized("team_split.summary.even", "Even split") }

    static var memberStations: String { localized("team_split.member.stations", "Stations") }
    static var memberRunning: String { localized("team_split.member.running", "Running") }
    static var memberRest: String { localized("team_split.member.rest", "Rest") }

    static var resetButton: String { localized("team_split.button.reset", "Reset to even split") }

    static func imbalanceWarning(percent: Int) -> String {
        String(
            format: localized(
                "team_split.warning.imbalance",
                "One athlete is carrying %d%% of the station work. You still have to run together, so the heavier side sets the pace."
            ),
            percent
        )
    }

    static func referenceNote(division: String) -> String {
        String(
            format: localized(
                "team_split.note.reference",
                "Station times come from %@ race results at this finish time."
            ),
            division
        )
    }

    static func estimatedNote(division: String) -> String {
        String(
            format: localized(
                "team_split.note.estimated",
                "No published relay table exists, so these splits are scaled from %@ results. Reference only."
            ),
            division
        )
    }

    static func sharePercent(_ share: Double) -> String {
        String(format: localized("team_split.share.format", "%d%%"), Int((share * 100).rounded()))
    }

    private static func localized(_ key: String, _ fallback: String) -> String {
        Bundle.module.localizedString(forKey: key, value: fallback, table: "Localizable")
    }
}
