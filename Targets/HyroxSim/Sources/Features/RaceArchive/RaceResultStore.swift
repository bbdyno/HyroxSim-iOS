//
//  RaceResultStore.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import Foundation
import HyroxCore
import os

/// 대회 기록 보관함의 저장소. 기록 수가 많지 않아(한 해 몇 건) JSON 파일 하나로 둔다.
///
/// SwiftData 스키마에 넣지 않은 이유: 스키마를 바꾸면 기존 사용자의 저장소 마이그레이션이
/// 따라오는데, 운동 기록과 관계가 없는 독립된 목록에 그 위험을 질 이유가 없다.
@MainActor
final class RaceResultStore {

    static let didChangeNotification = Notification.Name("RaceResultStore.didChange")

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.bbdyno.app.HyroxSim", category: "RaceArchive")
    private var cache: [RaceResult]?

    /// - Parameter directory: 생략하면 Application Support.
    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent("race-results.json")
    }

    /// 최신 대회가 앞.
    func all() -> [RaceResult] {
        if let cache { return cache }
        var loaded: [RaceResult] = []
        if let data = try? Data(contentsOf: fileURL) {
            do {
                loaded = try Self.decoder.decode([RaceResult].self, from: data)
            } catch {
                // 읽지 못한 파일을 빈 목록으로 덮어쓰면 기록이 사라진다. 옆에 남겨 둔다.
                logger.error("대회 기록 읽기 실패: \(error.localizedDescription, privacy: .public)")
                let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
        }
        let sorted = loaded.sorted { $0.date > $1.date }
        cache = sorted
        return sorted
    }

    /// 같은 id 가 있으면 바꾸고, 없으면 더한다.
    func save(_ result: RaceResult) throws {
        var items = all().filter { $0.id != result.id }
        items.append(result)
        try write(items)
    }

    func delete(id: UUID) throws {
        try write(all().filter { $0.id != id })
    }

    private func write(_ items: [RaceResult]) throws {
        let sorted = items.sorted { $0.date > $1.date }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.encoder.encode(sorted).write(to: fileURL, options: .atomic)
        cache = sorted
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // 날짜는 `Date` 가 안에 들고 있는 값 그대로 쓴다. ISO 8601 은 소수 초를 버리고,
        // 1970 기준 초로 바꾸면 끝자리가 달라져 저장 전후 값이 어긋난다.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }()
}
