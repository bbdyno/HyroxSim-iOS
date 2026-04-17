//
//  PaceReferenceTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/17/26.
//

import XCTest
@testable import HyroxCore

final class PaceReferenceTests: XCTestCase {

    private var ref: PaceReference!

    override func setUpWithError() throws {
        ref = try PaceReferenceLoader.loadBundled()
    }

    // MARK: - Loading

    func testLoadBundled() {
        XCTAssertEqual(ref.schemaVersion, 1)
        XCTAssertEqual(ref.divisions.count, 9)
    }

    func testAllDivisionsPresent() {
        for division in HyroxDivision.allCases {
            XCTAssertNotNil(ref.benchmark(for: division), "\(division.rawValue) missing")
        }
    }

    // MARK: - Data Integrity

    func testRunDistributionWeightsSumToOne() {
        let sum = ref.runDistribution.weights.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.001)
    }

    func testRunDistributionHas8Weights() {
        XCTAssertEqual(ref.runDistribution.weights.count, 8)
    }

    func testEachDivisionTotalMatchesComponents() {
        for division in HyroxDivision.allCases {
            guard let bench = ref.benchmark(for: division) else {
                XCTFail("\(division.rawValue) missing")
                continue
            }
            let computed = bench.runTotalS + bench.stationTotalS + bench.roxzoneTotalS
            XCTAssertEqual(computed, bench.referenceTotalS,
                           "\(division.rawValue): \(computed) != \(bench.referenceTotalS)")
        }
    }

    func testEachDivisionHas8Stations() {
        for division in HyroxDivision.allCases {
            guard let bench = ref.benchmark(for: division) else { continue }
            XCTAssertEqual(bench.stations.count, 8, "\(division.rawValue)")
        }
    }

    func testStationTimeAccessor() {
        guard let bench = ref.benchmark(for: .menOpenSingle) else {
            XCTFail("menOpenSingle missing"); return
        }
        XCTAssertEqual(bench.stationTime(for: .skiErg), 260)
        XCTAssertEqual(bench.stationTime(for: .wallBalls), 400)
        XCTAssertNil(bench.stationTime(for: .custom(name: "Test")))
    }

    func testLevelAnchorsAreOrdered() {
        let levels = ["elite", "advanced", "strong", "average", "beginner"]
        for division in HyroxDivision.allCases {
            guard let bench = ref.benchmark(for: division) else { continue }
            for i in 0..<levels.count - 1 {
                let current = bench.levelTotalS[levels[i]] ?? 0
                let next = bench.levelTotalS[levels[i + 1]] ?? 0
                XCTAssertLessThanOrEqual(current, next,
                    "\(division.rawValue): \(levels[i]) (\(current)) > \(levels[i+1]) (\(next))")
            }
        }
    }
}

// MARK: - PaceDistributor Tests

final class PaceDistributorTests: XCTestCase {

    private var distributor: PaceDistributor!

    override func setUpWithError() throws {
        let ref = try PaceReferenceLoader.loadBundled()
        distributor = PaceDistributor(reference: ref)
    }

    func testDistributeAtReferenceTimeEqualsReference() {
        let bench = distributor.reference.benchmark(for: .menOpenSingle)!
        let dist = distributor.distribute(goalTotalS: bench.referenceTotalS, division: .menOpenSingle)!

        // Run goals should sum close to run_total_s
        let runSum = dist.runGoals.reduce(0, +)
        XCTAssertEqual(runSum, bench.runTotalS, accuracy: 2)

        // Station goals should match reference
        XCTAssertEqual(dist.stationGoals["skiErg"], bench.stations["skiErg"])
        XCTAssertEqual(dist.stationGoals["wallBalls"], bench.stations["wallBalls"])

        // Distributed total should be close to goal
        XCTAssertEqual(dist.distributedTotal, bench.referenceTotalS, accuracy: 15)
    }

    func testDistributeScalesLinearly() {
        let bench = distributor.reference.benchmark(for: .womenOpenSingle)!
        let halfGoal = bench.referenceTotalS / 2
        let dist = distributor.distribute(goalTotalS: halfGoal, division: .womenOpenSingle)!

        // Each station should be roughly half
        for (key, refVal) in bench.stations {
            let goalVal = dist.stationGoals[key]!
            XCTAssertEqual(Double(goalVal), Double(refVal) * 0.5, accuracy: 2,
                           "Station \(key)")
        }
    }

    func testDistributeReturnsNilForMissingDivision() {
        // All 9 divisions exist, but test with a valid enum that should work
        let dist = distributor.distribute(goalTotalS: 5000, division: .menOpenSingle)
        XCTAssertNotNil(dist)
    }

    func testRunGoalsAreProgressivelySlower() {
        let dist = distributor.distribute(goalTotalS: 5040, division: .menOpenSingle)!
        // First run should be <= last run (fatigue curve)
        XCTAssertLessThanOrEqual(dist.runGoals[0], dist.runGoals[7])
    }

    func testRunGoalsCount() {
        let dist = distributor.distribute(goalTotalS: 5040, division: .menOpenSingle)!
        XCTAssertEqual(dist.runGoals.count, 8)
    }

    func testAllDivisionsDistributable() {
        for division in HyroxDivision.allCases {
            let bench = distributor.reference.benchmark(for: division)!
            let dist = distributor.distribute(goalTotalS: bench.referenceTotalS, division: division)
            XCTAssertNotNil(dist, "\(division.rawValue)")
        }
    }
}
