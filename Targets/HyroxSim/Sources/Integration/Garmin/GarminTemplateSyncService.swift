//
//  GarminTemplateSyncService.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//

import Foundation
import os
import HyroxCore

/// Pushes user-built `WorkoutTemplate`s (including `usesRoxZone=false`
/// variants) to the Garmin watch's `TemplateStore`.
///
/// 전송은 전부 `GarminSyncDispatcher`(= 영속 outbox)를 거친다. 워치 앱이 닫혀
/// 있어도 메시지는 디스크에 남고, 다음 연결에서 순서대로 나간다. 예전에는
/// `GarminBridge.sendEnvelope` 를 바로 불러서, 연결이 없으면 특히
/// `template.delete` 가 그대로 사라졌다(지운 템플릿이 워치에 영원히 남았다).
///
/// 재전송 폭주 방지: `pushAll` / `pushGoal` 은 `GarminSyncStateStore` 에
/// 남긴 내용 지문과 비교해 **바뀐 것만** 큐에 넣는다. `hello.ack` 마다 커스텀
/// 템플릿 전체와 프리셋 목표 9건을 통째로 다시 보내던 동작이 사라진다.
@MainActor
public final class GarminTemplateSyncService {

    private let logger = Logger(subsystem: "com.bbdyno.app.HyroxSim", category: "GarminSync")
    private let dispatcher: GarminSyncDispatcher
    private let syncState: GarminSyncStateStore

    public init(
        dispatcher: GarminSyncDispatcher? = nil,
        syncState: GarminSyncStateStore? = nil
    ) {
        // 기본 인자 자리에서 만들면 nonisolated 컨텍스트라 @MainActor 초기화가 막힌다.
        self.dispatcher = dispatcher ?? .shared
        let syncState = syncState ?? GarminSyncStateStore()
        self.syncState = syncState
        // 재시도 상한을 넘겨 버려진 메시지는 "보냈음" 표시도 지운다. 그래야
        // 다음 재동기화에서 다시 변경분으로 잡혀 워치에 도달할 기회가 생긴다.
        self.dispatcher.onEntryDropped = { [syncState] key in
            syncState.forget(key: key)
        }
    }

    /// 사용자가 템플릿을 저장/수정한 직후. 내용이 같아도 무조건 보낸다 —
    /// 사용자가 방금 한 동작이므로 "바뀐 게 없으니 건너뜀" 은 혼란스럽다.
    public func push(_ template: WorkoutTemplate) {
        enqueueUpsert(template, force: true)
        pushGoal(for: template, force: true)
    }

    /// 재동기화용 일괄 전송. 마지막 동기화 이후 바뀐 것만 나간다.
    public func pushAll(_ templates: [WorkoutTemplate]) {
        var changed = 0
        for template in templates {
            if enqueueUpsert(template, force: false) { changed += 1 }
            if pushGoal(for: template, force: false) { changed += 1 }
        }
        logger.info("pushAll templates=\(templates.count) queued=\(changed)")
    }

    public func delete(id: UUID) {
        let envelope = GarminMessageCodec.encodeTemplateDelete(id: id)
        // upsert 와 같은 dedupe 키. 저장 직후 삭제하면 upsert 는 사라지고
        // delete 만 남아, 워치가 지운 템플릿을 잠깐 보는 일이 없다.
        dispatcher.send(envelope, dedupeKey: GarminSyncDispatcher.DedupeKey.template(id))
        // 같은 id 로 다시 만들면 새로 보내야 하므로 지문을 잊는다.
        syncState.forget(key: GarminSyncDispatcher.DedupeKey.template(id))
        logger.info("queued template.delete id=\(id.uuidString, privacy: .public)")
    }

    // Mirrors a template's per-segment `goalDurationSeconds` onto the
    // watch's `GoalStore` via a `goal.set` envelope. The watch keeps
    // templates and per-division goals in separate stores, so a template
    // push alone leaves the delta badge falling back to PaceReference
    // defaults — the user's pace-planner output never reaches the screen
    // unless this also fires.
    //
    // Public so callers re-syncing built-in HYROX presets (which the
    // watch generates locally) can push only the goal half without
    // duplicating the template entry into MY WORKOUTS.
    @discardableResult
    public func pushGoal(for template: WorkoutTemplate, force: Bool = false) -> Bool {
        guard let division = template.division else { return false }
        let segGoalsMs: [Int64] = template.segments.map { seg in
            Int64((seg.goalDurationSeconds ?? 0) * 1000)
        }
        let totalMs = segGoalsMs.reduce(0, +)
        // All-zero goals = the user never set a target. Skip to avoid
        // overwriting a previously synced goal with a meaningless one.
        guard totalMs > 0 else { return false }

        let envelope = GarminMessageCodec.encodeGoalSet(
            division: division,
            templateName: template.name,
            targetTotalMs: totalMs,
            targetSegmentsMs: segGoalsMs
        )
        let key = GarminSyncDispatcher.DedupeKey.goal(division: division.rawValue)
        return enqueue(envelope, key: key, force: force, label: "goal.set")
    }

    // MARK: - Private

    @discardableResult
    private func enqueueUpsert(_ template: WorkoutTemplate, force: Bool) -> Bool {
        let envelope = GarminMessageCodec.encodeTemplateUpsert(template)
        let key = GarminSyncDispatcher.DedupeKey.template(template.id)
        return enqueue(envelope, key: key, force: force, label: "template.upsert")
    }

    private func enqueue(_ envelope: [String: Any], key: String, force: Bool, label: String) -> Bool {
        guard let fingerprint = GarminMessageCodec.payloadFingerprint(of: envelope) else {
            logger.error("\(label, privacy: .public) skipped — payload not serialisable")
            return false
        }
        guard force || syncState.hasChanged(key: key, fingerprint: fingerprint) else {
            return false
        }
        guard dispatcher.send(envelope, dedupeKey: key) else { return false }
        syncState.markSynced(key: key, fingerprint: fingerprint)
        logger.info("queued \(label, privacy: .public) key=\(key, privacy: .public)")
        return true
    }
}
