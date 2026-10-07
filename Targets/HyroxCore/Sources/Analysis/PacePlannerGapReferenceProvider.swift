//
//  PacePlannerGapReferenceProvider.swift
//  HyroxCore
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

/// 번들된 v3 버킷 데이터(`pace_planner.json`)로 구간별 기준 기록을 만드는 프로바이더.
///
/// 페이스 플래너와 같은 계산을 쓴다. 목표 시간 → `PacePlanner.computePlan` → 8회 러닝
/// 합계·스테이션 8개. 러닝 시간에 섞여 있는 록스존은 버킷이 알려주는 `roxFraction` 으로
/// 떼어 낸다(플래너가 화면에 러닝/록스존을 나눠 보여줄 때 쓰는 그 비율).
///
/// v4 퍼센타일 데이터셋이 준비되면 같은 `GapReferenceProviding` 을 구현한 타입으로
/// 교체하면 되고, `GapAnalyzer` 는 손대지 않아도 된다.
public struct PacePlannerGapReferenceProvider: GapReferenceProviding {

    private let planner: PacePlanner
    private let mode: PacePlanner.RunMode

    public init(planner: PacePlanner, mode: PacePlanner.RunMode = .adaptive) {
        self.planner = planner
        self.mode = mode
    }

    /// 번들 데이터를 읽어 프로바이더를 만든다.
    /// - Throws: `PaceReferenceError` — 리소스가 없거나 디코딩에 실패한 경우.
    public init(mode: PacePlanner.RunMode = .adaptive) throws {
        self.init(planner: try PaceReferenceLoader.loadPacePlanner(), mode: mode)
    }

    public func reference(for target: GapTarget, division: HyroxDivision) -> GapReference? {
        guard let goalSeconds = resolveGoalSeconds(target, division: division),
              goalSeconds > 0,
              let plan = planner.computePlan(goalTotalS: goalSeconds, division: division, mode: mode)
        else { return nil }

        // `runTimes` 는 록스존을 포함한 러닝 구간이다. 화면과 같은 비율로 분리한다.
        let split = plan.splitRunRox(plan.runTotal)

        var stations: [StationKind: TimeInterval] = [:]
        for (dataKey, seconds) in plan.stationTimes {
            guard let kind = StationKind.standardStation(forDataKey: dataKey) else { continue }
            stations[kind] = TimeInterval(seconds)
        }
        guard stations.count == StationKind.standardOrder.count else { return nil }

        return GapReference(
            totalSeconds: TimeInterval(plan.computedTotal),
            runSeconds: TimeInterval(split.run),
            roxZoneSeconds: TimeInterval(split.rox),
            stationSeconds: stations,
            percentile: plan.percentile,
            // 목표가 데이터 바깥이면 스테이블 배분은 가장자리 버킷에 고정된 값이다.
            // 그대로 격차를 계산하면 차이가 전부 러닝으로 쏠린 가짜 분석이 나온다.
            isExtrapolated: plan.rangeStatus != .inRange || plan.computedTotal != goalSeconds
        )
    }

    // MARK: - Target resolution

    private func resolveGoalSeconds(_ target: GapTarget, division: HyroxDivision) -> Int? {
        switch target {
        case .finishTime(let seconds):
            guard seconds.isFinite, seconds > 0 else { return nil }
            return Int(seconds.rounded())

        case .percentile(let percentile):
            guard percentile.isFinite, percentile > 0, percentile <= 100 else { return nil }
            return finishSeconds(forPercentile: percentile, division: division)
        }
    }

    /// 퍼센타일 → 완주 시간(초). 버킷 중앙값끼리 선형 보간한다.
    ///
    /// 버킷은 시간 오름차순이고 퍼센타일도 같이 오름차순이라(느릴수록 순위가 낮다)
    /// `PacePlanner.medianGoalSeconds` 가 50 퍼센타일을 찾는 방식과 동일하다.
    private func finishSeconds(forPercentile percentile: Double, division: HyroxDivision) -> Int? {
        guard let buckets = planner.data.divisions[division.rawValue]?.buckets,
              let first = buckets.first,
              let last = buckets.last else { return nil }

        if percentile <= Self.midPercentile(first) {
            return Int((Self.midMinutes(first) * 60).rounded())
        }

        for (index, bucket) in buckets.enumerated() where Self.midPercentile(bucket) >= percentile {
            guard index > 0 else { return Int((Self.midMinutes(bucket) * 60).rounded()) }

            let previous = buckets[index - 1]
            let span = Self.midPercentile(bucket) - Self.midPercentile(previous)
            guard span > 0 else { return Int((Self.midMinutes(bucket) * 60).rounded()) }

            let t = (percentile - Self.midPercentile(previous)) / span
            let minutes = Self.midMinutes(previous) + (Self.midMinutes(bucket) - Self.midMinutes(previous)) * t
            return Int((minutes * 60).rounded())
        }

        return Int((Self.midMinutes(last) * 60).rounded())
    }

    private static func midMinutes(_ bucket: TimeBucket) -> Double {
        Double(bucket.loMin + bucket.hiMin) / 2.0
    }

    private static func midPercentile(_ bucket: TimeBucket) -> Double {
        (bucket.pctRange[0] + bucket.pctRange[1]) / 2.0
    }
}
