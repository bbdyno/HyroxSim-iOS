//
//  PFTBenchmarkEvaluator.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

// MARK: - 결과 값

/// PFT 완료 시간이 가리키는 출전 등급.
public enum PFTRecommendedDivision: String, Hashable, Sendable, CaseIterable {
    case pro
    case open

    /// 이 등급에 해당하는 실제 디비전.
    public func division(matching division: HyroxDivision) -> HyroxDivision {
        switch (self, division) {
        case (.pro, .menOpenSingle), (.pro, .menProSingle): return .menProSingle
        case (.pro, .menOpenDouble), (.pro, .menProDouble): return .menProDouble
        case (.pro, .womenOpenSingle), (.pro, .womenProSingle): return .womenProSingle
        case (.pro, .womenOpenDouble), (.pro, .womenProDouble): return .womenProDouble
        case (.open, .menOpenSingle), (.open, .menProSingle): return .menOpenSingle
        case (.open, .menOpenDouble), (.open, .menProDouble): return .menOpenDouble
        case (.open, .womenOpenSingle), (.open, .womenProSingle): return .womenOpenSingle
        case (.open, .womenOpenDouble), (.open, .womenProDouble): return .womenOpenDouble
        // 혼성 더블스는 Pro/Open 구분이 없다.
        case (_, .mixedDouble): return .mixedDouble
        }
    }
}

/// PFT 한 구간을 대회 기록 표와 맞대어 본 결과.
public struct PFTStepComparison: Hashable, Sendable, Identifiable {
    public let step: PFTStep
    public let seconds: TimeInterval
    /// 기록 표에서 읽은 퍼센타일. 낮을수록 빠르다.
    public let percentile: Double
    /// 대회 구간과 볼륨·조건이 정확히 같지 않아 어림으로 봐야 하는 항목인지 여부.
    public let isApproximate: Bool

    public var id: PFTStep { step }

    public init(step: PFTStep, seconds: TimeInterval, percentile: Double, isApproximate: Bool) {
        self.step = step
        self.seconds = seconds
        self.percentile = percentile
        self.isApproximate = isApproximate
    }
}

/// PFT 한 번의 해석 결과.
public struct PFTBenchmarkResult: Hashable, Sendable {

    public let totalSeconds: TimeInterval
    /// 완료 시간이 가리키는 등급.
    public let recommended: PFTRecommendedDivision
    /// 보도된 기준 구간(15–35분) 밖이라 권장 근거가 약한 경우 `true`.
    public let isOutsideReportedBand: Bool
    /// 예상 HYROX 완주 시간 범위(초).
    public let projectedFinishRange: ClosedRange<Int>
    /// 범위를 계산한 기준 디비전.
    public let projectionDivision: HyroxDivision
    /// 범위에 대응하는 퍼센타일 구간. 낮을수록 빠르다.
    public let projectedPercentileRange: ClosedRange<Double>
    /// 구간별 비교. 대회와 볼륨이 맞는 항목만 들어간다.
    public let stepComparisons: [PFTStepComparison]

    public init(
        totalSeconds: TimeInterval,
        recommended: PFTRecommendedDivision,
        isOutsideReportedBand: Bool,
        projectedFinishRange: ClosedRange<Int>,
        projectionDivision: HyroxDivision,
        projectedPercentileRange: ClosedRange<Double>,
        stepComparisons: [PFTStepComparison]
    ) {
        self.totalSeconds = totalSeconds
        self.recommended = recommended
        self.isOutsideReportedBand = isOutsideReportedBand
        self.projectedFinishRange = projectedFinishRange
        self.projectionDivision = projectionDivision
        self.projectedPercentileRange = projectedPercentileRange
        self.stepComparisons = stepComparisons
    }

    /// 범위의 폭(초).
    public var projectedSpreadSeconds: Int {
        projectedFinishRange.upperBound - projectedFinishRange.lowerBound
    }
}

// MARK: - 해석

/// PFT 완료 시간을 등급 권장과 예상 완주 범위로 바꾼다.
///
/// 순수 함수다. 입력은 완료 시간·기준 디비전·기록 표뿐이고 시계도 저장소도 읽지 않는다.
///
/// **근거와 한계.** 등급 경계(Pro 15–25분 / Open 25–35분)는 공식 산출식이 아니라
/// 보도된 기준값이다. PFT 시간과 대회 완주 시간을 잇는 공개된 회귀식도 없다. 그래서
/// 이 계산은 "PFT 시간 → 그 밴드 안에서의 위치 → 같은 위치의 대회 퍼센타일 → 그 퍼센타일의
/// 완주 시간" 이라는 한 단계짜리 대응일 뿐이며, 결과를 점이 아니라 **범위** 로만 낸다.
/// 밴드(15–35분)를 벗어나면 대응할 근거가 아예 없으므로 벗어난 만큼 범위를 더 넓힌다.
/// 화면에서는 항상 참고용임을 밝혀야 한다.
public enum PFTBenchmarkEvaluator {

    // MARK: 보도된 기준값

    /// 보도 기준 가장 빠른 완료 시간(15분).
    public static let reportedFastestSeconds: TimeInterval = 15 * 60
    /// Pro 와 Open 을 가르는 완료 시간(25분). 이 값 이하가 Pro.
    public static let proBoundarySeconds: TimeInterval = 25 * 60
    /// 보도 기준 가장 느린 완료 시간(35분).
    public static let reportedSlowestSeconds: TimeInterval = 35 * 60

    /// 밴드의 양 끝에 대응시키는 퍼센타일. 근거가 약해 넉넉하게 잡는다.
    static let fastestPercentile: Double = 2
    static let slowestPercentile: Double = 90
    /// 밴드 안에서의 기본 범위 폭(가운데 값의 ±6 %).
    ///
    /// 퍼센타일이 아니라 시간 비율로 잡는다. 퍼센타일 폭은 상위권에서 바닥(0 %)에 눌려
    /// 한쪽만 잘려 버리는데, 시간 비율은 어느 구간에서나 같은 뜻으로 읽힌다.
    static let baseSpreadFraction: Double = 0.06
    /// 밴드를 1분 벗어날 때마다 더 넓히는 비율, 그리고 그 상한.
    static let extraSpreadPerMinute: Double = 0.01
    static let maximumExtraSpreadFraction: Double = 0.10

    // MARK: 등급

    /// 완료 시간이 가리키는 등급. 25:00 정각은 Pro 로 본다.
    public static func recommendedDivision(forTotalSeconds seconds: TimeInterval) -> PFTRecommendedDivision {
        seconds <= proBoundarySeconds ? .pro : .open
    }

    /// 보도된 기준 구간(15–35분) 밖인지 여부.
    public static func isOutsideReportedBand(_ seconds: TimeInterval) -> Bool {
        seconds < reportedFastestSeconds || seconds > reportedSlowestSeconds
    }

    // MARK: 퍼센타일 대응

    /// 완료 시간을 대회 퍼센타일로 옮긴다. 밴드 밖은 양 끝 값으로 고정한다.
    ///
    /// 완료 시간이 늘면 퍼센타일도 절대 줄지 않는다(단조). 예상 범위의 단조성이 여기서 나온다.
    public static func estimatedPercentile(forTotalSeconds seconds: TimeInterval) -> Double {
        guard seconds.isFinite else { return slowestPercentile }
        if seconds <= reportedFastestSeconds { return fastestPercentile }
        if seconds >= reportedSlowestSeconds { return slowestPercentile }

        let span = reportedSlowestSeconds - reportedFastestSeconds
        let t = (seconds - reportedFastestSeconds) / span
        return fastestPercentile + (slowestPercentile - fastestPercentile) * t
    }

    // MARK: 해석

    /// PFT 결과를 해석한다.
    ///
    /// - Parameters:
    ///   - totalSeconds: PFT 완료 시간.
    ///   - projectionDivision: 예상 완주 범위를 계산할 기준 디비전.
    ///   - dataset: 그 디비전의 기록 표.
    ///   - stepSeconds: 구간별 소요 시간. 비어 있으면 구간 비교 없이 총평만 낸다.
    public static func evaluate(
        totalSeconds: TimeInterval,
        projectionDivision: HyroxDivision,
        dataset: PaceDataset,
        stepSeconds: [PFTStep: TimeInterval] = [:]
    ) -> PFTBenchmarkResult {

        let total = max(0, totalSeconds)
        let centre = estimatedPercentile(forTotalSeconds: total)
        let centreFinish = dataset.goalSeconds(atPercentile: centre)
        let range = finishRange(forTotalSeconds: total, centreFinishSeconds: centreFinish)

        // 표의 퍼센타일은 완주 시간에 대해 단조라 아래 끝이 곧 빠른 쪽이다.
        // 그래도 두 값을 정렬해 두어 잘못된 구간이 만들어질 여지를 없앤다.
        let lowerPercentile = dataset.percentile(forGoalSeconds: range.lowerBound)
        let upperPercentile = dataset.percentile(forGoalSeconds: range.upperBound)
        let percentileRange = min(lowerPercentile, upperPercentile)...max(lowerPercentile, upperPercentile)

        return PFTBenchmarkResult(
            totalSeconds: total,
            recommended: recommendedDivision(forTotalSeconds: total),
            isOutsideReportedBand: isOutsideReportedBand(total),
            projectedFinishRange: range,
            projectionDivision: projectionDivision,
            projectedPercentileRange: percentileRange,
            stepComparisons: comparisons(for: stepSeconds, dataset: dataset)
        )
    }

    /// 예상 완주 시간 범위.
    ///
    /// 밴드 밖에서는 **바깥쪽으로만** 더 넓힌다 — 빨라질수록 아래 끝만 더 내려가고
    /// 느려질수록 위 끝만 더 올라간다. 가운데 값과 각 배율이 모두 완료 시간에 대해
    /// 단조라서, 두 끝도 단조를 유지한다(느린 PFT 가 더 빠른 예상을 내는 일이 없다).
    static func finishRange(
        forTotalSeconds seconds: TimeInterval,
        centreFinishSeconds centre: Int
    ) -> ClosedRange<Int> {
        let minutesBelow = max(0, (reportedFastestSeconds - seconds) / 60)
        let minutesAbove = max(0, (seconds - reportedSlowestSeconds) / 60)

        let extraBelow = min(maximumExtraSpreadFraction, minutesBelow * extraSpreadPerMinute)
        let extraAbove = min(maximumExtraSpreadFraction, minutesAbove * extraSpreadPerMinute)

        let base = Double(max(0, centre))
        let lower = Int((base * (1 - baseSpreadFraction - extraBelow)).rounded())
        let upper = Int((base * (1 + baseSpreadFraction + extraAbove)).rounded())

        return min(lower, upper)...max(lower, upper)
    }

    // MARK: 구간 비교

    /// 대회 기록 표와 맞대어 볼 수 있는 구간만 비교한다.
    ///
    /// - 로잉 1 km, 월볼 100 회: 대회 볼륨과 **같다** → 그대로 비교.
    /// - 런 1 km: 대회 러닝 평균 한 바퀴와 비교하되, 그 평균에는 록스존과 누적 피로가
    ///   섞여 있으므로 어림값(`isApproximate`)으로 표시한다.
    /// - 버피(50회 vs 80 m) · 런지(무게 없음) · 푸시업(대회에 없음): 견줄 기준이 없어 제외.
    static func comparisons(
        for stepSeconds: [PFTStep: TimeInterval],
        dataset: PaceDataset
    ) -> [PFTStepComparison] {

        var result: [PFTStepComparison] = []
        let grid = dataset.gridP

        for step in PFTStep.allCases {
            guard let seconds = stepSeconds[step], seconds > 0 else { continue }

            let curve: [Double]?
            let isApproximate: Bool

            switch step {
            case .row, .wallBalls:
                curve = step.standardStation
                    .flatMap { dataset.components.seconds(for: $0) }
                    .map { $0.map(Double.init) }
                isApproximate = false

            case .run:
                // 표의 러닝 값은 8바퀴 + 록스존 합계다. 한 바퀴 기준으로 낮춰서 본다.
                let laps = Double(PacePlanner.runCount)
                curve = dataset.components.runRoxS.map { Double($0) / laps }
                isApproximate = true

            case .burpeeBroadJumps, .lunges, .pushUps:
                curve = nil
                isApproximate = true
            }

            guard let curve,
                  let value = percentile(forSeconds: seconds, curve: curve, grid: grid) else { continue }

            result.append(
                PFTStepComparison(
                    step: step,
                    seconds: seconds,
                    percentile: value,
                    isApproximate: isApproximate
                )
            )
        }

        return result
    }

    /// 구간 시간을 퍼센타일로 옮긴다.
    ///
    /// 곡선이 단조 증가일 때만 답한다. 표본이 적은 구간은 곡선이 평평하거나 뒤집힐 수
    /// 있는데, 그런 곡선에서 읽은 값은 "느릴수록 좋은 등수" 같은 거짓을 만들기 때문이다.
    static func percentile(forSeconds seconds: TimeInterval, curve: [Double], grid: [Double]) -> Double? {
        guard curve.count == grid.count, curve.count >= 2 else { return nil }
        guard zip(curve, curve.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        return PaceInterpolation.interpolate(seconds, xs: curve, ys: grid)
    }
}
