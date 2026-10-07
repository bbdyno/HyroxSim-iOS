//
//  StationTarget.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// Represents the target/goal for a station exercise.
/// Weight is handled separately via `WorkoutSegment.weightKg` since it varies by division.
public enum StationTarget: Codable, Hashable, Sendable {
    case distance(meters: Double)
    case reps(count: Int)
    case duration(seconds: TimeInterval)
    case none

    /// Human-readable formatted string
    /// 비정상 값(NaN/무한대/`Int` 범위 초과)이 들어와도 트랩 없이 포맷한다.
    public var formatted: String {
        switch self {
        case .distance(let meters):
            return "\(DurationFormatter.safeInt(meters)) m"
        case .reps(let count):
            return "\(count) reps"
        case .duration(let seconds):
            return DurationFormatter.ms(seconds)
        case .none:
            return "—"
        }
    }
}
