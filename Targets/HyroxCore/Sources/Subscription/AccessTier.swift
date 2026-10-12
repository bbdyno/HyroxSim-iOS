//
//  AccessTier.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 사용자가 앱에서 쓸 수 있는 범위.
public enum AccessTier: String, Codable, Hashable, Sendable {
    /// 2.0 부터 무료로 받은 사용자. 일부 기능과 개수에 제한이 있다.
    case free
    /// 구독 중.
    case subscriber
    /// 2.0 이전에 유료 앱으로 구매한 사용자. 구독 없이 전부 쓴다.
    case legacyBuyer

    public var isUnlocked: Bool { self != .free }
}

/// 구독해야 열리는 기능. 페이월이 "무엇 때문에 떴는지" 보여 줄 때도 쓴다.
public enum PremiumFeature: String, CaseIterable, Hashable, Sendable {
    case unlimitedHistory
    case unlimitedTemplates
    case allTrainingSessions
    case levelAssessment
    case weaknessDiagnosis
    case finishPrediction
    case teamStrategy
    case trainingPlan
    case raceArchive
    case resultScan
    case shareTemplates
    case seasonReport
    case cloudBackup
    case aiCoach
    case voiceGuide
}

/// 무료 범위의 개수 제한과 기능 잠금을 한곳에서 판단한다.
///
/// 화면마다 `tier == .free` 를 직접 비교하지 않고 이 타입에 묻는다. 제한 수치가
/// 여기에만 있어야 페이월 문구·스토어 설명·실제 동작이 어긋나지 않는다.
public struct FeatureGate: Hashable, Sendable {

    public static let freeHistoryLimit = 5
    public static let freeCustomTemplateLimit = 1
    public static let freeTrainingSessionLimit = 1
    public static let freeRaceArchiveLimit = 1
    public static let freeShareTemplateLimit = 1

    public let tier: AccessTier

    public init(tier: AccessTier) {
        self.tier = tier
    }

    public func allows(_ feature: PremiumFeature) -> Bool {
        tier.isUnlocked
    }

    /// 기록 목록에서 최신순 `index` 번째 기록을 열어 볼 수 있는가.
    /// 기록 자체는 무료 사용자도 계속 저장된다 — 구독하면 전부 다시 보인다.
    public func canOpenHistory(at index: Int) -> Bool {
        tier.isUnlocked || index < Self.freeHistoryLimit
    }

    public func visibleHistoryCount(total: Int) -> Int {
        tier.isUnlocked ? total : min(total, Self.freeHistoryLimit)
    }

    /// 커스텀 템플릿을 하나 더 만들 수 있는가.
    public func canCreateCustomTemplate(existingCount: Int) -> Bool {
        tier.isUnlocked || existingCount < Self.freeCustomTemplateLimit
    }

    /// 훈련 세션 목록에서 `index` 번째를 시작할 수 있는가.
    public func canStartTrainingSession(at index: Int) -> Bool {
        tier.isUnlocked || index < Self.freeTrainingSessionLimit
    }

    public func canAddRaceResult(existingCount: Int) -> Bool {
        tier.isUnlocked || existingCount < Self.freeRaceArchiveLimit
    }

    public func canUseShareTemplate(at index: Int) -> Bool {
        tier.isUnlocked || index < Self.freeShareTemplateLimit
    }
}
