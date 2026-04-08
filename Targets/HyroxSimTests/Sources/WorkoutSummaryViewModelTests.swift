//
//  WorkoutSummaryViewModelTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
import HyroxKit
@testable import HyroxSim

@MainActor
final class WorkoutSummaryViewModelTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    private func makeSampleWorkout() -> CompletedWorkout {
        let start = t0
        let segments: [SegmentRecord] = [
            SegmentRecord(segmentId: UUID(), index: 0, type: .run, startedAt: start, endedAt: start.addingTimeInterval(360), stationDisplayName: nil, plannedDistanceMeters: 1000),
            SegmentRecord(segmentId: UUID(), index: 1, type: .roxZone, startedAt: start.addingTimeInterval(360), endedAt: start.addingTimeInterval(390)),
            SegmentRecord(segmentId: UUID(), index: 2, type: .station, startedAt: start.addingTimeInterval(390), endedAt: start.addingTimeInterval(630), measurements: SegmentMeasurements(heartRateSamples: [
                HeartRateSample(timestamp: start.addingTimeInterval(400), bpm: 150),
                HeartRateSample(timestamp: start.addingTimeInterval(500), bpm: 170),
                HeartRateSample(timestamp: start.addingTimeInterval(600), bpm: 180)
            ]), stationDisplayName: "SkiErg"),
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
        XCTAssertEqual(vm.titleText, "Men's Open — Singles")
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
        XCTAssertTrue(vm.shareText.contains("Men's Open — Singles"))
        XCTAssertTrue(vm.shareText.contains("0:10:30"))
    }
}
