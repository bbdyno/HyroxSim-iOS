//
//  BackupArchiveTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
import HyroxCore
import HyroxPersistenceApple
@testable import HyroxSim

@MainActor
final class BackupArchiveTests: XCTestCase {

    private var directories: [URL] = []

    override func tearDown() async throws {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func makeStore() -> RaceResultStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)")
        directories.append(directory)
        return RaceResultStore(directory: directory)
    }

    private func seededSource() throws -> (PersistenceController, RaceResultStore) {
        let persistence = try PersistenceController(inMemory: true)
        let store = makeStore()
        for workout in ScreenshotFixtures.fullRaceHistory(endingAt: Date(timeIntervalSince1970: 1_800_000_000)) {
            try persistence.saveCompletedWorkout(workout)
        }
        try persistence.saveTemplate(ScreenshotFixtures.customTemplate)
        try persistence.upsertRaceTarget(RaceTarget(
            eventName: "HYROX Seoul", date: Date(timeIntervalSince1970: 1_810_000_000),
            division: .menOpenSingle, goalDurationSeconds: 5100
        ))
        try store.save(RaceResult(
            eventName: "HYROX Incheon", date: Date(timeIntervalSince1970: 1_790_000_000),
            division: .menOpenSingle, totalSeconds: 5300, stationSeconds: ["skiErg": 250]
        ))
        return (persistence, store)
    }

    func testArchiveContainsEverything() throws {
        let (persistence, store) = try seededSource()
        let archive = try BackupArchive.make(persistence: persistence, raceResults: store, appVersion: "2.0.0")
        XCTAssertEqual(archive.counts, .init(workouts: 3, templates: 1, raceTargets: 1, raceResults: 1))
        XCTAssertEqual(archive.format, BackupArchive.currentFormat)
    }

    /// 새 기기: 파일에서 전부 되살아난다.
    func testRoundTripIntoAnEmptyDevice() throws {
        let (source, sourceStore) = try seededSource()
        let data = try BackupArchive.make(persistence: source, raceResults: sourceStore, appVersion: "2.0.0").encoded()

        let target = try PersistenceController(inMemory: true)
        let targetStore = makeStore()
        let restored = try BackupArchive.decode(data).restore(into: target, raceResults: targetStore)

        XCTAssertEqual(restored, .init(workouts: 3, templates: 1, raceTargets: 1, raceResults: 1))
        XCTAssertEqual(
            Set(try target.fetchAllCompletedWorkouts().map(\.id)), Set(try source.fetchAllCompletedWorkouts().map(\.id))
        )
        XCTAssertEqual(try target.fetchAllCompletedWorkouts().first?.segments.count, 31)
        XCTAssertEqual(try target.fetchAllTemplates().map(\.id), try source.fetchAllTemplates().map(\.id))
        XCTAssertEqual(try target.fetchRaceTargets().first?.goalDurationSeconds, 5100)
        XCTAssertEqual(targetStore.all(), sourceStore.all())
    }

    /// 합치기: 이 기기에만 있는 기록은 남고, 두 번 복원해도 늘지 않는다.
    func testRestoreMergesAndIsIdempotent() throws {
        let (source, sourceStore) = try seededSource()
        let archive = try BackupArchive.make(persistence: source, raceResults: sourceStore, appVersion: "2.0.0")

        let target = try PersistenceController(inMemory: true)
        let targetStore = makeStore()
        try target.saveCompletedWorkout(ScreenshotFixtures.summaryWorkout)

        _ = try archive.restore(into: target, raceResults: targetStore)
        _ = try archive.restore(into: target, raceResults: targetStore)

        XCTAssertEqual(try target.fetchAllCompletedWorkouts().count, 4)
        XCTAssertEqual(try target.fetchAllTemplates().count, 1)
        XCTAssertEqual(try target.fetchRaceTargets().count, 1)
        XCTAssertEqual(targetStore.all().count, 1)
    }

    /// 이 기기에서 지운 운동 기록은 백업으로 되살리지 않는다.
    func testDeletedWorkoutsStayDeleted() throws {
        let (source, sourceStore) = try seededSource()
        let archive = try BackupArchive.make(persistence: source, raceResults: sourceStore, appVersion: "2.0.0")
        let gone = try XCTUnwrap(archive.workouts.first)

        let target = try PersistenceController(inMemory: true)
        try target.saveCompletedWorkout(gone)
        try target.deleteCompletedWorkout(id: gone.id)

        let restored = try archive.restore(into: target, raceResults: makeStore())
        XCTAssertEqual(restored.workouts, 2)
        XCTAssertFalse(try target.fetchAllCompletedWorkouts().contains { $0.id == gone.id })
    }

    func testRejectsNewerFormatAndGarbage() throws {
        XCTAssertThrowsError(try BackupArchive.decode(Data("nope".utf8))) {
            XCTAssertEqual($0 as? BackupArchive.BackupError, .unreadable)
        }
        let newer = Data(#"{"format": 99, "exportedAt": 0}"#.utf8)
        XCTAssertThrowsError(try BackupArchive.decode(newer)) {
            XCTAssertEqual($0 as? BackupArchive.BackupError, .newerFormat(99))
        }
        let truncated = Data(#"{"format": 1}"#.utf8)
        XCTAssertThrowsError(try BackupArchive.decode(truncated)) {
            XCTAssertEqual($0 as? BackupArchive.BackupError, .unreadable)
        }
    }

    func testFileNameIsDatedAndStable() {
        let name = BackupArchive.fileName(now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(name.hasPrefix("HyroxSim-20"))
        XCTAssertTrue(name.hasSuffix(".hyroxsimbackup"))
    }
}
