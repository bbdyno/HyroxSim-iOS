//
//  TrainingSessionLocalization.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore

/// 훈련 세션 문구를 앱 번들에서 읽는다.
///
/// `HyroxCore` 는 문자열 리소스를 갖지 않아서 세션 이름/설명의 *키* 만 노출한다.
/// 키가 동적이라 SwiftGen 접근자를 쓸 수 없어 번들을 직접 조회하고,
/// 문구가 없으면 코어의 영문 기본값으로 떨어진다.
enum TrainingSessionLocalization {

    static func name(for kind: TrainingSessionKind) -> String {
        localized(kind.nameLocalizationKey, fallback: kind.defaultName)
    }

    static func summary(for kind: TrainingSessionKind) -> String {
        localized(kind.summaryLocalizationKey, fallback: kind.defaultSummary)
    }

    /// 카드 왼쪽 배지에 넣는 짧은 태그. 프리셋 카드의 OPEN/PRO 와 같은 자리다.
    static func badge(for kind: TrainingSessionKind) -> String {
        switch kind {
        case .compromisedRun: return "RUN"
        case .halfSimulation: return "SIM"
        case .stationIntervals: return "STN"
        case .roxZoneDrill: return "ROX"
        case .wallBallLadder: return "WB"
        case .pftBenchmark: return "PFT"
        }
    }

    private static func localized(_ key: String, fallback: String) -> String {
        Bundle.module.localizedString(forKey: key, value: fallback, table: "Localizable")
    }
}
