//
//  CoachInsight.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 코치가 한 번의 기록에서 짚어 줄 것. 문장이 아니라 사실이다 — 문구는 앱이 언어별로 만든다.
public enum CoachInsight: Hashable, Sendable {
    /// 완주 기록의 위치.
    case standing(topPercent: Double)
    /// 같은 수준 선수보다 가장 많이 잃은 구간과, 그걸 보강할 훈련.
    case biggestLoss(WeaknessItem.Kind, lostSeconds: Double, drill: TrainingSessionKind)
    /// 같은 수준 선수보다 가장 많이 번 구간.
    case strength(WeaknessItem.Kind, gainedSeconds: Double)
    /// 마지막 러닝이 첫 러닝보다 이만큼(%) 느렸다.
    case fade(percent: Double)
    /// 러닝 페이스를 끝까지 유지했다.
    case evenPacing
    /// 최근 기록의 주당 변화(초). 음수면 빨라지는 중.
    case trend(secondsPerWeek: Double)
}

/// 기록에서 코치가 말할 사실을 고른다. 규칙만 쓰고, 같은 입력이면 항상 같은 결과다.
public enum CoachInsightBuilder {

    /// 러닝이 이만큼 느려지면 "후반에 처졌다" 고 본다.
    public static let fadeThresholdPercent = 8.0
    /// 이보다 작으면 "고르게 달렸다" 고 본다.
    public static let evenThresholdPercent = 3.0

    public static func build(
        workout: CompletedWorkout,
        diagnosis: WeaknessDiagnosis?,
        prediction: FinishPrediction?
    ) -> [CoachInsight] {
        var insights: [CoachInsight] = []

        if let diagnosis {
            insights.append(.standing(topPercent: diagnosis.finishTopPercent))
            if let worst = diagnosis.weaknesses.first {
                insights.append(.biggestLoss(worst.kind, lostSeconds: worst.lostSeconds, drill: drill(for: worst.kind)))
            }
            if let best = diagnosis.strengths.first {
                insights.append(.strength(best.kind, gainedSeconds: -best.lostSeconds))
            }
        }

        // 러닝 랩이 실제로 8개 있을 때만 — 대회 기록을 8등분한 값으로는 페이스를 말할 수 없다.
        let runs = workout.runSegments.map(\.activeDuration)
        if workout.isStandardHyroxCourse, runs.count == 8, let first = runs.first, let last = runs.last, first > 0,
           Set(runs.map { ($0 * 10).rounded() }).count > 1 {
            let percent = (last - first) / first * 100
            if percent >= fadeThresholdPercent {
                insights.append(.fade(percent: percent))
            } else if abs(percent) <= evenThresholdPercent {
                insights.append(.evenPacing)
            }
        }

        if let trend = prediction?.trendSecondsPerWeek, abs(trend) >= 5 {
            insights.append(.trend(secondsPerWeek: trend))
        }
        return insights
    }

    /// 약점 구간을 보강할 때 권하는 앱 내 훈련.
    public static func drill(for kind: WeaknessItem.Kind) -> TrainingSessionKind {
        switch kind {
        case .running: return .compromisedRun
        case .station(.wallBalls): return .wallBallLadder
        case .station: return .stationIntervals
        }
    }
}
