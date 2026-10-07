//
//  GarminImportService.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//

import Foundation
import os
import HyroxCore
import HyroxPersistenceApple

/// Receives `workout.completed` envelopes from the Garmin watch and persists
/// them into the shared SwiftData store via `PersistenceController`.
///
/// 멱등성: 봉투는 안정적인 `id` 를 싣고 오고, 저장은 `upsertCompletedWorkout`
/// 을 쓴다. 세그먼트 id 까지 `(기록 id, 인덱스)` 에서 결정적으로 만들기 때문에
/// (`GarminMessageCodec.stableSegmentId`) 워치가 같은 기록을 몇 번을 다시
/// 보내도 행이 하나로 유지된다. 예전에는 `saveCompletedWorkout`(순수 insert)
/// 이라 재전송마다 중복이 쌓였고, 사용자가 지운 기록(tombstone)까지 되살아났다.
///
/// 거부: 버전이 다르거나 세그먼트를 해석하지 못하면 `ack` 대신 `nack` 을
/// 보낸다. 워치는 ack 를 받아야 원본을 지우므로, 거부하면 기록이 워치에 남아
/// 다음 기회에 다시 올 수 있다.
///
/// `source` is tracked by `WorkoutSource.garmin` but requires the
/// `StoredWorkout` migration described in the repo handoff to persist —
/// until then the record is saved with default `source=.watch`.
@MainActor
public final class GarminImportService {

    private let logger = Logger(subsystem: "com.bbdyno.app.HyroxSim", category: "GarminImport")
    private let bridge: GarminBridge
    private let replySender: GarminReplySender
    private let makePersistence: () -> PersistenceController
    private let notificationCenter: NotificationCenter

    public init(
        bridge: GarminBridge = .shared,
        replySender: GarminReplySender? = nil,
        notificationCenter: NotificationCenter = .default,
        makePersistence: @escaping () -> PersistenceController
    ) {
        self.bridge = bridge
        self.replySender = replySender ?? (bridge as GarminReplySender)
        self.notificationCenter = notificationCenter
        self.makePersistence = makePersistence
    }

    public func start() {
        bridge.onMessageReceived = { [weak self] envelope in
            Task { @MainActor in
                self?.handle(envelope: envelope)
            }
        }
    }

    // MARK: - Handling

    func handle(envelope: [String: Any]) {
        guard let type = envelope[GarminMessageCodec.Key.type] as? String else { return }
        switch type {
        case GarminMessageCodec.MessageType.workoutCompleted:
            handleWorkoutCompleted(envelope: envelope)
        // `ack` 은 `GarminBridge` 가 곧바로 `GarminSyncDispatcher` 로 넘긴다.
        // 이 서비스가 시작되기 전에 도착해도 큐가 정리되도록 한 곳에서만 처리한다.
        default:
            break
        }
    }

    private func handleWorkoutCompleted(envelope: [String: Any]) {
        let messageId = (envelope[GarminMessageCodec.Key.id] as? String) ?? UUID().uuidString

        switch GarminMessageCodec.decodeWorkoutCompletedStrict(envelope) {
        case .failure(let failure):
            // ack 를 보내지 않는 것이 핵심이다. 워치는 원본을 지우지 않는다.
            logger.error("reject workout.completed reason=\(failure.rawValue, privacy: .public)")
            reject(messageId: messageId, reason: failure.rejectReason)

        case .success(let completed):
            do {
                let stored = try makePersistence().upsertCompletedWorkout(completed)
                if stored {
                    logger.info("imported workout id=\(completed.id.uuidString, privacy: .public) segments=\(completed.segments.count)")
                    notificationCenter.post(name: .syncDataUpdated, object: nil)
                } else {
                    // 사용자가 지운 기록. 저장하지 않지만 ack 는 보낸다 —
                    // 그래야 워치가 계속 재전송하지 않는다.
                    logger.info("skipped tombstoned workout id=\(completed.id.uuidString, privacy: .public)")
                }
                acknowledge(messageId: messageId)
            } catch {
                logger.error("persist failed: \(error.localizedDescription, privacy: .public)")
                reject(messageId: messageId, reason: GarminMessageCodec.RejectReason.persistFailed)
            }
        }
    }

    private func acknowledge(messageId: String) {
        replySender.sendEnvelope(
            GarminMessageCodec.makeEnvelope(
                type: GarminMessageCodec.MessageType.ack,
                id: messageId
            )
        )
    }

    private func reject(messageId: String, reason: String) {
        replySender.sendEnvelope(
            GarminMessageCodec.encodeReject(id: messageId, reason: reason)
        )
    }
}
