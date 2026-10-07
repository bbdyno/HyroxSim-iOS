//
//  RaceLapCounter.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

/// 런 구간의 랩 수를 세는 카운터.
///
/// HYROX 대회장에서 **랩은 선수 본인이 센다**. 트랙 한 바퀴 길이는 행사장마다 다르고
/// 누락하면 3분/5분/7분 또는 실격이라, 1 km 안에서 몇 바퀴를 돌았는지 직접 붙들고 있어야 한다.
///
/// 기록에는 남기지 않는다 — 화면 보조 정보이고, 구간이 바뀌면 0 으로 돌아간다.
public struct RaceLapCounter: Equatable, Sendable {

    /// 현재 구간에서 센 바퀴 수. 0 밑으로 내려가지 않는다.
    public private(set) var count: Int
    /// 지금 세고 있는 구간. 이 값이 바뀌면 카운트를 초기화한다.
    public private(set) var segmentId: UUID?

    public init(count: Int = 0, segmentId: UUID? = nil) {
        self.count = max(0, count)
        self.segmentId = segmentId
    }

    public mutating func increment() {
        count += 1
    }

    /// 한 바퀴 되돌린다. 0 에서는 아무 일도 일어나지 않는다 (잘못 눌러도 음수가 되지 않도록).
    public mutating func decrement() {
        count = max(0, count - 1)
    }

    public mutating func set(_ value: Int) {
        count = max(0, value)
    }

    public mutating func reset() {
        count = 0
    }

    /// 표시 중인 구간을 알려준다. 구간이 바뀌었으면 카운트를 0 으로 되돌린다.
    /// - Returns: 세고 있던 값이 실제로 버려졌으면 `true` (구간은 바뀌었지만 0 이었다면 `false`).
    @discardableResult
    public mutating func syncSegment(_ id: UUID?) -> Bool {
        guard segmentId != id else { return false }
        segmentId = id
        let hadCount = count > 0
        count = 0
        return hadCount
    }
}
