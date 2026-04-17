//
//  PaceDistributor.swift
//  HyroxCore
//
//  Created by bbdyno on 4/17/26.
//

import Foundation

/// Distributes a user's goal total time across 31 segments based on benchmark ratios.
public struct PaceDistributor: Sendable {

    public let reference: PaceReference

    public init(reference: PaceReference) {
        self.reference = reference
    }

    /// Result of distributing a goal time for a division.
    public struct Distribution: Sendable {
        /// Goal time per run lap (8 values, in seconds).
        public let runGoals: [Int]
        /// Goal time per station, keyed by StationKind raw string (8 entries).
        public let stationGoals: [String: Int]
        /// Goal time per roxzone transition, in seconds (all 15 equal).
        public let roxzoneGoalPerZone: Int
        /// The total after distribution (should equal goalTotalS).
        public let distributedTotal: Int
    }

    /// Distribute `goalTotalS` across segments for the given division.
    /// Returns nil if the division has no benchmark data.
    public func distribute(goalTotalS: Int, division: HyroxDivision) -> Distribution? {
        guard let bench = reference.benchmark(for: division) else { return nil }

        let scale = Double(goalTotalS) / Double(bench.referenceTotalS)

        // Station goals
        var stationGoals: [String: Int] = [:]
        for (key, refSeconds) in bench.stations {
            stationGoals[key] = Int((Double(refSeconds) * scale).rounded())
        }

        // Run goals with progressive fatigue
        let scaledRunTotal = Double(bench.runTotalS) * scale
        let weights = reference.runDistribution.weights
        var runGoals = weights.map { Int((scaledRunTotal * $0).rounded()) }

        // Adjust rounding error on the last run
        let runSum = runGoals.reduce(0, +)
        let targetRunTotal = Int(scaledRunTotal.rounded())
        runGoals[7] += targetRunTotal - runSum

        // Roxzone: 15 zones, distributed equally
        let scaledRoxTotal = Double(bench.roxzoneTotalS) * scale
        let roxPerZone = Int((scaledRoxTotal / 15.0).rounded())

        // Compute distributed total
        let stationTotal = stationGoals.values.reduce(0, +)
        let roxTotal = roxPerZone * 15
        let distributedTotal = targetRunTotal + stationTotal + roxTotal

        return Distribution(
            runGoals: runGoals,
            stationGoals: stationGoals,
            roxzoneGoalPerZone: roxPerZone,
            distributedTotal: distributedTotal
        )
    }
}
