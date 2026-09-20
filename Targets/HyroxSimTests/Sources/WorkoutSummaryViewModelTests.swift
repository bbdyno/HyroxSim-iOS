//
//  WorkoutSummaryViewModelTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
import HyroxCore
@testable import HyroxSim

@MainActor
final class WorkoutSummaryViewModelTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    private func makeSampleWorkout() -> CompletedWorkout {
        let start = t0
        let segments: [SegmentRecord] = [
            SegmentRecord(
                segmentId: UUID(),
                index: 0,
                type: .run,
                startedAt: start,
                endedAt: start.addingTimeInterval(360),
                stationDisplayName: nil,
                plannedDistanceMeters: 1000,
                goalDurationSeconds: 390
            ),
            SegmentRecord(
                segmentId: UUID(),
                index: 1,
                type: .roxZone,
                startedAt: start.addingTimeInterval(360),
                endedAt: start.addingTimeInterval(390),
                goalDurationSeconds: 30
            ),
            SegmentRecord(segmentId: UUID(), index: 2, type: .station, startedAt: start.addingTimeInterval(390), endedAt: start.addingTimeInterval(630), measurements: SegmentMeasurements(heartRateSamples: [
                HeartRateSample(timestamp: start.addingTimeInterval(400), bpm: 150),
                HeartRateSample(timestamp: start.addingTimeInterval(500), bpm: 170),
                HeartRateSample(timestamp: start.addingTimeInterval(600), bpm: 180)
            ]), stationDisplayName: "SkiErg", goalDurationSeconds: 240),
        ]
        return CompletedWorkout(
            templateName: "Test Workout",
            division: .menOpenSingle,
            startedAt: start,
            finishedAt: start.addingTimeInterval(630),
            segments: segments
        )
    }

    func testHeaderTexts() {
        let vm = WorkoutSummaryViewModel(workout: makeSampleWorkout())
        XCTAssertEqual(vm.totalTimeText, "0:10:30")
        // 3493837 이후 요약 헤더는 디비전 이름이 아니라 템플릿(커스텀) 이름을 쓴다
        XCTAssertEqual(vm.titleText, "Test Workout")
        XCTAssertEqual(vm.totalGoalText, "0:11:00")
        XCTAssertEqual(vm.totalDelta.text, "-0:30")
        XCTAssertFalse(vm.dateText.isEmpty)
    }

    func testSummaryMetrics() {
        let vm = WorkoutSummaryViewModel(workout: makeSampleWorkout())
        // No GPS data → distance is 0
        XCTAssertEqual(vm.distanceText, "0 m")
        XCTAssertEqual(vm.averagePaceText, "—")
    }

    func testHeartRateMetrics() {
        let vm = WorkoutSummaryViewModel(workout: makeSampleWorkout(), maxHeartRate: 200)
        // HR only in station segment: avg (150+170+180)/3 = 166
        XCTAssertEqual(vm.averageHeartRateText, "166")
        XCTAssertEqual(vm.maxHeartRateText, "180")
    }

    func testRunPaces() {
        let vm = WorkoutSummaryViewModel(workout: makeSampleWorkout())
        XCTAssertEqual(vm.runPaces.count, 1)
        XCTAssertEqual(vm.runPaces[0].index, 1)
    }

    func testStationItems() {
        let vm = WorkoutSummaryViewModel(workout: makeSampleWorkout())
        XCTAssertEqual(vm.stationItems.count, 1)
        XCTAssertEqual(vm.stationItems[0].name, "SkiErg")
        XCTAssertEqual(vm.stationItems[0].durationSeconds, 240, accuracy: 0.001)
    }

    func testHeartRateZoneDistribution() {
        let vm = WorkoutSummaryViewModel(workout: makeSampleWorkout(), maxHeartRate: 200)
        let zones = vm.heartRateZoneDistribution
        XCTAssertFalse(zones.isEmpty)
        // bpm 150=75%→Z3, 170=85%→Z4, 180=90%→Z5
        let zoneNames = zones.filter { $0.ratio > 0 }.map(\.zone)
        XCTAssertTrue(zoneNames.contains(.z3))
        XCTAssertTrue(zoneNames.contains(.z4))
        XCTAssertTrue(zoneNames.contains(.z5))
    }

    func testBreakdownItems() {
        let vm = WorkoutSummaryViewModel(workout: makeSampleWorkout())
        XCTAssertEqual(vm.breakdownItems.count, 3)
        XCTAssertEqual(vm.breakdownItems[0].title, "RUN")
        XCTAssertEqual(vm.breakdownItems[1].title, "ROX ZONE")
        XCTAssertEqual(vm.breakdownItems[2].title, "SkiErg")
    }

    func testSectionsGroupRunAndRoxForExpandableLayout() {
        let vm = WorkoutSummaryViewModel(workout: makeSampleWorkout())
        XCTAssertEqual(vm.sections.count, 1)
        XCTAssertEqual(vm.sections[0].runGroup?.title, "RUN 1 + ROX")
        XCTAssertEqual(vm.sections[0].runGroup?.durationText, "0:06:30")
        XCTAssertEqual(vm.sections[0].runGroup?.delta.text, "-0:30")
        XCTAssertEqual(vm.sections[0].runGroup?.detailItems.count, 2)
        XCTAssertEqual(vm.sections[0].runGroup?.detailItems[0].title, "Run 1")
        XCTAssertEqual(vm.sections[0].runGroup?.detailItems[1].title, "Rox Zone")
        XCTAssertEqual(vm.sections[0].station?.title, "SkiErg")
    }

    func testSectionsKeepSequentialRunNumbersWhenExitRoxPrecedesNextRun() {
        let start = t0
        let workout = CompletedWorkout(
            templateName: "Men's Open — Singles",
            division: .menOpenSingle,
            startedAt: start,
            finishedAt: start.addingTimeInterval(16),
            segments: [
                SegmentRecord(segmentId: UUID(), index: 0, type: .run, startedAt: start, endedAt: start.addingTimeInterval(2), goalDurationSeconds: 10),
                SegmentRecord(segmentId: UUID(), index: 1, type: .roxZone, startedAt: start.addingTimeInterval(2), endedAt: start.addingTimeInterval(3), goalDurationSeconds: 5),
                SegmentRecord(segmentId: UUID(), index: 2, type: .station, startedAt: start.addingTimeInterval(3), endedAt: start.addingTimeInterval(5), stationDisplayName: "SkiErg", goalDurationSeconds: 20),
                SegmentRecord(segmentId: UUID(), index: 3, type: .roxZone, startedAt: start.addingTimeInterval(5), endedAt: start.addingTimeInterval(6), goalDurationSeconds: 5),
                SegmentRecord(segmentId: UUID(), index: 4, type: .run, startedAt: start.addingTimeInterval(6), endedAt: start.addingTimeInterval(8), goalDurationSeconds: 10),
                SegmentRecord(segmentId: UUID(), index: 5, type: .roxZone, startedAt: start.addingTimeInterval(8), endedAt: start.addingTimeInterval(9), goalDurationSeconds: 5),
                SegmentRecord(segmentId: UUID(), index: 6, type: .station, startedAt: start.addingTimeInterval(9), endedAt: start.addingTimeInterval(11), stationDisplayName: "Sled Push", goalDurationSeconds: 20),
                SegmentRecord(segmentId: UUID(), index: 7, type: .roxZone, startedAt: start.addingTimeInterval(11), endedAt: start.addingTimeInterval(12), goalDurationSeconds: 5),
                SegmentRecord(segmentId: UUID(), index: 8, type: .run, startedAt: start.addingTimeInterval(12), endedAt: start.addingTimeInterval(16), goalDurationSeconds: 10)
            ]
        )

        let vm = WorkoutSummaryViewModel(workout: workout)
        XCTAssertEqual(vm.sections.count, 3)
        XCTAssertEqual(vm.sections[0].runGroup?.index, 1)
        XCTAssertEqual(vm.sections[1].runGroup?.index, 2)
        XCTAssertEqual(vm.sections[2].runGroup?.index, 3)
        XCTAssertEqual(vm.sections[0].station?.durationText, "0:00:02")
        XCTAssertEqual(vm.sections[0].station?.delta.text, "-0:18")
        XCTAssertEqual(vm.sections[1].runGroup?.detailItems.map(\.title), ["Rox Zone", "Run 2", "Rox Zone"])
        XCTAssertEqual(vm.sections[1].runGroup?.durationText, "0:00:04")
    }

    func testStationNameFallsBackFromDivisionOrder() {
        let start = t0
        let workout = CompletedWorkout(
            templateName: "Men's Open — Singles",
            division: .menOpenSingle,
            startedAt: start,
            finishedAt: start.addingTimeInterval(630),
            segments: [
                SegmentRecord(
                    segmentId: UUID(),
                    index: 0,
                    type: .run,
                    startedAt: start,
                    endedAt: start.addingTimeInterval(360)
                ),
                SegmentRecord(
                    segmentId: UUID(),
                    index: 1,
                    type: .roxZone,
                    startedAt: start.addingTimeInterval(360),
                    endedAt: start.addingTimeInterval(390)
                ),
                SegmentRecord(
                    segmentId: UUID(),
                    index: 2,
                    type: .station,
                    startedAt: start.addingTimeInterval(390),
                    endedAt: start.addingTimeInterval(630)
                )
            ]
        )

        let vm = WorkoutSummaryViewModel(workout: workout)
        XCTAssertEqual(vm.stationItems[0].name, "SkiErg")
        XCTAssertEqual(vm.breakdownItems[2].title, "SkiErg")
    }

    func testShareText() {
        let vm = WorkoutSummaryViewModel(workout: makeSampleWorkout())
        XCTAssertTrue(vm.shareText.contains("Test Workout"))
        XCTAssertTrue(vm.shareText.contains("0:10:30"))
        XCTAssertTrue(vm.shareText.contains("Goal: 0:11:00"))
        XCTAssertTrue(vm.shareText.contains("Delta: -0:30"))
    }

    // MARK: - 심박 존

    func testHeartRateZonesAreOmittedWithoutMaxHeartRate() {
        // 최대 심박을 모르면 남의 기준으로 존을 그리느니 아무것도 그리지 않는다.
        let vm = WorkoutSummaryViewModel(workout: makeSampleWorkout())
        XCTAssertTrue(vm.heartRateZoneDistribution.isEmpty)
    }
}

// MARK: - 격차 분석 카드

/// 고정된 기준 기록을 주는 테스트용 데이터 소스.
private struct StubGapReferenceProvider: GapReferenceProviding {
    var runSeconds: TimeInterval = 8 * 300
    var roxZoneSeconds: TimeInterval = 15 * 30
    var stationSeconds: TimeInterval = 240
    var isExtrapolated = false

    func reference(for target: GapTarget, division: HyroxDivision) -> GapReference? {
        var stations: [StationKind: TimeInterval] = [:]
        for kind in StationKind.standardOrder {
            stations[kind] = stationSeconds
        }
        return GapReference(
            totalSeconds: runSeconds + roxZoneSeconds + stationSeconds * 8,
            runSeconds: runSeconds,
            roxZoneSeconds: roxZoneSeconds,
            stationSeconds: stations,
            percentile: 20,
            isExtrapolated: isExtrapolated
        )
    }
}

@MainActor
final class WorkoutSummaryGapCardTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    /// 공식 코스 기록. 구간 목표(`goalDurationSeconds`)가 있으면 뷰모델이 그걸 목표로 잡는다.
    private func makeStandardWorkout(
        runSeconds: TimeInterval = 320,
        roxSeconds: TimeInterval = 40,
        stationSeconds: TimeInterval = 240,
        stationOverrides: [StationKind: TimeInterval] = [:],
        goalSecondsPerSegment: TimeInterval? = 200
    ) -> CompletedWorkout {
        var records: [SegmentRecord] = []
        var cursor = t0
        var index = 0

        func append(_ type: SegmentType, duration: TimeInterval, station: StationKind? = nil) {
            records.append(
                SegmentRecord(
                    segmentId: UUID(),
                    index: index,
                    type: type,
                    startedAt: cursor,
                    endedAt: cursor.addingTimeInterval(duration),
                    stationDisplayName: station?.displayName,
                    plannedDistanceMeters: type == .run ? 1000 : nil,
                    goalDurationSeconds: goalSecondsPerSegment
                )
            )
            cursor = cursor.addingTimeInterval(duration)
            index += 1
        }

        for (stationIndex, kind) in StationKind.standardOrder.enumerated() {
            append(.run, duration: runSeconds)
            append(.roxZone, duration: roxSeconds)
            append(.station, duration: stationOverrides[kind] ?? stationSeconds, station: kind)
            if stationIndex < StationKind.standardOrder.count - 1 {
                append(.roxZone, duration: roxSeconds)
            }
        }

        return CompletedWorkout(
            templateName: "Race Simulation",
            division: .menOpenSingle,
            startedAt: t0,
            finishedAt: cursor,
            segments: records
        )
    }

    private func makeCustomWorkout() -> CompletedWorkout {
        CompletedWorkout(
            templateName: "Half Rox",
            division: .menOpenSingle,
            startedAt: t0,
            finishedAt: t0.addingTimeInterval(600),
            segments: [
                SegmentRecord(
                    segmentId: UUID(),
                    index: 0,
                    type: .run,
                    startedAt: t0,
                    endedAt: t0.addingTimeInterval(300),
                    plannedDistanceMeters: 500,
                    goalDurationSeconds: 280
                ),
                SegmentRecord(
                    segmentId: UUID(),
                    index: 1,
                    type: .station,
                    startedAt: t0.addingTimeInterval(300),
                    endedAt: t0.addingTimeInterval(600),
                    stationDisplayName: StationKind.skiErg.displayName,
                    goalDurationSeconds: 280
                )
            ]
        )
    }

    func testCardIsHiddenForCustomCourse() {
        let vm = WorkoutSummaryViewModel(
            workout: makeCustomWorkout(),
            gapReferenceProvider: StubGapReferenceProvider()
        )
        XCTAssertEqual(vm.gapCard.status, .unsupportedCourse)
        XCTAssertFalse(vm.gapCard.isVisible)
        XCTAssertTrue(vm.gapHighlights.isEmpty)
    }

    func testCardAsksForAGoalWhenTheWorkoutHasNone() {
        let vm = WorkoutSummaryViewModel(
            workout: makeStandardWorkout(goalSecondsPerSegment: nil),
            gapReferenceProvider: StubGapReferenceProvider()
        )
        XCTAssertEqual(vm.gapCard.status, .noGoal)
        XCTAssertTrue(vm.gapCard.isVisible)
        XCTAssertNotNil(vm.gapCard.message)
        XCTAssertTrue(vm.gapCard.rows.isEmpty)
    }

    func testCardIsHiddenWhenTheGoalSitsOutsideTheReferenceData() {
        let vm = WorkoutSummaryViewModel(
            workout: makeStandardWorkout(),
            gapReferenceProvider: StubGapReferenceProvider(isExtrapolated: true)
        )
        XCTAssertEqual(vm.gapCard.status, .noReference)
        XCTAssertTrue(vm.gapCard.rows.isEmpty)
    }

    func testCardShowsTopThreeGaps() throws {
        // 러닝 +160 · 록스존 +150 · 월볼 +180 · 로잉 +60 = 되찾을 수 있는 시간 550초
        let workout = makeStandardWorkout(
            stationOverrides: [.wallBalls: 420, .rowing: 300]
        )
        let vm = WorkoutSummaryViewModel(
            workout: workout,
            gapReferenceProvider: StubGapReferenceProvider()
        )
        let card = vm.gapCard

        XCTAssertEqual(card.status, .gaps)
        XCTAssertEqual(card.rows.count, 3)
        // 월볼(+180) → 러닝(+160) → 록스존(+150) 순.
        XCTAssertEqual(card.rows[0].title, "Wall Balls")
        XCTAssertEqual(card.rows.map(\.accent), [.station, .run, .roxZone])
        XCTAssertEqual(card.rows[0].deltaText, "\u{2212}3:00")
        XCTAssertEqual(card.rows[0].barRatio, 1, accuracy: 0.0001)
        XCTAssertEqual(card.rows[1].barRatio, 160.0 / 180.0, accuracy: 0.0001)
        XCTAssertTrue(card.rows[0].shareText.contains("33"))
        // 네 번째 구간(로잉 +60)은 접혀서 한 줄로만 남는다.
        let remainderText = try XCTUnwrap(card.remainderText)
        XCTAssertTrue(remainderText.contains("1:00"))
        // 총 회수 가능 시간 9:10
        XCTAssertTrue(try XCTUnwrap(card.message).contains("9:10"))
        XCTAssertNotNil(card.subtitle)
    }

    func testCardReportsGoalAlreadyMet() {
        let workout = makeStandardWorkout(runSeconds: 280, roxSeconds: 25, stationSeconds: 220)
        let vm = WorkoutSummaryViewModel(
            workout: workout,
            gapReferenceProvider: StubGapReferenceProvider()
        )
        let card = vm.gapCard

        XCTAssertEqual(card.status, .goalMet)
        XCTAssertTrue(card.rows.isEmpty)
        XCTAssertNotNil(card.message)
    }

    func testShareContentUsesGapHighlights() {
        let workout = makeStandardWorkout(stationOverrides: [.wallBalls: 420, .rowing: 300])
        let vm = WorkoutSummaryViewModel(
            workout: workout,
            gapReferenceProvider: StubGapReferenceProvider()
        )

        XCTAssertEqual(vm.gapHighlights.count, 3)
        XCTAssertEqual(vm.shareCardContent.highlights.count, 3)
        XCTAssertEqual(vm.shareCardContent.highlights[0].valueText, "\u{2212}3:00")
        XCTAssertEqual(vm.shareCardContent.division, "Men's Open — Singles")
        XCTAssertTrue(vm.shareText.contains("\u{2212}3:00"))
    }

    func testShareContentFallsBackToSlowestStations() {
        let vm = WorkoutSummaryViewModel(
            workout: makeCustomWorkout(),
            gapReferenceProvider: StubGapReferenceProvider()
        )
        let content = vm.shareCardContent

        XCTAssertTrue(content.highlights.isEmpty)
        XCTAssertNil(content.highlightTitle)
        XCTAssertEqual(content.fallbackHighlights.count, 1)
        XCTAssertEqual(content.fallbackHighlights[0].title, "SkiErg")
    }
}

// MARK: - 리뷰 요청 조건

final class ReviewRequestPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let policy = ReviewRequestPolicy()

    private func snapshot(
        count: Int = 5,
        personalRecord: Bool = true,
        lastRequestedAt: Date? = nil
    ) -> ReviewRequestPolicy.Snapshot {
        ReviewRequestPolicy.Snapshot(
            completedWorkoutCount: count,
            didSetPersonalRecord: personalRecord,
            lastRequestedAt: lastRequestedAt
        )
    }

    func testRequestsWhenEveryConditionIsMet() {
        XCTAssertTrue(policy.shouldRequest(snapshot(count: 3), now: now))
    }

    func testDoesNotRequestBelowTheWorkoutThreshold() {
        XCTAssertFalse(policy.shouldRequest(snapshot(count: 2), now: now))
    }

    func testDoesNotRequestWithoutAPersonalRecord() {
        XCTAssertFalse(policy.shouldRequest(snapshot(personalRecord: false), now: now))
    }

    func testDoesNotRequestInsideTheCooldown() {
        let recent = now.addingTimeInterval(-119 * 24 * 60 * 60)
        XCTAssertFalse(policy.shouldRequest(snapshot(lastRequestedAt: recent), now: now))
    }

    func testRequestsAgainAfterTheCooldown() {
        let old = now.addingTimeInterval(-121 * 24 * 60 * 60)
        XCTAssertTrue(policy.shouldRequest(snapshot(lastRequestedAt: old), now: now))
    }
}

@MainActor
final class ReviewRequestGateTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        suiteName = "review-gate-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    private func makeWorkout(finishedAt: Date, durationSeconds: TimeInterval) -> CompletedWorkout {
        let started = finishedAt.addingTimeInterval(-durationSeconds)
        return CompletedWorkout(
            templateName: "Race Simulation",
            division: .menOpenSingle,
            startedAt: started,
            finishedAt: finishedAt,
            segments: [
                SegmentRecord(
                    segmentId: UUID(),
                    index: 0,
                    type: .run,
                    startedAt: started,
                    endedAt: finishedAt,
                    plannedDistanceMeters: 1000
                )
            ]
        )
    }

    func testAsksOnceThreeWorkoutsAndAPersonalRecordAreIn() {
        let gate = ReviewRequestGate(defaults: defaults)

        // 1회차: 비교할 기록이 없으므로 "갱신"이 아니다.
        XCTAssertFalse(gate.evaluate(makeWorkout(finishedAt: now, durationSeconds: 3_600), now: now))
        // 2회차: 기록은 갱신했지만 아직 3회가 아니다.
        XCTAssertFalse(gate.evaluate(makeWorkout(finishedAt: now, durationSeconds: 3_540), now: now))
        // 3회차: 3회 + 기록 갱신.
        XCTAssertTrue(gate.evaluate(makeWorkout(finishedAt: now, durationSeconds: 3_480), now: now))
        XCTAssertEqual(gate.completedWorkoutCount, 3)
    }

    func testDoesNotAskWhenTheRecordWasNotBeaten() {
        let gate = ReviewRequestGate(defaults: defaults)
        XCTAssertFalse(gate.evaluate(makeWorkout(finishedAt: now, durationSeconds: 3_600), now: now))
        XCTAssertFalse(gate.evaluate(makeWorkout(finishedAt: now, durationSeconds: 3_540), now: now))
        // 3회차지만 이전 기록보다 느리다.
        XCTAssertFalse(gate.evaluate(makeWorkout(finishedAt: now, durationSeconds: 3_600), now: now))
        XCTAssertEqual(gate.completedWorkoutCount, 3)
    }

    func testDoesNotAskAgainInsideTheCooldown() {
        let gate = ReviewRequestGate(defaults: defaults)
        gate.markRequested(at: now.addingTimeInterval(-30 * 24 * 60 * 60))

        XCTAssertFalse(gate.evaluate(makeWorkout(finishedAt: now, durationSeconds: 3_600), now: now))
        XCTAssertFalse(gate.evaluate(makeWorkout(finishedAt: now, durationSeconds: 3_540), now: now))
        XCTAssertFalse(gate.evaluate(makeWorkout(finishedAt: now, durationSeconds: 3_480), now: now))
    }

    func testTheSameWorkoutIsCountedOnce() {
        let gate = ReviewRequestGate(defaults: defaults)
        let workout = makeWorkout(finishedAt: now, durationSeconds: 3_600)

        XCTAssertFalse(gate.evaluate(workout, now: now))
        XCTAssertFalse(gate.evaluate(workout, now: now))
        XCTAssertEqual(gate.completedWorkoutCount, 1)
    }

    func testBrowsingOldRecordsDoesNotCount() {
        let gate = ReviewRequestGate(defaults: defaults)
        let old = makeWorkout(finishedAt: now.addingTimeInterval(-3 * 24 * 60 * 60), durationSeconds: 3_600)

        XCTAssertFalse(gate.evaluate(old, now: now))
        XCTAssertEqual(gate.completedWorkoutCount, 0)
    }
}
