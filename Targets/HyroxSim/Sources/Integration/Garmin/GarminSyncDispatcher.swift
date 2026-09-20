//
//  GarminSyncDispatcher.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import os

/// 가민으로 나가는 모든 상태 메시지의 단일 창구.
///
/// 예전에는 각 sync 서비스가 `GarminBridge.sendEnvelope` 를 직접 불렀고,
/// 결과는 로그로만 남았다. 워치 앱이 닫혀 있을 때 보낸 `template.delete` 는
/// 그대로 사라져서, 폰에서 지운 템플릿이 워치에는 영원히 남았다.
///
/// 이제 모든 메시지는 `GarminOutbox` 를 거친다:
///  1. `send(_:dedupeKey:)` 가 큐에 넣고, 연결돼 있으면 즉시 flush 를 시도한다.
///  2. 전송이 성공하면(= ConnectIQ 가 워치 앱에 실제로 전달) 큐에서 지운다.
///  3. 워치가 `ack` 를 보내오면 그때도 지운다(먼저 오는 쪽이 이긴다).
///  4. 실패하면 남겨 두고, 다음 연결 이벤트에서 **큐 순서대로** 다시 보낸다.
@MainActor
public final class GarminSyncDispatcher {

    public static let shared = GarminSyncDispatcher(transport: GarminBridge.shared)

    /// 같은 대상을 가리키는 메시지를 합치기 위한 키 규칙.
    public enum DedupeKey {
        /// 템플릿 upsert 와 delete 는 **같은 키**를 쓴다.
        /// 저장 직후 삭제하면 delete 만 남고, 삭제 후 다시 만들면 upsert 만 남는다.
        public static func template(_ id: UUID) -> String { "template:\(id.uuidString)" }
        /// 목표는 디비전 단위로 최신 것만 의미가 있다.
        public static func goal(division: String) -> String { "goal:\(division)" }
    }

    /// 이 횟수만큼 실패하면 항목을 버린다. 영원히 실패하는 메시지가
    /// 뒤의 정상 메시지를 막는 것을 방지한다.
    public static let maxAttempts = 12
    /// 한 번의 flush 에서 처리할 최대 개수. 동기 transport(테스트)에서
    /// 재귀가 깊어지지 않게 하는 안전장치.
    public static let maxBatch = 100

    private let logger = Logger(subsystem: "com.bbdyno.app.HyroxSim", category: "GarminSync")
    private let transport: GarminEnvelopeTransport
    private let outbox: GarminOutbox

    private var isFlushing = false
    private var flushAgainRequested = false

    /// 재시도 상한을 넘겨 **버려진** 항목의 `dedupeKey`.
    /// 변경 추적(`GarminSyncStateStore`)을 되돌려, 다음 재동기화에서 그 대상이
    /// 다시 "바뀐 것" 으로 잡히게 한다. 버려진 뒤에도 "보냈음" 으로 남으면
    /// 그 템플릿은 영영 워치에 도달하지 못한다.
    public var onEntryDropped: ((String) -> Void)?

    public init(transport: GarminEnvelopeTransport, outbox: GarminOutbox? = nil) {
        // 기본 인자 자리에서 만들면 nonisolated 컨텍스트라 @MainActor 초기화가 막힌다.
        self.transport = transport
        self.outbox = outbox ?? GarminOutbox()
    }

    // MARK: - Queue state (진단 / 테스트)

    public var pendingCount: Int { outbox.count }
    public var pendingTypes: [String] { outbox.pending.map(\.type) }
    public var pendingDedupeKeys: [String] { outbox.pending.map(\.dedupeKey) }
    public var pendingMessageIds: [String] { outbox.pending.map(\.messageId) }
    public var isConnected: Bool { transport.garminConnectionState.isConnected }

    /// 기기를 해제했을 때. 다음 기기가 남의 큐를 물려받으면 안 된다.
    public func reset(reason: String) {
        outbox.removeAll(reason: reason)
    }

    // MARK: - Sending

    /// 봉투를 큐에 넣고, 연결돼 있으면 바로 보낸다.
    /// - Returns: 큐에 들어갔으면 true. 직렬화가 불가능한 봉투는 false.
    @discardableResult
    public func send(_ envelope: [String: Any], dedupeKey: String) -> Bool {
        guard outbox.enqueue(envelope, dedupeKey: dedupeKey) != nil else { return false }
        flush(reason: "enqueue")
        return true
    }

    /// 워치가 보낸 `ack` 를 큐에 반영한다.
    public func acknowledge(messageId: String) {
        if outbox.acknowledge(messageId: messageId) {
            logger.info("ack matched id=\(messageId, privacy: .public) depth=\(self.outbox.count)")
        }
        // ack 가 하나 빠졌으니 뒤에 밀려 있던 것들을 이어서 보낸다.
        flush(reason: "ack")
    }

    /// 연결 상태가 바뀌었을 때 호출. 연결되면 밀린 큐부터 비운다.
    public func connectionDidChange(to state: GarminConnectionState) {
        logger.info("connection state=\(state.rawValue, privacy: .public) depth=\(self.outbox.count)")
        guard state.isConnected else { return }
        flush(reason: "connected")
    }

    /// 워치 앱이 살아 있다는 신호(`hello.ack` / `sync.request`)를 받았을 때.
    public func watchDidBecomeReachable() {
        flush(reason: "hello.ack")
    }

    /// 큐를 앞에서부터 순서대로 비운다. 재진입 안전.
    public func flush(reason: String) {
        guard !isFlushing else {
            flushAgainRequested = true
            return
        }
        let state = transport.garminConnectionState
        guard state.isConnected else {
            if !outbox.isEmpty {
                logger.info(
                    "flush deferred reason=\(reason, privacy: .public) state=\(state.rawValue, privacy: .public) depth=\(self.outbox.count)"
                )
            }
            return
        }
        guard !outbox.isEmpty else { return }

        isFlushing = true
        logger.info("flush start reason=\(reason, privacy: .public) depth=\(self.outbox.count)")
        sendNext(budget: Self.maxBatch)
    }

    // MARK: - Private

    private func sendNext(budget: Int) {
        guard budget > 0 else {
            logger.info("flush batch limit reached depth=\(self.outbox.count)")
            finishFlush()
            return
        }
        guard transport.garminConnectionState.isConnected else {
            logger.info("flush stopped — disconnected depth=\(self.outbox.count)")
            finishFlush()
            return
        }
        guard let entry = outbox.pending.first else {
            logger.info("flush drained")
            finishFlush()
            return
        }
        guard let envelope = entry.envelope else {
            // 파일이 깨졌거나 포맷이 바뀐 항목. 뒤를 막지 않도록 버린다.
            logger.error("dropping unreadable entry t=\(entry.type, privacy: .public)")
            drop(messageId: entry.messageId, dedupeKey: entry.dedupeKey, reason: "unreadable")
            sendNext(budget: budget - 1)
            return
        }

        let updated = outbox.recordAttempt(messageId: entry.messageId)
        let attempt = updated?.attemptCount ?? entry.attemptCount + 1
        let type = entry.type
        let messageId = entry.messageId
        let dedupeKey = entry.dedupeKey

        transport.transmit(envelope) { [weak self] outcome in
            // transport 의 completion 은 ConnectIQ 가 아무 큐에서나 부른다.
            // 큐 조작은 전부 메인에서. 이미 메인이면 동기적으로 이어 간다.
            GarminSyncDispatcher.onMain {
                self?.handle(
                    outcome: outcome,
                    messageId: messageId,
                    dedupeKey: dedupeKey,
                    type: type,
                    attempt: attempt,
                    budget: budget
                )
            }
        }
    }

    private func handle(
        outcome: GarminSendOutcome,
        messageId: String,
        dedupeKey: String,
        type: String,
        attempt: Int,
        budget: Int
    ) {
        switch outcome {
        case .delivered:
            logger.info("TX ok t=\(type, privacy: .public) try=\(attempt)")
            outbox.remove(messageId: messageId, reason: "delivered")
            sendNext(budget: budget - 1)

        case .failed(let reason):
            logger.error("TX fail t=\(type, privacy: .public) try=\(attempt) reason=\(reason, privacy: .public)")
            if attempt >= Self.maxAttempts {
                logger.error("giving up t=\(type, privacy: .public) after \(attempt) attempts")
                drop(messageId: messageId, dedupeKey: dedupeKey, reason: "max-attempts")
                sendNext(budget: budget - 1)
            } else {
                // 순서를 지켜야 하므로 뒤 항목을 앞질러 보내지 않는다.
                // 다음 연결 이벤트에서 이 항목부터 다시 시작한다.
                finishFlush()
            }
        }
    }

    /// 큐에서 버린다. 다시 보낼 기회를 주기 위해 변경 추적도 되돌린다.
    private func drop(messageId: String, dedupeKey: String, reason: String) {
        outbox.remove(messageId: messageId, reason: reason)
        onEntryDropped?(dedupeKey)
    }

    private func finishFlush() {
        isFlushing = false
        if flushAgainRequested {
            flushAgainRequested = false
            flush(reason: "requeued")
        }
    }

    /// 메인에서 실행. 이미 메인이면 동기적으로 — 테스트가 비동기 대기 없이
    /// flush 결과를 바로 확인할 수 있게 한다.
    nonisolated private static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in work() }
        }
    }
}
