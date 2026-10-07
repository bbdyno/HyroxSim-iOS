//
//  TeamSplitReference.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

/// 팀 목표 시간에 해당하는 코스 구성 — "이 시간에 들어오려면 각 구간에 몇 초씩 쓰는가".
///
/// 분담 계산의 유일한 입력이다. 계산기(`TeamSplitCalculator`)는 이 값만 보고 움직이므로,
/// 기록 표가 바뀌든 사용자가 직접 숫자를 넣든 계산 쪽은 손대지 않아도 된다.
///
/// 불변식: `runRoxSeconds + 스테이션 8종 합 == totalSeconds`. 만드는 경로가 모두
/// `apportion` 으로 나머지를 나눠 담으므로 반올림 때문에 어긋나지 않는다.
public struct TeamSplitReference: Hashable, Sendable {

    /// 팀 목표 완주 시간(초).
    public let totalSeconds: TimeInterval
    /// 러닝 8회 + 록스존 전환을 합친 시간.
    ///
    /// 더블스에서는 이 시간이 통째로 **팀 공통** 이다 — 둘이 함께 뛰어야 하므로 나눌 수 없다.
    /// 릴레이에서는 구간(1 km + 스테이션)을 맡은 사람의 몫으로 들어간다.
    public let runRoxSeconds: TimeInterval
    /// 공식 8개 스테이션의 예상 소요 시간.
    public let stationSeconds: [StationKind: TimeInterval]
    /// 구성을 빌려 온 디비전.
    public let division: HyroxDivision
    /// 기록 표에서 그대로 읽지 못하고 비율로 늘린 값인지 여부.
    ///
    /// 릴레이는 공식 기록 표가 없어 항상 `true` 다. 더블스도 목표가 표의 범위를 벗어나면 `true`.
    public let isEstimated: Bool

    public init(
        totalSeconds: TimeInterval,
        runRoxSeconds: TimeInterval,
        stationSeconds: [StationKind: TimeInterval],
        division: HyroxDivision,
        isEstimated: Bool
    ) {
        self.totalSeconds = totalSeconds
        self.runRoxSeconds = runRoxSeconds
        self.stationSeconds = stationSeconds
        self.division = division
        self.isEstimated = isEstimated
    }

    /// 공식 8개 스테이션 합계. 사전에 뭐가 더 들어 있어도 공식 종목만 더한다.
    public var stationTotalSeconds: TimeInterval {
        StationKind.standardOrder.reduce(0) { $0 + (stationSeconds[$1] ?? 0) }
    }

    public func seconds(for station: StationKind) -> TimeInterval {
        stationSeconds[station] ?? 0
    }

    /// 릴레이 한 구간(1 km + 전환)의 러닝 시간. 8구간으로 균등하게 본다.
    public var runRoxSecondsPerLeg: TimeInterval {
        runRoxSeconds / Double(StationKind.standardOrder.count)
    }
}

// MARK: - 기록 표에서 만들기

extension TeamSplitReference {

    /// 릴레이 구성을 빌려 올 퍼센타일.
    ///
    /// 릴레이는 기록 표가 없다. 그래서 같은 디비전 표의 *중앙값* 구성 비율만 가져와
    /// 팀 목표 시간에 맞춰 늘리거나 줄인다. 어느 퍼센타일을 쓰든 구간 비율은 크게 다르지
    /// 않지만, 값이 눈에 띄게 흔들리지 않도록 한 점에 고정해 둔다.
    static let relayShapePercentile: Double = 50

    /// 팀 목표 시간에 해당하는 구성을 만든다.
    ///
    /// - 더블스: 자기 디비전 기록 표에서 목표 시간의 구간 구성을 그대로 읽는다.
    ///   목표가 표가 덮는 구간 밖이면 가장 가까운 끝의 *비율* 을 목표에 맞춰 늘리고
    ///   `isEstimated` 를 세운다.
    /// - 릴레이: 표가 없으므로 중앙값 구성 비율을 목표에 맞춰 늘린다. 항상 추정값이다.
    public static func make(
        entry: TeamEntry,
        dataset: PaceDataset,
        goalSeconds: Int
    ) -> TeamSplitReference {
        let goal = max(1, goalSeconds)

        switch entry.format {
        case .doubles:
            let split = dataset.components(forGoalSeconds: goal)
            return scaled(
                split,
                to: goal,
                division: entry.referenceDivision,
                isEstimated: !dataset.coversGoalSeconds(goal)
            )

        case .relay:
            let split = dataset.components(atPercentile: relayShapePercentile)
            return scaled(
                split,
                to: goal,
                division: entry.referenceDivision,
                isEstimated: true
            )
        }
    }

    /// 구간 구성을 목표 시간에 비례해서 늘린다.
    ///
    /// 9개 값(러닝+록스존, 스테이션 8종)을 같은 비율로 곱한 뒤 최대 잔여 방식으로 반올림해,
    /// 합이 목표 시간과 **정확히** 같아지게 한다. 비율만 쓰므로 목표를 키우면 모든 구간이
    /// 같이 커진다(단조).
    static func scaled(
        _ split: PaceComponentSplit,
        to totalSeconds: Int,
        division: HyroxDivision,
        isEstimated: Bool
    ) -> TeamSplitReference {
        let stations = StationKind.standardOrder
        let source = split.overallSeconds
        let factor = source > 0 ? Double(totalSeconds) / Double(source) : 0

        var exact: [Double] = [Double(split.runRoxSeconds) * factor]
        for station in stations {
            exact.append(Double(split.seconds(for: station) ?? 0) * factor)
        }

        let apportioned = PaceInterpolation.apportion(exact, total: totalSeconds)

        var stationSeconds: [StationKind: TimeInterval] = [:]
        for (offset, station) in stations.enumerated() where offset + 1 < apportioned.count {
            stationSeconds[station] = TimeInterval(apportioned[offset + 1])
        }

        return TeamSplitReference(
            totalSeconds: TimeInterval(totalSeconds),
            runRoxSeconds: TimeInterval(apportioned.first ?? 0),
            stationSeconds: stationSeconds,
            division: division,
            isEstimated: isEstimated
        )
    }
}
