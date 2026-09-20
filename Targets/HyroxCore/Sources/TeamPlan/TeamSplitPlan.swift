//
//  TeamSplitPlan.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

// MARK: - 포맷

/// 팀으로 치르는 방식.
///
/// 규칙이 서로 달라서 분담 계산이 갈린다.
/// - 더블스: 스테이션만 파트너끼리 자유롭게 나누고(YGIG), **런은 둘이 함께** 뛴다.
///   한 명이 앞서 가면 1분 페널티, 동행 위반이 3회를 넘으면 실격이다.
///   그래서 러닝 시간은 분담 대상이 아니라 팀 공통 시간이다.
/// - 릴레이: 1인당 2 × (1 km + 스테이션). 런도 자기 구간이므로 함께 나눈다.
public enum TeamFormat: String, Codable, Hashable, CaseIterable, Sendable {
    case doubles
    case relay

    public var memberCount: Int {
        switch self {
        case .doubles: return 2
        case .relay: return 4
        }
    }

    /// 런까지 나눠 뛰는 포맷인지 여부. 더블스는 `false` — 런은 팀 공통이다.
    public var splitsRunning: Bool { self == .relay }
}

/// 릴레이 디비전 (26/27 기준 3종).
///
/// `HyroxDivision` 에 케이스를 더하지 않는다. 그 열거형은 앱 전체가 `switch` 로 받고 있어서
/// 케이스가 늘면 전부 깨지고, 릴레이는 기록 표·프리셋도 따로 없다.
/// 릴레이는 여기 플랜/템플릿 수준에서만 표현한다.
public enum RelayDivision: String, Codable, Hashable, CaseIterable, Sendable {
    case men
    case women
    /// 여자 2 + 남자 2.
    case mixed

    public var displayName: String {
        switch self {
        case .men: return "Men's Relay"
        case .women: return "Women's Relay"
        case .mixed: return "Mixed Relay"
        }
    }

    /// 개인 디비전에서 같은 성별의 릴레이 디비전으로 옮긴다.
    /// 화면에서 "더블스 ↔ 릴레이" 를 전환할 때 쓰는 기본값이다.
    public init(matching division: HyroxDivision) {
        switch division {
        case .menOpenSingle, .menOpenDouble, .menProSingle, .menProDouble:
            self = .men
        case .womenOpenSingle, .womenOpenDouble, .womenProSingle, .womenProDouble:
            self = .women
        case .mixedDouble:
            self = .mixed
        }
    }

    /// 팀원 수 (모든 릴레이 디비전이 4인).
    public var memberCount: Int { 4 }

    /// 슬롯별 무게 기준 디비전.
    ///
    /// 릴레이 무게는 **성별 Open** 을 따른다. 혼성은 사람마다 자기 성별 Open 을 쓰므로
    /// 슬롯마다 답이 다르다. 기본 배치는 여자 2 명(슬롯 0·1) + 남자 2 명(슬롯 2·3)이고,
    /// 실제 출전 순서는 팀이 정하는 값이라 화면에서 바꿀 수 있어야 한다.
    /// (연령대는 팀 평균 나이 기준이라 무게에는 영향이 없다.)
    public func weightDivision(forSlot slot: Int) -> HyroxDivision {
        switch self {
        case .men: return .menOpenSingle
        case .women: return .womenOpenSingle
        case .mixed: return slot < 2 ? .womenOpenSingle : .menOpenSingle
        }
    }
}

/// 팀이 어떤 자격으로 나가는지.
///
/// 포맷과 디비전을 한 값으로 묶어, 팀원 수·무게·참조 기록 표가 서로 어긋날 수 없게 한다.
public enum TeamEntry: Codable, Hashable, Sendable {
    case doubles(HyroxDivision)
    case relay(RelayDivision)

    public var format: TeamFormat {
        switch self {
        case .doubles: return .doubles
        case .relay: return .relay
        }
    }

    public var memberCount: Int { format.memberCount }

    /// 구간 구성을 읽어 올 기록 표의 디비전.
    ///
    /// 더블스는 자기 디비전 표가 그대로 있다. 릴레이는 표가 없어서 같은 성별 Open 구성을
    /// *비율* 로만 빌려 쓴다 — 그래서 `TeamSplitReference` 가 릴레이를 항상 추정값으로 표시한다.
    public var referenceDivision: HyroxDivision {
        switch self {
        case .doubles(let division): return division
        case .relay(let relay):
            switch relay {
            case .men: return .menOpenDouble
            case .women: return .womenOpenDouble
            case .mixed: return .mixedDouble
            }
        }
    }

    public func weightDivision(forSlot slot: Int) -> HyroxDivision {
        switch self {
        case .doubles(let division): return division
        case .relay(let relay): return relay.weightDivision(forSlot: slot)
        }
    }

    public var displayName: String {
        switch self {
        case .doubles(let division): return division.displayName
        case .relay(let relay): return relay.displayName
        }
    }

    /// 기본 팀원 이름 (A · B · C · D).
    public var defaultMemberNames: [String] {
        (0..<memberCount).map { Self.defaultMemberName(forSlot: $0) }
    }

    public static func defaultMemberName(forSlot slot: Int) -> String {
        let letters = ["A", "B", "C", "D"]
        return letters.indices.contains(slot) ? letters[slot] : "\(slot + 1)"
    }
}

// MARK: - HyroxDivision 보조

extension HyroxDivision {

    /// 2인 1조로 치르는 디비전인지 여부.
    public var isDoubles: Bool {
        switch self {
        case .menOpenDouble, .menProDouble, .womenOpenDouble, .womenProDouble, .mixedDouble:
            return true
        case .menOpenSingle, .menProSingle, .womenOpenSingle, .womenProSingle:
            return false
        }
    }

    /// 같은 성별·등급의 더블스 디비전. 이미 더블스면 자기 자신.
    /// 싱글 디비전을 고른 사용자가 분담 계획을 열었을 때 쓸 출발점이다.
    public var doublesCounterpart: HyroxDivision {
        switch self {
        case .menOpenSingle, .menOpenDouble: return .menOpenDouble
        case .menProSingle, .menProDouble: return .menProDouble
        case .womenOpenSingle, .womenOpenDouble: return .womenOpenDouble
        case .womenProSingle, .womenProDouble: return .womenProDouble
        case .mixedDouble: return .mixedDouble
        }
    }
}

// MARK: - 분담 계획

/// 더블스·릴레이 팀의 스테이션 분담 계획.
///
/// 값 타입이고 계산을 갖지 않는다. 실제 시간 배분은 `TeamSplitCalculator` 가
/// `TeamSplitReference`(목표 시간에 해당하는 구간 구성)와 함께 순수 함수로 계산한다.
///
/// 불변식: `stationShares` 는 `StationKind.standardOrder` 와 같은 길이(8)이고,
/// 각 행은 팀원 수만큼의 값을 가지며 합이 정확히 1 이다. 모든 생성·수정 경로가
/// `normalized(_:memberCount:)` 를 지나므로 이 불변식은 깨질 수 없다.
public struct TeamSplitPlan: Codable, Hashable, Sendable {

    /// 공식 스테이션 수.
    public static let stationCount = StationKind.standardOrder.count

    public let entry: TeamEntry
    /// 팀 목표 완주 시간(초).
    public var goalTotalSeconds: TimeInterval
    /// 팀원 표시 이름. 팀원 수와 길이가 같다.
    public var memberNames: [String]
    /// 스테이션별 분담 비율. 바깥 배열은 공식 스테이션 순서, 안쪽 배열은 팀원 순서.
    public private(set) var stationShares: [[Double]]

    public init(
        entry: TeamEntry,
        goalTotalSeconds: TimeInterval,
        memberNames: [String]? = nil,
        stationShares: [[Double]]? = nil
    ) {
        self.entry = entry
        self.goalTotalSeconds = max(0, goalTotalSeconds)

        let count = entry.memberCount
        var names = memberNames ?? entry.defaultMemberNames
        if names.count < count {
            names += (names.count..<count).map { TeamEntry.defaultMemberName(forSlot: $0) }
        }
        self.memberNames = Array(names.prefix(count))

        self.stationShares = Self.normalizedShares(
            stationShares ?? Self.defaultShares(for: entry),
            memberCount: count
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 저장된 값이 불변식을 만족한다고 믿지 않는다 — 항상 지정 이니셜라이저를 통과시킨다.
        self.init(
            entry: try container.decode(TeamEntry.self, forKey: .entry),
            goalTotalSeconds: try container.decode(TimeInterval.self, forKey: .goalTotalSeconds),
            memberNames: try container.decodeIfPresent([String].self, forKey: .memberNames),
            stationShares: try container.decodeIfPresent([[Double]].self, forKey: .stationShares)
        )
    }

    // MARK: - 기본 분담

    /// 기본 분담으로 만든 계획.
    /// - 더블스: 모든 스테이션 50 : 50.
    /// - 릴레이: 1 · 2 · 3 · 4 번이 차례로 한 구간씩, 두 바퀴 (1인당 2구간).
    public static func balanced(entry: TeamEntry, goalTotalSeconds: TimeInterval) -> TeamSplitPlan {
        TeamSplitPlan(entry: entry, goalTotalSeconds: goalTotalSeconds)
    }

    private static func defaultShares(for entry: TeamEntry) -> [[Double]] {
        let count = entry.memberCount
        switch entry.format {
        case .doubles:
            let even = 1.0 / Double(count)
            return (0..<stationCount).map { _ in Array(repeating: even, count: count) }
        case .relay:
            // 릴레이는 한 구간을 한 사람이 통째로 맡는다. 순번대로 돌면 1인당 정확히 2구간.
            return (0..<stationCount).map { index in
                Self.oneHot(owner: index % count, memberCount: count)
            }
        }
    }

    static func oneHot(owner: Int, memberCount: Int) -> [Double] {
        let clamped = min(max(0, owner), memberCount - 1)
        return (0..<memberCount).map { $0 == clamped ? 1 : 0 }
    }

    // MARK: - 조회

    public var memberCount: Int { entry.memberCount }

    public func name(forSlot slot: Int) -> String {
        memberNames.indices.contains(slot)
            ? memberNames[slot]
            : TeamEntry.defaultMemberName(forSlot: slot)
    }

    /// `stationIndex` 번째 스테이션에서 `slot` 번 팀원이 맡은 비율(0...1).
    public func share(stationAt stationIndex: Int, slot: Int) -> Double {
        guard stationShares.indices.contains(stationIndex),
              stationShares[stationIndex].indices.contains(slot) else { return 0 }
        return stationShares[stationIndex][slot]
    }

    /// 릴레이에서 한 구간을 통째로 맡은 팀원. 나눠 맡았으면 `nil`.
    public func owner(stationAt stationIndex: Int) -> Int? {
        guard stationShares.indices.contains(stationIndex) else { return nil }
        return stationShares[stationIndex].firstIndex { $0 >= 0.999 }
    }

    /// 기본 분담과 같은지 여부. 화면의 "되돌리기" 버튼 상태에 쓴다.
    public var isBalanced: Bool {
        stationShares == Self.normalizedShares(
            Self.defaultShares(for: entry),
            memberCount: memberCount
        )
    }

    // MARK: - 수정

    /// 한 스테이션에서 `slot` 번 팀원의 비율을 바꾼다.
    ///
    /// 남은 몫은 나머지 팀원이 **지금 비율대로** 나눠 갖는다. 나머지가 전부 0 이면 균등 배분한다.
    /// 2 인 더블스에서는 자연히 "상대는 1 − x" 가 된다.
    public func settingShare(
        _ share: Double,
        stationAt stationIndex: Int,
        slot: Int
    ) -> TeamSplitPlan {
        guard stationShares.indices.contains(stationIndex),
              stationShares[stationIndex].indices.contains(slot) else { return self }

        var copy = self
        var row = stationShares[stationIndex]
        let target = min(max(0, share), 1)
        let remainder = 1 - target

        let others = row.indices.filter { $0 != slot }
        let othersTotal = others.reduce(0.0) { $0 + row[$1] }

        for index in others {
            row[index] = othersTotal > 0
                ? row[index] / othersTotal * remainder
                : remainder / Double(others.count)
        }
        row[slot] = target

        copy.stationShares[stationIndex] = Self.normalizedRow(row, memberCount: memberCount)
        return copy
    }

    /// 한 구간을 `slot` 번 팀원에게 통째로 넘긴다 (릴레이 구간 배정).
    public func assigning(stationAt stationIndex: Int, to slot: Int) -> TeamSplitPlan {
        guard stationShares.indices.contains(stationIndex) else { return self }
        var copy = self
        copy.stationShares[stationIndex] = Self.oneHot(owner: slot, memberCount: memberCount)
        return copy
    }

    /// 모든 스테이션을 기본 분담으로 되돌린다.
    public func resettingToBalanced() -> TeamSplitPlan {
        var copy = self
        copy.stationShares = Self.normalizedShares(
            Self.defaultShares(for: entry),
            memberCount: memberCount
        )
        return copy
    }

    public func settingGoalTotalSeconds(_ seconds: TimeInterval) -> TeamSplitPlan {
        var copy = self
        copy.goalTotalSeconds = max(0, seconds)
        return copy
    }

    // MARK: - 정규화

    private static func normalizedShares(_ shares: [[Double]], memberCount: Int) -> [[Double]] {
        (0..<stationCount).map { index in
            normalizedRow(shares.indices.contains(index) ? shares[index] : [], memberCount: memberCount)
        }
    }

    /// 한 행을 "길이 = 팀원 수, 값 0...1, 합 = 1" 로 맞춘다.
    ///
    /// 음수·NaN·모자라거나 남는 칸은 전부 여기서 정리된다. 합이 0 이면 균등 분배로 떨어뜨린다.
    private static func normalizedRow(_ row: [Double], memberCount: Int) -> [Double] {
        guard memberCount > 0 else { return [] }

        var values = (0..<memberCount).map { index -> Double in
            guard row.indices.contains(index) else { return 0 }
            let value = row[index]
            return value.isFinite ? max(0, value) : 0
        }

        let total = values.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: 1 / Double(memberCount), count: memberCount)
        }

        for index in values.indices {
            values[index] /= total
        }
        return values
    }
}
