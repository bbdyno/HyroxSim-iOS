//
//  SegmentStrip.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 레이스를 한 줄로 보여 주는 구간 띠의 한 칸.
public enum SegmentStripState: Hashable, Sendable {
    /// 끝난 칸 — 목표보다 빨랐다.
    case ahead
    /// 끝난 칸 — 목표보다 느렸다.
    case behind
    /// 끝난 칸 — 목표가 없었다.
    case neutral
    /// 지금 하고 있는 칸.
    case current
    /// 아직 안 한 칸.
    case upcoming
}

/// 운동 중 구간 띠를 만든다. 스테이션은 한 칸, 그 사이의 런·록스존은 묶어서 한 칸이다
/// (표준 코스면 16칸).
public enum SegmentStripBuilder {

    /// - Parameter currentIndex: 지금 구간의 번호. 운동이 끝났으면 nil — 전부 끝난 칸으로 그린다.
    public static func cells(
        segments: [WorkoutSegment],
        records: [SegmentRecord],
        currentIndex: Int?
    ) -> [SegmentStripState] {
        let position = currentIndex ?? segments.count
        var cells: [SegmentStripState] = []

        func append(_ range: Range<Int>) {
            if range.contains(position) {
                cells.append(.current)
            } else if range.upperBound <= position {
                var actual: TimeInterval = 0
                var goal: TimeInterval = 0
                var hasGoal = false
                for index in range where index < records.count {
                    actual += records[index].activeDuration
                    if let segmentGoal = records[index].goalDurationSeconds {
                        goal += segmentGoal
                        hasGoal = true
                    }
                }
                cells.append(hasGoal ? (actual > goal ? .behind : .ahead) : .neutral)
            } else {
                cells.append(.upcoming)
            }
        }

        var index = 0
        while index < segments.count {
            if segments[index].type == .station {
                append(index..<(index + 1))
                index += 1
            } else {
                var end = index
                while end < segments.count, segments[end].type != .station { end += 1 }
                append(index..<end)
                index = end
            }
        }
        return cells
    }
}
