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

    public init(t: Int, r: [Double]) {
        self.t = t
        self.r = r
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(Int.self, forKey: .t)
        let ratios = try container.decode([Double].self, forKey: .r)
        // `runTime(index:)` indexes this array with 0..<8 — a short row would trap.
        guard ratios.count == PacePlanner.runCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .r,
                in: container,
                debugDescription: "run_ratio_table row t=\(t) has \(ratios.count) ratios, expected \(PacePlanner.runCount)"
            )
        }
        r = ratios
    }
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
    /// Exactly the 8 official stations, keyed by `StationKind.dataKey`.
    /// Anything else in the JSON is dropped while decoding so that summing the
    /// dictionary can never mix in a non-standard station.
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        loMin = try container.decode(Int.self, forKey: .loMin)
        hiMin = try container.decode(Int.self, forKey: .hiMin)
        count = try container.decode(Int.self, forKey: .count)
        avgOverall = try container.decode(Int.self, forKey: .avgOverall)
        avgRun = try container.decode(Int.self, forKey: .avgRun)
        avgRox = try container.decode(Int.self, forKey: .avgRox)
        avgRunRox = try container.decode(Int.self, forKey: .avgRunRox)
        avgPace87 = try container.decode(Int.self, forKey: .avgPace87)
        avgStationTotal = try container.decode(Int.self, forKey: .avgStationTotal)

        let percentiles = try container.decode([Double].self, forKey: .pctRange)
        guard percentiles.count >= 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .pctRange,
                in: container,
                debugDescription: "bucket \(loMin)-\(hiMin) has \(percentiles.count) pct_range values, expected 2"
            )
        }
        pctRange = percentiles

        // A missing station would silently shrink every station total and push the
        // difference into the runs, so treat it as corrupt data instead.
        let decoded = try container.decode([String: Int].self, forKey: .stations)
        var standard: [String: Int] = [:]
        for key in StationKind.standardDataKeys {
            guard let value = decoded[key] else {
                throw DecodingError.dataCorruptedError(
                    forKey: .stations,
                    in: container,
                    debugDescription: "bucket \(loMin)-\(hiMin) is missing station key '\(key)'"
                )
            }
            standard[key] = value
        }
        stations = standard
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

// MARK: - Goal Range

/// Where a goal time sits relative to the finish times the bundled data covers.
public enum RangeStatus: String, Codable, Sendable {
    /// The goal can be interpolated from real buckets.
    case inRange
    /// Faster than the fastest bucket — the plan is pinned to that bucket's splits.
    case fasterThanData
    /// Slower than the slowest bucket — the plan is pinned to that bucket's splits.
    case slowerThanData
}

/// The span of goal finish times the division's buckets actually hold results for:
/// the low edge of the first bucket to the high edge of the last one.
///
/// Past those edges `lerp` has nothing to interpolate, so it returns the outermost
/// bucket verbatim: the station splits freeze and the entire difference lands on the
/// runs. That is what produced a 2:38/km target for a 48:00 Men's Pro goal.
///
/// Inside the outermost buckets the splits are pinned to that bucket's averages too
/// (anything past its midpoint), but those are real results for that finish time, so
/// they stay `inRange`. The tail buckets are wide because slow finishes are sparse.
public struct PaceGoalRange: Sendable, Equatable {
    public let minTotalS: Int
    public let maxTotalS: Int

    public init(minTotalS: Int, maxTotalS: Int) {
        self.minTotalS = minTotalS
        self.maxTotalS = maxTotalS
    }

    public func status(for goalTotalS: Int) -> RangeStatus {
        if goalTotalS < minTotalS { return .fasterThanData }
        if goalTotalS > maxTotalS { return .slowerThanData }
        return .inRange
    }
}

// MARK: - Pace Planner Engine

/// Pace planner matching hyrox-predictor site algorithm exactly.
public struct PacePlanner: Sendable {

    /// Runs in a standard HYROX race.
    public static let runCount = 8

    public let data: PacePlannerData

    public init(data: PacePlannerData) {
        self.data = data
    }

    // MARK: - Bucket Interpolation (lerp)

    /// Interpolate bucket data for a target time in minutes.
    public func interpolate(targetMinutes: Double, division: HyroxDivision) -> InterpolatedBucket? {
        guard let div = data.divisions[division.rawValue] else { return nil }
        return lerp(buckets: div.buckets, targetMinutes: targetMinutes)
    }

    private func lerp(buckets: [TimeBucket], targetMinutes: Double) -> InterpolatedBucket? {
        var lo: TimeBucket?
        var hi: TimeBucket?

        for b in buckets {
            if Self.midMinutes(b) <= targetMinutes { lo = b }
            if Self.midMinutes(b) >= targetMinutes && hi == nil { hi = b }
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

        let t = (targetMinutes - Self.midMinutes(loB)) / (Self.midMinutes(hiB) - Self.midMinutes(loB))
        func L(_ a: Int, _ b: Int) -> Int { Int((Double(a) + Double(b - a) * t).rounded()) }
        func Ld(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }

        var stations: [String: Int] = [:]
        for key in StationKind.standardDataKeys {
            guard let loVal = loB.stations[key], let hiVal = hiB.stations[key] else { continue }
            stations[key] = L(loVal, hiVal)
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

    private static func midMinutes(_ bucket: TimeBucket) -> Double {
        Double(bucket.loMin + bucket.hiMin) / 2.0
    }

    private static func midPercentile(_ bucket: TimeBucket) -> Double {
        (bucket.pctRange[0] + bucket.pctRange[1]) / 2.0
    }

    // MARK: - Data Coverage

    /// Goal finish times this division's buckets hold results for, in seconds.
    public func goalRange(for division: HyroxDivision) -> PaceGoalRange? {
        guard let div = data.divisions[division.rawValue],
              let first = div.buckets.first,
              let last = div.buckets.last else { return nil }

        return PaceGoalRange(
            minTotalS: first.loMin * 60,
            maxTotalS: last.hiMin * 60
        )
    }

    /// Median (50th percentile) finish time for a division, in seconds.
    ///
    /// The starting point for an athlete who has never set a goal: half the field
    /// in the dataset finished faster, half slower.
    public func medianGoalSeconds(for division: HyroxDivision) -> Int? {
        guard let div = data.divisions[division.rawValue],
              let first = div.buckets.first,
              let last = div.buckets.last else { return nil }

        let buckets = div.buckets
        for (index, bucket) in buckets.enumerated() where Self.midPercentile(bucket) >= 50 {
            guard index > 0 else { return Int((Self.midMinutes(first) * 60).rounded()) }

            let previous = buckets[index - 1]
            let span = Self.midPercentile(bucket) - Self.midPercentile(previous)
            guard span > 0 else { return Int((Self.midMinutes(bucket) * 60).rounded()) }

            let t = (50 - Self.midPercentile(previous)) / span
            let minutes = Self.midMinutes(previous) + (Self.midMinutes(bucket) - Self.midMinutes(previous)) * t
            return Int((minutes * 60).rounded())
        }

        // No bucket reaches the 50th percentile (malformed data): fall back to the
        // middle of the whole span rather than returning nothing.
        return Int(((Self.midMinutes(first) + Self.midMinutes(last)) / 2 * 60).rounded())
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
            return Int((totalRun / Double(Self.runCount)).rounded())
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
            return Array(repeating: 1, count: Self.runCount)
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
    ///
    /// A goal outside `goalRange(for:)` is still planned — it is pinned to the
    /// nearest bucket, exactly as before — but the returned plan reports that with
    /// `rangeStatus` so the UI can refuse to apply an extrapolated split.
    public func computePlan(goalTotalS: Int, division: HyroxDivision, mode: RunMode = .adaptive) -> PacePlan? {
        let targetMin = Double(goalTotalS) / 60.0
        guard let bucket = interpolate(targetMinutes: targetMin, division: division),
              let div = data.divisions[division.rawValue],
              let range = goalRange(for: division) else { return nil }

        // Station totals from bucket
        var stationTimes = bucket.stations
        var stnTotal = Self.stationTotal(stationTimes)

        // Solve for pace (matching renderDetail)
        let targetRun = goalTotalS - stnTotal
        let basePace = max(1, Int((Double(targetRun) / 8.7).rounded()))
        var bestPace = basePace
        var bestDiff = Int.max
        for p in max(1, basePace - 3)...basePace + 3 {
            let runT = Self.runCount * Int((Double(p) * 8.7 / Double(Self.runCount)).rounded())
            let diff = abs(targetRun - runT)
            if diff < bestDiff { bestDiff = diff; bestPace = p }
        }

        // Compute run times
        var runTimes: [Int] = []
        for i in 0..<Self.runCount {
            runTimes.append(runTime(index: i, paceSeconds87: bestPace, totalSeconds: goalTotalS, mode: mode))
        }

        // Rebalance stations (matching rebalanceStations)
        let runTotal = runTimes.reduce(0, +)
        let residual = goalTotalS - (runTotal + stnTotal)
        let stationOrder = StationKind.standardDataKeys

        if residual != 0 {
            let sign = residual > 0 ? 1 : -1
            var remaining = abs(residual)
            var idx = 0
            while remaining > 0 && idx < 400 {
                let key = stationOrder[idx % stationOrder.count]
                if let val = stationTimes[key], val + sign >= 1 {
                    stationTimes[key] = val + sign
                    remaining -= 1
                }
                idx += 1
            }
            stnTotal = Self.stationTotal(stationTimes)
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
            roxFraction: bucket.roxFraction,
            goalRange: range,
            rangeStatus: range.status(for: goalTotalS)
        )
    }

    /// Sum of the 8 official stations only — never whatever else a dictionary holds.
    static func stationTotal(_ stationTimes: [String: Int]) -> Int {
        StationKind.standardDataKeys.reduce(0) { $0 + (stationTimes[$1] ?? 0) }
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
}

// MARK: - Pace Plan Result

public struct PacePlan: Sendable {
    public let goalTotalS: Int
    /// Per-run times (8 values, includes roxzone).
    public let runTimes: [Int]
    /// Per-station times, keyed by `StationKind.dataKey`.
    public let stationTimes: [String: Int]
    /// Pace in seconds for 8.7km equivalent.
    public let paceSeconds87: Int
    /// Percentile rank (0-100).
    public let percentile: Double
    /// Total athletes in dataset.
    public let totalAthletes: Int
    /// Computed total. Equals `goalTotalS` whenever the rebalance loop converged.
    public let computedTotal: Int
    /// Distribution mode used.
    public let mode: PacePlanner.RunMode
    /// Fraction of run+rox that is roxzone (0.0-1.0), from bucket data.
    public let roxFraction: Double
    /// Goal times the underlying data covers.
    public let goalRange: PaceGoalRange
    /// Whether `goalTotalS` sits inside that range.
    public let rangeStatus: RangeStatus

    /// Total run time.
    public var runTotal: Int { runTimes.reduce(0, +) }
    /// Total station time (8 official stations).
    public var stationTotal: Int { PacePlanner.stationTotal(stationTimes) }

    /// Whether this plan may be written onto a template.
    ///
    /// False when the goal is extrapolated past the data (the split would be
    /// invented) or when the rebalance loop could not land on the goal exactly.
    public var isApplicable: Bool {
        goalTotalS > 0 && rangeStatus == .inRange && computedTotal == goalTotalS
    }

    /// Split a combined run+rox time into (run, rox) using the data-driven fraction.
    public func splitRunRox(_ combinedS: Int) -> (run: Int, rox: Int) {
        let rox = Int((Double(combinedS) * roxFraction).rounded())
        return (combinedS - rox, rox)
    }
}

// MARK: - Standard Course Detection

extension WorkoutTemplate {

    /// Run distance of every lap in an official race.
    public static let standardRunDistanceMeters: Double = 1000

    /// Segment count of an official course with ROX Zones (8 × [run, rox, station, rox] − 1).
    public static let standardSegmentCountWithRox = 31

    /// Segment count of an official course without ROX Zones (8 runs + 8 stations).
    public static let standardSegmentCountWithoutRox = 16

    /// Whether this template is an untouched official HYROX course: eight 1 km runs
    /// alternating with the eight official stations in race order.
    ///
    /// The pace data is built from 8 × 1 km + 8 stations races, so a duplicated preset
    /// that was reshaped (half distance, 2 km runs, a swapped-in custom station) keeps
    /// its `division` but must not be planned against that data.
    public var isStandardHyroxCourse: Bool {
        let logical = logicalSegments
        let stations = StationKind.standardOrder
        guard logical.count == stations.count * 2 else { return false }

        let expectedSegmentCount = usesRoxZone
            ? Self.standardSegmentCountWithRox
            : Self.standardSegmentCountWithoutRox
        guard segments.count == expectedSegmentCount else { return false }

        for (index, segment) in logical.enumerated() {
            if index.isMultiple(of: 2) {
                guard segment.type == .run,
                      let distance = segment.distanceMeters,
                      abs(distance - Self.standardRunDistanceMeters) < 0.5 else { return false }
            } else {
                guard segment.type == .station,
                      segment.stationKind == stations[index / 2] else { return false }
            }
        }

        return true
    }
}
