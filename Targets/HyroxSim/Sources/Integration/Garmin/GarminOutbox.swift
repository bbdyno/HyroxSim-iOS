//
//  GarminOutbox.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import os

/// 가민으로 보낼 메시지를 담아 두는 영속 큐.
///
/// ConnectIQ 의 폰→워치 채널은 워치 앱이 닫혀 있으면 메시지를 버린다.
/// 그래서 `template.delete` 처럼 "한 번 못 보내면 영영 못 보내는" 메시지는
/// 디스크에 남겨 두고, 다시 연결됐을 때 순서대로 재전송해야 한다.
///
/// 규칙:
///  - **FIFO** — 넣은 순서대로 보낸다. 같은 템플릿의 upsert 뒤 delete 가
///    뒤집히면 지운 템플릿이 되살아나므로 순서는 타협 대상이 아니다.
///  - **dedupe** — 같은 대상(`dedupeKey`)을 가리키는 옛 항목은 새 항목이
///    들어올 때 버린다. 같은 템플릿을 열 번 고쳐도 마지막 상태 하나만 나간다.
///    이때 새 항목은 **큐의 맨 뒤**에 붙으므로, 다른 대상과의 상대 순서는
///    "가장 최근에 바뀐 것이 가장 나중" 이라는 일관된 규칙을 따른다.
///  - **영속** — 변경할 때마다 JSON 파일로 원자적 저장. 앱이 죽어도 남는다.
///
/// 파일이 깨져 있으면 빈 큐로 시작한다(로그만 남김). 큐를 못 읽는다고
/// 앱이 못 뜨는 쪽이 훨씬 나쁘다.
@MainActor
public final class GarminOutbox {

    // MARK: - Entry

    public struct Entry: Codable, Equatable {
        /// 봉투의 `id`. 워치가 보내는 `ack` 의 `id` 와 대조해 큐에서 지운다.
        public let messageId: String
        /// 봉투의 `t`. 로그와 테스트 가독성용.
        public let type: String
        /// 같은 대상을 가리키는 메시지를 합치기 위한 키.
        /// 예) `template:<uuid>` — 같은 템플릿의 upsert 와 delete 가 서로를 대체한다.
        public let dedupeKey: String
        public let createdAt: Date
        /// 직렬화된 봉투. `[String: Any]` 는 `Codable` 이 아니라 JSON 으로 보관한다.
        public let envelopeData: Data
        public private(set) var attemptCount: Int
        public private(set) var lastAttemptAt: Date?

        init(
            messageId: String,
            type: String,
            dedupeKey: String,
            createdAt: Date,
            envelopeData: Data,
            attemptCount: Int = 0,
            lastAttemptAt: Date? = nil
        ) {
            self.messageId = messageId
            self.type = type
            self.dedupeKey = dedupeKey
            self.createdAt = createdAt
            self.envelopeData = envelopeData
            self.attemptCount = attemptCount
            self.lastAttemptAt = lastAttemptAt
        }

        /// 저장된 봉투를 다시 딕셔너리로. 깨졌으면 nil — 호출자가 항목을 버린다.
        public var envelope: [String: Any]? {
            (try? JSONSerialization.jsonObject(with: envelopeData)) as? [String: Any]
        }

        fileprivate mutating func recordAttempt(at date: Date) {
            attemptCount += 1
            lastAttemptAt = date
        }
    }

    // MARK: - Config

    /// 큐 상한. 넘으면 오래된 것부터 버린다. 워치를 몇 달 안 켜도 디스크가 새지 않게.
    public static let maxEntries = 200

    // MARK: - State

    private let logger = Logger(subsystem: "com.bbdyno.app.HyroxSim", category: "GarminOutbox")
    private let fileURL: URL?
    private var entries: [Entry] = []

    private init(storeURL: URL?) {
        self.fileURL = storeURL
        load()
    }

    /// Application Support 아래 `Garmin/GarminOutbox.json` 을 쓰는 기본 큐.
    public convenience init() {
        self.init(storeURL: Self.defaultFileURL())
    }

    /// 지정한 파일을 쓰는 큐. 테스트는 임시 경로를 준다.
    public convenience init(fileURL: URL) {
        self.init(storeURL: fileURL)
    }

    /// 메모리 전용 큐(영속화 없음). 테스트 전용.
    public static func inMemory() -> GarminOutbox {
        GarminOutbox(storeURL: nil)
    }

    // MARK: - Reading

    /// 보내야 할 항목을 넣은 순서대로.
    public var pending: [Entry] { entries }
    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    public func entry(messageId: String) -> Entry? {
        entries.first { $0.messageId == messageId }
    }

    // MARK: - Mutating

    /// 봉투를 큐에 넣는다. 같은 `dedupeKey` 의 기존 항목은 사라진다.
    /// - Returns: 저장된 항목. 봉투를 JSON 으로 만들 수 없으면 nil.
    @discardableResult
    public func enqueue(
        _ envelope: [String: Any],
        dedupeKey: String,
        now: Date = Date()
    ) -> Entry? {
        let safe = GarminMessageCodec.sanitizedForTransport(envelope)
        guard
            let messageId = safe[GarminMessageCodec.Key.id] as? String,
            let type = safe[GarminMessageCodec.Key.type] as? String,
            JSONSerialization.isValidJSONObject(safe),
            let data = try? JSONSerialization.data(withJSONObject: safe)
        else {
            logger.error("enqueue dropped — envelope is not serialisable key=\(dedupeKey, privacy: .public)")
            return nil
        }

        let superseded = entries.filter { $0.dedupeKey == dedupeKey }
        if !superseded.isEmpty {
            entries.removeAll { $0.dedupeKey == dedupeKey }
            logger.info(
                "enqueue superseded n=\(superseded.count) key=\(dedupeKey, privacy: .public) t=\(type, privacy: .public)"
            )
        }

        let entry = Entry(
            messageId: messageId,
            type: type,
            dedupeKey: dedupeKey,
            createdAt: now,
            envelopeData: data
        )
        entries.append(entry)

        if entries.count > Self.maxEntries {
            let overflow = entries.count - Self.maxEntries
            entries.removeFirst(overflow)
            logger.error("outbox overflow — dropped \(overflow) oldest entries")
        }

        persist()
        logger.info("enqueued t=\(type, privacy: .public) key=\(dedupeKey, privacy: .public) depth=\(self.entries.count)")
        return entry
    }

    /// 워치의 `ack` 로 항목을 제거한다.
    /// - Returns: 실제로 지운 항목이 있으면 true.
    @discardableResult
    public func acknowledge(messageId: String) -> Bool {
        remove(messageId: messageId, reason: "ack")
    }

    @discardableResult
    public func remove(messageId: String, reason: String) -> Bool {
        guard let index = entries.firstIndex(where: { $0.messageId == messageId }) else { return false }
        let entry = entries.remove(at: index)
        persist()
        logger.info(
            "removed t=\(entry.type, privacy: .public) reason=\(reason, privacy: .public) depth=\(self.entries.count)"
        )
        return true
    }

    /// 전송 시도 횟수를 올린다. 재시도 상한 판정에 쓴다.
    @discardableResult
    public func recordAttempt(messageId: String, at date: Date = Date()) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.messageId == messageId }) else { return nil }
        entries[index].recordAttempt(at: date)
        persist()
        return entries[index]
    }

    public func removeAll(reason: String) {
        guard !entries.isEmpty else { return }
        logger.info("cleared n=\(self.entries.count) reason=\(reason, privacy: .public)")
        entries.removeAll()
        persist()
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("Garmin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("GarminOutbox.json")
    }

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([Entry].self, from: data)
            if !entries.isEmpty {
                logger.info("restored \(self.entries.count) pending entries")
            }
        } catch {
            // 깨진 큐 때문에 앱이 못 뜨면 안 된다. 비우고 계속 간다.
            entries = []
            logger.error("outbox load failed — starting empty: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("outbox persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
