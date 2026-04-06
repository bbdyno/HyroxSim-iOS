//
//  SegmentType.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// Represents the type of a workout segment
public enum SegmentType: String, Codable, Hashable, Sendable {
    /// 1 km run segment (GPS-based tracking)
    case run
    /// ROX Zone transition segment (GPS-based tracking)
    case roxZone
    /// Station exercise segment (heart rate only, no GPS)
    case station

    /// Whether this segment type uses location tracking
    public var tracksLocation: Bool {
        switch self {
        case .run, .roxZone: return true
        case .station: return false
        }
    }

    /// Whether this segment type tracks heart rate
    public var tracksHeartRate: Bool { true }
}
