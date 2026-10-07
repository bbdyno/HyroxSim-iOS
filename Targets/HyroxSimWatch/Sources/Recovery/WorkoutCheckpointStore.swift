//
//  WorkoutCheckpointStore.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore

/// 진행 중이거나 저장에 실패한 운동의 스냅샷.
/// 크래시·강제 종료로 앱이 죽어도 다음 실행에서 완료 기록으로 복구하기 위한 최소 정보만 담는다.
struct WorkoutCheckpoint: Codable, Sendable {
    let id: UUID
    let templateName: String
    let division: HyroxDivision?
    let startedAt: Date
    var updatedAt: Date
    /// 엔진이 완료 처리한 세그먼트 기록. 진행 중인 세그먼트는 포함되지 않는다.
    var segments: [SegmentRecord]
    /// 운동은 정상 종료했지만 로컬 저장에 실패한 경우 true
    var isFinished: Bool
    /// 정상 종료 시각 (`isFinished == true` 일 때만 채워진다)
    var finishedAt: Date?

    /// 복구용 완료 기록. 완료된 세그먼트가 하나도 없으면 복구할 내용도 없으므로 nil.
    func makeCompletedWorkout() -> CompletedWorkout? {
        guard !segments.isEmpty else { return nil }
        let endedAt = finishedAt ?? segments.map(\.endedAt).max() ?? updatedAt
        return CompletedWorkout(
            id: id,
            templateName: templateName,
            division: division,
            startedAt: startedAt,
            finishedAt: endedAt,
            segments: segments
        )
    }
}

/// 체크포인트 파일 입출력. Application Support 아래에 JSON 으로 원자적 저장한다.
/// 구간 전환·일시정지·종료마다 갱신되고, 저장에 성공하면 삭제된다.
@MainActor
final class WorkoutCheckpointStore {
    static let shared = WorkoutCheckpointStore()

    private let directoryName = "HyroxSim"
    private let fileName = "active-workout-checkpoint.json"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var fileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(fileName)
    }

    func save(_ checkpoint: WorkoutCheckpoint) {
        guard let fileURL else { return }
        do {
            let data = try encoder.encode(checkpoint)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[WatchCheckpoint] Failed to write checkpoint: \(error)")
        }
    }

    func load() -> WorkoutCheckpoint? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try decoder.decode(WorkoutCheckpoint.self, from: data)
        } catch {
            // 손상된 파일은 제거해 다음 실행을 계속 막지 않도록 한다.
            print("[WatchCheckpoint] Failed to decode checkpoint: \(error)")
            clear()
            return nil
        }
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
