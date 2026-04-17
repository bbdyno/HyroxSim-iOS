//
//  PacePlanner.swift
//  HyroxCore
//
//  Created by bbdyno on 4/17/26.
//

import Foundation

// MARK: - JSON Schema (matches pace_planner.json)

/// Pre-computed bucket data for pace planning (matching hyrox-predictor site algorithm).
public struct PacePlannerData: Codable, Sendable {
    public let schemaVersion: Int
    public let updatedAt: String
    public let bucketSizeMin: Int
    public let runRatioTable: [RunRatioRow]
    public let divisions: [String: PlannerDivision]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case bucketSizeMin = "bucket_size_min"
        case runRatioTable = "run_ratio_table"
        case divisions
    }
}

/// Row in the run ratio table (fatigue curve by finish time).
public struct RunRatioRow: Codable, Sendable {
    /// Target overall time in seconds.
    public let t: Int
    /// 8 ratio values (Run1=Run2=1.0, later runs progressively slower).
    public let r: [Double]
}

/// Bucket data for one division.
public struct PlannerDivision: Codable, Sendable {
    public let totalAthletes: Int
    public let buckets: [TimeBucket]

    enum CodingKeys: String, CodingKey {
        case totalAthletes = "total_athletes"
        case buckets
    }
}

/// A 5-minute time bucket with averages.
public struct TimeBucket: Codable, Sendable {
    public let loMin: Int
    public let hiMin: Int
    public let count: Int
    public let pctRange: [Double]
    public let avgOverall: Int
    public let avgRun: Int
    public let avgRox: Int
    public let avgRunRox: Int
    public let avgPace87: Int
    public let avgStationTotal: Int
    public let stations: [String: Int]

    enum CodingKeys: String, CodingKey {
        case loMin = "lo_min"
        case hiMin = "hi_min"
        case count
        case pctRange = "pct_range"
        case avgOverall = "avg_overall"
        case avgRun = "avg_run"
        case avgRox = "avg_rox"
        case avgRunRox = "avg_run_rox"
        case avgPace87 = "avg_pace_8_7"
        case avgStationTotal = "avg_station_total"
        case stations
    }
}

// MARK: - Interpolated Result

/// Linearly interpolated result between two buckets.
public struct InterpolatedBucket: Sendable {
    public let pctRange: (Double, Double)
    public let avgOverall: Int
    public let avgRun: Int
    public let avgRox: Int
    public let avgRunRox: Int
    public let avgPace87: Int
    public let avgStationTotal: Int
    public let stations: [String: Int]

    /// Midpoint percentile.
    public var percentile: Double { (pctRange.0 + pctRange.1) / 2 }

    /// Fraction of run+rox that is roxzone (0.0-1.0).
    public var roxFraction: Double {
        avgRunRox > 0 ? Double(avgRox) / Double(avgRunRox) : 0
    }
}

// MARK: - Pace Planner Engine

/// Pace planner matching hyrox-predictor site algorithm exactly.
public struct PacePlanner: Sendable {

    public let data: PacePlannerData
    public let reference: PaceReference?

    public init(data: PacePlannerData, reference: PaceReference? = nil) {
        self.data = data
        self.reference = reference
    }

    // MARK: - Bucket Interpolation (lerp)

    /// Interpolate bucket data for a target time in minutes.
    public func interpolate(targetMinutes: Double, division: HyroxDivision) -> InterpolatedBucket? {
        guard let div = data.divisions[division.rawValue] else { return nil }
        return lerp(buckets: div.buckets, targetMinutes: targetMinutes)
    }

    private func lerp(buckets: [TimeBucket], targetMinutes: Double) -> InterpolatedBucket? {
        func mid(_ b: TimeBucket) -> Double { Double(b.loMin + b.hiMin) / 2.0 }

        var lo: TimeBucket?
        var hi: TimeBucket?

        for b in buckets {
            if mid(b) <= targetMinutes { lo = b }
            if mid(b) >= targetMinutes && hi == nil { hi = b }
        }

        guard let loB = lo ?? hi, let hiB = hi ?? lo else { return nil }

        if loB.loMin == hiB.loMin && loB.hiMin == hiB.hiMin {
            return InterpolatedBucket(
                pctRange: (loB.pctRange[0], loB.pctRange[1]),
                avgOverall: loB.avgOverall,
                avgRun: loB.avgRun,
                avgRox: loB.avgRox,
                avgRunRox: loB.avgRunRox,
                avgPace87: loB.avgPace87,
                avgStationTotal: loB.avgStationTotal,
                stations: loB.stations
            )
        }

        let t = (targetMinutes - mid(loB)) / (mid(hiB) - mid(loB))
        func L(_ a: Int, _ b: Int) -> Int { Int((Double(a) + Double(b - a) * t).rounded()) }
        func Ld(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }

        var stations: [String: Int] = [:]
        for (key, loVal) in loB.stations {
            if let hiVal = hiB.stations[key] {
                stations[key] = L(loVal, hiVal)
            }
        }

        return InterpolatedBucket(
            pctRange: (
                (Ld(loB.pctRange[0], hiB.pctRange[0]) * 10).rounded() / 10,
                (Ld(loB.pctRange[1], hiB.pctRange[1]) * 10).rounded() / 10
            ),
            avgOverall: L(loB.avgOverall, hiB.avgOverall),
            avgRun: L(loB.avgRun, hiB.avgRun),
            avgRox: L(loB.avgRox, hiB.avgRox),
            avgRunRox: L(loB.avgRunRox, hiB.avgRunRox),
            avgPace87: L(loB.avgPace87, hiB.avgPace87),
            avgStationTotal: L(loB.avgStationTotal, hiB.avgStationTotal),
            stations: stations
        )
    }

    // MARK: - Run Distribution

    /// Run mode for distributing total run time across 8 laps.
    public enum RunMode: String, Sendable {
        case equal    // 균등: all runs equal
        case adaptive // 실전: data-driven fatigue curve
    }

    /// Get run time for a specific lap.
    /// - Parameters:
    ///   - index: Run index (0-7)
    ///   - paceSeconds87: Pace in seconds per 8.7km-equivalent lap
    ///   - totalSeconds: Target overall time in seconds (for adaptive ratio lookup)
    ///   - mode: Distribution mode
    public func runTime(index: Int, paceSeconds87: Int, totalSeconds: Int, mode: RunMode) -> Int {
        let totalRun = Double(paceSeconds87) * 8.7

        switch mode {
        case .equal:
            return Int((totalRun / 8.0).rounded())
        case .adaptive:
            let ratios = interpolatedRunRatios(targetSeconds: totalSeconds)
            let sum = ratios.reduce(0, +)
            return Int((totalRun * ratios[index] / sum).rounded())
        }
    }

    /// Interpolate run ratios from the table for a given target time.
    public func interpolatedRunRatios(targetSeconds: Int) -> [Double] {
        let table = data.runRatioTable
        let target = Double(targetSeconds)

        guard let first = table.first, let last = table.last else {
            return [1, 1, 1, 1, 1, 1, 1, 1]
        }

        if target <= Double(first.t) { return first.r }
        if target >= Double(last.t) { return last.r }

        for i in 0..<table.count - 1 {
            let lo = table[i], hi = table[i + 1]
            if target >= Double(lo.t) && target <= Double(hi.t) {
                let f = (target - Double(lo.t)) / Double(hi.t - lo.t)
                return zip(lo.r, hi.r).map { $0.0 + ($0.1 - $0.0) * f }
            }
        }

        return last.r
    }

    // MARK: - Full Plan Computation (matching renderDetail)

    /// Compute a full pace plan for a target time.
    public func computePlan(goalTotalS: Int, division: HyroxDivision, mode: RunMode = .adaptive) -> PacePlan? {
        let targetMin = Double(goalTotalS) / 60.0
        guard let bucket = interpolate(targetMinutes: targetMin, division: division),
              let div = data.divisions[division.rawValue] else { return nil }

        // Station totals from bucket
        var stationTimes = bucket.stations
        var stnTotal = stationTimes.values.reduce(0, +)

        // Solve for pace (matching renderDetail)
        let targetRun = goalTotalS - stnTotal
        let basePace = max(1, Int((Double(targetRun) / 8.7).rounded()))
        var bestPace = basePace
        var bestDiff = Int.max
        for p in max(1, basePace - 3)...basePace + 3 {
            let runT = 8 * Int((Double(p) * 8.7 / 8.0).rounded())
            let diff = abs(targetRun - runT)
            if diff < bestDiff { bestDiff = diff; bestPace = p }
        }

        // Compute run times
        var runTimes: [Int] = []
        for i in 0..<8 {
            runTimes.append(runTime(index: i, paceSeconds87: bestPace, totalSeconds: goalTotalS, mode: mode))
        }

        // Rebalance stations (matching rebalanceStations)
        let runTotal = runTimes.reduce(0, +)
        var residual = goalTotalS - (runTotal + stnTotal)
        let stationOrder = ["skiErg", "sledPush", "sledPull", "burpeeBroadJumps",
                            "rowing", "farmersCarry", "sandbagLunges", "wallBalls"]

        if residual != 0 {
            let sign = residual > 0 ? 1 : -1
            var remaining = abs(residual)
            var idx = 0
            while remaining > 0 && idx < 400 {
                let key = stationOrder[idx % 8]
                if let val = stationTimes[key], val + sign >= 1 {
                    stationTimes[key] = val + sign
                    remaining -= 1
                }
                idx += 1
            }
            stnTotal = stationTimes.values.reduce(0, +)
        }

        let total = runTotal + stnTotal

        return PacePlan(
            goalTotalS: goalTotalS,
            runTimes: runTimes,
            stationTimes: stationTimes,
            paceSeconds87: bestPace,
            percentile: bucket.percentile,
            totalAthletes: div.totalAthletes,
            computedTotal: total,
            mode: mode,
            roxFraction: bucket.roxFraction
        )
    }

    // MARK: - Percentile Tier

    public static func tier(for percentile: Double) -> String {
        if percentile <= 1 { return "APEX" }
        if percentile <= 3 { return "PRO" }
        if percentile <= 5 { return "EXPERT" }
        if percentile <= 10 { return "STRONG" }
        if percentile <= 25 { return "SOLID" }
        if percentile <= 50 { return "STEADY" }
        if percentile <= 75 { return "RISING" }
        return "STARTER"
    }

    /// Level label from benchmark data (optional, for backward compat).
    public func levelLabel(totalS: Int, division: HyroxDivision) -> String? {
        guard let bench = reference?.benchmark(for: division) else { return nil }
        let levels: [(String, String)] = [
            ("elite", "Elite"), ("advanced", "Advanced"), ("strong", "Strong"),
            ("average", "Average"), ("beginner", "Beginner"),
        ]
        for (key, label) in levels {
            if let threshold = bench.levelTotalS[key], totalS <= threshold { return label }
        }
        return "Beginner+"
    }
}

// MARK: - Pace Plan Result

public struct PacePlan: Sendable {
    public let goalTotalS: Int
    /// Per-run times (8 values, includes roxzone).
    public let runTimes: [Int]
    /// Per-station times, keyed by StationKind raw string.
    public let stationTimes: [String: Int]
    /// Pace in seconds for 8.7km equivalent.
    public let paceSeconds87: Int
    /// Percentile rank (0-100).
    public let percentile: Double
    /// Total athletes in dataset.
    public let totalAthletes: Int
    /// Computed total (should equal goalTotalS).
    public let computedTotal: Int
    /// Distribution mode used.
    public let mode: PacePlanner.RunMode
    /// Fraction of run+rox that is roxzone (0.0-1.0), from bucket data.
    public let roxFraction: Double

    /// Total run time.
    public var runTotal: Int { runTimes.reduce(0, +) }
    /// Total station time.
    public var stationTotal: Int { stationTimes.values.reduce(0, +) }

    /// Split a combined run+rox time into (run, rox) using the data-driven fraction.
    public func splitRunRox(_ combinedS: Int) -> (run: Int, rox: Int) {
        let rox = Int((Double(combinedS) * roxFraction).rounded())
        return (combinedS - rox, rox)
    }
}
