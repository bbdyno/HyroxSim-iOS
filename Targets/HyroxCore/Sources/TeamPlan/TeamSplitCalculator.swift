//
//  TeamSplitCalculator.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

// MARK: - 결과 값

/// 한 사람이 한 스테이션에서 맡은 몫.
public struct TeamStationLoad: Hashable, Sendable {
    /// 코스 순서(0...7).
    public let stationIndex: Int
    public let station: StationKind
    /// 이 사람이 맡은 비율(0...1).
    public let share: Double
    /// 그 비율에 해당하는 시간(초).
    public let seconds: TimeInterval

    public init(stationIndex: Int, station: StationKind, share: Double, seconds: TimeInterval) {
        self.stationIndex = stationIndex
        self.station = station
        self.share = share
        self.seconds = seconds
    }
}

/// 한 사람의 총 부하.
public struct TeamMemberLoad: Hashable, Sendable, Identifiable {
    public let slot: Int
    public let name: String
    /// 맡은 스테이션 작업 시간 합.
    public let stationSeconds: TimeInterval
    /// 직접 뛰는 러닝 시간. 더블스는 0 — 런은 둘이 함께라 분담 대상이 아니다.
    public let runSeconds: TimeInterval
    /// 몫이 있는 스테이션만, 코스 순서대로.
    public let stations: [TeamStationLoad]
    /// 팀이 움직이는 동안 이 사람이 쉬는 시간.
    ///
    /// 더블스는 파트너가 스테이션을 처리하는 동안이 곧 휴식이다(런은 함께 뛰므로 제외).
    /// 릴레이는 자기 구간이 아닌 나머지 전부가 휴식이다.
    public let restSeconds: TimeInterval

    public var id: Int { slot }

    /// 실제로 몸을 쓰는 시간 합.
    public var totalSeconds: TimeInterval { stationSeconds + runSeconds }

    public init(
        slot: Int,
        name: String,
        stationSeconds: TimeInterval,
        runSeconds: TimeInterval,
        stations: [TeamStationLoad],
        restSeconds: TimeInterval
    ) {
        self.slot = slot
        self.name = name
        self.stationSeconds = stationSeconds
        self.runSeconds = runSeconds
        self.stations = stations
        self.restSeconds = restSeconds
    }
}

/// 분담 계산 결과.
public struct TeamSplitResult: Hashable, Sendable {

    public let members: [TeamMemberLoad]
    public let reference: TeamSplitReference
    /// 둘이 함께 뛰는 시간(더블스). 릴레이는 0 — 런도 나눠 뛴다.
    public let sharedRunRoxSeconds: TimeInterval
    /// 팀 예상 완주 시간.
    ///
    /// 분담을 바꿔도 이 값은 변하지 않는다. 코스에서 해야 할 일의 총량은 그대로이고,
    /// 달라지는 것은 *누가* 하느냐뿐이기 때문이다. 목표 시간을 바꾸면 따라 움직인다.
    public let projectedTotalSeconds: TimeInterval
    /// 가장 많이 맡은 사람과 가장 적게 맡은 사람의 작업 시간 차이.
    public let imbalanceSeconds: TimeInterval
    /// 스테이션 작업량에서 한 사람이 가진 가장 큰 비중(0...1).
    /// 더블스 50 : 50 이면 0.5, 한 명이 전부 맡으면 1.0.
    public let peakStationShare: Double

    public init(
        members: [TeamMemberLoad],
        reference: TeamSplitReference,
        sharedRunRoxSeconds: TimeInterval,
        projectedTotalSeconds: TimeInterval,
        imbalanceSeconds: TimeInterval,
        peakStationShare: Double
    ) {
        self.members = members
        self.reference = reference
        self.sharedRunRoxSeconds = sharedRunRoxSeconds
        self.projectedTotalSeconds = projectedTotalSeconds
        self.imbalanceSeconds = imbalanceSeconds
        self.peakStationShare = peakStationShare
    }

    /// 스테이션 작업 시간 합(팀 전체).
    public var teamStationSeconds: TimeInterval {
        members.reduce(0) { $0 + $1.stationSeconds }
    }
}

// MARK: - 계산

/// 분담 계획을 사람별 부하로 바꾼다.
///
/// 순수 함수다. 시계도 저장소도 읽지 않고, 같은 입력에는 항상 같은 값을 낸다.
///
/// 규칙을 그대로 옮긴 부분:
/// - **더블스**: 스테이션만 나눈다. 런은 둘이 함께 뛰어야 하므로(앞서 가면 1분 페널티,
///   3회 초과 시 실격) 러닝 시간은 누구의 몫으로도 넣지 않고 `sharedRunRoxSeconds` 로 뺀다.
/// - **릴레이**: 1인당 2 × (1 km + 스테이션). 구간을 맡으면 그 구간의 런도 같이 맡으므로
///   러닝 시간이 스테이션 비율을 그대로 따라간다.
public enum TeamSplitCalculator {

    public static func result(
        for plan: TeamSplitPlan,
        reference: TeamSplitReference
    ) -> TeamSplitResult {

        let stations = StationKind.standardOrder
        let splitsRunning = plan.entry.format.splitsRunning
        let runPerLeg = splitsRunning ? reference.runRoxSecondsPerLeg : 0

        var members: [TeamMemberLoad] = []
        var stationTotals: [TimeInterval] = Array(repeating: 0, count: plan.memberCount)
        var runTotals: [TimeInterval] = Array(repeating: 0, count: plan.memberCount)
        var breakdowns: [[TeamStationLoad]] = Array(repeating: [], count: plan.memberCount)

        for (index, station) in stations.enumerated() {
            let stationSeconds = reference.seconds(for: station)
            for slot in 0..<plan.memberCount {
                let share = plan.share(stationAt: index, slot: slot)
                guard share > 0 else { continue }
                let seconds = stationSeconds * share
                stationTotals[slot] += seconds
                runTotals[slot] += runPerLeg * share
                breakdowns[slot].append(
                    TeamStationLoad(
                        stationIndex: index,
                        station: station,
                        share: share,
                        seconds: seconds
                    )
                )
            }
        }

        let teamStationSeconds = stationTotals.reduce(0, +)

        for slot in 0..<plan.memberCount {
            let own = stationTotals[slot] + runTotals[slot]
            // 더블스: 파트너가 스테이션을 처리하는 동안이 휴식. 런은 함께 뛰므로 빠진다.
            // 릴레이: 코스 전체에서 내 구간을 뺀 나머지가 휴식.
            let rest = splitsRunning
                ? max(0, reference.totalSeconds - own)
                : max(0, teamStationSeconds - stationTotals[slot])

            members.append(
                TeamMemberLoad(
                    slot: slot,
                    name: plan.name(forSlot: slot),
                    stationSeconds: stationTotals[slot],
                    runSeconds: runTotals[slot],
                    stations: breakdowns[slot],
                    restSeconds: rest
                )
            )
        }

        let loads = members.map(\.totalSeconds)
        let imbalance = (loads.max() ?? 0) - (loads.min() ?? 0)
        let peakShare = teamStationSeconds > 0
            ? (stationTotals.max() ?? 0) / teamStationSeconds
            : 0

        return TeamSplitResult(
            members: members,
            reference: reference,
            sharedRunRoxSeconds: splitsRunning ? 0 : reference.runRoxSeconds,
            projectedTotalSeconds: reference.runRoxSeconds + teamStationSeconds,
            imbalanceSeconds: imbalance,
            peakStationShare: peakShare
        )
    }
}
