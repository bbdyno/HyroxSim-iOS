//
//  LevelAssessment.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 퍼센타일 격자 위의 기록 곡선. `percentiles[i]` 지점의 기록이 `seconds[i]` 다.
///
/// 퍼센타일은 "상위 몇 %" 다 — 작을수록 빠르다.
public struct PercentileCurve: Hashable, Sendable {

    public let percentiles: [Double]
    public let seconds: [Double]

    /// 길이가 다르거나 점이 둘 미만이면 nil.
    ///
    /// 구간 기록 곡선은 표본이 적은 끝단에서 살짝 뒤집히는 일이 있다. 역방향 조회
    /// (기록 → 퍼센타일)가 한 값으로 정해지도록 누적 최댓값으로 단조 증가하게 만든다.
    public init?(percentiles: [Double], seconds: [Int]) {
        guard percentiles.count == seconds.count, percentiles.count >= 2 else { return nil }
        var monotone: [Double] = []
        monotone.reserveCapacity(seconds.count)
        var runningMax = -Double.infinity
        for value in seconds {
            runningMax = max(runningMax, Double(value))
            monotone.append(runningMax)
        }
        self.percentiles = percentiles
        self.seconds = monotone
    }

    /// 이 기록이 상위 몇 % 인지. 곡선 밖이면 가장자리 값에 고정하고 `isClamped` 가 참이다.
    public func topPercent(forSeconds value: Double) -> (value: Double, isClamped: Bool) {
        guard let first = seconds.first, let last = seconds.last,
              let firstP = percentiles.first, let lastP = percentiles.last else { return (100, true) }
        if value <= first { return (firstP, value < first) }
        if value >= last { return (lastP, value > last) }
        // seconds[index - 1] < value <= seconds[index]
        guard let index = seconds.firstIndex(where: { $0 >= value }), index > 0 else { return (firstP, false) }
        let lower = seconds[index - 1], upper = seconds[index]
        let fraction = upper > lower ? (value - lower) / (upper - lower) : 0
        return (percentiles[index - 1] + fraction * (percentiles[index] - percentiles[index - 1]), false)
    }

    /// 상위 `percent` % 지점의 기록(초). 격자 밖이면 nil.
    public func seconds(atTopPercent percent: Double) -> Double? {
        guard let firstP = percentiles.first, let lastP = percentiles.last,
              percent >= firstP, percent <= lastP else { return nil }
        guard let index = percentiles.firstIndex(where: { $0 >= percent }) else { return nil }
        if index == 0 { return seconds[0] }
        let lowerP = percentiles[index - 1], upperP = percentiles[index]
        let fraction = upperP > lowerP ? (percent - lowerP) / (upperP - lowerP) : 0
        return seconds[index - 1] + fraction * (seconds[index] - seconds[index - 1])
    }
}

/// 완주 기록이 실제 대회 참가자들 사이에서 어디쯤인지.
public struct LevelAssessment: Hashable, Sendable {

    public struct AgeGroupStanding: Hashable, Sendable {
        /// 데이터의 연령대 표기 (예: `30-34`).
        public let label: String
        public let topPercent: Double
        /// 연령대 곡선이 덮는 범위(상위 5~95%) 밖이라 가장자리에 고정된 값인지.
        public let isClamped: Bool
        /// 이 연령대 곡선을 만든 선수 수.
        public let athletes: Int
    }

    /// 다음으로 넘을 만한 선. "상위 20% 까지 1:32 남음".
    public struct Milestone: Hashable, Sendable {
        public let topPercent: Double
        public let finishSeconds: Double
        /// 지금 기록에서 줄여야 하는 시간(초). 항상 양수.
        public let gapSeconds: Double
    }

    public let division: HyroxDivision
    public let finishSeconds: Double
    /// 전체 참가자 중 상위 몇 %.
    public let overallTopPercent: Double
    /// 데이터가 덮는 범위(상위 0.1~99.9%) 밖이라 가장자리에 고정된 값인지.
    public let isOverallClamped: Bool
    public let ageGroup: AgeGroupStanding?
    public let nextMilestone: Milestone?
    /// 비교 대상 선수 수.
    public let athletes: Int?
    public let seasonLabel: String?
    public let datasetVersion: String
}

/// 대회 기록과 비교할 수 있는 기록인지 가르는 기준.
public enum RacePlausibility {
    /// 공식 코스를 이보다 빨리 끝낸 기록은 실제 레이스가 아니다(세계 기록도 50분대다).
    /// 화면을 눌러 넘기기만 한 기록에 "상위 0.1%" 가 붙지 않게 한다.
    public static let minimumFinishSeconds: TimeInterval = 30 * 60

    public static func isPlausible(finishSeconds: TimeInterval) -> Bool {
        finishSeconds >= minimumFinishSeconds
    }
}

public enum LevelAssessor {

    /// 넘을 선으로 제시하는 상위 %. 큰 값부터.
    static let milestones: [Double] = [90, 75, 50, 30, 20, 10, 5, 1]

    /// - Parameters:
    ///   - ageGroup: 데이터의 연령대 표기. 없거나 그 연령대 곡선이 없으면 전체 순위만 낸다.
    /// - Returns: 데이터셋이 디비전을 모르거나 곡선이 비정상이면 nil.
    public static func assess(
        finishSeconds: TimeInterval,
        dataset: PaceDataset,
        ageGroup: String? = nil
    ) -> LevelAssessment? {
        guard RacePlausibility.isPlausible(finishSeconds: finishSeconds), let division = dataset.division,
              let overall = PercentileCurve(percentiles: dataset.gridP, seconds: dataset.overallS) else {
            return nil
        }
        let standing = overall.topPercent(forSeconds: finishSeconds)

        var ageStanding: LevelAssessment.AgeGroupStanding?
        if let ageGroup,
           let group = dataset.ageGroups.first(where: { $0.ageGroup == ageGroup }),
           let curve = PercentileCurve(percentiles: group.gridP, seconds: group.overallS) {
            let result = curve.topPercent(forSeconds: finishSeconds)
            ageStanding = .init(
                label: group.ageGroup, topPercent: result.value, isClamped: result.isClamped, athletes: group.n
            )
        }

        // 지금 순위보다 앞에 있는 선 가운데 가장 가까운 것.
        var milestone: LevelAssessment.Milestone?
        if let target = milestones.first(where: { $0 < standing.value - 0.05 }),
           let seconds = overall.seconds(atTopPercent: target), seconds < finishSeconds {
            milestone = .init(topPercent: target, finishSeconds: seconds, gapSeconds: finishSeconds - seconds)
        }

        return LevelAssessment(
            division: division,
            finishSeconds: finishSeconds,
            overallTopPercent: standing.value,
            isOverallClamped: standing.isClamped,
            ageGroup: ageStanding,
            nextMilestone: milestone,
            athletes: dataset.coverage.athletesWithFinishTime ?? dataset.coverage.athletesInBuckets,
            seasonLabel: dataset.coverage.seasonLabel,
            datasetVersion: dataset.datasetVersion
        )
    }

    /// 데이터에 있는 연령대 표기 목록 (나이 순).
    public static func ageGroups(in dataset: PaceDataset) -> [String] {
        dataset.ageGroups.map(\.ageGroup).sorted { lowerBound($0) < lowerBound($1) }
    }

    /// 나이에 해당하는 연령대 표기. 데이터에 그 구간이 없으면 nil.
    public static func ageGroup(forAge age: Int, in dataset: PaceDataset) -> String? {
        dataset.ageGroups.map(\.ageGroup).first { label in
            let parts = label.split(separator: "-").compactMap { Int($0) }
            if parts.count == 2 { return age >= parts[0] && age <= parts[1] }
            // "70+" 같은 열린 구간.
            if label.hasSuffix("+"), let lower = Int(label.dropLast()) { return age >= lower }
            return false
        }
    }

    private static func lowerBound(_ label: String) -> Int {
        Int(label.prefix { $0.isNumber }) ?? .max
    }
}

// MARK: - 약점 진단

/// 구간 하나가 내 완주 수준에 비해 어떤지.
public struct WeaknessItem: Hashable, Sendable, Identifiable {

    public enum Kind: Hashable, Sendable {
        /// 러닝 8회 + 록스존 합계. 데이터가 둘을 합쳐서만 준다.
        case running
        case station(StationKind)
    }

    public let kind: Kind
    public let actualSeconds: Double
    /// 나와 같은 완주 기록을 낸 선수들의 이 구간 기록.
    public let expectedSeconds: Double
    /// 이 구간 기록만 보면 상위 몇 % 수준인지. 완주 순위보다 크면 약점이다.
    public let levelTopPercent: Double

    /// 같은 수준 선수보다 더 쓴 시간(초). 음수면 강점.
    public var lostSeconds: Double { actualSeconds - expectedSeconds }
    public var id: Kind { kind }
}

public struct WeaknessDiagnosis: Hashable, Sendable {
    public let finishTopPercent: Double
    /// 손실이 큰 순.
    public let items: [WeaknessItem]

    /// 같은 수준 선수보다 느린 구간, 손실이 큰 순.
    public var weaknesses: [WeaknessItem] { items.filter { $0.lostSeconds >= Self.threshold } }
    /// 같은 수준 선수보다 빠른 구간, 이득이 큰 순.
    public var strengths: [WeaknessItem] {
        items.filter { $0.lostSeconds <= -Self.threshold }.sorted { $0.lostSeconds < $1.lostSeconds }
    }
    /// 약점 구간을 같은 수준만큼만 해도 줄어드는 시간(초).
    public var recoverableSeconds: Double { weaknesses.reduce(0) { $0 + $1.lostSeconds } }

    /// 이보다 작은 차이는 측정 오차로 보고 약점·강점으로 부르지 않는다.
    public static let threshold: Double = 5
}

public enum WeaknessDiagnoser {

    /// - Returns: 공식 코스 그대로 완주한 기록이 아니면 nil — 참조 데이터와 비교할 수 없다.
    public static func diagnose(_ workout: CompletedWorkout, dataset: PaceDataset) -> WeaknessDiagnosis? {
        guard workout.isStandardHyroxCourse,
              let overall = PercentileCurve(percentiles: dataset.gridP, seconds: dataset.overallS) else {
            return nil
        }
        let stationKinds = workout.orderedStationKinds
        let stationRecords = workout.stationSegments
        guard stationKinds.count == stationRecords.count, !stationRecords.isEmpty else { return nil }

        // 일시정지를 뺀 시간으로 비교한다. 구간 합과 순위가 같은 기준이어야 한다.
        let total = workout.segments.reduce(0) { $0 + $1.activeDuration }
        guard RacePlausibility.isPlausible(finishSeconds: total) else { return nil }
        let finish = overall.topPercent(forSeconds: total).value

        var items: [WeaknessItem] = []

        let runningActual = (workout.runSegments + workout.roxZoneSegments).reduce(0) { $0 + $1.activeDuration }
        if let curve = PercentileCurve(percentiles: dataset.gridP, seconds: dataset.components.runRoxS),
           let expected = curve.seconds(atTopPercent: finish) {
            items.append(WeaknessItem(
                kind: .running,
                actualSeconds: runningActual,
                expectedSeconds: expected,
                levelTopPercent: curve.topPercent(forSeconds: runningActual).value
            ))
        }

        for (kind, record) in zip(stationKinds, stationRecords) {
            guard let values = dataset.components.seconds(for: kind),
                  let curve = PercentileCurve(percentiles: dataset.gridP, seconds: values),
                  let expected = curve.seconds(atTopPercent: finish) else { return nil }
            items.append(WeaknessItem(
                kind: .station(kind),
                actualSeconds: record.activeDuration,
                expectedSeconds: expected,
                levelTopPercent: curve.topPercent(forSeconds: record.activeDuration).value
            ))
        }

        return WeaknessDiagnosis(
            finishTopPercent: finish,
            items: items.sorted { $0.lostSeconds > $1.lostSeconds }
        )
    }
}
