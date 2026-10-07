//
//  GarminImportServiceTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/19/26.
//

import XCTest
import HyroxCore
import HyroxPersistenceApple
@testable import HyroxSim

// MARK: - Test doubles

/// 전송 결과를 마음대로 정하는 가짜 전송로. `GarminEnvelopeTransport` 는
/// 전역 액터가 없으므로 평범한 클래스로 구현할 수 있다.
private final class FakeGarminTransport: GarminEnvelopeTransport {
    var garminConnectionState: GarminConnectionState = .disconnected
    var outcome: GarminSendOutcome = .delivered
    private(set) var sent: [[String: Any]] = []

    var sentTypes: [String] {
        sent.compactMap { $0[GarminMessageCodec.Key.type] as? String }
    }

    func transmit(_ envelope: [String: Any], completion: @escaping (GarminSendOutcome) -> Void) {
        if case .delivered = outcome { sent.append(envelope) }
        completion(outcome)
    }
}

private final class FakeReplySender: GarminReplySender {
    private(set) var sent: [[String: Any]] = []

    var types: [String] { sent.compactMap { $0[GarminMessageCodec.Key.type] as? String } }

    func sendEnvelope(_ envelope: [String: Any]) { sent.append(envelope) }

    func reason(at index: Int) -> String? {
        guard sent.indices.contains(index),
              let payload = sent[index][GarminMessageCodec.Key.payload] as? [String: Any]
        else { return nil }
        return payload["reason"] as? String
    }
}

@MainActor
final class GarminImportServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeWorkoutEnvelope(
        workoutId: UUID,
        messageId: String = "wk-42",
        version: Any = 1,
        segments: [[String: Any]]? = nil
    ) -> [String: Any] {
        [
            GarminMessageCodec.Key.version: version,
            GarminMessageCodec.Key.type: GarminMessageCodec.MessageType.workoutCompleted,
            GarminMessageCodec.Key.id: messageId,
            GarminMessageCodec.Key.payload: [
                "id": workoutId.uuidString,
                "templateName": "Hyrox Men's Open",
                "division": "menOpenSingle",
                "startedAtMs": 1_000,
                "finishedAtMs": 10_000,
                "source": "garmin",
                "segments": segments ?? [
                    [
                        "index": 0,
                        "type": "run",
                        "startedAtMs": 1_000,
                        "endedAtMs": 2_000,
                        "pausedDurationMs": 0,
                    ],
                ],
            ],
        ]
    }

    private func makeTemplate(name: String = "Custom", id: UUID = UUID()) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id,
            name: name,
            division: .menOpenSingle,
            segments: [
                .run(distanceMeters: 1000),
                .station(.skiErg, target: .distance(meters: 1000))
            ]
        )
    }

    private func makeDispatcher(
        _ transport: FakeGarminTransport
    ) -> GarminSyncDispatcher {
        GarminSyncDispatcher(transport: transport, outbox: .inMemory())
    }

    // MARK: - Import

    func test_handleWorkoutCompleted_persistsWorkout() throws {
        let persistence = try PersistenceController(inMemory: true)
        let reply = FakeReplySender()
        let service = GarminImportService(replySender: reply, makePersistence: { persistence })

        service.handle(envelope: makeWorkoutEnvelope(workoutId: UUID()))

        let all = try persistence.fetchAllCompletedWorkouts()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.templateName, "Hyrox Men's Open")
        XCTAssertEqual(all.first?.segments.count, 1)
        XCTAssertEqual(reply.types, [GarminMessageCodec.MessageType.ack])
    }

    func test_handleNonWorkoutEnvelope_doesNothing() throws {
        let persistence = try PersistenceController(inMemory: true)
        let service = GarminImportService(makePersistence: { persistence })

        service.handle(envelope: [
            GarminMessageCodec.Key.type: "hello",
            GarminMessageCodec.Key.id: "x",
        ])

        let all = try persistence.fetchAllCompletedWorkouts()
        XCTAssertTrue(all.isEmpty)
    }

    /// 워치가 같은 기록을 다시 보내도 1건만 남아야 한다.
    /// (`saveCompletedWorkout` 시절에는 재전송마다 중복이 쌓였다)
    func test_handleWorkoutCompleted_repeatedDelivery_keepsSingleRecord() throws {
        let persistence = try PersistenceController(inMemory: true)
        let reply = FakeReplySender()
        let service = GarminImportService(replySender: reply, makePersistence: { persistence })
        let workoutId = UUID()

        service.handle(envelope: makeWorkoutEnvelope(workoutId: workoutId))
        let firstSegmentIds = try persistence.fetchAllCompletedWorkouts().first?.segments.map(\.id)

        service.handle(envelope: makeWorkoutEnvelope(workoutId: workoutId, messageId: "wk-42-retry"))

        let all = try persistence.fetchAllCompletedWorkouts()
        XCTAssertEqual(all.count, 1)
        // 세그먼트 id 는 (기록 id, 인덱스)에서 결정적으로 나오므로 그대로여야 한다.
        XCTAssertEqual(all.first?.segments.map(\.id), firstSegmentIds)
        XCTAssertEqual(reply.types, [
            GarminMessageCodec.MessageType.ack,
            GarminMessageCodec.MessageType.ack
        ])
    }

    /// 사용자가 지운 기록(tombstone)은 다시 저장하지 않는다.
    /// 다만 ack 는 보내야 워치가 무한 재전송을 멈춘다.
    func test_handleWorkoutCompleted_tombstoned_isNotStored() throws {
        let persistence = try PersistenceController(inMemory: true)
        let reply = FakeReplySender()
        let service = GarminImportService(replySender: reply, makePersistence: { persistence })
        let workoutId = UUID()

        _ = try persistence.markCompletedWorkoutDeleted(id: workoutId)
        service.handle(envelope: makeWorkoutEnvelope(workoutId: workoutId))

        XCTAssertTrue(try persistence.fetchAllCompletedWorkouts().isEmpty)
        XCTAssertEqual(reply.types, [GarminMessageCodec.MessageType.ack])
    }

    /// 모르는 프로토콜 버전은 ack 대신 nack. 워치가 원본을 지우지 않게.
    func test_handleWorkoutCompleted_unsupportedVersion_isRejected() throws {
        let persistence = try PersistenceController(inMemory: true)
        let reply = FakeReplySender()
        let service = GarminImportService(replySender: reply, makePersistence: { persistence })

        service.handle(envelope: makeWorkoutEnvelope(workoutId: UUID(), version: 99))

        XCTAssertTrue(try persistence.fetchAllCompletedWorkouts().isEmpty)
        XCTAssertEqual(reply.types, [GarminMessageCodec.MessageType.nack])
        XCTAssertEqual(reply.reason(at: 0), GarminMessageCodec.RejectReason.unsupportedVersion)
    }

    func test_handleWorkoutCompleted_missingVersion_isRejected() throws {
        let persistence = try PersistenceController(inMemory: true)
        let reply = FakeReplySender()
        let service = GarminImportService(replySender: reply, makePersistence: { persistence })

        var envelope = makeWorkoutEnvelope(workoutId: UUID())
        envelope.removeValue(forKey: GarminMessageCodec.Key.version)
        service.handle(envelope: envelope)

        XCTAssertTrue(try persistence.fetchAllCompletedWorkouts().isEmpty)
        XCTAssertEqual(reply.reason(at: 0), GarminMessageCodec.RejectReason.unsupportedVersion)
    }

    /// 세그먼트 하나라도 해석하지 못하면 통째로 거부한다. 일부만 저장하면
    /// 기록이 조용히 망가진다.
    func test_handleWorkoutCompleted_malformedSegment_isRejected() throws {
        let persistence = try PersistenceController(inMemory: true)
        let reply = FakeReplySender()
        let service = GarminImportService(replySender: reply, makePersistence: { persistence })

        let envelope = makeWorkoutEnvelope(
            workoutId: UUID(),
            segments: [
                ["index": 0, "type": "run", "startedAtMs": 1_000, "endedAtMs": 2_000],
                ["index": 1, "type": "🙃", "startedAtMs": 2_000, "endedAtMs": 3_000],
            ]
        )
        service.handle(envelope: envelope)

        XCTAssertTrue(try persistence.fetchAllCompletedWorkouts().isEmpty)
        XCTAssertEqual(reply.types, [GarminMessageCodec.MessageType.nack])
        XCTAssertEqual(reply.reason(at: 0), GarminMessageCodec.RejectReason.malformedSegment)
    }

    func test_handleWorkoutCompleted_postsSyncNotification() throws {
        let persistence = try PersistenceController(inMemory: true)
        let center = NotificationCenter()
        let service = GarminImportService(
            replySender: FakeReplySender(),
            notificationCenter: center,
            makePersistence: { persistence }
        )

        var posted = 0
        // queue: nil — 알림을 보낸 스레드에서 동기적으로 실행된다.
        let token = center.addObserver(forName: .syncDataUpdated, object: nil, queue: nil) { _ in
            posted += 1
        }
        defer { center.removeObserver(token) }

        service.handle(envelope: makeWorkoutEnvelope(workoutId: UUID()))
        XCTAssertEqual(posted, 1)
    }

    // MARK: - Outbox

    /// 연결이 없으면 큐에 쌓이고, 연결되면 넣은 순서대로 나간다.
    func test_outbox_queuesWhileDisconnected_andFlushesInOrder() {
        let transport = FakeGarminTransport()
        let dispatcher = makeDispatcher(transport)
        let templateId = UUID()

        dispatcher.send(
            GarminMessageCodec.encodeTemplateUpsert(makeTemplate(id: templateId)),
            dedupeKey: GarminSyncDispatcher.DedupeKey.template(templateId)
        )
        dispatcher.send(
            GarminMessageCodec.encodeGoalSet(
                division: .menOpenSingle,
                templateName: "Preset",
                targetTotalMs: 90 * 60 * 1000,
                targetSegmentsMs: [1, 2, 3]
            ),
            dedupeKey: GarminSyncDispatcher.DedupeKey.goal(division: "menOpenSingle")
        )
        let deletedId = UUID()
        dispatcher.send(
            GarminMessageCodec.encodeTemplateDelete(id: deletedId),
            dedupeKey: GarminSyncDispatcher.DedupeKey.template(deletedId)
        )

        XCTAssertEqual(dispatcher.pendingCount, 3)
        XCTAssertTrue(transport.sent.isEmpty)

        transport.garminConnectionState = .connected
        dispatcher.connectionDidChange(to: .connected)

        XCTAssertEqual(dispatcher.pendingCount, 0)
        XCTAssertEqual(transport.sentTypes, [
            GarminMessageCodec.MessageType.templateUpsert,
            GarminMessageCodec.MessageType.goalSet,
            GarminMessageCodec.MessageType.templateDelete,
        ])
    }

    /// 같은 대상은 최신 것만 남는다. 템플릿 upsert 를 반복해도 1건.
    func test_outbox_dedupesSameTarget_keepingLatest() {
        let transport = FakeGarminTransport()
        let dispatcher = makeDispatcher(transport)
        let templateId = UUID()
        let key = GarminSyncDispatcher.DedupeKey.template(templateId)

        dispatcher.send(
            GarminMessageCodec.encodeTemplateUpsert(makeTemplate(name: "v1", id: templateId)),
            dedupeKey: key
        )
        dispatcher.send(
            GarminMessageCodec.encodeTemplateUpsert(makeTemplate(name: "v2", id: templateId)),
            dedupeKey: key
        )

        XCTAssertEqual(dispatcher.pendingCount, 1)

        transport.garminConnectionState = .connected
        dispatcher.flush(reason: "test")

        XCTAssertEqual(transport.sent.count, 1)
        let payload = transport.sent[0][GarminMessageCodec.Key.payload] as? [String: Any]
        XCTAssertEqual(payload?["name"] as? String, "v2")
    }

    /// upsert 뒤에 delete 가 오면 delete 만 남아야 한다. 같은 dedupe 키를
    /// 쓰므로 워치가 지운 템플릿을 잠깐이라도 보는 일이 없다.
    func test_outbox_deleteSupersedesPendingUpsert() {
        let transport = FakeGarminTransport()
        let dispatcher = makeDispatcher(transport)
        let templateId = UUID()
        let key = GarminSyncDispatcher.DedupeKey.template(templateId)

        dispatcher.send(GarminMessageCodec.encodeTemplateUpsert(makeTemplate(id: templateId)), dedupeKey: key)
        dispatcher.send(GarminMessageCodec.encodeTemplateDelete(id: templateId), dedupeKey: key)

        XCTAssertEqual(dispatcher.pendingCount, 1)
        XCTAssertEqual(dispatcher.pendingTypes, [GarminMessageCodec.MessageType.templateDelete])
    }

    /// ack 이 오면 큐에서 빠진다.
    func test_outbox_ackRemovesEntry() throws {
        let transport = FakeGarminTransport()
        transport.garminConnectionState = .connected
        // 전송은 계속 실패시켜 두고, 제거가 ack 때문인지만 본다.
        transport.outcome = .failed(reason: "test")
        let dispatcher = makeDispatcher(transport)
        let templateId = UUID()

        dispatcher.send(
            GarminMessageCodec.encodeTemplateUpsert(makeTemplate(id: templateId)),
            dedupeKey: GarminSyncDispatcher.DedupeKey.template(templateId)
        )
        XCTAssertEqual(dispatcher.pendingCount, 1)

        let messageId = try XCTUnwrap(dispatcher.pendingMessageIds.first)
        dispatcher.acknowledge(messageId: messageId)

        XCTAssertEqual(dispatcher.pendingCount, 0)
        // 모르는 id 는 무시된다.
        dispatcher.acknowledge(messageId: "unknown")
        XCTAssertEqual(dispatcher.pendingCount, 0)
    }

    /// 전송 실패는 큐를 비우지 않고, 순서도 흐트러뜨리지 않는다.
    func test_outbox_failureKeepsQueueAndOrder() {
        let transport = FakeGarminTransport()
        let dispatcher = makeDispatcher(transport)
        let firstId = UUID()
        let secondId = UUID()

        dispatcher.send(
            GarminMessageCodec.encodeTemplateUpsert(makeTemplate(name: "first", id: firstId)),
            dedupeKey: GarminSyncDispatcher.DedupeKey.template(firstId)
        )
        dispatcher.send(
            GarminMessageCodec.encodeTemplateDelete(id: secondId),
            dedupeKey: GarminSyncDispatcher.DedupeKey.template(secondId)
        )

        transport.garminConnectionState = .connected
        transport.outcome = .failed(reason: "app-not-found")
        dispatcher.flush(reason: "test")

        // 첫 항목에서 막히고 둘 다 큐에 남아야 한다.
        XCTAssertEqual(dispatcher.pendingCount, 2)
        XCTAssertTrue(transport.sent.isEmpty)

        transport.outcome = .delivered
        dispatcher.flush(reason: "retry")

        XCTAssertEqual(dispatcher.pendingCount, 0)
        XCTAssertEqual(transport.sentTypes, [
            GarminMessageCodec.MessageType.templateUpsert,
            GarminMessageCodec.MessageType.templateDelete,
        ])
    }

    /// 앱이 죽어도 큐가 남는다.
    func test_outbox_survivesRelaunch() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let templateId = UUID()
        let first = GarminOutbox(fileURL: url)
        first.enqueue(
            GarminMessageCodec.encodeTemplateDelete(id: templateId),
            dedupeKey: GarminSyncDispatcher.DedupeKey.template(templateId)
        )
        XCTAssertEqual(first.count, 1)

        let reloaded = GarminOutbox(fileURL: url)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.pending.first?.type, GarminMessageCodec.MessageType.templateDelete)
    }

    /// 템플릿 봉투는 nil 필드가 섞여 있어도 JSON 으로 저장 가능해야 한다.
    func test_outbox_storesTemplateEnvelopeWithOptionalFields() throws {
        let outbox = GarminOutbox.inMemory()
        let template = WorkoutTemplate(
            name: "No division",
            division: nil,
            segments: [.run(distanceMeters: 1000), .roxZone()]
        )
        let entry = outbox.enqueue(
            GarminMessageCodec.encodeTemplateUpsert(template),
            dedupeKey: GarminSyncDispatcher.DedupeKey.template(template.id)
        )
        let restored = try XCTUnwrap(entry?.envelope)
        let payload = try XCTUnwrap(restored[GarminMessageCodec.Key.payload] as? [String: Any])
        XCTAssertEqual(payload["name"] as? String, "No division")
        XCTAssertNil(payload["division"])
        XCTAssertEqual((payload["segments"] as? [[String: Any]])?.count, 2)
    }

    // MARK: - Goal sync

    func test_goalSync_queuesWhenNotConnected() {
        let transport = FakeGarminTransport()
        let svc = GarminGoalSyncService(dispatcher: makeDispatcher(transport))
        let result = svc.sendGoal(
            division: .menOpenSingle,
            templateName: "Preset",
            targetTotalMs: 90 * 60 * 1000,
            targetSegmentsMs: Array(repeating: Int64(150_000), count: 31)
        )
        // 예전에는 페어링이 없으면 그냥 버렸다. 이제는 큐에 남아 다음 연결에 나간다.
        XCTAssertEqual(result, .queued)
    }

    func test_goalSync_sendsWhenConnected() {
        let transport = FakeGarminTransport()
        transport.garminConnectionState = .connected
        let svc = GarminGoalSyncService(dispatcher: makeDispatcher(transport))
        let result = svc.sendGoal(
            division: .menOpenSingle,
            templateName: "Preset",
            targetTotalMs: 90 * 60 * 1000,
            targetSegmentsMs: Array(repeating: Int64(150_000), count: 31)
        )
        XCTAssertEqual(result, .sent)
        XCTAssertEqual(transport.sentTypes, [GarminMessageCodec.MessageType.goalSet])
    }

    // MARK: - Change detection

    /// `hello.ack` 재동기화는 바뀐 것만 보낸다.
    /// 예전에는 ack 마다 커스텀 템플릿 전체 + 프리셋 목표 9건이 통째로 나갔다.
    func test_templateSync_pushAll_onlySendsChangedTemplates() {
        let transport = FakeGarminTransport()
        transport.garminConnectionState = .connected
        let service = GarminTemplateSyncService(
            dispatcher: makeDispatcher(transport),
            syncState: GarminSyncStateStore(defaults: makeScratchDefaults())
        )
        let template = makeTemplate(name: "Stable")

        service.pushAll([template])
        let afterFirst = transport.sent.count
        XCTAssertEqual(afterFirst, 2) // template.upsert + goal.set

        // 같은 내용을 다시 밀면 한 건도 나가지 않는다.
        service.pushAll([template])
        XCTAssertEqual(transport.sent.count, afterFirst)

        // 이름만 바꿔도 변경으로 잡힌다.
        var edited = template
        edited.name = "Renamed"
        service.pushAll([edited])
        XCTAssertEqual(transport.sent.count, afterFirst + 2)
        XCTAssertEqual(transport.sentTypes.last, GarminMessageCodec.MessageType.goalSet)
    }

    /// 사용자가 직접 저장한 템플릿은 내용이 같아도 즉시 보낸다.
    func test_templateSync_push_alwaysSends() {
        let transport = FakeGarminTransport()
        transport.garminConnectionState = .connected
        let service = GarminTemplateSyncService(
            dispatcher: makeDispatcher(transport),
            syncState: GarminSyncStateStore(defaults: makeScratchDefaults())
        )
        let template = makeTemplate(name: "Manual")

        service.push(template)
        service.push(template)

        XCTAssertEqual(transport.sent.count, 4)
    }

    /// 삭제는 연결이 없어도 사라지지 않는다 — 이번 수정의 핵심.
    func test_templateSync_deleteSurvivesDisconnectedWatch() {
        let transport = FakeGarminTransport()
        let dispatcher = makeDispatcher(transport)
        let service = GarminTemplateSyncService(
            dispatcher: dispatcher,
            syncState: GarminSyncStateStore(defaults: makeScratchDefaults())
        )
        let templateId = UUID()

        service.delete(id: templateId)
        XCTAssertEqual(dispatcher.pendingTypes, [GarminMessageCodec.MessageType.templateDelete])
        XCTAssertTrue(transport.sent.isEmpty)

        transport.garminConnectionState = .connected
        dispatcher.connectionDidChange(to: .connected)

        XCTAssertEqual(transport.sentTypes, [GarminMessageCodec.MessageType.templateDelete])
        XCTAssertEqual(dispatcher.pendingCount, 0)
    }

    private func makeScratchDefaults() -> UserDefaults {
        let suite = "garmin.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
