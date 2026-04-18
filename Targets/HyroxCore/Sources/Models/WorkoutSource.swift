//
//  WorkoutSource.swift
//  HyroxCore
//
//  Created by bbdyno on 4/19/26.
//

import Foundation

/// Where a completed workout came from. Used to distinguish Apple Watch
/// recordings, manual entries, and Garmin imports in history and analytics.
///
/// Raw values are the single source of truth for interop — also referenced
/// in `MESSAGE_PROTOCOL.md` and the Monkey C / Kotlin ports.
public enum WorkoutSource: String, Codable, Hashable, Sendable {
    case watch
    case manual
    case garmin

    public var displayName: String {
        switch self {
        case .watch:  return "Apple Watch"
        case .manual: return "Manual"
        case .garmin: return "Garmin"
        }
    }
}
