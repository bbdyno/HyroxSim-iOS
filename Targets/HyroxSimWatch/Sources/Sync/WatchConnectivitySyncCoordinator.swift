//
//  WatchConnectivitySyncCoordinator.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import WatchConnectivity
import HyroxKit

/// watchOS-side WatchConnectivity sync coordinator.
/// Sends completed workouts to phone, receives custom templates from phone.
/// Code overlap with iOS coordinator is intentional — could be shared in a future refactor.
@MainActor
public final class WatchConnectivitySyncCoordinator: NSObject, SyncCoordinator, @unchecked Sendable {

    private let session: WCSession
    private let persistence: PersistenceController

    public var onReceiveTemplate: ((WorkoutTemplate) -> Void)?
    public var onReceiveCompletedWorkout: ((CompletedWorkout) -> Void)?
    public var onReceiveTemplateDeleted: ((UUID) -> Void)?

    public init(persistence: PersistenceController) {
        self.persistence = persistence
        self.session = WCSession.default
        super.init()
    }

    /// 폰에서 보낸 원격 명령 수신 콜백
    public var onReceiveCommand: ((WorkoutCommand) -> Void)?

    public var isSupported: Bool { WCSession.isSupported() }
    public var isPaired: Bool { true } // Always true from watch perspective
    public var isReachable: Bool { session.isReachable }

    public func activate() {
        guard isSupported else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Send

    /// Watch doesn't create templates — noop.
    public func sendTemplate(_ template: WorkoutTemplate) throws {}

    public func sendCompletedWorkout(_ workout: CompletedWorkout) throws {
        let envelope = try SyncEnvelopeCoder.encode(workout, kind: .completedWorkout)
        let data = try JSONEncoder().encode(envelope)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workout-\(workout.id).json")
        try data.write(to: url)
        session.transferFile(url, metadata: nil)
    }

    public func sendTemplateDeleted(id: UUID) throws {
        let envelope = try SyncEnvelopeCoder.encode(id, kind: .templateDeleted)
        let dict = try SyncEnvelopeCoder.toDictionary(envelope)
        session.transferUserInfo(dict)
    }

    /// 워치에 저장된 모든 완료 워크아웃을 폰으로 전송 (기존 히스토리 동기화)
    /// upsert이므로 중복 전송해도 안전
    public func syncAllCompletedWorkouts() {
        guard let workouts = try? persistence.fetchAllCompletedWorkouts() else { return }
        for workout in workouts {
            try? sendCompletedWorkout(workout)
        }
    }

    // MARK: - 실시간 운동 전송

    /// 폰에 운동 시작을 알림 (템플릿 정보 포함)
    public func sendWorkoutStarted(template: WorkoutTemplate) {
        guard session.isReachable else { return }
        guard let data = try? JSONEncoder().encode(template) else { return }
        let msg: [String: Any] = [LiveSyncKeys.workoutStarted: true, LiveSyncKeys.templateData: data]
        session.sendMessage(msg, replyHandler: nil, errorHandler: nil)
    }

    /// 실시간 상태 전송 (매 초)
    public func sendLiveState(_ state: LiveWorkoutState) {
        guard session.isReachable else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        session.sendMessage([LiveSyncKeys.liveState: data], replyHandler: nil, errorHandler: nil)
    }

    /// 운동 종료 알림
    public func sendWorkoutFinished() {
        guard session.isReachable else { return }
        session.sendMessage([LiveSyncKeys.workoutFinished: true], replyHandler: nil, errorHandler: nil)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivitySyncCoordinator: WCSessionDelegate {

    nonisolated public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor [weak self] in
            self?.syncAllCompletedWorkouts()
        }
    }

    /// 폰에서 보낸 실시간 메시지 수신 (원격 명령)
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let cmdRaw = message[LiveSyncKeys.command] as? String,
           let cmd = WorkoutCommand(rawValue: cmdRaw) {
            Task { @MainActor [weak self] in
                self?.onReceiveCommand?(cmd)
            }
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor [weak self] in
            self?.handleDict(userInfo)
        }
    }

    nonisolated public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let url = file.fileURL
        Task { @MainActor [weak self] in
            self?.handleFile(at: url)
        }
    }
}

// MARK: - Private

extension WatchConnectivitySyncCoordinator {

    @MainActor
    private func handleDict(_ dict: [String: Any]) {
        do {
            let envelope = try SyncEnvelopeCoder.fromDictionary(dict)
            switch envelope.kind {
            case .template:
                let t = try SyncEnvelopeCoder.decodeTemplate(envelope)
                try persistence.upsertTemplate(t)
                onReceiveTemplate?(t)
            case .completedWorkout:
                let w = try SyncEnvelopeCoder.decodeCompletedWorkout(envelope)
                try persistence.upsertCompletedWorkout(w)
                onReceiveCompletedWorkout?(w)
            case .templateDeleted:
                let id = try SyncEnvelopeCoder.decodeDeletedId(envelope)
                try? persistence.deleteTemplate(id: id)
                onReceiveTemplateDeleted?(id)
            }
        } catch {
            print("[Sync] Receive dict failed: \(error)")
        }
    }

    @MainActor
    private func handleFile(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let envelope = try JSONDecoder().decode(SyncEnvelope.self, from: data)
            let workout = try SyncEnvelopeCoder.decodeCompletedWorkout(envelope)
            try persistence.upsertCompletedWorkout(workout)
            onReceiveCompletedWorkout?(workout)
        } catch {
            print("[Sync] Receive file failed: \(error)")
        }
    }
}
