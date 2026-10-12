//
//  PremiumAccess.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import UIKit

/// 깊은 화면에서 "이 기능을 써도 되는가" 를 묻는 창구.
///
/// 코디네이터가 띄우지 않는 화면(대회 편집 → 팀 분담처럼 화면이 화면을 띄우는 경우)까지
/// 구독 저장소를 인자로 끌고 내려가지 않기 위한 것이다. 앱 시작 때 코디네이터가 연결한다.
/// 연결 전에는 전부 허용한다 — 테스트와 미리보기에서 화면이 잠긴 채 뜨지 않게.
@MainActor
enum PremiumAccess {

    static var gate: () -> FeatureGate = { FeatureGate(tier: .subscriber) }
    static var presentPaywall: (PremiumFeature) -> Void = { _ in }
    /// 가장 최근 공식 코스 기록에서 본 약점(손실이 큰 순). 훈련 계획이 강조할 곳을 정할 때 쓴다.
    static var latestWeaknesses: (HyroxDivision) -> [WeaknessItem.Kind] = { _ in [] }

    /// 열려 있으면 `true`. 잠겨 있으면 페이월을 띄우고 `false`.
    static func require(_ feature: PremiumFeature) -> Bool {
        if gate().allows(feature) { return true }
        presentPaywall(feature)
        return false
    }
}
