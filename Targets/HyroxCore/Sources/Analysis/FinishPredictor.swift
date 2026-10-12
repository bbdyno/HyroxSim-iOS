//
//  FinishPredictor.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 대회 예상 완주 기록.
public struct FinishPrediction: Hashable, Sendable {

    /// 예측을 얼마나 믿을 만한지. 근거가 된 기록 수로만 정한다.
    public enum Confidence: Hashable, Sendable {
        /// 기록 1개.
        case low
        /// 기록 2개.
        case medium
        /// 기록 3개 이상.
        case high
    }

    public let division: HyroxDivision
    /// 예상 완주 시간(초).
    public let seconds: Double
    /// 예상 범위. 근거가 된 기록 가운데 가장 빠른 것과 느린 것.
    public let fastestSeconds: Double
    public let slowestSeconds: Double
    public let confidence: Confidence
    /// 근거가 된 기록 수.
    public let basedOn: Int
    /// 근거가 된 가장 최근 기록의 날짜.
    public let latestDate: Date
    /// 주당 변화(초). 음수면 빨라지는 중. 기록이 2개 미만이거나 기간이 1주 미만이면 nil.
    public let trendSecondsPerWeek: Double?
    /// 예상 기록이 실제 대회 참가자 중 상위 몇 % 인지.
    public let topPercent: Double?
    /// 등록한 대회 목표가 있으면, 예상 − 목표(초). 양수면 목표보다 느리다.
    public let gapToGoalSeconds: Double?
}

/// 최근 공식 코스 기록으로 대회 기록을 예상한다.
///
/// 일부러 단순하다. 훈련 세션이나 커스텀 운동은 쓰지 않는다 — 기록에 스테이션의 거리·무게가
/// 남지 않아 공식 규격으로 한 것인지 알 수 없고, 쉬지 않고 이어 달린 피로도 반영되지 않는다.
/// 공식 코스를 처음부터 끝까지 달린 기록만이 대회 기록과 같은 것을 잰다.
///
/// 예상값은 최근 3개 기록의 가중 평균(최신일수록 무겁게)이고, 추세를 미래로 늘려 잡지 않는다.
public enum FinishPredictor {

    /// 이보다 오래된 기록은 지금 체력을 말해 주지 않는다고 본다.
    public static let lookbackDays = 180
    static let weights: [Double] = [3, 2, 1]

    /// - Parameters:
    ///   - workouts: 순서 무관. 디비전이 다르거나 공식 코스가 아닌 기록은 걸러 낸다.
    ///   - dataset: 있으면 예상 기록의 순위를 함께 낸다.
    ///   - goalSeconds: 등록한 대회의 목표 시간.
    /// - Returns: 근거로 쓸 기록이 하나도 없으면 nil.
    public static func predict(
        from workouts: [CompletedWorkout],
        division: HyroxDivision,
        dataset: PaceDataset? = nil,
        goalSeconds: TimeInterval? = nil,
        now: Date = Date()
    ) -> FinishPrediction? {
        let cutoff = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        let races = workouts
            .filter { $0.division == division && $0.finishedAt >= cutoff && $0.finishedAt <= now }
            .filter { $0.isStandardHyroxCourse }
            .filter { RacePlausibility.isPlausible(finishSeconds: $0.totalActiveDuration) }
            .sorted { $0.finishedAt > $1.finishedAt }
        guard let latest = races.first else { return nil }

        let recent = Array(races.prefix(weights.count))
        let times = recent.map(\.totalActiveDuration)
        let usedWeights = weights.prefix(times.count)
        let weighted = zip(times, usedWeights).reduce(0.0) { $0 + $1.0 * $1.1 }
        let seconds = weighted / usedWeights.reduce(0, +)

        let confidence: FinishPrediction.Confidence
        switch races.count {
        case 1: confidence = .low
        case 2: confidence = .medium
        default: confidence = .high
        }

        var topPercent: Double?
        if let dataset, dataset.division == division,
           let curve = PercentileCurve(percentiles: dataset.gridP, seconds: dataset.overallS) {
            topPercent = curve.topPercent(forSeconds: seconds).value
        }

        return FinishPrediction(
            division: division,
            seconds: seconds,
            fastestSeconds: times.min() ?? seconds,
            slowestSeconds: times.max() ?? seconds,
            confidence: confidence,
            basedOn: recent.count,
            latestDate: latest.finishedAt,
            trendSecondsPerWeek: trend(of: recent),
            topPercent: topPercent,
            gapToGoalSeconds: goalSeconds.map { seconds - $0 }
        )
    }

    /// 근거 기록의 처음과 끝을 이은 기울기.
    private static func trend(of recent: [CompletedWorkout]) -> Double? {
        guard let newest = recent.first, let oldest = recent.last, recent.count >= 2 else { return nil }
        let weeks = newest.finishedAt.timeIntervalSince(oldest.finishedAt) / (7 * 86_400)
        guard weeks >= 1 else { return nil }
        return (newest.totalActiveDuration - oldest.totalActiveDuration) / weeks
    }
}
