//
//  HeartRateSample.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// A single heart rate measurement.
/// Pure value type — no HealthKit dependency. The app layer converts
/// `HKQuantitySample` → `HeartRateSample` via an adapter.
public struct HeartRateSample: Hashable, Sendable, Codable {
    public let timestamp: Date
    /// Heart rate in beats per minute
    public let bpm: Int

    public init(timestamp: Date, bpm: Int) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}
