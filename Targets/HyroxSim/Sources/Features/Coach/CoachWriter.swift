//
//  CoachWriter.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import Foundation
import HyroxCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 코치의 말을 만든다.
///
/// 사실(`CoachInsight`)은 규칙으로 정하고, 문장은 두 가지 방법으로 쓴다.
/// - 항상: 사실마다 정해진 문장 (`lines`). 어떤 기기에서도 바로 나온다.
/// - 가능할 때: 기기에 내장된 언어 모델이 그 사실만으로 한 문단을 다시 쓴다 (`rewrite`).
///   모델은 iPhone 안에서 돌고, 기록은 기기 밖으로 나가지 않는다. 비용도 없다.
enum CoachWriter {

    private typealias L = HyroxSimStrings.Localizable.Coach

    // MARK: - 정해진 문장

    static func lines(for insights: [CoachInsight]) -> [String] {
        insights.map(line(for:))
    }

    static func line(for insight: CoachInsight) -> String {
        switch insight {
        case .standing(let top):
            return L.standing(LevelViewModel.percentText(top, clamped: false))
        case .biggestLoss(let kind, let lost, let drill):
            return L.biggestLoss(name(kind), DurationFormatter.ms(lost), TrainingSessionLocalization.name(for: drill))
        case .strength(let kind, let gained):
            return L.strength(name(kind), DurationFormatter.ms(gained))
        case .fade(let percent):
            return L.fade(Int(percent.rounded()))
        case .evenPacing:
            return L.evenPacing
        case .trend(let perWeek):
            let amount = DurationFormatter.ms(abs(perWeek))
            return perWeek < 0 ? L.trendFaster(amount) : L.trendSlower(amount)
        }
    }

    private static func name(_ kind: WeaknessItem.Kind) -> String {
        switch kind {
        case .running: return HyroxSimStrings.Localizable.Coach.running
        case .station(let station): return station.displayName
        }
    }

    // MARK: - 기기 내 모델

    /// 기기 내 모델을 쓸 수 있는가. 지원하지 않는 기기·OS, Apple Intelligence 가 꺼진 기기는 `false`.
    static var isOnDeviceModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// 사실만으로 짧은 코칭 문단을 쓴다. 모델을 쓸 수 없거나 결과가 쓸 만하지 않으면 nil —
    /// 그때는 정해진 문장이 그대로 남는다.
    static func rewrite(lines: [String], languageName: String) async -> String? {
        guard !lines.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(instructions: """
                You are a concise HYROX coach. Rewrite the given facts as one short paragraph of advice \
                (3 to 4 sentences) addressed to the athlete. Use only the facts provided: do not add numbers, \
                times, exercises or medical advice that are not in the facts. Do not add any time period, \
                event, cause or claim that the facts do not state. Keep every number exactly as given. \
                Write in \(languageName).
                """)
            let prompt = "Facts:\n" + lines.map { "- \($0)" }.joined(separator: "\n")
            // 같은 사실에는 같은 글이 나오게, 그리고 덜 지어내게 가장 그럴듯한 단어만 고른다.
            let options = GenerationOptions(sampling: .greedy)
            guard let response = try? await session.respond(to: prompt, options: options) else { return nil }
            return accepted(response.content, facts: lines)
        }
        #endif
        return nil
    }

    /// 모델이 쓴 글을 그대로 믿지 않는다. 너무 길거나, 사실에 없는 숫자가 들어 있으면 버린다.
    static func accepted(_ text: String, facts: [String]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20, trimmed.count <= 700 else { return nil }
        let allowed = Set(numbers(in: facts.joined(separator: " ")))
        guard numbers(in: trimmed).allSatisfy(allowed.contains) else { return nil }
        return trimmed
    }

    /// "01:38", "27", "65%" 에서 숫자 덩어리만.
    static func numbers(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        // "01" 과 "1" 은 같은 숫자다.
        return result.map { String(Int($0) ?? 0) }
    }
}
