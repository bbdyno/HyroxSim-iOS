//
//  PersistenceControllerTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
import SwiftData
@testable import HyroxCore
import HyroxPersistenceApple

@MainActor
final class PersistenceControllerTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    /// 기기 시간대와 무관하게 같은 결과가 나오도록 고정한 달력.
    private var utcCalendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0) ?? result.timeZone
        return result
    }

    private static let day: TimeInterval = 86_400

    private func makeController() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }

    private func makeSampleWorkout(
        finishedAtOffset: TimeInterval = 600,
        division: HyroxDivision? = .menOpenSingle
    ) -> CompletedWorkout {
        let start = t0
        let finish = t0.addingTimeInterval(finishedAtOffset)
        let segments = [
            SegmentRecord(
                segmentId: UUID(),
                index: 0,
                type: .run,
                startedAt: start,
                endedAt: start.addingTimeInterval(300),
                measurements: SegmentMeasurements(
                    locationSamples: [
                        LocationSample(timestamp: start, latitude: 37.5665, longitude: 126.978, horizontalAccuracy: 5)
                    ],
                    heartRateSamples: [
                        HeartRateSample(timestamp: start.addingTimeInterval(10), bpm: 150)
                    ]
                ),
                plannedDistanceMeters: 1000
            ),
            SegmentRecord(
                segmentId: UUID(),
                index: 1,
                type: .station,
                startedAt: start.addingTimeInterval(300),
                endedAt: finish,
                stationDisplayName: "SkiErg"
            )
        ]
        return CompletedWorkout(
            templateName: "Test Workout",
            division: division,
            startedAt: start,
            finishedAt: finish,
            segments: segments
        )
    }

    // MARK: - Save & Fetch

    func testSaveAndFetchCompletedWorkout() throws {
        let ctrl = try makeController()
        let workout = makeSampleWorkout()

        try ctrl.saveCompletedWorkout(workout)
        let fetched = try ctrl.fetchAllCompletedWorkouts()

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, workout.id)
        XCTAssertEqual(fetched[0].templateName, "Test Workout")
    }

    // MARK: - Segments Cascade

    func testSegmentsPreservedOnFetch() throws {
        let ctrl = try makeController()
        let workout = makeSampleWorkout()

        try ctrl.saveCompletedWorkout(workout)
        let fetched = try ctrl.fetchCompletedWorkout(id: workout.id)

        XCTAssertEqual(fetched.segments.count, 2)
        XCTAssertEqual(fetched.segments[0].type, .run)
        XCTAssertEqual(fetched.segments[1].type, .station)
        XCTAssertEqual(fetched.segments[0].duration, 300, accuracy: 0.001)
        XCTAssertEqual(fetched.segments[0].plannedDistanceMeters, 1000)
        XCTAssertEqual(fetched.segments[1].stationDisplayName, "SkiErg")
    }

    // MARK: - Measurements Round-trip

    func testMeasurementsRoundTrip() throws {
        let ctrl = try makeController()
        let workout = makeSampleWorkout()

        try ctrl.saveCompletedWorkout(workout)
        let fetched = try ctrl.fetchCompletedWorkout(id: workout.id)

        let runSegment = fetched.segments[0]
        XCTAssertEqual(runSegment.measurements.locationSamples.count, 1)
        XCTAssertEqual(runSegment.measurements.heartRateSamples.count, 1)
        XCTAssertEqual(runSegment.measurements.heartRateSamples[0].bpm, 150)
    }

    // MARK: - Delete

    func testDeleteCompletedWorkout() throws {
        let ctrl = try makeController()
        let workout = makeSampleWorkout()

        try ctrl.saveCompletedWorkout(workout)
        try ctrl.deleteCompletedWorkout(id: workout.id)

        let fetched = try ctrl.fetchAllCompletedWorkouts()
        XCTAssertEqual(fetched.count, 0)
    }

    // MARK: - Not Found

    func testFetchNotFoundThrows() throws {
        let ctrl = try makeController()
        let randomId = UUID()

        XCTAssertThrowsError(try ctrl.fetchCompletedWorkout(id: randomId)) { error in
            XCTAssertEqual(error as? PersistenceError, .notFound(id: randomId))
        }
    }

    // MARK: - Sort Order

    func testFetchAllSortedByMostRecent() throws {
        let ctrl = try makeController()

        let w1 = makeSampleWorkout(finishedAtOffset: 100)
        let w2 = makeSampleWorkout(finishedAtOffset: 300)
        let w3 = makeSampleWorkout(finishedAtOffset: 200)

        try ctrl.saveCompletedWorkout(w1)
        try ctrl.saveCompletedWorkout(w2)
        try ctrl.saveCompletedWorkout(w3)

        let fetched = try ctrl.fetchAllCompletedWorkouts()
        XCTAssertEqual(fetched.count, 3)
        // Most recent first
        XCTAssertEqual(fetched[0].id, w2.id)
        XCTAssertEqual(fetched[1].id, w3.id)
        XCTAssertEqual(fetched[2].id, w1.id)
    }

    // MARK: - Race Targets

    private func makeRaceTarget(
        id: UUID = UUID(),
        eventName: String = "HYROX Seoul",
        dayOffset: TimeInterval,
        goalDurationSeconds: TimeInterval? = 5_400
    ) -> RaceTarget {
        RaceTarget(
            id: id,
            eventName: eventName,
            city: "Seoul",
            date: t0.addingTimeInterval(dayOffset * Self.day),
            division: .menOpenSingle,
            goalDurationSeconds: goalDurationSeconds,
            note: "숙소 예약 완료",
            createdAt: t0,
            updatedAt: t0
        )
    }

    func testSaveAndFetchRaceTarget() throws {
        let ctrl = try makeController()
        let target = makeRaceTarget(dayOffset: 30)

        try ctrl.upsertRaceTarget(target)
        let fetched = try ctrl.fetchRaceTargets()

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, target.id)
        XCTAssertEqual(fetched[0].eventName, "HYROX Seoul")
        XCTAssertEqual(fetched[0].city, "Seoul")
        XCTAssertEqual(fetched[0].division, .menOpenSingle)
        XCTAssertEqual(fetched[0].goalDurationSeconds, 5_400)
        XCTAssertEqual(fetched[0].note, "숙소 예약 완료")
    }

    func testFetchRaceTargetsSortedByDateAscending() throws {
        let ctrl = try makeController()
        let later = makeRaceTarget(eventName: "HYROX Tokyo", dayOffset: 90)
        let soon = makeRaceTarget(eventName: "HYROX Seoul", dayOffset: 10)
        let past = makeRaceTarget(eventName: "HYROX Busan", dayOffset: -20)

        try ctrl.upsertRaceTarget(later)
        try ctrl.upsertRaceTarget(soon)
        try ctrl.upsertRaceTarget(past)

        let names = try ctrl.fetchRaceTargets().map(\.eventName)
        XCTAssertEqual(names, ["HYROX Busan", "HYROX Seoul", "HYROX Tokyo"])
    }

    func testDeleteRaceTarget() throws {
        let ctrl = try makeController()
        let target = makeRaceTarget(dayOffset: 30)

        try ctrl.upsertRaceTarget(target)
        try ctrl.deleteRaceTarget(id: target.id)

        XCTAssertEqual(try ctrl.fetchRaceTargets().count, 0)
    }

    func testDeleteMissingRaceTargetThrows() throws {
        let ctrl = try makeController()
        let randomId = UUID()

        XCTAssertThrowsError(try ctrl.deleteRaceTarget(id: randomId)) { error in
            XCTAssertEqual(error as? PersistenceError, .notFound(id: randomId))
        }
    }

    // MARK: - Upcoming Race Target

    func testFetchUpcomingRaceTargetPicksNearestFutureRace() throws {
        let ctrl = try makeController()
        try ctrl.upsertRaceTarget(makeRaceTarget(eventName: "HYROX Busan", dayOffset: -20))
        try ctrl.upsertRaceTarget(makeRaceTarget(eventName: "HYROX Tokyo", dayOffset: 90))
        try ctrl.upsertRaceTarget(makeRaceTarget(eventName: "HYROX Seoul", dayOffset: 10))

        let upcoming = try ctrl.fetchUpcomingRaceTarget(now: t0, calendar: utcCalendar)
        XCTAssertEqual(upcoming?.eventName, "HYROX Seoul")
    }

    /// 대회 당일은 아직 "다가오는 대회"다 — 아침에 시작한 대회를 오후에 열어도
    /// 허브가 다음 대회로 건너뛰면 안 된다.
    func testFetchUpcomingRaceTargetIncludesRaceDay() throws {
        let ctrl = try makeController()
        let today = RaceTarget(
            eventName: "HYROX Seoul",
            date: t0.addingTimeInterval(6 * 3_600),
            createdAt: t0,
            updatedAt: t0
        )
        try ctrl.upsertRaceTarget(today)

        let upcoming = try ctrl.fetchUpcomingRaceTarget(
            now: t0.addingTimeInterval(20 * 3_600),
            calendar: utcCalendar
        )
        XCTAssertEqual(upcoming?.id, today.id)
    }

    func testFetchUpcomingRaceTargetReturnsNilWhenAllRacesArePast() throws {
        let ctrl = try makeController()
        try ctrl.upsertRaceTarget(makeRaceTarget(eventName: "HYROX Busan", dayOffset: -20))
        try ctrl.upsertRaceTarget(makeRaceTarget(eventName: "HYROX Seoul", dayOffset: -1))

        XCTAssertNil(try ctrl.fetchUpcomingRaceTarget(now: t0, calendar: utcCalendar))
    }

    func testFetchUpcomingRaceTargetReturnsNilWhenEmpty() throws {
        let ctrl = try makeController()
        XCTAssertNil(try ctrl.fetchUpcomingRaceTarget(now: t0, calendar: utcCalendar))
    }

    // MARK: - Schema Migration

    /// 스키마가 버전별로 나열되고, 버전 사이마다 마이그레이션 단계가 하나씩 있어야 한다.
    /// 새 버전을 추가하면서 단계를 빠뜨리면 기존 사용자 앱이 컨테이너 생성부터 실패한다.
    func testMigrationPlanCoversEverySchemaVersion() {
        let versions = HyroxMigrationPlan.schemas.map { $0.versionIdentifier }
        XCTAssertEqual(versions, versions.sorted(), "스키마는 오래된 순서로 나열되어야 한다")
        XCTAssertEqual(
            HyroxMigrationPlan.stages.count,
            max(HyroxMigrationPlan.schemas.count - 1, 0),
            "버전 사이마다 마이그레이션 단계가 하나씩 있어야 한다"
        )
        XCTAssertEqual(
            HyroxMigrationPlan.schemas.last.map { $0.versionIdentifier },
            HyroxModelContainerFactory.currentVersionedSchema.versionIdentifier,
            "팩토리가 여는 스키마는 계획의 마지막 버전이어야 한다"
        )
    }

    /// 출시된 스키마(v1)로 만든 스토어가 현재 스키마에서 그대로 열려야 한다.
    /// 기록·템플릿·툼스톤이 살아 있고, v2 에서 추가된 대회 목표도 바로 쓸 수 있어야 한다.
    func testStoreWrittenWithSchemaV1OpensUnderCurrentSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyroxSchemaMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("hyrox.store")

        let workout = makeSampleWorkout()
        let template = WorkoutTemplate(name: "Legacy Custom", segments: [.run(distanceMeters: 1000)])
        let deletedWorkoutId = UUID()
        try seedSchemaV1Store(
            at: storeURL,
            workout: workout,
            template: template,
            deletedWorkoutId: deletedWorkoutId
        )

        let ctrl = try PersistenceController(storeURL: storeURL)

        let workouts = try ctrl.fetchAllCompletedWorkouts()
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts[0].id, workout.id)
        XCTAssertEqual(workouts[0].segments.count, 2)

        let templates = try ctrl.fetchAllTemplates()
        XCTAssertEqual(templates.map(\.name), ["Legacy Custom"])

        XCTAssertTrue(ctrl.isCompletedWorkoutDeleted(id: deletedWorkoutId))

        // v2 에서 추가된 엔티티가 마이그레이션 후 실제로 쓰이는지
        let target = makeRaceTarget(dayOffset: 30)
        try ctrl.upsertRaceTarget(target)
        XCTAssertEqual(try ctrl.fetchRaceTargets().map(\.id), [target.id])
    }

    /// 두 번째 실행: 이미 현재 버전인 스토어를 다시 열어도 데이터가 그대로여야 한다.
    func testCurrentSchemaStoreReopensWithoutLoss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyroxSchemaReopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("hyrox.store")

        let workout = makeSampleWorkout()
        let target = makeRaceTarget(dayOffset: 45)
        try seedCurrentSchemaStore(at: storeURL, workout: workout, target: target)

        let second = try PersistenceController(storeURL: storeURL)
        XCTAssertEqual(try second.fetchAllCompletedWorkouts().map(\.id), [workout.id])
        XCTAssertEqual(try second.fetchRaceTargets().map(\.id), [target.id])
    }

    /// 첫 실행을 흉내 낸다. 컨트롤러가 이 함수 밖으로 새어 나가지 않아야
    /// 두 번째 열기가 "앱을 껐다 켠" 상황이 된다.
    private func seedCurrentSchemaStore(
        at storeURL: URL,
        workout: CompletedWorkout,
        target: RaceTarget
    ) throws {
        let controller = try PersistenceController(storeURL: storeURL)
        try controller.saveCompletedWorkout(workout)
        try controller.upsertRaceTarget(target)
    }

    /// v1 컨테이너를 이 함수 안에서만 살려 둔다 — 같은 파일을 두 컨테이너가 동시에
    /// 잡고 있으면 마이그레이션 경로를 검증할 수 없다.
    private func seedSchemaV1Store(
        at storeURL: URL,
        workout: CompletedWorkout,
        template: WorkoutTemplate,
        deletedWorkoutId: UUID
    ) throws {
        let container = try HyroxModelContainerFactory.makeContainer(
            versionedSchema: HyroxSchemaV1.self,
            storeURL: storeURL
        )
        let context = container.mainContext
        context.insert(try CompletedWorkoutMapper.toStored(workout))
        context.insert(try WorkoutTemplateMapper.toStored(template))
        context.insert(StoredWorkoutTombstone(workoutId: deletedWorkoutId, deletedAt: t0))
        try context.save()
    }
}
