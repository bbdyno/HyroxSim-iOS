//
//  BackupArchive.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import Foundation
import HyroxCore
import HyroxPersistenceApple

/// 사용자의 기록을 파일 하나로 내보내고 다시 들여오는 묶음.
///
/// 파일은 사용자가 고른 곳(iCloud Drive, 파일 앱 등)에 저장된다. 앱이 직접 서버나 iCloud 에
/// 올리지 않는다.
struct BackupArchive: Codable, Equatable {

    static let currentFormat = 1
    static let fileExtension = "hyroxsimbackup"

    var format: Int = BackupArchive.currentFormat
    var exportedAt: Date
    var appVersion: String
    var workouts: [CompletedWorkout]
    var templates: [WorkoutTemplate]
    var raceTargets: [RaceTarget]
    var raceResults: [RaceResult]

    struct Counts: Equatable {
        var workouts = 0
        var templates = 0
        var raceTargets = 0
        var raceResults = 0
        var total: Int { workouts + templates + raceTargets + raceResults }
    }

    enum BackupError: Error, Equatable {
        /// 이 앱보다 새 버전에서 만든 파일.
        case newerFormat(Int)
        case unreadable
    }

    var counts: Counts {
        Counts(workouts: workouts.count, templates: templates.count,
               raceTargets: raceTargets.count, raceResults: raceResults.count)
    }

    // MARK: - 만들기

    @MainActor
    static func make(
        persistence: PersistenceController,
        raceResults: RaceResultStore,
        appVersion: String,
        now: Date = Date()
    ) throws -> BackupArchive {
        BackupArchive(
            exportedAt: now,
            appVersion: appVersion,
            workouts: try persistence.fetchAllCompletedWorkouts(),
            templates: try persistence.fetchAllTemplates(),
            raceTargets: try persistence.fetchRaceTargets(),
            raceResults: raceResults.all()
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> BackupArchive {
        struct Header: Decodable { let format: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw BackupError.unreadable }
        guard header.format <= currentFormat else { throw BackupError.newerFormat(header.format) }
        do {
            return try JSONDecoder().decode(BackupArchive.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
    }

    static func fileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "HyroxSim-\(formatter.string(from: now)).\(fileExtension)"
    }

    // MARK: - 들여오기

    /// 기존 기록에 **합친다**. 같은 id 는 덮어쓰고, 지금 기기에만 있는 기록은 건드리지 않는다.
    /// 사용자가 지운 운동 기록은 되살리지 않는다.
    /// - Returns: 실제로 들어간 수.
    @MainActor
    func restore(into persistence: PersistenceController, raceResults store: RaceResultStore) throws -> Counts {
        var counts = Counts()
        for workout in workouts where try persistence.upsertCompletedWorkout(workout) {
            counts.workouts += 1
        }
        for template in templates {
            try persistence.upsertTemplate(template)
            counts.templates += 1
        }
        for target in raceTargets {
            try persistence.upsertRaceTarget(target)
            counts.raceTargets += 1
        }
        for result in raceResults {
            try store.save(result)
            counts.raceResults += 1
        }
        return counts
    }
}
