//
//  RaceModel.swift
//  HyroxCore
//
//  Created by bbdyno on 4/17/26.
//

import Foundation

// MARK: - JSON Schema

/// Pre-computed polynomial regression model from 685K+ race results.
public struct RaceModel: Codable, Sendable {
    public let schemaVersion: Int
    public let updatedAt: String
    public let polyDegree: Int
    public let divisions: [String: DivisionModel]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case polyDegree = "poly_degree"
        case divisions
    }
}

/// Regression model for one division.
public struct DivisionModel: Codable, Sendable {
    public let nAthletes: Int
    public let runFit: PolyFit
    /// Fit for run + roxzone combined (used for percentile ranking, matching site algorithm).
    public let combinedFit: PolyFit
    public let stationFits: [String: PolyFit]
    public let percentiles: [String: PercentileSnapshot]

    enum CodingKeys: String, CodingKey {
        case nAthletes = "n_athletes"
        case runFit = "run_fit"
        case combinedFit = "combined_fit"
        case stationFits = "station_fits"
        case percentiles
    }
}

/// Normalized polynomial coefficients.
public struct PolyFit: Codable, Sendable {
    /// Polynomial coefficients, highest degree first (same as numpy polyfit).
    public let coeffs: [Double]
    /// Center of the normalization range.
    public let xMid: Double
    /// Half-width of the normalization range.
    public let xScale: Double

    enum CodingKeys: String, CodingKey {
        case coeffs
        case xMid = "x_mid"
        case xScale = "x_scale"
    }

    /// Evaluate the polynomial at the given x value.
    public func evaluate(at x: Double) -> Double {
        let xNorm = (x - xMid) / xScale
        var result = 0.0
        for c in coeffs {
            result = result * xNorm + c
        }
        return result
    }
}

/// Pre-computed station times at a specific percentile rank.
public struct PercentileSnapshot: Codable, Sendable {
    public let runS: Int
    public let combinedRunRoxS: Int
    public let stations: [String: Int]
    public let totalS: Int

    enum CodingKeys: String, CodingKey {
        case runS = "run_s"
        case combinedRunRoxS = "combined_run_rox_s"
        case stations
        case totalS = "total_s"
    }
}

// MARK: - Convenience

extension RaceModel {

    public func model(for division: HyroxDivision) -> DivisionModel? {
        divisions[division.rawValue]
    }
}

// MARK: - Race Predictor

/// Predicts HYROX station times from running pace using polynomial regression.
public struct RacePredictor: Sendable {

    public let model: RaceModel
    /// Optional benchmark data for level indicators.
    public let reference: PaceReference?

    public init(model: RaceModel, reference: PaceReference? = nil) {
        self.model = model
        self.reference = reference
    }

    /// Prediction result for a given running pace.
    public struct Prediction: Sendable {
        /// Predicted time per station (seconds), keyed by StationKind raw string.
        public let stationTimes: [String: Int]
        /// Predicted total running time across 8 laps (seconds).
        public let runTotalS: Int
        /// Predicted roxzone total (seconds).
        public let roxzoneS: Int
        /// Estimated percentile rank (0-100, lower = faster).
        public let percentile: Double
        /// Estimated total finish time (seconds).
        public var totalS: Int {
            runTotalS + stationTimes.values.reduce(0, +) + roxzoneS
        }
        /// Number of athletes in the dataset for this division.
        public let nAthletes: Int
    }

    /// Predict station times for a given running pace.
    /// - Parameters:
    ///   - paceSecondsPerKm: Running pace in seconds per km (e.g., 310 for 5:10/km)
    ///   - division: HYROX division
    /// - Returns: Prediction or nil if division has no model
    public func predict(paceSecondsPerKm: Double, division: HyroxDivision) -> Prediction? {
        guard let div = model.model(for: division) else { return nil }

        let n = Double(div.nAthletes)

        // Total run time = pace × 8 km (8 laps of 1 km)
        let targetRunTotal = paceSecondsPerKm * 8.0

        // Binary search for the rank that gives this run time
        let estRank = findRank(targetValue: targetRunTotal, fit: div.runFit, maxRank: n)

        // Evaluate each station at this rank
        var stationTimes: [String: Int] = [:]
        for (key, fit) in div.stationFits where key != "roxzone" {
            let t = max(30, fit.evaluate(at: estRank))
            stationTimes[key] = Int(t.rounded())
        }

        // Roxzone
        let roxzoneTime: Int
        if let roxFit = div.stationFits["roxzone"] {
            roxzoneTime = max(60, Int(roxFit.evaluate(at: estRank).rounded()))
        } else {
            roxzoneTime = 420
        }

        // Percentile
        let percentile = min(100, max(0, (estRank / n) * 100))

        return Prediction(
            stationTimes: stationTimes,
            runTotalS: Int(targetRunTotal.rounded()),
            roxzoneS: roxzoneTime,
            percentile: percentile,
            nAthletes: div.nAthletes
        )
    }

    /// Distribute a prediction across template segments.
    public func applyPrediction(
        _ prediction: Prediction,
        to template: inout WorkoutTemplate,
        runDistribution: [Double] = [0.118, 0.118, 0.123, 0.124, 0.126, 0.128, 0.130, 0.133]
    ) {
        var runIndex = 0
        let runTotal = Double(prediction.runTotalS)

        for i in template.segments.indices {
            let seg = template.segments[i]
            switch seg.type {
            case .run:
                if runIndex < runDistribution.count {
                    let goal = runTotal * runDistribution[runIndex]
                    template.segments[i].goalDurationSeconds = goal.rounded()
                    runIndex += 1
                }
            case .station:
                if let kind = seg.stationKind {
                    let key = stationKindKey(kind)
                    if let secs = prediction.stationTimes[key] {
                        template.segments[i].goalDurationSeconds = TimeInterval(secs)
                    }
                }
            case .roxZone:
                // Distribute roxzone equally across 15 zones
                let perZone = Double(prediction.roxzoneS) / 15.0
                template.segments[i].goalDurationSeconds = perZone.rounded()
            }
        }
    }

    /// Predict station breakdown for a target total finish time.
    /// Uses binary search to find the rank whose predicted total matches goalTotalS,
    /// then evaluates each station polynomial at that rank.
    public func predictFromGoalTime(goalTotalS: Int, division: HyroxDivision) -> Prediction? {
        guard let div = model.model(for: division) else { return nil }

        let n = Double(div.nAthletes)
        let goal = Double(goalTotalS)

        // Binary search for the rank whose total (run + stations + rox) ≈ goal
        var lo = 1.0
        var hi = n

        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            let total = evaluateTotal(at: mid, div: div)
            if total < goal {
                lo = mid
            } else {
                hi = mid
            }
        }

        let estRank = (lo + hi) / 2
        let runTotal = max(480, div.runFit.evaluate(at: estRank))

        var stationTimes: [String: Int] = [:]
        for (key, fit) in div.stationFits where key != "roxzone" {
            stationTimes[key] = max(30, Int(fit.evaluate(at: estRank).rounded()))
        }

        let roxzoneTime: Int
        if let roxFit = div.stationFits["roxzone"] {
            roxzoneTime = max(60, Int(roxFit.evaluate(at: estRank).rounded()))
        } else {
            roxzoneTime = 420
        }

        let percentile = min(100, max(0, (estRank / n) * 100))

        return Prediction(
            stationTimes: stationTimes,
            runTotalS: Int(runTotal.rounded()),
            roxzoneS: roxzoneTime,
            percentile: percentile,
            nAthletes: div.nAthletes
        )
    }

    /// Level label from benchmark data.
    public func levelLabel(totalS: Int, division: HyroxDivision) -> String? {
        guard let bench = reference?.benchmark(for: division) else { return nil }
        let levels: [(String, String)] = [
            ("elite", "Elite"),
            ("advanced", "Advanced"),
            ("strong", "Strong"),
            ("average", "Average"),
            ("beginner", "Beginner"),
        ]
        for (key, label) in levels {
            if let threshold = bench.levelTotalS[key], totalS <= threshold {
                return label
            }
        }
        return "Beginner+"
    }

    // MARK: - Private

    /// Evaluate total predicted time (run + all stations + roxzone) at a given rank.
    private func evaluateTotal(at rank: Double, div: DivisionModel) -> Double {
        var total = div.runFit.evaluate(at: rank)
        for (key, fit) in div.stationFits {
            total += fit.evaluate(at: rank)
        }
        return total
    }

    /// Binary search for the rank that produces the given value from a polynomial fit.
    private func findRank(targetValue: Double, fit: PolyFit, maxRank: Double) -> Double {
        var lo = 1.0
        var hi = maxRank

        for _ in 0..<50 {
            let mid = (lo + hi) / 2
            let val = fit.evaluate(at: mid)
            if val < targetValue {
                lo = mid
            } else {
                hi = mid
            }
        }
        return (lo + hi) / 2
    }

    private func stationKindKey(_ kind: StationKind) -> String {
        switch kind {
        case .skiErg: return "skiErg"
        case .sledPush: return "sledPush"
        case .sledPull: return "sledPull"
        case .burpeeBroadJumps: return "burpeeBroadJumps"
        case .rowing: return "rowing"
        case .farmersCarry: return "farmersCarry"
        case .sandbagLunges: return "sandbagLunges"
        case .wallBalls: return "wallBalls"
        case .custom: return ""
        }
    }
}
