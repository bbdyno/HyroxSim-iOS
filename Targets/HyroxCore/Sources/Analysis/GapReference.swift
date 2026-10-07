//
//  GapReference.swift
//  HyroxCore
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

/// 격차 분석이 "무엇을 향해" 비교할지 정하는 목표.
///
/// 두 형태를 모두 허용하는 이유: 목표 시간을 직접 정한 사용자(`finishTime`)와
/// "상위 20% 안에 들고 싶다"는 사용자(`percentile`)의 요구가 다르기 때문이다.
/// 어느 쪽이든 `GapReferenceProviding` 이 하나의 구간별 기준 기록으로 환산한다.
public enum GapTarget: Hashable, Sendable {
    /// 목표 완주 시간(초).
    case finishTime(seconds: TimeInterval)
    /// 목표 퍼센타일. `10` 이면 상위 10%. 유효 범위는 0 초과 100 이하.
    case percentile(Double)
}

/// 목표에 해당하는 구간별 기준 기록.
///
/// 러닝/록스존/스테이션의 합은 `totalSeconds` 와 같아야 한다. 합이 어긋나면
/// 구간 격차의 총합이 전체 격차와 달라져서 "비중"이 거짓말을 하게 된다.
public struct GapReference: Hashable, Sendable {
    /// 기준 완주 시간(초).
    public let totalSeconds: TimeInterval
    /// 8회 러닝 합계(록스존 제외).
    public let runSeconds: TimeInterval
    /// 록스존 합계.
    public let roxZoneSeconds: TimeInterval
    /// 공식 8개 스테이션의 기준 기록.
    public let stationSeconds: [StationKind: TimeInterval]
    /// 이 기준이 위치한 퍼센타일. 데이터가 알려주지 않으면 nil.
    public let percentile: Double?
    /// 참조 데이터가 실제로 덮는 범위를 벗어나 가장자리 버킷으로 고정된 경우 `true`.
    ///
    /// 이때 구간 배분은 실제 기록이 아니라 외삽이라, 화면에서는 분석을 감추는 편이 낫다.
    public let isExtrapolated: Bool

    public init(
        totalSeconds: TimeInterval,
        runSeconds: TimeInterval,
        roxZoneSeconds: TimeInterval,
        stationSeconds: [StationKind: TimeInterval],
        percentile: Double? = nil,
        isExtrapolated: Bool = false
    ) {
        self.totalSeconds = totalSeconds
        self.runSeconds = runSeconds
        self.roxZoneSeconds = roxZoneSeconds
        self.stationSeconds = stationSeconds
        self.percentile = percentile
        self.isExtrapolated = isExtrapolated
    }
}

/// 격차 분석이 읽는 참조 기록 데이터 소스.
///
/// 현재 구현은 v3 버킷(`PacePlanner`) 기반이지만, v4 퍼센타일 데이터셋이 들어오면
/// 이 프로토콜의 다른 구현으로 갈아끼우면 된다. `GapAnalyzer` 는 데이터 형식을 모른다.
public protocol GapReferenceProviding: Sendable {
    /// 주어진 디비전에서 목표에 해당하는 구간별 기준 기록.
    /// 데이터가 없거나 목표를 해석할 수 없으면 nil.
    func reference(for target: GapTarget, division: HyroxDivision) -> GapReference?
}

// MARK: - Station data key lookup

extension StationKind {

    /// `dataKey` 로 공식 스테이션을 되찾는다. 커스텀 스테이션은 데이터가 없어 nil.
    ///
    /// `StationKind.dataKey` 의 역방향 조회. 페이스 데이터가 `[String: Int]` 로 주는
    /// 스테이션 기록을 도메인 타입으로 올리는 데만 쓴다.
    static func standardStation(forDataKey dataKey: String) -> StationKind? {
        standardOrder.first { $0.dataKey == dataKey }
    }
}
