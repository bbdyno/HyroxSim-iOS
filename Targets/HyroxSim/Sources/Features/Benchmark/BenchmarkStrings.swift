//
//  BenchmarkStrings.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import Foundation
import HyroxCore

/// PFT 벤치마크 문구.
///
/// 구간 이름은 `HyroxCore` 가 키만 노출하므로 어차피 동적 조회가 필요하다. 한 화면 안에서
/// 문구를 읽는 방법이 둘로 갈리지 않도록 나머지도 같은 방식으로 읽는다
/// (`TrainingSessionLocalization` 과 같은 패턴).
enum BenchmarkStrings {

    // MARK: 템플릿

    static var templateName: String {
        localized(PFTBenchmark.nameLocalizationKey, PFTBenchmark.defaultName)
    }

    static var templateSummary: String {
        localized(PFTBenchmark.summaryLocalizationKey, PFTBenchmark.defaultSummary)
    }

    static func stepName(_ step: PFTStep) -> String {
        localized(step.nameLocalizationKey, step.defaultName)
    }

    // MARK: 화면

    static var title: String { localized("benchmark.title", "PFT Benchmark") }

    // MARK: 대회 화면 진입 (키 이름공간은 `race_target.*` — 문구가 그 화면에 있기 때문)

    static var entryTitle: String { localized("race_target.action.benchmark", "PFT benchmark") }
    static var entrySubtitle: String {
        localized("race_target.action.benchmark.subtitle", "Find your division from one fitness test")
    }
    static var sectionProtocol: String { localized("benchmark.section.protocol", "TEST PROTOCOL") }
    static var sectionTime: String { localized("benchmark.section.time", "YOUR TIME") }
    static var sectionDivision: String { localized("benchmark.section.division", "PROJECT AGAINST") }
    static var sectionResult: String { localized("benchmark.section.result", "RESULT") }
    static var sectionSplits: String { localized("benchmark.section.splits", "SPLIT PERCENTILES") }
    static var sectionNext: String { localized("benchmark.section.next", "NEXT STEP") }

    static func recommendation(_ value: PFTRecommendedDivision) -> String {
        switch value {
        case .pro: return localized("benchmark.recommend.pro", "PRO")
        case .open: return localized("benchmark.recommend.open", "OPEN")
        }
    }

    static func recommendationHeadline(_ division: String) -> String {
        String(
            format: localized("benchmark.recommend.headline", "This time points at the %@ division."),
            division
        )
    }

    static var projectionTitle: String {
        localized("benchmark.projection.title", "Projected HYROX finish")
    }

    static func projectionRange(_ fastest: String, _ slowest: String) -> String {
        String(format: localized("benchmark.projection.range", "%@ – %@"), fastest, slowest)
    }

    static func projectionBasis(_ division: String) -> String {
        String(format: localized("benchmark.projection.basis", "Against %@ results"), division)
    }

    static func projectionPercentile(_ fastest: Int, _ slowest: Int) -> String {
        String(
            format: localized("benchmark.projection.percentile", "Top %d%% – %d%%"),
            fastest,
            slowest
        )
    }

    static var noteSource: String {
        localized(
            "benchmark.note.source",
            "Pro 15–25 min and Open 25–35 min are reported reference figures, not an official formula — treat the range as a guide."
        )
    }

    static var noteOutsideBand: String {
        localized(
            "benchmark.note.outside_band",
            "This time sits outside the reported 15–35 minute band, so the range is widened."
        )
    }

    static func recordSource(_ date: String) -> String {
        String(format: localized("benchmark.record.source", "From your PFT on %@"), date)
    }

    static var recordNone: String {
        localized(
            "benchmark.record.none",
            "No PFT record yet. Enter the time by hand, or run the PFT template to unlock split percentiles."
        )
    }

    static var recordEdited: String {
        localized("benchmark.record.edited", "Split percentiles apply to the recorded time only.")
    }

    static var splitsEmpty: String {
        localized("benchmark.splits.empty", "Run the PFT in the app to compare your splits with race results.")
    }

    static var splitsApproximate: String { localized("benchmark.splits.approximate", "approx.") }

    static func splitPercentile(_ percentile: Double) -> String {
        String(format: localized("benchmark.splits.percentile", "Top %.1f%%"), percentile)
    }

    static var nextStepBody: String {
        localized(
            "benchmark.next.body",
            "Run a full race simulation next. Its summary opens the gap analysis, which shows where the time actually goes."
        )
    }

    static var unavailable: String {
        localized("benchmark.unavailable", "No reference results for this division yet.")
    }

    private static func localized(_ key: String, _ fallback: String) -> String {
        Bundle.module.localizedString(forKey: key, value: fallback, table: "Localizable")
    }
}
