//
//  WorkoutSegmentTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

final class WorkoutSegmentTests: XCTestCase {

    // MARK: - Convenience Constructors

    func testRunConvenienceConstructor() {
        let segment = WorkoutSegment.run()
        XCTAssertEqual(segment.type, .run)
        XCTAssertEqual(segment.distanceMeters, 1000)
        XCTAssertNil(segment.stationKind)
        XCTAssertNil(segment.weightKg)
    }

    func testRunWithCustomDistance() {
        let segment = WorkoutSegment.run(distanceMeters: 500)
        XCTAssertEqual(segment.distanceMeters, 500)
    }

    func testRoxZoneConvenienceConstructor() {
        let segment = WorkoutSegment.roxZone()
        XCTAssertEqual(segment.type, .roxZone)
        XCTAssertNil(segment.distanceMeters)
        XCTAssertNil(segment.stationKind)
    }

    func testStationConvenienceConstructor() {
        let segment = WorkoutSegment.station(.skiErg, target: .distance(meters: 1000))
        XCTAssertEqual(segment.type, .station)
        XCTAssertEqual(segment.stationKind, .skiErg)
        XCTAssertEqual(segment.stationTarget, .distance(meters: 1000))
        XCTAssertNil(segment.distanceMeters)
    }

    func testStationWithWeight() {
        let segment = WorkoutSegment.station(.sledPush, target: .distance(meters: 50), weightKg: 152, weightNote: "sled total")
        XCTAssertEqual(segment.weightKg, 152)
        XCTAssertEqual(segment.weightNote, "sled total")
    }

    // MARK: - Validation (valid cases)

    func testValidRunSegment() {
        XCTAssertNoThrow(try WorkoutSegment.run().validate())
    }

    func testValidStationSegment() {
        XCTAssertNoThrow(try WorkoutSegment.station(.wallBalls, target: .reps(count: 100), weightKg: 6).validate())
    }

    func testValidRoxZoneSegment() {
        XCTAssertNoThrow(try WorkoutSegment.roxZone().validate())
    }

    // MARK: - Validation (invalid cases)

    func testRunWithStationKindThrows() {
        let segment = WorkoutSegment(type: .run, stationKind: .skiErg)
        XCTAssertThrowsError(try segment.validate()) { error in
            XCTAssertEqual(error as? WorkoutSegment.ValidationError, .runSegmentHasStationData)
        }
    }

    func testRunWithWeightThrows() {
        let segment = WorkoutSegment(type: .run, weightKg: 10)
        XCTAssertThrowsError(try segment.validate()) { error in
            XCTAssertEqual(error as? WorkoutSegment.ValidationError, .runSegmentHasStationData)
        }
    }

    func testRoxZoneWithWeightThrows() {
        let segment = WorkoutSegment(type: .roxZone, weightKg: 10)
        XCTAssertThrowsError(try segment.validate()) { error in
            XCTAssertEqual(error as? WorkoutSegment.ValidationError, .runSegmentHasStationData)
        }
    }

    func testStationWithDistanceThrows() {
        let segment = WorkoutSegment(type: .station, distanceMeters: 1000, stationKind: .skiErg)
        XCTAssertThrowsError(try segment.validate()) { error in
            XCTAssertEqual(error as? WorkoutSegment.ValidationError, .stationSegmentHasDistanceData)
        }
    }
}

// MARK: - 레이스 데이: 페이스 카드

/// 페이스 카드는 운동 화면과 **같은 블록 규칙**(RoxZone 을 소유 Run 에 합산)을 써야
/// 대회장에서 표와 시계가 어긋나지 않는다. 여기서 검증하는 건 그 합산과 누적 계산이다.
final class RacePaceCardTests: XCTestCase {

    /// Run(300) + Rox(30) / SkiErg(240) / Rox(30) + Run(300) = 900
    private func makeTemplate(withGoals: Bool = true) -> WorkoutTemplate {
        func goal(_ value: TimeInterval) -> TimeInterval? { withGoals ? value : nil }
        return WorkoutTemplate(
            name: "Race",
            segments: [
                WorkoutSegment(type: .run, distanceMeters: 1000, goalDurationSeconds: goal(300)),
                WorkoutSegment(type: .roxZone, goalDurationSeconds: goal(30)),
                WorkoutSegment(
                    type: .station,
                    goalDurationSeconds: goal(240),
                    stationKind: .skiErg,
                    stationTarget: .distance(meters: 1000)
                ),
                WorkoutSegment(type: .roxZone, goalDurationSeconds: goal(30)),
                WorkoutSegment(type: .run, distanceMeters: 1000, goalDurationSeconds: goal(300))
            ]
        )
    }

    func testRowsFoldTransitionsIntoTheOwningRun() {
        let card = RacePaceCard.make(template: makeTemplate())

        XCTAssertEqual(card.rows.count, 3)
        XCTAssertEqual(card.rows.map(\.kind), [.run, .station, .run])
        XCTAssertEqual(card.rows[0].title, "RUN 1")
        XCTAssertEqual(card.rows[1].title, "SkiErg")
        XCTAssertEqual(card.rows[2].title, "RUN 2")
        XCTAssertEqual(card.rows.compactMap(\.goalSeconds), [330, 240, 330])
    }

    func testCumulativeTargetsAccumulateAcrossRows() {
        let card = RacePaceCard.make(template: makeTemplate())

        XCTAssertEqual(card.rows.compactMap(\.cumulativeSeconds), [330, 570, 900])
        XCTAssertEqual(card.totalGoalSeconds, 900)
        XCTAssertTrue(card.hasGoals)
        XCTAssertFalse(card.isScaledToRaceGoal)
    }

    func testRunRowsCarryTargetPace() {
        let card = RacePaceCard.make(template: makeTemplate())

        // 전환 구간을 뺀 런 자체 목표(300초 / 1 km)가 페이스가 된다.
        XCTAssertEqual(card.rows[0].paceSecondsPerKm ?? 0, 300, accuracy: 0.001)
        XCTAssertNil(card.rows[1].paceSecondsPerKm)
    }

    func testRaceGoalScalesEverySplit() {
        let card = RacePaceCard.make(template: makeTemplate(), raceGoalSeconds: 450)

        XCTAssertTrue(card.isScaledToRaceGoal)
        XCTAssertEqual(card.rows.compactMap(\.goalSeconds), [165, 120, 165])
        XCTAssertEqual(card.rows.compactMap(\.cumulativeSeconds), [165, 285, 450])
        XCTAssertEqual(card.totalGoalSeconds, 450)
    }

    /// 나누어떨어지지 않는 목표라도 마지막 누적값은 목표와 정확히 같아야 한다.
    /// 대회장에서 "총합이 1초 모자란 표"를 보면 신뢰가 무너진다.
    func testScalingAbsorbsRoundingInTheCumulativeColumn() {
        let card = RacePaceCard.make(template: makeTemplate(), raceGoalSeconds: 901)

        XCTAssertEqual(card.rows.last?.cumulativeSeconds, 901)
        XCTAssertEqual(card.totalGoalSeconds, 901)
        XCTAssertEqual(card.rows.compactMap(\.goalSeconds).reduce(0, +), 901)
    }

    func testTemplateWithoutGoalsProducesEmptyTargets() {
        let card = RacePaceCard.make(template: makeTemplate(withGoals: false))

        XCTAssertEqual(card.rows.count, 3)
        XCTAssertFalse(card.hasGoals)
        XCTAssertNil(card.totalGoalSeconds)
        XCTAssertTrue(card.rows.allSatisfy { $0.goalSeconds == nil && $0.cumulativeSeconds == nil })
    }

    /// 목표가 없으면 비율 조정도 할 수 없다 — 대회 목표만 들어와도 표는 비어 있어야 한다.
    func testRaceGoalWithoutTemplateGoalsStaysEmpty() {
        let card = RacePaceCard.make(template: makeTemplate(withGoals: false), raceGoalSeconds: 5400)

        XCTAssertFalse(card.hasGoals)
        XCTAssertFalse(card.isScaledToRaceGoal)
    }

    func testTitleFallsBackToTemplateName() {
        let card = RacePaceCard.make(template: makeTemplate())
        XCTAssertEqual(card.title, "Race")

        let named = RacePaceCard.make(template: makeTemplate(), title: "HYROX Seoul")
        XCTAssertEqual(named.title, "HYROX Seoul")
    }
}

// MARK: - 레이스 데이: 체크리스트

final class RaceDayChecklistTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "RaceDayChecklistTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: 카탈로그

    func testRuleItemCount() {
        XCTAssertEqual(RaceDayChecklist.rules.count, 8)
        XCTAssertTrue(RaceDayChecklist.rules.allSatisfy { $0.category == .rule })
    }

    /// 룰 항목은 근거 한 줄과 페널티 배지를 전부 갖고 있어야 한다.
    /// 근거 없이 "하세요"만 있는 줄은 대회장에서 무시된다.
    func testEveryRuleItemCarriesEvidenceAndPenalty() {
        for item in RaceDayChecklist.rules {
            XCTAssertNotNil(item.defaultEvidence, "\(item.id) 에 근거가 없습니다")
            XCTAssertNotNil(item.evidenceLocalizationKey, "\(item.id) 에 근거 키가 없습니다")
            XCTAssertNotNil(item.penaltyBadge, "\(item.id) 에 페널티 배지가 없습니다")
        }
    }

    func testGearAndNutritionItemsHaveNoEvidenceLine() {
        for item in RaceDayChecklist.gear + RaceDayChecklist.nutrition {
            XCTAssertNil(item.defaultEvidence)
            XCTAssertNil(item.evidenceLocalizationKey)
        }
    }

    func testItemIdsAreUnique() {
        XCTAssertEqual(RaceDayChecklist.allIds.count, RaceDayChecklist.all.count)
    }

    func testLocalizationKeysFollowTheFeaturePrefix() {
        let item = RaceDayChecklist.rules[0]
        XCTAssertEqual(item.titleLocalizationKey, "race_day.checklist.chip_ankle.title")
        XCTAssertEqual(item.evidenceLocalizationKey, "race_day.checklist.chip_ankle.evidence")
    }

    // MARK: 저장

    func testCheckStatePersists() {
        let store = RaceDayChecklistStore(defaults: defaults)
        store.setChecked(true, itemId: "chip_ankle")

        let reopened = RaceDayChecklistStore(defaults: defaults)
        XCTAssertTrue(reopened.isChecked("chip_ankle"))
        XCTAssertFalse(reopened.isChecked("fast_lane"))
    }

    func testToggleReturnsNewState() {
        let store = RaceDayChecklistStore(defaults: defaults)

        XCTAssertTrue(store.toggle(itemId: "fast_lane"))
        XCTAssertFalse(store.toggle(itemId: "fast_lane"))
        XCTAssertFalse(store.isChecked("fast_lane"))
    }

    func testResetClearsOnlyThatRace() {
        let store = RaceDayChecklistStore(defaults: defaults)
        store.setChecked(true, itemId: "chip_ankle", raceKey: "seoul")
        store.setChecked(true, itemId: "chip_ankle", raceKey: "tokyo")

        store.reset(raceKey: "seoul")

        XCTAssertTrue(store.checkedItemIds(raceKey: "seoul").isEmpty)
        XCTAssertTrue(store.isChecked("chip_ankle", raceKey: "tokyo"))
    }

    func testResetAllClearsEverything() {
        let store = RaceDayChecklistStore(defaults: defaults)
        store.setChecked(true, itemId: "chip_ankle", raceKey: "seoul")
        store.setChecked(true, itemId: "warm_up", raceKey: "tokyo")

        store.resetAll()

        XCTAssertTrue(store.checkedItemIds(raceKey: "seoul").isEmpty)
        XCTAssertTrue(store.checkedItemIds(raceKey: "tokyo").isEmpty)
    }

    /// 항목이 사라진 뒤에도 옛 ID 가 남아 진행률을 부풀리면 안 된다.
    func testUnknownItemIdsAreIgnored() {
        defaults.set(["default": ["chip_ankle", "removed_item"]], forKey: "raceDay.checklist.checkedItems.v1")
        let store = RaceDayChecklistStore(defaults: defaults)

        XCTAssertEqual(store.checkedItemIds(), ["chip_ankle"])
        store.setChecked(true, itemId: "removed_item")
        XCTAssertEqual(store.checkedItemIds(), ["chip_ankle"])
    }

    func testProgressCountsCheckedItemsPerCategory() {
        let store = RaceDayChecklistStore(defaults: defaults)
        store.setChecked(true, itemId: "chip_ankle")
        store.setChecked(true, itemId: "assigned_wave")

        let rules = store.progress(in: .rule)
        XCTAssertEqual(rules.done, 2)
        XCTAssertEqual(rules.total, 8)
        XCTAssertEqual(store.progress(in: .gear).done, 0)
    }

    func testRaceKeyFallsBackWhenNoRaceRegistered() {
        XCTAssertEqual(RaceDayChecklistStore.raceKey(for: nil), RaceDayChecklistStore.defaultRaceKey)

        let target = RaceTarget(eventName: "HYROX Seoul", date: Date())
        XCTAssertEqual(RaceDayChecklistStore.raceKey(for: target), target.id.uuidString)
    }
}

// MARK: - 레이스 데이: 랩 카운터

final class RaceLapCounterTests: XCTestCase {

    func testIncrementCounts() {
        var counter = RaceLapCounter()
        counter.increment()
        counter.increment()
        XCTAssertEqual(counter.count, 2)
    }

    /// 잘못 눌러도 음수로 내려가면 안 된다 — 대회장에서 되돌릴 방법이 없다.
    func testDecrementStopsAtZero() {
        var counter = RaceLapCounter()
        counter.increment()
        counter.decrement()
        counter.decrement()
        XCTAssertEqual(counter.count, 0)
    }

    func testSetClampsNegativeValues() {
        var counter = RaceLapCounter()
        counter.set(5)
        XCTAssertEqual(counter.count, 5)
        counter.set(-3)
        XCTAssertEqual(counter.count, 0)
    }

    func testSegmentChangeResetsCount() {
        let first = UUID()
        let second = UUID()
        var counter = RaceLapCounter()
        counter.syncSegment(first)
        counter.increment()
        counter.increment()

        XCTAssertTrue(counter.syncSegment(second))
        XCTAssertEqual(counter.count, 0)
    }

    func testSameSegmentKeepsCount() {
        let segment = UUID()
        var counter = RaceLapCounter()
        counter.syncSegment(segment)
        counter.increment()

        XCTAssertFalse(counter.syncSegment(segment))
        XCTAssertEqual(counter.count, 1)
    }
}
