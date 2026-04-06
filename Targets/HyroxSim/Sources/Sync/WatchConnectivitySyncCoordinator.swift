//
//  WatchConnectivitySyncCoordinator.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import WatchConnectivity
import HyroxKit

/// iOS-side WatchConnectivity sync coordinator.
/// Sends custom templates to watch, receives completed workouts from watch.
@MainActor
public final class WatchConnectivitySyncCoordinator: NSObject, SyncCoordinator, @unchecked Sendable {

    private let session: WCSession
    private let persistence: PersistenceController

    public var onReceiveTemplate: ((WorkoutTemplate) -> Void)?
    public var onReceiveCompletedWorkout: ((CompletedWorkout) -> Void)?
    public var onReceiveTemplateDeleted: ((UUID) -> Void)?

    /// 워치에서 운동 시작됨 (템플릿 포함)
    public var onWorkoutStarted: ((WorkoutTemplate) -> Void)?
    /// 워치에서 실시간 상태 수신
    public var onLiveStateReceived: ((LiveWorkoutState) -> Void)?
    /// 워치에서 운동 종료됨
    public var onWorkoutFinished: (() -> Void)?

    public init(persistence: PersistenceController) {
        self.persistence = persistence
        self.session = WCSession.default
        super.init()
    }

    public var isSupported: Bool { WCSession.isSupported() }
    public var isPaired: Bool { session.isPaired }
    public var isReachable: Bool { session.isReachable }

    public func activate() {
        guard isSupported else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Send

    public func sendTemplate(_ template: WorkoutTemplate) throws {
        let envelope = try SyncEnvelopeCoder.encode(template, kind: .template)
        let dict = try SyncEnvelopeCoder.toDictionary(envelope)
        session.transferUserInfo(dict)
    }

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

    /// 워치에 원격 명령 전송
    public func sendCommand(_ command: WorkoutCommand) {
        guard session.isReachable else { return }
        session.sendMessage([LiveSyncKeys.command: command.rawValue], replyHandler: nil, errorHandler: nil)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivitySyncCoordinator: WCSessionDelegate {

    nonisolated public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    /// 워치에서 보낸 실시간 메시지 수신
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.handleLiveMessage(message)
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
    private func handleLiveMessage(_ msg: [String: Any]) {
        // 운동 시작 알림
        if msg[LiveSyncKeys.workoutStarted] as? Bool == true,
           let data = msg[LiveSyncKeys.templateData] as? Data,
           let template = try? JSONDecoder().decode(WorkoutTemplate.self, from: data) {
            onWorkoutStarted?(template)
            return
        }
        // 실시간 상태
        if let data = msg[LiveSyncKeys.liveState] as? Data,
           let state = try? JSONDecoder().decode(LiveWorkoutState.self, from: data) {
            onLiveStateReceived?(state)
            return
        }
        // 운동 종료
        if msg[LiveSyncKeys.workoutFinished] as? Bool == true {
            onWorkoutFinished?()
            return
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
