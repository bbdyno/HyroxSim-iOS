//
//  TeamStrategyRecommender.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 추천된 스테이션 분담.
public struct TeamStrategy: Hashable, Sendable {
    /// `TeamSplitPlan.stationShares` 와 같은 모양 — 바깥은 공식 스테이션 순서, 안쪽은 팀원 순서.
    public let stationShares: [[Double]]
    /// 스테이션별로 "이 사람이 강하다" 는 입력이 반영됐는지. 입력이 없던 스테이션은 `true`.
    ///
    /// 릴레이는 1인당 2구간이라, 한 사람을 세 군데 이상에 지목하면 다 들어줄 수 없다.
    public let honored: [Bool]
    /// 팀원별 스테이션 시간 비중(합 = 1).
    public let memberLoadShares: [Double]

    public var unhonoredStationIndices: [Int] {
        honored.indices.filter { !honored[$0] }
    }
}

/// 팀원의 강점에 맞춰 스테이션 분담을 추천한다.
///
/// 입력은 스테이션마다 "누가 더 강한가" 하나뿐이다(없어도 된다). 개인별 기록을 받지 않는
/// 이유: 파트너의 스테이션 기록을 아는 사용자는 드물고, 모르는 숫자를 넣게 하면 추천이
/// 그럴듯하기만 한 값이 된다.
public enum TeamStrategyRecommender {

    /// 더블스에서 강한 쪽이 가져가는 비율.
    public static let favoredShare = 0.65
    /// 더블스에서 한 사람의 스테이션 시간 비중이 이 값을 넘지 않게 맞춘다.
    public static let maxLoadShare = 0.55
    static let balanceStep = 0.05

    /// - Parameter strongerSlot: 공식 스테이션 순서대로, 더 강한 팀원의 순번. 비슷하면 nil.
    ///   길이가 모자라면 nil 로 채우고, 범위를 벗어난 순번은 nil 로 본다.
    public static func recommend(
        entry: TeamEntry,
        strongerSlot: [Int?],
        reference: TeamSplitReference
    ) -> TeamStrategy {
        let stations = StationKind.standardOrder
        let count = entry.memberCount
        let preferences: [Int?] = stations.indices.map { index in
            guard strongerSlot.indices.contains(index), let slot = strongerSlot[index],
                  (0..<count).contains(slot) else { return nil }
            return slot
        }
        let seconds = stations.map { reference.seconds(for: $0) }

        switch entry.format {
        case .doubles:
            return doubles(preferences: preferences, seconds: seconds)
        case .relay:
            return relay(preferences: preferences, seconds: seconds, memberCount: count)
        }
    }

    // MARK: - 더블스

    private static func doubles(preferences: [Int?], seconds: [TimeInterval]) -> TeamStrategy {
        // shareA[i] = 0번 팀원의 비율.
        var shareA: [Double] = preferences.map { slot in
            switch slot {
            case 0: return favoredShare
            case 1: return 1 - favoredShare
            default: return 0.5
            }
        }
        let total = seconds.reduce(0, +)

        func loadA() -> Double {
            guard total > 0 else { return 0.5 }
            return zip(shareA, seconds).reduce(0.0) { $0 + $1.0 * $1.1 } / total
        }

        // 강점대로만 나누면 한쪽에 일이 몰릴 수 있다. 강점 입력이 없던 스테이션부터,
        // 긴 스테이션 순으로 조금씩 넘겨 균형을 맞춘다. 강점이 지정된 스테이션은 건드리지 않는다.
        let adjustable = preferences.indices
            .filter { preferences[$0] == nil }
            .sorted { seconds[$0] > seconds[$1] }
        var guardCounter = 0
        while guardCounter < 200 {
            guardCounter += 1
            let load = loadA()
            let overloadedIsA = load > maxLoadShare
            let overloadedIsB = (1 - load) > maxLoadShare
            guard overloadedIsA || overloadedIsB else { break }
            let direction: Double = overloadedIsA ? -1 : 1
            // 이번 한 바퀴에서 한 스테이션만 한 칸 옮긴다 — 지나치게 넘어가지 않도록.
            guard let index = adjustable.first(where: { i in
                let next = shareA[i] + direction * balanceStep
                return next >= (1 - favoredShare) - 1e-9 && next <= favoredShare + 1e-9
            }) else { break }
            shareA[index] += direction * balanceStep
        }

        let load = loadA()
        return TeamStrategy(
            stationShares: shareA.map { [$0, 1 - $0] },
            honored: Array(repeating: true, count: preferences.count),
            memberLoadShares: [load, 1 - load]
        )
    }

    // MARK: - 릴레이

    /// 8개 구간을 4명에게 2개씩. 강점 입력을 최대한 많이 들어주고, 동률이면 부하가 고른 쪽,
    /// 그래도 동률이면 기본 순번(1·2·3·4·1·2·3·4)에 가까운 쪽을 고른다.
    private static func relay(preferences: [Int?], seconds: [TimeInterval], memberCount: Int) -> TeamStrategy {
        let stationCount = preferences.count
        let perMember = stationCount / memberCount
        var best: [Int] = (0..<stationCount).map { $0 % memberCount }
        var bestScore: (honored: Int, spread: Double, drift: Int) = score(best, preferences, seconds, memberCount)

        var current = Array(repeating: 0, count: stationCount)
        var used = Array(repeating: 0, count: memberCount)

        func search(_ index: Int) {
            if index == stationCount {
                let candidate = score(current, preferences, seconds, memberCount)
                if isBetter(candidate, than: bestScore) {
                    best = current
                    bestScore = candidate
                }
                return
            }
            for slot in 0..<memberCount where used[slot] < perMember {
                current[index] = slot
                used[slot] += 1
                search(index + 1)
                used[slot] -= 1
            }
        }
        search(0)

        let total = seconds.reduce(0, +)
        var loads = Array(repeating: 0.0, count: memberCount)
        for (index, slot) in best.enumerated() { loads[slot] += seconds[index] }
        return TeamStrategy(
            stationShares: best.map { TeamSplitPlan.oneHot(owner: $0, memberCount: memberCount) },
            honored: preferences.indices.map { preferences[$0] == nil || preferences[$0] == best[$0] },
            memberLoadShares: loads.map { total > 0 ? $0 / total : 1 / Double(memberCount) }
        )
    }

    private static func score(
        _ assignment: [Int], _ preferences: [Int?], _ seconds: [TimeInterval], _ memberCount: Int
    ) -> (honored: Int, spread: Double, drift: Int) {
        var honored = 0
        var drift = 0
        var loads = Array(repeating: 0.0, count: memberCount)
        for (index, slot) in assignment.enumerated() {
            if let preferred = preferences[index], preferred == slot { honored += 1 }
            if slot != index % memberCount { drift += 1 }
            loads[slot] += seconds[index]
        }
        return (honored, (loads.max() ?? 0) - (loads.min() ?? 0), drift)
    }

    private static func isBetter(
        _ a: (honored: Int, spread: Double, drift: Int),
        than b: (honored: Int, spread: Double, drift: Int)
    ) -> Bool {
        if a.honored != b.honored { return a.honored > b.honored }
        if abs(a.spread - b.spread) > 0.5 { return a.spread < b.spread }
        return a.drift < b.drift
    }
}
