//
//  PaceReference.swift
//  HyroxCore
//
//  Created by bbdyno on 4/17/26.
//

import Foundation

/// Top-level container for pace reference data (matches pace-reference.v1.json).
public struct PaceReference: Codable, Sendable {
    public let schemaVersion: Int
    public let updatedAt: String
    public let runDistribution: RunDistribution
    public let divisions: [String: DivisionBenchmark]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case runDistribution = "run_distribution"
        case divisions
    }
}

/// Progressive fatigue curve for distributing total run time across 8 laps.
public struct RunDistribution: Codable, Sendable {
    public let weights: [Double]
}

/// Benchmark data for a single division.
public struct DivisionBenchmark: Codable, Sendable {
    /// Reference total time in seconds (≈50th percentile median).
    public let referenceTotalS: Int
    /// Total running time across 8 laps in seconds.
    public let runTotalS: Int
    /// Total roxzone (transition + rest) time in seconds.
    public let roxzoneTotalS: Int
    /// Per-station time in seconds, keyed by StationKind raw string.
    public let stations: [String: Int]
    /// Level anchor total times in seconds.
    public let levelTotalS: [String: Int]

    enum CodingKeys: String, CodingKey {
        case referenceTotalS = "reference_total_s"
        case runTotalS = "run_total_s"
        case roxzoneTotalS = "roxzone_total_s"
        case stations
        case levelTotalS = "level_total_s"
    }
}

// MARK: - Convenience

extension PaceReference {

    /// Look up benchmark for a specific division.
    public func benchmark(for division: HyroxDivision) -> DivisionBenchmark? {
        divisions[division.rawValue]
    }
}

extension DivisionBenchmark {

    /// Station time for a given StationKind. Returns nil for `.custom`.
    public func stationTime(for kind: StationKind) -> Int? {
        switch kind {
        case .skiErg: return stations["skiErg"]
        case .sledPush: return stations["sledPush"]
        case .sledPull: return stations["sledPull"]
        case .burpeeBroadJumps: return stations["burpeeBroadJumps"]
        case .rowing: return stations["rowing"]
        case .farmersCarry: return stations["farmersCarry"]
        case .sandbagLunges: return stations["sandbagLunges"]
        case .wallBalls: return stations["wallBalls"]
        case .custom: return nil
        }
    }

    /// Sum of all station times.
    public var stationTotalS: Int {
        stations.values.reduce(0, +)
    }
}
