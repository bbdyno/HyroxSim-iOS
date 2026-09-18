//
//  WorkoutCheckpointStore.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore

/// 진행 중이던 폰 운동의 스냅샷.
/// `workout` 은 "지금 끝났다고 가정한" 잠정 결과라서, 복구 시 그대로 저장하면 된다.
public struct WorkoutCheckpoint: Codable, Sendable {
    public let workout: CompletedWorkout
    public let updatedAt: Date
}

/// 운동 진행 상태를 파일로 체크포인트한다.
///
/// 앱이 크래시/강제 종료되어도 마지막 체크포인트까지의 기록이 남고,
/// 다음 실행에서 `AppCoordinator` 가 이를 완료 기록으로 저장한다.
/// 쓰기는 항상 원자적(`Data.WritingOptions.atomic`)이라 중간에 죽어도 파일이 깨지지 않는다.
public final class WorkoutCheckpointStore: @unchecked Sendable {

    public static let shared = WorkoutCheckpointStore()

    private let fileURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.bbdyno.app.HyroxSim.workout-checkpoint")

    /// - Parameter directory: 체크포인트 파일이 놓일 디렉터리. 기본값은 Application Support.
    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.fileURL = base.appendingPathComponent("ActiveWorkoutCheckpoint.json")
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return support
    }

    // MARK: - API

    /// 잠정 결과를 저장한다. 실패해도 운동 진행을 막지 않는다(조용히 무시).
    ///
    /// GPS/HR 샘플까지 들어가면 수백 KB 가 될 수 있어 인코딩·쓰기는 전용 직렬 큐에서 한다.
    /// 큐가 직렬이므로 `load()` / `clear()` 와의 순서는 그대로 보장된다.
    public func save(workout: CompletedWorkout, at date: Date = Date()) {
        let checkpoint = WorkoutCheckpoint(workout: workout, updatedAt: date)
        queue.async { [self] in
            do {
                try ensureDirectoryExists()
                let data = try Self.makeEncoder().encode(checkpoint)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                print("[Checkpoint] Failed to write checkpoint: \(error)")
            }
        }
    }

    /// 남아 있는 체크포인트를 읽는다. 없거나 깨졌으면 nil.
    public func load() -> WorkoutCheckpoint? {
        queue.sync { () -> WorkoutCheckpoint? in
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            do {
                return try Self.makeDecoder().decode(WorkoutCheckpoint.self, from: data)
            } catch {
                print("[Checkpoint] Failed to decode checkpoint, discarding: \(error)")
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
        }
    }

    /// 체크포인트를 제거한다(정상 저장 완료 / 복구 완료 후).
    public func clear() {
        queue.sync {
            guard fileManager.fileExists(atPath: fileURL.path) else { return }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Private

    private func ensureDirectoryExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
