//
//  TeamSplitPlanStore.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

/// 팀 분담 계획을 대회별로 기억한다.
///
/// 계획은 파트너와 합의한 내용이라 화면을 닫았다고 사라지면 쓸모가 없다. 기록이나 템플릿과
/// 달리 워치·가민으로 보낼 일이 없어(운동 자체가 아니라 *약속* 이다) `UserDefaults` 에만 둔다.
/// 키를 대회 ID 로 나누므로 대회가 둘이면 계획도 둘이다.
///
/// 저장 실패는 조용히 넘긴다 — 분담 계획을 저장하지 못했다고 사용자가 할 수 있는 일이 없고,
/// 화면은 메모리에 든 값으로 계속 동작한다.
@MainActor
public final class TeamSplitPlanStore {

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 대회 ID 별 저장 키. 대회를 고르지 않은 경우(`nil`)를 위한 공용 슬롯도 둔다.
    public static func storageKey(raceTargetId: UUID?) -> String {
        "com.hyroxsim.teamSplitPlan.\(raceTargetId?.uuidString ?? "default")"
    }

    public func plan(raceTargetId: UUID?) -> TeamSplitPlan? {
        guard let data = defaults.data(forKey: Self.storageKey(raceTargetId: raceTargetId)) else { return nil }
        return try? decoder.decode(TeamSplitPlan.self, from: data)
    }

    public func save(_ plan: TeamSplitPlan, raceTargetId: UUID?) {
        guard let data = try? encoder.encode(plan) else { return }
        defaults.set(data, forKey: Self.storageKey(raceTargetId: raceTargetId))
    }

    /// 대회를 지울 때 그 대회의 분담 계획도 함께 지우는 자리.
    ///
    /// 아직 대회 삭제 경로(코디네이터)에 연결되어 있지 않다. 연결 전까지 지워진 대회의
    /// 계획은 `UserDefaults` 에 남지만, 그 ID 로 화면을 열 길이 없으므로 보이지는 않는다.
    public func remove(raceTargetId: UUID?) {
        defaults.removeObject(forKey: Self.storageKey(raceTargetId: raceTargetId))
    }
}
