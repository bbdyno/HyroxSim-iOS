//
//  MappersTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore
import HyroxPersistenceApple

final class MappersTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    // MARK: - CompletedWorkoutMapper

    func testCompletedWorkoutRoundTrip() throws {
        let original = CompletedWorkout(
            templateName: "Men's Open — Singles",
            division: .menOpenSingle,
            startedAt: t0,
            finishedAt: t0.addingTimeInterval(3600),
            segments: [
                SegmentRecord(
                    segmentId: UUID(),
                    index: 0,
                    type: .run,
                    startedAt: t0,
                    endedAt: t0.addingTimeInterval(300),
                    pausedDuration: 10,
                    measurements: SegmentMeasurements(
                        locationSamples: [
                            LocationSample(timestamp: t0, latitude: 37.5, longitude: 127.0, horizontalAccuracy: 5)
                        ],
                        heartRateSamples: [
                            HeartRateSample(timestamp: t0.addingTimeInterval(10), bpm: 155)
                        ]
                    ),
                    plannedDistanceMeters: 1000
                ),
                SegmentRecord(
                    segmentId: UUID(),
                    index: 1,
                    type: .roxZone,
                    startedAt: t0.addingTimeInterval(300),
                    endedAt: t0.addingTimeInterval(330)
                ),
                SegmentRecord(
                    segmentId: UUID(),
                    index: 2,
                    type: .station,
                    startedAt: t0.addingTimeInterval(330),
                    endedAt: t0.addingTimeInterval(600),
                    stationDisplayName: "SkiErg"
                )
            ]
        )

        let stored = try CompletedWorkoutMapper.toStored(original)
        let restored = try CompletedWorkoutMapper.toDomain(stored)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.templateName, original.templateName)
        XCTAssertEqual(restored.division, original.division)
        XCTAssertEqual(restored.segments.count, 3)
        XCTAssertEqual(restored.segments[0].type, .run)
        XCTAssertEqual(restored.segments[0].pausedDuration, 10, accuracy: 0.001)
        XCTAssertEqual(restored.segments[0].measurements.locationSamples.count, 1)
        XCTAssertEqual(restored.segments[0].measurements.heartRateSamples[0].bpm, 155)
        XCTAssertEqual(restored.segments[0].plannedDistanceMeters, 1000)
        XCTAssertEqual(restored.segments[1].type, .roxZone)
        XCTAssertEqual(restored.segments[2].type, .station)
        XCTAssertEqual(restored.segments[2].stationDisplayName, "SkiErg")
    }

    func testEmptySegmentsWorkoutRoundTrip() throws {
        let original = CompletedWorkout(
            templateName: "Empty",
            startedAt: t0,
            finishedAt: t0,
            segments: []
        )

        let stored = try CompletedWorkoutMapper.toStored(original)
        let restored = try CompletedWorkoutMapper.toDomain(stored)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.segments.count, 0)
    }

    // MARK: - WorkoutTemplateMapper

    func testWorkoutTemplateRoundTrip() throws {
        let original = WorkoutTemplate(
            name: "Custom Half",
            segments: [
                .run(distanceMeters: 500),
                .roxZone(),
                .station(.wallBalls, target: .reps(count: 50), weightKg: 6)
            ]
        )

        let stored = try WorkoutTemplateMapper.toStored(original)
        let restored = try WorkoutTemplateMapper.toDomain(stored)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.name, "Custom Half")
        XCTAssertEqual(restored.segments.count, 3)
        XCTAssertEqual(restored.segments[0].distanceMeters, 500)
        XCTAssertEqual(restored.segments[2].stationKind, .wallBalls)
        XCTAssertEqual(restored.segments[2].weightKg, 6)
        XCTAssertFalse(restored.isBuiltIn)
        XCTAssertTrue(restored.usesRoxZone)
    }

    // MARK: - usesRoxZone

    private func makeRoxTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            name: "Custom ROX",
            segments: [
                .run(distanceMeters: 1000),
                .roxZone(),
                .station(.skiErg, target: .distance(meters: 1000)),
                .roxZone(),
                .run(distanceMeters: 1000)
            ],
            usesRoxZone: true
        )
    }

    /// Turning ROX Zone off used to be lost on save: the flag had nowhere to live,
    /// so the template came back with the `true` default and the "NEXT" cue returned.
    func testWorkoutTemplateWithRoxZoneOffRoundTrip() throws {
        let original = makeRoxTemplate().settingUsesRoxZone(false)
        XCTAssertFalse(original.segments.contains { $0.type == .roxZone })

        let stored = try WorkoutTemplateMapper.toStored(original)
        let restored = try WorkoutTemplateMapper.toDomain(stored)

        XCTAssertFalse(restored.usesRoxZone)
        XCTAssertEqual(restored.segments.count, 3)
        XCTAssertFalse(restored.segments.contains { $0.type == .roxZone })
    }

    func testWorkoutTemplateWithRoxZoneOnRoundTrip() throws {
        let original = makeRoxTemplate()

        let stored = try WorkoutTemplateMapper.toStored(original)
        let restored = try WorkoutTemplateMapper.toDomain(stored)

        XCTAssertTrue(restored.usesRoxZone)
        XCTAssertEqual(restored.segments.count, 5)
        XCTAssertEqual(restored.segments.filter { $0.type == .roxZone }.count, 2)
    }

    /// Rows written before the attribute existed decode as `nil` and the flag is
    /// inferred from the segments, so existing users keep working templates.
    func testLegacyStoredTemplateInfersRoxZoneFromSegments() throws {
        let withRox = try makeLegacyStored(segments: makeRoxTemplate().segments)
        XCTAssertTrue(try WorkoutTemplateMapper.toDomain(withRox).usesRoxZone)

        let withoutRox = try makeLegacyStored(segments: [
            .run(distanceMeters: 1000),
            .station(.skiErg),
            .run(distanceMeters: 1000)
        ])
        XCTAssertFalse(try WorkoutTemplateMapper.toDomain(withoutRox).usesRoxZone)

        // No run↔station boundary: both settings produce the same segments, so the
        // default (ON) is kept.
        let runsOnly = try makeLegacyStored(segments: [.run(distanceMeters: 1000), .run(distanceMeters: 500)])
        XCTAssertTrue(try WorkoutTemplateMapper.toDomain(runsOnly).usesRoxZone)
    }

    private func makeLegacyStored(segments: [WorkoutSegment]) throws -> StoredTemplate {
        StoredTemplate(
            id: UUID(),
            name: "Legacy",
            divisionRaw: nil,
            createdAt: t0,
            segmentsData: try JSONEncoder().encode(segments)
            // usesRoxZone deliberately omitted — mirrors a row from an older build
        )
    }

    // MARK: - RaceTargetMapper

    private func makeRaceTarget(
        division: HyroxDivision? = .womenProSingle,
        goalDurationSeconds: TimeInterval? = 4_500,
        note: String? = "셔틀 07:30"
    ) -> RaceTarget {
        RaceTarget(
            eventName: "HYROX Seoul",
            city: "Seoul",
            date: t0.addingTimeInterval(45 * 86_400),
            division: division,
            goalDurationSeconds: goalDurationSeconds,
            note: note,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(3_600)
        )
    }

    func testRaceTargetRoundTrip() throws {
        let original = makeRaceTarget()

        let restored = RaceTargetMapper.toDomain(RaceTargetMapper.toStored(original))

        XCTAssertEqual(restored, original)
    }

    func testRaceTargetRoundTripKeepsOptionalsNil() throws {
        let original = makeRaceTarget(division: nil, goalDurationSeconds: nil, note: nil)

        let restored = RaceTargetMapper.toDomain(RaceTargetMapper.toStored(original))

        XCTAssertNil(restored.division)
        XCTAssertNil(restored.goalDurationSeconds)
        XCTAssertNil(restored.note)
        XCTAssertEqual(restored.eventName, "HYROX Seoul")
    }

    /// 더 새 빌드가 보낸 모르는 디비전 문자열 때문에 레코드 전체를 버리면 안 된다.
    func testRaceTargetUnknownDivisionDecodesAsNil() throws {
        let stored = StoredRaceTarget(
            id: UUID(),
            eventName: "HYROX Seoul",
            date: t0,
            divisionRaw: "menSuperPro",
            createdAt: t0,
            updatedAt: t0
        )

        let restored = RaceTargetMapper.toDomain(stored)

        XCTAssertNil(restored.division)
        XCTAssertEqual(restored.eventName, "HYROX Seoul")
    }

    // MARK: - RaceTarget D-day

    private func calendar(secondsFromGMT: Int) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: secondsFromGMT) ?? result.timeZone
        return result
    }

    private func makeRaceTarget(at date: Date) -> RaceTarget {
        RaceTarget(eventName: "HYROX Seoul", date: date, createdAt: t0, updatedAt: t0)
    }

    func testDaysRemainingCountsWholeDays() {
        let utc = calendar(secondsFromGMT: 0)
        let target = makeRaceTarget(at: t0.addingTimeInterval(3 * 86_400))

        XCTAssertEqual(target.daysRemaining(asOf: t0, calendar: utc), 3)
        XCTAssertTrue(target.isUpcoming(asOf: t0, calendar: utc))
    }

    /// 시각이 아니라 날짜로 세기 때문에, 대회 당일은 아침이든 밤이든 D-0 이다.
    func testDaysRemainingIsZeroOnRaceDay() {
        let utc = calendar(secondsFromGMT: 0)
        let target = makeRaceTarget(at: t0.addingTimeInterval(9 * 3_600))

        XCTAssertEqual(target.daysRemaining(asOf: t0, calendar: utc), 0)
        XCTAssertEqual(target.daysRemaining(asOf: t0.addingTimeInterval(23 * 3_600), calendar: utc), 0)
        XCTAssertTrue(target.isUpcoming(asOf: t0.addingTimeInterval(23 * 3_600), calendar: utc))
    }

    func testDaysRemainingIsNegativeForPastRace() {
        let utc = calendar(secondsFromGMT: 0)
        let target = makeRaceTarget(at: t0.addingTimeInterval(-2 * 86_400))

        XCTAssertEqual(target.daysRemaining(asOf: t0, calendar: utc), -2)
        XCTAssertFalse(target.isUpcoming(asOf: t0, calendar: utc))
    }

    /// 날짜 경계는 주입한 달력의 시간대를 따른다. 같은 순간이라도 UTC 에서는 오늘,
    /// 한국 시간에서는 내일 열리는 대회가 될 수 있다.
    func testDaysRemainingUsesInjectedCalendarTimeZone() {
        let raceInstant = t0.addingTimeInterval(20 * 3_600) // 2001-01-01 20:00 UTC
        let target = makeRaceTarget(at: raceInstant)

        XCTAssertEqual(target.daysRemaining(asOf: t0, calendar: calendar(secondsFromGMT: 0)), 0)
        XCTAssertEqual(target.daysRemaining(asOf: t0, calendar: calendar(secondsFromGMT: 9 * 3_600)), 1)
    }
}
