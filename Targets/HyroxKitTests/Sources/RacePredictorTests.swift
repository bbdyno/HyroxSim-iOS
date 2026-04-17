//
//  RacePredictorTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/17/26.
//

import XCTest
@testable import HyroxCore

final class RaceModelTests: XCTestCase {

    private var model: RaceModel!

    override func setUpWithError() throws {
        model = try PaceReferenceLoader.loadRaceModel()
    }

    func testLoadModel() {
        XCTAssertEqual(model.schemaVersion, 2)
        XCTAssertEqual(model.polyDegree, 9)
    }

    func testAllDivisionsPresent() {
        for division in HyroxDivision.allCases {
            XCTAssertNotNil(model.model(for: division), "\(division.rawValue) missing")
        }
    }

    func testEachDivisionHas9StationFits() {
        for division in HyroxDivision.allCases {
            guard let div = model.model(for: division) else { continue }
            // 8 stations + roxzone = 9
            XCTAssertEqual(div.stationFits.count, 9, "\(division.rawValue)")
        }
    }

    func testEachDivisionHasPercentiles() {
        for division in HyroxDivision.allCases {
            guard let div = model.model(for: division) else { continue }
            XCTAssertEqual(div.percentiles.count, 9, "\(division.rawValue)")
            for pct in ["1", "5", "10", "25", "50", "75", "90", "95", "99"] {
                XCTAssertNotNil(div.percentiles[pct], "\(division.rawValue) missing p\(pct)")
            }
        }
    }

    func testPolynomialCoefficientsCount() {
        for division in HyroxDivision.allCases {
            guard let div = model.model(for: division) else { continue }
            // degree 9 → 10 coefficients
            XCTAssertEqual(div.runFit.coeffs.count, 10, "\(division.rawValue) runFit")
            for (key, fit) in div.stationFits {
                XCTAssertEqual(fit.coeffs.count, 10, "\(division.rawValue) \(key)")
            }
        }
    }

    func testPolyEvalMonotonic() {
        // For menOpenSingle run fit, later ranks should give higher times
        guard let div = model.model(for: .menOpenSingle) else { XCTFail(); return }
        let n = Double(div.nAthletes)
        let early = div.runFit.evaluate(at: n * 0.1)
        let mid = div.runFit.evaluate(at: n * 0.5)
        let late = div.runFit.evaluate(at: n * 0.9)
        XCTAssertLessThan(early, mid, "Rank 10% should be faster than 50%")
        XCTAssertLessThan(mid, late, "Rank 50% should be faster than 90%")
    }
}

final class RacePredictorTests: XCTestCase {

    private var predictor: RacePredictor!

    override func setUpWithError() throws {
        predictor = try PaceReferenceLoader.loadPredictor()
    }

    func testPredictMenOpen() {
        // 5:10/km pace → expect total around 1:24:00 (5040s) ± large margin
        let pred = predictor.predict(paceSecondsPerKm: 310, division: .menOpenSingle)
        XCTAssertNotNil(pred)
        guard let pred else { return }

        XCTAssertEqual(pred.runTotalS, 2480) // 310 × 8
        XCTAssertEqual(pred.stationTimes.count, 8)
        XCTAssertGreaterThan(pred.totalS, 3600) // at least 1 hour
        XCTAssertLessThan(pred.totalS, 7200) // less than 2 hours
        XCTAssertGreaterThan(pred.percentile, 0)
        XCTAssertLessThan(pred.percentile, 100)
    }

    func testFasterPaceGivesBetterPercentile() {
        let fast = predictor.predict(paceSecondsPerKm: 240, division: .menOpenSingle)!
        let slow = predictor.predict(paceSecondsPerKm: 400, division: .menOpenSingle)!
        XCTAssertLessThan(fast.percentile, slow.percentile)
        XCTAssertLessThan(fast.totalS, slow.totalS)
    }

    func testAllDivisionsPredictable() {
        for division in HyroxDivision.allCases {
            let pred = predictor.predict(paceSecondsPerKm: 330, division: division)
            XCTAssertNotNil(pred, "\(division.rawValue)")
        }
    }

    func testStationTimesAreReasonable() {
        let pred = predictor.predict(paceSecondsPerKm: 310, division: .menOpenSingle)!
        for (key, secs) in pred.stationTimes {
            XCTAssertGreaterThan(secs, 30, "\(key) too low")
            XCTAssertLessThan(secs, 900, "\(key) too high") // < 15 min per station
        }
    }

    func testLevelLabel() {
        let label = predictor.levelLabel(totalS: 4500, division: .menOpenSingle)
        XCTAssertNotNil(label)
        // 4500s is advanced level for men open
        XCTAssertEqual(label, "Advanced")
    }

    // MARK: - Goal Time Prediction

    func testPredictFromGoalTime() {
        // 1:24:00 = 5040s goal for men open
        let pred = predictor.predictFromGoalTime(goalTotalS: 5040, division: .menOpenSingle)
        XCTAssertNotNil(pred)
        guard let pred else { return }

        XCTAssertEqual(pred.stationTimes.count, 8)
        // Predicted total should be close to goal
        XCTAssertEqual(pred.totalS, 5040, accuracy: 100)
        XCTAssertGreaterThan(pred.percentile, 0)
        XCTAssertLessThan(pred.percentile, 100)
    }

    func testGoalTimeShorterGivesBetterPercentile() {
        let fast = predictor.predictFromGoalTime(goalTotalS: 3600, division: .menOpenSingle)!
        let slow = predictor.predictFromGoalTime(goalTotalS: 6000, division: .menOpenSingle)!
        XCTAssertLessThan(fast.percentile, slow.percentile)
    }

    func testAllDivisionsGoalTimePredictable() {
        for division in HyroxDivision.allCases {
            let pred = predictor.predictFromGoalTime(goalTotalS: 5000, division: division)
            XCTAssertNotNil(pred, "\(division.rawValue)")
        }
    }
}
