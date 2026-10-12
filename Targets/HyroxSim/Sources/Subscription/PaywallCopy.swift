//
//  PaywallCopy.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import Foundation
import HyroxCore

/// 구독 기능을 사용자에게 설명하는 문구. 페이월과 잠금 안내가 같은 표현을 쓴다.
enum PaywallCopy {

    /// 페이월 목록에 올리는 기능과 순서.
    static let highlighted: [PremiumFeature] = [
        .levelAssessment, .weaknessDiagnosis, .finishPrediction, .teamStrategy,
        .trainingPlan, .aiCoach, .raceArchive, .shareTemplates, .unlimitedHistory
    ]

    static func title(for feature: PremiumFeature) -> String {
        NSLocalizedString("paywall.feature.\(feature.rawValue).title", comment: "")
    }

    static func detail(for feature: PremiumFeature) -> String {
        NSLocalizedString("paywall.feature.\(feature.rawValue).detail", comment: "")
    }
}
