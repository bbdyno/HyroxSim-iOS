//
//  GapAnalyzer.swift
//  HyroxCore
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

/// 격차 분석의 한 줄. "이 구간에서 목표 대비 몇 초를 잃었는가".
public struct GapItem: Hashable, Sendable, Identifiable {

    /// 분석 단위. 러닝 8회와 록스존 전부는 각각 한 항목으로 묶는다.
    /// 한 회씩 쪼개면 스테이션보다 항상 작아 보여서, 정작 가장 큰 손실이 눈에 띄지 않는다.
    public enum Kind: Hashable, Sendable {
        /// 8회 러닝 합계.
        case run
        /// 록스존 전부의 합계.
        case roxZone
        /// 공식 스테이션 한 종목.
        case station(StationKind)
    }

    public let kind: Kind
    /// 내 기록(초).
    public let actualSeconds: TimeInterval
    /// 목표 구간 평균(초).
    public let referenceSeconds: TimeInterval
    /// 전체 격차에서 이 구간이 차지하는 비중(0...1). 목표보다 빨랐던 구간은 0.
    public let share: Double

    /// 목표 대비 차이(초). 양수면 그만큼 느렸다 = 되찾을 수 있는 시간.
    public var deltaSeconds: TimeInterval { actualSeconds - referenceSeconds }

    /// 목표보다 느렸는지 여부.
    public var isBehind: Bool { deltaSeconds > 0 }

    public var id: Kind { kind }

    public init(
        kind: Kind,
        actualSeconds: TimeInterval,
        referenceSeconds: TimeInterval,
        share: Double
    ) {
        self.kind = kind
        self.actualSeconds = actualSeconds
        self.referenceSeconds = referenceSeconds
        self.share = share
    }
}

/// 한 기록에 대한 격차 분석 결과.
public struct GapAnalysis: Hashable, Sendable {

    /// 비교 대상이 된 목표.
    public let target: GapTarget
    /// 목표의 완주 시간(초).
    public let targetTotalSeconds: TimeInterval
    /// 목표가 위치한 퍼센타일(알 수 있을 때).
    public let targetPercentile: Double?
    /// 내 구간 합계(초). 구간의 합이므로 항목 차이의 총합과 정확히 맞는다.
    public let actualTotalSeconds: TimeInterval
    /// 차이 큰 순으로 정렬된 구간 목록.
    public let items: [GapItem]
    /// 참조 데이터 범위를 벗어난 목표라 구간 배분이 외삽인 경우 `true`.
    public let isReferenceExtrapolated: Bool

    /// 목표 대비 전체 차이(초). 양수면 목표보다 느렸다.
    public var totalGapSeconds: TimeInterval { actualTotalSeconds - targetTotalSeconds }

    /// 느렸던 구간들에서만 모은 되찾을 수 있는 시간(초).
    ///
    /// `totalGapSeconds` 와 다를 수 있다. 어떤 구간은 이미 목표보다 빨랐기 때문이다.
    public var recoverableSeconds: TimeInterval {
        items.reduce(0) { $0 + max(0, $1.deltaSeconds) }
    }

    /// 이미 목표를 넘어선 기록인지 여부.
    public var isGoalAlreadyMet: Bool { totalGapSeconds <= 0 }

    /// 느렸던 구간만 차이 큰 순으로.
    public var behindItems: [GapItem] { items.filter(\.isBehind) }
}

/// 완료된 기록을 목표 구간 기록과 맞대어 "어디서 얼마를 줄여야 하는지" 계산한다.
///
/// 순수 함수다. 입력은 기록·목표·참조 데이터뿐이고 시계도 저장소도 읽지 않는다.
public struct GapAnalyzer: Sendable {

    private let referenceProvider: any GapReferenceProviding

    public init(referenceProvider: any GapReferenceProviding) {
        self.referenceProvider = referenceProvider
    }

    /// 격차 분석을 계산한다.
    ///
    /// - Parameters:
    ///   - workout: 완료된 기록.
    ///   - target: 목표(완주 시간 또는 퍼센타일).
    ///   - division: 비교에 쓸 디비전. 생략하면 기록에 붙은 디비전을 쓴다.
    /// - Returns: 표준 HYROX 코스가 아니거나, 디비전을 알 수 없거나, 참조 데이터가 없으면 nil.
    public func analyze(
        _ workout: CompletedWorkout,
        target: GapTarget,
        division: HyroxDivision? = nil
    ) -> GapAnalysis? {
        guard let division = division ?? workout.division else { return nil }
        guard workout.isStandardHyroxCourse else { return nil }
        guard let reference = referenceProvider.reference(for: target, division: division) else { return nil }

        let stationKinds = workout.orderedStationKinds
        let stationRecords = workout.stationSegments
        guard stationKinds.count == stationRecords.count else { return nil }

        let runActual = workout.runSegments.reduce(0) { $0 + $1.activeDuration }
        let roxActual = workout.roxZoneSegments.reduce(0) { $0 + $1.activeDuration }
        let hasRoxZone = !workout.roxZoneSegments.isEmpty

        var rawItems: [(kind: GapItem.Kind, actual: TimeInterval, reference: TimeInterval)] = []

        if hasRoxZone {
            rawItems.append((.run, runActual, reference.runSeconds))
            rawItems.append((.roxZone, roxActual, reference.roxZoneSeconds))
        } else {
            // 록스존 없이 달린 코스에서는 전환 시간이 러닝 기록 안에 들어 있다.
            // 기준도 러닝+록스존을 합쳐야 같은 것끼리 비교된다.
            rawItems.append((.run, runActual, reference.runSeconds + reference.roxZoneSeconds))
        }

        for (kind, record) in zip(stationKinds, stationRecords) {
            guard let referenceSeconds = reference.stationSeconds[kind] else { return nil }
            rawItems.append((.station(kind), record.activeDuration, referenceSeconds))
        }

        // 비중의 분모는 "느렸던 구간의 손실 합". 전체 격차를 분모로 쓰면 이미 목표보다
        // 빨랐던 구간이 손실을 상쇄해서 비중이 100%를 넘어 버린다.
        let totalLoss = rawItems.reduce(0.0) { $0 + max(0, $1.actual - $1.reference) }

        let items = rawItems
            .map { raw -> GapItem in
                let delta = raw.actual - raw.reference
                let share = totalLoss > 0 ? max(0, delta) / totalLoss : 0
                return GapItem(
                    kind: raw.kind,
                    actualSeconds: raw.actual,
                    referenceSeconds: raw.reference,
                    share: share
                )
            }
            .sorted { lhs, rhs in
                if lhs.deltaSeconds != rhs.deltaSeconds {
                    return lhs.deltaSeconds > rhs.deltaSeconds
                }
                // 차이가 같으면 공식 순서(러닝 → 록스존 → 스테이션 8개)로 고정해
                // 같은 입력이 항상 같은 순서를 내도록 한다.
                return Self.orderIndex(lhs.kind) < Self.orderIndex(rhs.kind)
            }

        let actualTotal = rawItems.reduce(0.0) { $0 + $1.actual }

        return GapAnalysis(
            target: target,
            targetTotalSeconds: reference.totalSeconds,
            targetPercentile: reference.percentile,
            actualTotalSeconds: actualTotal,
            items: items,
            isReferenceExtrapolated: reference.isExtrapolated
        )
    }

    private static func orderIndex(_ kind: GapItem.Kind) -> Int {
        switch kind {
        case .run:
            return 0
        case .roxZone:
            return 1
        case .station(let station):
            let index = StationKind.standardOrder.firstIndex(of: station) ?? StationKind.standardOrder.count
            return 2 + index
        }
    }
}
