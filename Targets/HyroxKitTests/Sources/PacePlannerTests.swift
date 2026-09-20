//
//  PacePlannerTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/17/26.
//

import CryptoKit
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

// MARK: - v4 Dataset Fixtures

/// A minimal but fully valid `schema_version` 4 table.
///
/// Three grid points, eight stations, and component values that add up to
/// `overall_s` exactly — the same invariants the published files hold, small enough
/// that a test can reason about every number in it.
enum PaceDatasetFixture {

    static let gridP: [Double] = [10, 50, 90]
    static let overallS: [Int] = [3600, 4500, 5400]
    /// Every station carries the same curve, so the eight of them total 800/1000/1200.
    static let stationCurve: [Int] = [100, 125, 150]
    static let runRoxS: [Int] = [2800, 3500, 4200]

    static func stations(overriding key: String? = nil, with curve: [Int]? = nil) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        for standard in StationKind.standardDataKeys {
            result[standard] = stationCurve
        }
        if let key {
            if let curve {
                result[key] = curve
            } else {
                result.removeValue(forKey: key)
            }
        }
        return result
    }

    static func make(
        schemaVersion: Int = 4,
        datasetVersion: String = "2026.09.15",
        divisionKey: String = HyroxDivision.menOpenSingle.rawValue,
        gridP: [Double] = PaceDatasetFixture.gridP,
        overallS: [Int] = PaceDatasetFixture.overallS,
        runRoxS: [Int] = PaceDatasetFixture.runRoxS,
        stationsS: [String: [Int]]? = nil,
        ageGroups: [PaceDatasetAgeGroup] = [
            PaceDatasetAgeGroup(ageGroup: "30-34", n: 1_000, gridP: [25, 75], overallS: [4_000, 5_000])
        ]
    ) -> PaceDataset {
        PaceDataset(
            schemaVersion: schemaVersion,
            datasetVersion: datasetVersion,
            divisionKey: divisionKey,
            gridP: gridP,
            overallS: overallS,
            components: PaceDatasetComponents(
                runRoxS: runRoxS,
                stationsS: stationsS ?? stations()
            ),
            ageGroups: ageGroups
        )
    }
}

// MARK: - Bundled v4 Snapshot

final class PaceDatasetBundleTests: XCTestCase {

    func testBundledSnapshotCoversEveryDivision() throws {
        let snapshot = try PaceReferenceLoader.loadBundledPaceData()

        XCTAssertEqual(snapshot.origin, .bundled)
        XCTAssertTrue(snapshot.isComplete)
        XCTAssertEqual(snapshot.availableDivisions.count, HyroxDivision.allCases.count)

        for division in HyroxDivision.allCases {
            let dataset = try snapshot.dataset(for: division)
            XCTAssertEqual(dataset.division, division)
            XCTAssertEqual(dataset.datasetVersion, snapshot.datasetVersion)
            XCTAssertEqual(dataset.schemaVersion, 4)
        }
    }

    func testBundledManifestMatchesTheBundledSnapshotVersion() throws {
        let manifest = try PaceReferenceLoader.loadBundledManifest()
        let snapshot = try PaceReferenceLoader.loadBundledPaceData()

        XCTAssertEqual(manifest.schemaVersion, 4)
        XCTAssertEqual(manifest.datasetVersion, snapshot.datasetVersion)
        XCTAssertEqual(try manifest.validatedFiles().count, HyroxDivision.allCases.count)
    }

    /// Guards the one mistake a snapshot refresh can silently make: copying the nine
    /// tables into the bundle but leaving the old `manifest.json` next to them. The
    /// app would then report a version that does not describe its own data.
    func testBundledFilesMatchTheChecksumsTheirManifestPublishes() throws {
        let manifest = try PaceReferenceLoader.loadBundledManifest()
        let entries = try manifest.validatedFiles()

        for (division, file) in entries {
            let data = try PaceReferenceLoader.bundledDatasetData(for: division)
            XCTAssertEqual(data.count, file.bytes, "\(division.rawValue) byte count")

            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(
                digest,
                file.sha256,
                "\(division.rawValue) sha256 — the bundled snapshot and its manifest disagree"
            )
        }
    }

    func testEveryBundledDatasetPassesValidation() throws {
        let snapshot = try PaceReferenceLoader.loadBundledPaceData()

        for division in HyroxDivision.allCases {
            let dataset = try snapshot.dataset(for: division)
            XCTAssertNoThrow(
                try PaceDatasetValidator.validate(
                    dataset,
                    expecting: division,
                    datasetVersion: snapshot.datasetVersion
                ),
                division.rawValue
            )
        }
    }

    func testBundledDatasetsCarryTheirProvenance() throws {
        let dataset = try PaceReferenceLoader.loadBundledPaceData().dataset(for: .menOpenSingle)

        XCTAssertFalse(dataset.sources.isEmpty)
        XCTAssertFalse(dataset.cleaning.rules.isEmpty)
        XCTAssertNotNil(dataset.method.overallS)
        XCTAssertGreaterThan(dataset.minCellN, 0)
        XCTAssertEqual(dataset.coverage.division, dataset.divisionKey)
    }
}

// MARK: - Validator Invariants

final class PaceDatasetValidatorTests: XCTestCase {

    private func assertRejects(
        _ dataset: PaceDataset,
        expecting division: HyroxDivision? = nil,
        datasetVersion: String? = nil,
        _ expected: PaceDatasetValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try PaceDatasetValidator.validate(
                dataset,
                expecting: division,
                datasetVersion: datasetVersion
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? PaceDatasetValidationError, expected, file: file, line: line)
        }
    }

    func testAcceptsAWellFormedDataset() {
        XCTAssertNoThrow(
            try PaceDatasetValidator.validate(
                PaceDatasetFixture.make(),
                expecting: .menOpenSingle,
                datasetVersion: "2026.09.15"
            )
        )
    }

    func testRejectsAnUnsupportedSchemaVersion() {
        assertRejects(
            PaceDatasetFixture.make(schemaVersion: 5),
            .unsupportedSchemaVersion(found: 5, supported: PaceDatasetValidator.supportedSchemaVersions)
        )
    }

    func testRejectsAnUnknownDivision() {
        assertRejects(
            PaceDatasetFixture.make(divisionKey: "kidsRelay"),
            .unknownDivision("kidsRelay")
        )
    }

    func testRejectsAPayloadForTheWrongDivision() {
        assertRejects(
            PaceDatasetFixture.make(divisionKey: HyroxDivision.womenProDouble.rawValue),
            expecting: .menOpenSingle,
            .divisionMismatch(
                expected: HyroxDivision.menOpenSingle.rawValue,
                found: HyroxDivision.womenProDouble.rawValue
            )
        )
    }

    func testRejectsAVersionTheManifestDidNotPromise() {
        assertRejects(
            PaceDatasetFixture.make(datasetVersion: "2026.09.15"),
            datasetVersion: "2026.10.01",
            .datasetVersionMismatch(expected: "2026.10.01", found: "2026.09.15")
        )
    }

    func testRejectsAnEmptyGrid() {
        assertRejects(
            PaceDatasetFixture.make(gridP: [], overallS: [], runRoxS: [], stationsS: [:]),
            .emptyGrid(field: "grid_p")
        )
    }

    func testRejectsAnOverallCurveOfTheWrongLength() {
        assertRejects(
            PaceDatasetFixture.make(overallS: [3_600, 4_500]),
            .lengthMismatch(field: "overall_s", expected: 3, found: 2)
        )
    }

    func testRejectsANonMonotonicOverallCurve() {
        assertRejects(
            PaceDatasetFixture.make(
                overallS: [3_600, 3_500, 5_400],
                runRoxS: [2_800, 2_500, 4_200]
            ),
            .notStrictlyIncreasing(field: "overall_s", index: 1)
        )
    }

    func testRejectsANonMonotonicPercentileGrid() {
        assertRejects(
            PaceDatasetFixture.make(gridP: [10, 10, 90]),
            .notStrictlyIncreasing(field: "grid_p", index: 1)
        )
    }

    func testRejectsAPercentileOutsideZeroToOneHundred() {
        assertRejects(
            PaceDatasetFixture.make(gridP: [10, 50, 140]),
            .percentileOutOfRange(field: "grid_p", index: 2, value: 140)
        )
    }

    func testRejectsAMissingStation() {
        assertRejects(
            PaceDatasetFixture.make(stationsS: PaceDatasetFixture.stations(overriding: "wallBalls")),
            .missingStation("wallBalls")
        )
    }

    func testRejectsAnUnknownStation() {
        var stations = PaceDatasetFixture.stations()
        stations["assaultBike"] = PaceDatasetFixture.stationCurve
        assertRejects(
            PaceDatasetFixture.make(stationsS: stations),
            .unexpectedStation("assaultBike")
        )
    }

    func testRejectsAStationCurveOfTheWrongLength() {
        assertRejects(
            PaceDatasetFixture.make(
                stationsS: PaceDatasetFixture.stations(overriding: "rowing", with: [100, 125])
            ),
            .lengthMismatch(field: "components.stations_s.rowing", expected: 3, found: 2)
        )
    }

    func testRejectsComponentsThatDoNotAddUpToTheFinishTime() {
        assertRejects(
            PaceDatasetFixture.make(
                stationsS: PaceDatasetFixture.stations(overriding: "sledPush", with: [100, 130, 150])
            ),
            .componentSumMismatch(index: 1, expected: 4_500, found: 4_505)
        )
    }

    func testRejectsANegativeComponent() {
        assertRejects(
            PaceDatasetFixture.make(
                overallS: [3_600, 4_400, 5_400],
                stationsS: PaceDatasetFixture.stations(overriding: "sledPull", with: [100, -100, 150])
            ),
            .negativeValue(field: "components.stations_s.sledPull", index: 1, value: -100)
        )
    }

    func testRejectsABrokenAgeGroupCurve() {
        assertRejects(
            PaceDatasetFixture.make(
                ageGroups: [
                    PaceDatasetAgeGroup(ageGroup: "40-44", n: 500, gridP: [25, 75], overallS: [5_000, 4_000])
                ]
            ),
            .notStrictlyIncreasing(field: "age_groups[40-44].overall_s", index: 1)
        )
    }

    func testSnapshotRefusesToPublishAPartiallyBrokenSet() {
        let good = PaceDatasetFixture.make(divisionKey: HyroxDivision.menOpenSingle.rawValue)
        let bad = PaceDatasetFixture.make(
            divisionKey: HyroxDivision.womenOpenSingle.rawValue,
            overallS: [3_600, 3_500, 5_400],
            runRoxS: [2_800, 2_500, 4_200]
        )

        XCTAssertThrowsError(
            try PaceDataSnapshot(
                datasetVersion: "2026.09.15",
                origin: .cached,
                datasets: [.menOpenSingle: good, .womenOpenSingle: bad]
            )
        )
    }
}

// MARK: - Lookups

final class PaceDatasetLookupTests: XCTestCase {

    func testReadsGridPointsBackExactly() {
        let dataset = PaceDatasetFixture.make()

        for (index, percentile) in PaceDatasetFixture.gridP.enumerated() {
            XCTAssertEqual(dataset.goalSeconds(atPercentile: percentile), PaceDatasetFixture.overallS[index])
            XCTAssertEqual(
                dataset.percentile(forGoalSeconds: PaceDatasetFixture.overallS[index]),
                percentile,
                accuracy: 0.0001
            )
        }
    }

    func testInterpolatesBetweenGridPoints() {
        let dataset = PaceDatasetFixture.make()

        // Halfway from p10 (3600 s) to p50 (4500 s).
        XCTAssertEqual(dataset.goalSeconds(atPercentile: 30), 4_050)
        XCTAssertEqual(dataset.percentile(forGoalSeconds: 4_050), 30, accuracy: 0.0001)

        // A quarter of the way from p50 (4500 s) to p90 (5400 s).
        XCTAssertEqual(dataset.goalSeconds(atPercentile: 60), 4_725)
        XCTAssertEqual(dataset.percentile(forGoalSeconds: 4_725), 60, accuracy: 0.0001)
    }

    func testPinsQueriesPastEitherEndOfTheCurve() {
        let dataset = PaceDatasetFixture.make()

        XCTAssertEqual(dataset.goalSeconds(atPercentile: 0.001), 3_600)
        XCTAssertEqual(dataset.goalSeconds(atPercentile: 100), 5_400)
        XCTAssertEqual(dataset.percentile(forGoalSeconds: 1_800), 10)
        XCTAssertEqual(dataset.percentile(forGoalSeconds: 9_999), 90)

        XCTAssertFalse(dataset.coversGoalSeconds(1_800))
        XCTAssertTrue(dataset.coversGoalSeconds(4_050))
        XCTAssertEqual(dataset.goalSecondsRange, 3_600...5_400)
        XCTAssertEqual(dataset.percentileRange, 10...90)
    }

    func testComponentsAddUpToTheFinishTimeOnAndBetweenGridPoints() {
        let dataset = PaceDatasetFixture.make()

        for percentile in stride(from: 10.0, through: 90.0, by: 2.5) {
            let split = dataset.components(atPercentile: percentile)
            XCTAssertEqual(
                split.runRoxSeconds + split.stationTotalSeconds,
                split.overallSeconds,
                "components drifted at p\(percentile)"
            )
            XCTAssertEqual(split.overallSeconds, dataset.goalSeconds(atPercentile: percentile))
            XCTAssertEqual(split.stationSeconds.count, StationKind.standardDataKeys.count)
        }
    }

    func testComponentsBetweenGridPointsStayWithinASecondOfTheLinearValue() {
        let dataset = PaceDatasetFixture.make()
        let split = dataset.components(atPercentile: 30)

        XCTAssertEqual(split.overallSeconds, 4_050)
        // run+rox interpolates to 3150 exactly; each station to 112.5.
        XCTAssertEqual(split.runRoxSeconds, 3_150)
        for key in StationKind.standardDataKeys {
            let value = split.stationSeconds[key]
            XCTAssertNotNil(value, key)
            XCTAssertTrue([112, 113].contains(value ?? 0), "\(key) was \(value ?? -1)")
        }
        XCTAssertEqual(split.stationTotalSeconds, 900)
    }

    func testLooksUpComponentsByGoalTime() {
        let dataset = PaceDatasetFixture.make()
        let byGoal = dataset.components(forGoalSeconds: 4_050)
        let byPercentile = dataset.components(atPercentile: 30)

        XCTAssertEqual(byGoal, byPercentile)
        XCTAssertEqual(byGoal.seconds(for: .wallBalls), byPercentile.stationSeconds["wallBalls"])
        XCTAssertNil(byGoal.seconds(for: .custom(name: "Assault Bike")))
    }

    func testAgeGroupLookups() {
        let dataset = PaceDatasetFixture.make()

        XCTAssertEqual(dataset.ageGroupIdentifiers, ["30-34"])
        XCTAssertEqual(dataset.ageGroupPercentile(forGoalSeconds: 4_500, ageGroup: "30-34"), 50)
        XCTAssertEqual(dataset.ageGroupGoalSeconds(atPercentile: 50, ageGroup: "30-34"), 4_500)
        XCTAssertNil(dataset.ageGroupPercentile(forGoalSeconds: 4_500, ageGroup: "70-74"))
        XCTAssertNil(dataset.ageGroupGoalSeconds(atPercentile: 50, ageGroup: "70-74"))
    }

    func testBundledCurvesRoundTripAtEveryGridPoint() throws {
        let snapshot = try PaceReferenceLoader.loadBundledPaceData()

        for division in HyroxDivision.allCases {
            let dataset = try snapshot.dataset(for: division)
            for (index, percentile) in dataset.gridP.enumerated() {
                XCTAssertEqual(
                    dataset.goalSeconds(atPercentile: percentile),
                    dataset.overallS[index],
                    "\(division.rawValue) p\(percentile)"
                )
            }
        }
    }

    func testBundledPercentilesNeverRunBackwards() throws {
        let dataset = try PaceReferenceLoader.loadBundledPaceData().dataset(for: .menOpenSingle)
        let range = dataset.goalSecondsRange

        var previous = -Double.infinity
        for seconds in stride(from: range.lowerBound, through: range.upperBound, by: 37) {
            let percentile = dataset.percentile(forGoalSeconds: seconds)
            XCTAssertGreaterThanOrEqual(percentile, previous, "percentile fell back at \(seconds) s")
            previous = percentile
        }
    }

    func testBundledComponentsAddUpBetweenGridPoints() throws {
        let dataset = try PaceReferenceLoader.loadBundledPaceData().dataset(for: .womenOpenSingle)

        for percentile in stride(from: 1.0, through: 99.0, by: 0.5) {
            let split = dataset.components(atPercentile: percentile)
            XCTAssertEqual(
                split.runRoxSeconds + split.stationTotalSeconds,
                split.overallSeconds,
                "components drifted at p\(percentile)"
            )
        }
    }
}

// MARK: - Manifest

final class PaceDataManifestTests: XCTestCase {

    private func makeFile(
        _ division: HyroxDivision,
        version: String = "2026.09.15",
        sha256: String = String(repeating: "a", count: 64),
        bytes: Int = 12_000
    ) -> PaceDataManifestFile {
        PaceDataManifestFile(
            name: "v4/\(version)/\(division.rawValue).json",
            sha256: sha256,
            bytes: bytes
        )
    }

    private func makeManifest(
        manifestVersion: Int = 1,
        schemaVersion: Int = 4,
        datasetVersion: String = "2026.09.15",
        files: [PaceDataManifestFile]? = nil,
        revoked: [String] = []
    ) -> PaceDataManifest {
        PaceDataManifest(
            manifestVersion: manifestVersion,
            datasetVersion: datasetVersion,
            schemaVersion: schemaVersion,
            files: files ?? HyroxDivision.allCases.map { makeFile($0, version: datasetVersion) },
            revoked: revoked
        )
    }

    func testAcceptsAWellFormedManifest() throws {
        let entries = try makeManifest().validatedFiles()
        XCTAssertEqual(entries.count, HyroxDivision.allCases.count)
        XCTAssertEqual(entries[.mixedDouble]?.division, .mixedDouble)
    }

    func testRejectsAnUnsupportedManifestVersion() {
        XCTAssertThrowsError(try makeManifest(manifestVersion: 2).validatedFiles()) { error in
            XCTAssertEqual(
                error as? PaceDataManifestError,
                .unsupportedManifestVersion(
                    found: 2,
                    supported: PaceDataManifest.supportedManifestVersions
                )
            )
        }
    }

    func testRejectsAnUnsupportedSchemaVersion() {
        XCTAssertThrowsError(try makeManifest(schemaVersion: 5).validatedFiles()) { error in
            XCTAssertEqual(
                error as? PaceDataManifestError,
                .unsupportedSchemaVersion(
                    found: 5,
                    supported: PaceDatasetValidator.supportedSchemaVersions
                )
            )
        }
    }

    func testRejectsARevokedDatasetVersion() {
        XCTAssertThrowsError(
            try makeManifest(datasetVersion: "2026.10.01", revoked: ["2026.10.01"]).validatedFiles()
        ) { error in
            XCTAssertEqual(error as? PaceDataManifestError, .revokedDatasetVersion("2026.10.01"))
        }
    }

    func testRejectsAnIncompleteCatalogue() {
        let files = HyroxDivision.allCases
            .filter { $0 != .mixedDouble }
            .map { makeFile($0) }

        XCTAssertThrowsError(try makeManifest(files: files).validatedFiles()) { error in
            XCTAssertEqual(
                error as? PaceDataManifestError,
                .missingDivisionFile(HyroxDivision.mixedDouble.rawValue)
            )
        }
    }

    func testRejectsADuplicatedDivision() {
        var files = HyroxDivision.allCases.map { makeFile($0) }
        files.append(makeFile(.menProSingle))

        XCTAssertThrowsError(try makeManifest(files: files).validatedFiles()) { error in
            XCTAssertEqual(
                error as? PaceDataManifestError,
                .duplicateDivisionFile(HyroxDivision.menProSingle.rawValue)
            )
        }
    }

    func testRejectsAMalformedChecksum() {
        var files = HyroxDivision.allCases.map { makeFile($0) }
        files[0] = PaceDataManifestFile(name: files[0].name, sha256: "not-a-digest", bytes: 12_000)

        XCTAssertThrowsError(try makeManifest(files: files).validatedFiles()) { error in
            XCTAssertEqual(error as? PaceDataManifestError, .invalidChecksum(name: files[0].name))
        }
    }

    func testRejectsAnOversizedFile() {
        var files = HyroxDivision.allCases.map { makeFile($0) }
        files[0] = makeFile(HyroxDivision.allCases[0], bytes: 50_000_000)

        XCTAssertThrowsError(
            try makeManifest(files: files).validatedFiles(maximumFileBytes: 2 * 1024 * 1024)
        ) { error in
            guard case .fileTooLarge = error as? PaceDataManifestError else {
                return XCTFail("expected fileTooLarge, got \(error)")
            }
        }
    }

    /// The names in a catalogue are joined onto a base URL, so traversal and absolute
    /// paths have to die here rather than in whatever consumes them.
    func testRejectsUnsafeFileNames() {
        let unsafe = [
            "../../../etc/passwd.json",
            "/absolute/menOpenSingle.json",
            "v4//menOpenSingle.json",
            "v4/2026.09.15/menOpenSingle.txt",
            "https://evil.example.com/menOpenSingle.json",
            ""
        ]

        for name in unsafe {
            XCTAssertFalse(PaceDataManifest.isSafeRelativePath(name), name)
        }

        XCTAssertTrue(PaceDataManifest.isSafeRelativePath("v4/2026.09.15/menOpenSingle.json"))

        var files = HyroxDivision.allCases.map { makeFile($0) }
        files[0] = PaceDataManifestFile(
            name: "../menOpenSingle.json",
            sha256: String(repeating: "b", count: 64),
            bytes: 12_000
        )
        XCTAssertThrowsError(try makeManifest(files: files).validatedFiles()) { error in
            XCTAssertEqual(error as? PaceDataManifestError, .unsafeFileName("../menOpenSingle.json"))
        }
    }

    func testIgnoresAFileForADivisionThisBuildDoesNotKnow() throws {
        var files = HyroxDivision.allCases.map { makeFile($0) }
        files.append(
            PaceDataManifestFile(
                name: "v4/2026.09.15/kidsRelay.json",
                sha256: String(repeating: "c", count: 64),
                bytes: 1_000
            )
        )

        let entries = try makeManifest(files: files).validatedFiles()
        XCTAssertEqual(entries.count, HyroxDivision.allCases.count)
    }

    func testDecodesThePublishedManifestShape() throws {
        let manifest = try PaceReferenceLoader.loadBundledManifest()

        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertTrue(manifest.revoked.isEmpty)
        XCTAssertEqual(manifest.seasonLabel, "S6-S9")
        XCTAssertNotNil(manifest.events)
        XCTAssertNotNil(manifest.athletesPublished)
        XCTAssertEqual(manifest.generator.script, "tools/pace-data/build_pace_data.py")
    }
}

// MARK: - Version Ordering

final class PaceDataVersionTests: XCTestCase {

    func testOrdersDateStampsNumericallyRatherThanAlphabetically() {
        XCTAssertTrue(PaceDataVersion.isNewer("2026.09.15", than: "2026.9.7"))
        XCTAssertTrue(PaceDataVersion.isNewer("2026.10.01", than: "2026.09.15"))
        XCTAssertTrue(PaceDataVersion.isNewer("2027.01.01", than: "2026.12.31"))
        XCTAssertFalse(PaceDataVersion.isNewer("2026.09.15", than: "2026.09.15"))
        XCTAssertFalse(PaceDataVersion.isNewer("2026.09.14", than: "2026.09.15"))
    }

    func testTreatsAMissingComponentAsOlder() {
        XCTAssertTrue(PaceDataVersion.isNewer("2026.09.15", than: "2026.09"))
        XCTAssertEqual(PaceDataVersion.compare("2026.09.15", "2026.09.15"), .orderedSame)
    }

    func testFallsBackToStringOrderForNonNumericStamps() {
        XCTAssertEqual(PaceDataVersion.compare("2026.09.15-beta", "2026.09.15-alpha"), .orderedDescending)
    }
}
