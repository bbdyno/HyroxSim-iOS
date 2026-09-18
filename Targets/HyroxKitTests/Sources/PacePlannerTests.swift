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

// MARK: - Data Coverage Guardrails
//
// Outside the bucket table `lerp` stops interpolating and returns an edge bucket
// verbatim: the station splits freeze and the whole remaining difference lands on
// the runs. A 48:00 Men's Pro goal used to come back as a silent 2:38/km target.
// The plan is still produced (the pinning is deliberate), but it now says so.

final class PacePlannerRangeTests: XCTestCase {

    private var planner: PacePlanner!

    override func setUpWithError() throws {
        planner = try PaceReferenceLoader.loadPacePlanner()
    }

    func testGoalRangeMatchesOuterBucketEdges() {
        for division in HyroxDivision.allCases {
            guard let buckets = planner.data.divisions[division.rawValue]?.buckets,
                  let first = buckets.first,
                  let last = buckets.last,
                  let range = planner.goalRange(for: division) else {
                XCTFail("\(division.rawValue) has no goal range")
                continue
            }

            XCTAssertEqual(range.minTotalS, first.loMin * 60, division.rawValue)
            XCTAssertEqual(range.maxTotalS, last.hiMin * 60, division.rawValue)
            XCTAssertLessThan(range.minTotalS, range.maxTotalS, division.rawValue)
        }
    }

    func testGoalFasterThanTheDataIsFlaggedAndNotApplicable() {
        for division in HyroxDivision.allCases {
            guard let range = planner.goalRange(for: division) else {
                XCTFail("\(division.rawValue) has no goal range")
                continue
            }

            let plan = planner.computePlan(goalTotalS: range.minTotalS - 60, division: division)
            XCTAssertEqual(plan?.rangeStatus, .fasterThanData, division.rawValue)
            XCTAssertEqual(plan?.isApplicable, false, division.rawValue)
        }
    }

    func testGoalSlowerThanTheDataIsFlaggedAndNotApplicable() {
        for division in HyroxDivision.allCases {
            guard let range = planner.goalRange(for: division) else {
                XCTFail("\(division.rawValue) has no goal range")
                continue
            }

            let plan = planner.computePlan(goalTotalS: range.maxTotalS + 60, division: division)
            XCTAssertEqual(plan?.rangeStatus, .slowerThanData, division.rawValue)
            XCTAssertEqual(plan?.isApplicable, false, division.rawValue)
        }
    }

    func testGoalOnTheEdgeOfTheDataIsInRange() {
        for division in HyroxDivision.allCases {
            guard let range = planner.goalRange(for: division) else {
                XCTFail("\(division.rawValue) has no goal range")
                continue
            }

            XCTAssertEqual(
                planner.computePlan(goalTotalS: range.minTotalS, division: division)?.rangeStatus,
                .inRange,
                division.rawValue
            )
            XCTAssertEqual(
                planner.computePlan(goalTotalS: range.maxTotalS, division: division)?.rangeStatus,
                .inRange,
                division.rawValue
            )
        }
    }

    func testGoalInsideTheDataIsApplicable() {
        let plan = planner.computePlan(goalTotalS: 5040, division: .menOpenSingle)
        XCTAssertEqual(plan?.rangeStatus, .inRange)
        XCTAssertEqual(plan?.computedTotal, 5040)
        XCTAssertEqual(plan?.isApplicable, true)
    }

    func testZeroGoalIsNeverApplicable() {
        let plan = planner.computePlan(goalTotalS: 0, division: .menOpenSingle)
        XCTAssertEqual(plan?.rangeStatus, .fasterThanData)
        XCTAssertEqual(plan?.isApplicable, false)
    }

    // MARK: - Median default

    func testMedianGoalLandsOnThe50thPercentile() {
        for division in HyroxDivision.allCases {
            guard let median = planner.medianGoalSeconds(for: division),
                  let bucket = planner.interpolate(
                    targetMinutes: Double(median) / 60.0,
                    division: division
                  ) else {
                XCTFail("\(division.rawValue) has no median")
                continue
            }

            // 1/10 퍼센트로 반올림된 버킷 경계 + 초 단위 반올림만큼의 오차만 허용.
            XCTAssertEqual(bucket.percentile, 50, accuracy: 1.0, division.rawValue)
        }
    }

    func testMedianGoalIsInsideTheDataRange() {
        for division in HyroxDivision.allCases {
            guard let median = planner.medianGoalSeconds(for: division),
                  let range = planner.goalRange(for: division) else {
                XCTFail("\(division.rawValue) has no median")
                continue
            }

            XCTAssertEqual(range.status(for: median), .inRange, division.rawValue)
        }
    }

    /// 프리셋 기본 목표(런 360초 × 8 + 스테이션 240초 × 8 + ROX 30초 × 15 ≈ 1:27:30)에서
    /// 디비전과 무관하게 늘 출발하던 게 원래 문제였다. 남자 프로 더블에서 그 값은 하위권이다.
    func testMedianGoalIsFasterThanThePresetDefaultForMenProDouble() {
        let presetDefaultTotal = Int(HyroxPresets.menProDouble.estimatedDurationSeconds)
        guard let median = planner.medianGoalSeconds(for: .menProDouble) else {
            XCTFail("menProDouble has no median")
            return
        }

        XCTAssertLessThan(median, presetDefaultTotal)
    }

    /// 디비전과 무관한 하나의 고정 시작값으로 되돌아가면 잡는다.
    func testMedianGoalVariesByDivision() {
        let medians = Set(HyroxDivision.allCases.compactMap { planner.medianGoalSeconds(for: $0) })
        XCTAssertEqual(medians.count, HyroxDivision.allCases.count)
        XCTAssertGreaterThan(
            planner.medianGoalSeconds(for: .womenOpenSingle) ?? 0,
            planner.medianGoalSeconds(for: .menProDouble) ?? 0
        )
    }
}

// MARK: - Bucket Decoding

final class PacePlannerDecodingTests: XCTestCase {

    func testDecodingFailsWhenAStationKeyIsMissing() {
        for missingKey in StationKind.standardDataKeys {
            var stations = PlannerFixture.standardStations
            stations.removeValue(forKey: missingKey)
            let data = PlannerFixture.dataJSON(buckets: [PlannerFixture.bucketJSON(stations: stations)])

            XCTAssertThrowsError(
                try JSONDecoder().decode(PacePlannerData.self, from: data),
                "decoding should fail without '\(missingKey)'"
            )
        }
    }

    func testDecodingDropsNonStandardStations() throws {
        var stations = PlannerFixture.standardStations
        stations["assaultBike"] = 999
        let data = PlannerFixture.dataJSON(buckets: [PlannerFixture.bucketJSON(stations: stations)])

        let decoded = try JSONDecoder().decode(PacePlannerData.self, from: data)
        let bucket = try XCTUnwrap(decoded.divisions[HyroxDivision.menOpenSingle.rawValue]?.buckets.first)

        XCTAssertEqual(bucket.stations.count, StationKind.standardDataKeys.count)
        XCTAssertNil(bucket.stations["assaultBike"])
    }

    func testDecodingFailsWhenARunRatioRowIsShort() {
        let data = PlannerFixture.dataJSON(
            buckets: [PlannerFixture.bucketJSON()],
            runRatioRow: #"{"t": 3600, "r": [1, 1, 1]}"#
        )

        XCTAssertThrowsError(try JSONDecoder().decode(PacePlannerData.self, from: data))
    }

    /// 두 버킷 사이에서 50퍼센타일을 정확히 보간하는지 — 실제 데이터와 무관하게 고정된 답.
    func testMedianInterpolatesBetweenBuckets() throws {
        let data = PlannerFixture.dataJSON(buckets: [
            PlannerFixture.bucketJSON(loMin: 80, hiMin: 90, pctLo: 20, pctHi: 30),
            PlannerFixture.bucketJSON(loMin: 90, hiMin: 100, pctLo: 70, pctHi: 80)
        ])

        let planner = PacePlanner(data: try JSONDecoder().decode(PacePlannerData.self, from: data))

        // 25퍼센타일(85분)과 75퍼센타일(95분) 사이의 정확히 절반 = 90분.
        XCTAssertEqual(planner.medianGoalSeconds(for: .menOpenSingle), 90 * 60)
    }
}

// MARK: - Fixtures

private enum PlannerFixture {

    static let standardStations: [String: Int] = [
        "skiErg": 260, "sledPush": 170, "sledPull": 220, "burpeeBroadJumps": 260,
        "rowing": 270, "farmersCarry": 130, "sandbagLunges": 240, "wallBalls": 400
    ]

    static func bucketJSON(
        loMin: Int = 80,
        hiMin: Int = 85,
        pctLo: Double = 40,
        pctHi: Double = 50,
        stations: [String: Int] = standardStations
    ) -> String {
        let pairs = stations
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\": \($0.value)" }
            .joined(separator: ", ")

        return """
        {
          "lo_min": \(loMin), "hi_min": \(hiMin), "count": 500,
          "pct_range": [\(pctLo), \(pctHi)],
          "avg_overall": \((loMin + hiMin) * 30),
          "avg_run": 2400, "avg_rox": 400, "avg_run_rox": 2800,
          "avg_pace_8_7": 276,
          "avg_station_total": \(stations.values.reduce(0, +)),
          "stations": {\(pairs)}
        }
        """
    }

    static func dataJSON(
        buckets: [String],
        division: HyroxDivision = .menOpenSingle,
        runRatioRow: String = #"{"t": 3600, "r": [1, 1, 1, 1, 1, 1, 1, 1]}"#
    ) -> Data {
        Data("""
        {
          "schema_version": 3,
          "updated_at": "2026-09-18",
          "bucket_size_min": 5,
          "run_ratio_table": [\(runRatioRow)],
          "divisions": {
            "\(division.rawValue)": {
              "total_athletes": 1000,
              "buckets": [\(buckets.joined(separator: ","))]
            }
          }
        }
        """.utf8)
    }
}

// MARK: - Standard Course Detection
//
// 페이스 데이터는 1km 런 8개 + 공식 스테이션 8개 경기에서만 뽑은 것이다.
// 프리셋을 복제해 구조를 바꾼 템플릿은 division 을 그대로 물고 다니므로,
// 구조 자체를 확인하지 않으면 8×8 기준 플랜이 엉뚱한 코스에 적용된다.

final class StandardHyroxCourseTests: XCTestCase {

    func testPresetWithRoxZonesIsStandard() {
        for division in HyroxDivision.allCases {
            let preset = HyroxPresets.template(for: division)
            XCTAssertEqual(preset.segments.count, 31, division.rawValue)
            XCTAssertTrue(preset.isStandardHyroxCourse, division.rawValue)
        }
    }

    func testPresetWithoutRoxZonesIsStandard() {
        let preset = HyroxPresets.menProSingle.settingUsesRoxZone(false)
        XCTAssertEqual(preset.segments.count, 16)
        XCTAssertTrue(preset.isStandardHyroxCourse)
    }

    func testCopyOfAPresetIsStandardEvenWhenNotBuiltIn() {
        let preset = HyroxPresets.menProSingle
        let copy = WorkoutTemplate(
            name: "My Pro copy",
            division: .menProSingle,
            segments: preset.segments,
            usesRoxZone: true,
            isBuiltIn: false
        )

        XCTAssertTrue(copy.isStandardHyroxCourse)
    }

    func testHalfCourseIsRejected() {
        var half = HyroxPresets.menProSingle
        half.segments = WorkoutTemplate.materializedSegments(
            from: Array(half.logicalSegments.prefix(8)),
            usesRoxZone: true
        )

        XCTAssertNotEqual(half.segments.count, 31)
        XCTAssertFalse(half.isStandardHyroxCourse)
    }

    func testTwoKilometreRunsAreRejected() {
        var template = HyroxPresets.menProSingle
        for index in template.segments.indices where template.segments[index].type == .run {
            template.segments[index].distanceMeters = 2000
        }

        XCTAssertEqual(template.segments.count, 31)
        XCTAssertFalse(template.isStandardHyroxCourse)
    }

    func testCustomStationIsRejected() throws {
        var template = HyroxPresets.menProSingle
        let index = try XCTUnwrap(template.segments.firstIndex { $0.stationKind == .wallBalls })
        template.segments[index].stationKind = .custom(name: "Assault Bike")

        XCTAssertFalse(template.isStandardHyroxCourse)
    }

    func testReorderedStationsAreRejected() throws {
        var template = HyroxPresets.menProSingle
        let stationIndices = template.segments.indices.filter { template.segments[$0].type == .station }
        let first = try XCTUnwrap(stationIndices.first)
        let last = try XCTUnwrap(stationIndices.last)
        template.segments.swapAt(first, last)

        XCTAssertFalse(template.isStandardHyroxCourse)
    }

    func testExtraRoxZoneIsRejected() {
        var template = HyroxPresets.menProSingle
        template.segments.append(.roxZone())

        XCTAssertEqual(template.segments.count, 32)
        XCTAssertFalse(template.isStandardHyroxCourse)
    }
}
