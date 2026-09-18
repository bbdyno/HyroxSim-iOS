//
//  PacePlannerTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/17/26.
//

import XCTest
@testable import HyroxCore

final class PacePlannerDataTests: XCTestCase {

    private var planner: PacePlanner!

    override func setUpWithError() throws {
        planner = try PaceReferenceLoader.loadPacePlanner()
    }

    func testLoadData() {
        XCTAssertEqual(planner.data.schemaVersion, 3)
        XCTAssertEqual(planner.data.bucketSizeMin, 5)
    }

    func testAllDivisionsPresent() {
        for division in HyroxDivision.allCases {
            XCTAssertNotNil(planner.data.divisions[division.rawValue], "\(division.rawValue) missing")
        }
    }

    func testBucketsAreSorted() {
        for (key, div) in planner.data.divisions {
            for i in 0..<div.buckets.count - 1 {
                XCTAssertLessThan(div.buckets[i].loMin, div.buckets[i + 1].loMin, "\(key) buckets not sorted")
            }
        }
    }

    func testBucketsHaveValidPctRange() {
        for (key, div) in planner.data.divisions {
            for b in div.buckets {
                XCTAssertLessThanOrEqual(b.pctRange[0], b.pctRange[1], "\(key) pct_range inverted")
                XCTAssertGreaterThanOrEqual(b.pctRange[0], 0, "\(key) negative pct")
                XCTAssertLessThanOrEqual(b.pctRange[1], 100.1, "\(key) pct > 100")
            }
        }
    }

    func testRunRatioTable() {
        XCTAssertEqual(planner.data.runRatioTable.count, 6)
        for row in planner.data.runRatioTable {
            XCTAssertEqual(row.r.count, 8)
            // Run 1 and Run 2 should be 1.0
            XCTAssertEqual(row.r[0], 1.0)
            XCTAssertEqual(row.r[1], 1.0)
            // Later runs should be >= 1.0
            for i in 2..<8 {
                XCTAssertGreaterThanOrEqual(row.r[i], 1.0)
            }
        }
    }

    // MARK: - Data invariants
    //
    // Buckets with few athletes are noisy by nature (the slowest ones hold a
    // handful of results), so these only cover the statistically dense part of the
    // table. 250 is the lowest threshold at which the shipped data is clean —
    // below it the long tail wobbles by a few seconds between adjacent buckets.

    private static let denseBucketMinCount = 250

    private func denseBuckets(_ divisionKey: String) -> [TimeBucket] {
        (planner.data.divisions[divisionKey]?.buckets ?? [])
            .filter { $0.count >= Self.denseBucketMinCount }
    }

    /// Slower finishers must not have *faster* sled splits. A contaminated
    /// menOpenSingle 65-70 bucket (sledPush 234s / sledPull 314s between
    /// neighbours of 138/207 and 156/247) used to break this.
    func testSledTimesIncreaseMonotonicallyInDenseBuckets() {
        for divisionKey in ["menOpenSingle", "womenOpenSingle"] {
            let buckets = denseBuckets(divisionKey)
            XCTAssertGreaterThan(buckets.count, 10, "\(divisionKey) has too few dense buckets to check")

            for station in ["sledPush", "sledPull"] {
                let values = buckets.compactMap { $0.stations[station] }
                XCTAssertEqual(values.count, buckets.count, "\(divisionKey).\(station) missing values")

                for i in 0..<(values.count - 1) {
                    XCTAssertLessThanOrEqual(
                        values[i],
                        values[i + 1],
                        """
                        \(divisionKey).\(station) drops from \(values[i])s to \(values[i + 1])s \
                        between the \(buckets[i].loMin)- and \(buckets[i + 1].loMin)-minute buckets
                        """
                    )
                }
            }
        }
    }

    /// Open pushes/pulls a lighter sled than Pro, so at the same goal time an
    /// Open athlete's sled split must not be slower.
    func testOpenSledTimesAreNotSlowerThanProAtTheSameGoal() {
        let open = Dictionary(uniqueKeysWithValues: denseBuckets("menOpenSingle").map { ($0.loMin, $0) })
        let pro = Dictionary(uniqueKeysWithValues: denseBuckets("menProSingle").map { ($0.loMin, $0) })
        let shared = Set(open.keys).intersection(pro.keys).sorted()
        XCTAssertGreaterThan(shared.count, 10)

        for loMin in shared {
            for station in ["sledPush", "sledPull"] {
                guard let openValue = open[loMin]?.stations[station],
                      let proValue = pro[loMin]?.stations[station] else {
                    XCTFail("missing \(station) at \(loMin) min")
                    continue
                }
                XCTAssertLessThanOrEqual(
                    openValue,
                    proValue,
                    "menOpenSingle.\(station) (\(openValue)s) is slower than menProSingle (\(proValue)s) at \(loMin) min"
                )
            }
        }
    }
}

final class PacePlannerLogicTests: XCTestCase {

    private var planner: PacePlanner!

    override func setUpWithError() throws {
        planner = try PaceReferenceLoader.loadPacePlanner()
    }

    // MARK: - Interpolation

    func testInterpolateMenOpenMiddle() {
        // 87 minutes should be near 50th percentile for Men Open
        let result = planner.interpolate(targetMinutes: 87, division: .menOpenSingle)
        XCTAssertNotNil(result)
        guard let r = result else { return }
        XCTAssertGreaterThan(r.percentile, 30)
        XCTAssertLessThan(r.percentile, 70)
        XCTAssertEqual(r.stations.count, 8)
    }

    func testInterpolateFastTime() {
        // 58 minutes for Men Open — should be near top
        let result = planner.interpolate(targetMinutes: 58, division: .menOpenSingle)
        XCTAssertNotNil(result)
        guard let r = result else { return }
        XCTAssertLessThan(r.percentile, 2)
    }

    // MARK: - Run Distribution

    func testEqualModeGivesEqualRuns() {
        let r1 = planner.runTime(index: 0, paceSeconds87: 300, totalSeconds: 5000, mode: .equal)
        let r8 = planner.runTime(index: 7, paceSeconds87: 300, totalSeconds: 5000, mode: .equal)
        XCTAssertEqual(r1, r8)
    }

    func testAdaptiveModeGivesProgressiveRuns() {
        let r1 = planner.runTime(index: 0, paceSeconds87: 300, totalSeconds: 5000, mode: .adaptive)
        let r8 = planner.runTime(index: 7, paceSeconds87: 300, totalSeconds: 5000, mode: .adaptive)
        XCTAssertLessThanOrEqual(r1, r8, "Run 1 should be faster or equal to Run 8")
    }

    func testRunRatiosRun1EqualsRun2() {
        let ratios = planner.interpolatedRunRatios(targetSeconds: 5000)
        XCTAssertEqual(ratios[0], ratios[1], accuracy: 0.001)
    }

    // MARK: - Full Plan

    func testComputePlanMenOpen() {
        let plan = planner.computePlan(goalTotalS: 5040, division: .menOpenSingle, mode: .adaptive)
        XCTAssertNotNil(plan)
        guard let p = plan else { return }

        XCTAssertEqual(p.runTimes.count, 8)
        XCTAssertEqual(p.stationTimes.count, 8)
        // Computed total should match goal
        XCTAssertEqual(p.computedTotal, 5040)
        XCTAssertGreaterThan(p.percentile, 0)
        XCTAssertLessThan(p.percentile, 100)
    }

    func testComputePlanEqualMode() {
        let plan = planner.computePlan(goalTotalS: 5040, division: .menOpenSingle, mode: .equal)
        XCTAssertNotNil(plan)
        guard let p = plan else { return }
        XCTAssertEqual(p.computedTotal, 5040)
        XCTAssertEqual(p.mode, .equal)
    }

    func testAllDivisionsPlannable() {
        for division in HyroxDivision.allCases {
            let plan = planner.computePlan(goalTotalS: 5000, division: division)
            XCTAssertNotNil(plan, "\(division.rawValue)")
        }
    }

    func testShorterGoalGivesBetterPercentile() {
        let fast = planner.computePlan(goalTotalS: 4200, division: .menOpenSingle)!
        let slow = planner.computePlan(goalTotalS: 6000, division: .menOpenSingle)!
        XCTAssertLessThan(fast.percentile, slow.percentile)
    }
}
