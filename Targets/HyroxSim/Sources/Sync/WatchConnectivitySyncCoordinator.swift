//
//  WatchConnectivitySyncCoordinator.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import WatchConnectivity
import HyroxCore
import HyroxPersistenceApple

/// iOS-side WatchConnectivity sync coordinator.
/// 양방향 실시간 운동 동기화 + 템플릿/워크아웃 백그라운드 동기화.
@MainActor
public final class WatchConnectivitySyncCoordinator: NSObject, SyncCoordinator, @unchecked Sendable {

    private let session: WCSession
    private let persistence: PersistenceController

    // MARK: - Background sync callbacks
    public var onReceiveTemplate: ((WorkoutTemplate) -> Void)?
    public var onReceiveCompletedWorkout: ((CompletedWorkout) -> Void)?
    public var onReceiveTemplateDeleted: ((UUID) -> Void)?

    // MARK: - Live workout callbacks (양방향)
    public var onWorkoutStarted: ((WorkoutTemplate, WorkoutOrigin) -> Void)?
    public var onLiveStateReceived: ((LiveWorkoutState) -> Void)?
    public var onWorkoutFinished: ((WorkoutOrigin) -> Void)?
    public var onReceiveCommand: ((WorkoutCommand) -> Void)?
    public var onHeartRateRelayReceived: ((HeartRateRelay) -> Void)?
    public var onReachabilityChanged: ((Bool) -> Void)?

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

    // MARK: - Background sync (transferUserInfo / transferFile)

    public func sendTemplate(_ template: WorkoutTemplate) throws {
        let envelope = try SyncEnvelopeCoder.encode(template, kind: .template)
        let dict = try SyncEnvelopeCoder.toDictionary(envelope)
        session.transferUserInfo(dict)

        // 빠른 경로: 워치가 reachable 이면 sendMessage 로 즉시 전송.
        // transferUserInfo 는 안정 전송용으로 병행 유지. 워치 save() 는 idempotent.
        if session.isReachable, let data = try? JSONEncoder().encode(template) {
            session.sendMessage(
                [LiveSyncKeys.templateSync: data],
                replyHandler: nil,
                errorHandler: nil
            )
        }
    }

    public func sendCompletedWorkout(_ workout: CompletedWorkout) throws {
        let envelope = try SyncEnvelopeCoder.encode(workout, kind: .completedWorkout)
        let data = try JSONEncoder().encode(envelope)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workout-\(workout.id).json")
        try data.write(to: url)
        session.transferFile(url, metadata: nil)

        if session.isReachable, data.count < 48_000 {
            session.sendMessage(
                [LiveSyncKeys.completedWorkoutData: data],
                replyHandler: nil,
                errorHandler: nil
            )
        }
    }

    public func sendTemplateDeleted(id: UUID) throws {
        let envelope = try SyncEnvelopeCoder.encode(id, kind: .templateDeleted)
        let dict = try SyncEnvelopeCoder.toDictionary(envelope)
        session.transferUserInfo(dict)
    }

    // MARK: - Live workout sync (sendMessage 양방향)

    public func sendWorkoutStarted(template: WorkoutTemplate, origin: WorkoutOrigin) {
        guard session.isReachable else { return }
        guard let data = try? JSONEncoder().encode(template) else { return }
        let msg: [String: Any] = [
            LiveSyncKeys.workoutStarted: true,
            LiveSyncKeys.templateData: data,
            LiveSyncKeys.workoutOrigin: origin.rawValue
        ]
        session.sendMessage(msg, replyHandler: nil, errorHandler: nil)
    }

    public func sendLiveState(_ state: LiveWorkoutState) {
        guard session.isReachable else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        session.sendMessage([LiveSyncKeys.liveState: data], replyHandler: nil, errorHandler: nil)
    }

    public func sendWorkoutFinished(origin: WorkoutOrigin) {
        guard session.isReachable else { return }
        session.sendMessage([
            LiveSyncKeys.workoutFinished: true,
            LiveSyncKeys.workoutOrigin: origin.rawValue
        ], replyHandler: nil, errorHandler: nil)
    }

    public func sendCommand(_ command: WorkoutCommand) {
        guard session.isReachable else { return }
        session.sendMessage([LiveSyncKeys.command: command.rawValue], replyHandler: nil, errorHandler: nil)
    }

    public func sendHeartRateRelay(_ relay: HeartRateRelay) {
        // iOS에서는 HR 릴레이 전송 불필요 (워치가 HR 센서 역할)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivitySyncCoordinator: WCSessionDelegate {

    nonisolated public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.onReachabilityChanged?(session.isReachable)
        }
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
        // WCSession은 콜백 종료 후 임시 파일을 삭제하므로 동기적으로 읽어야 함
        let data = try? Data(contentsOf: file.fileURL)
        Task { @MainActor [weak self] in
            guard let data else { return }
            self?.handleFileData(data)
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
        let origin = parseOrigin(msg)

        // 운동 시작 알림
        if msg[LiveSyncKeys.workoutStarted] as? Bool == true,
           let data = msg[LiveSyncKeys.templateData] as? Data,
           let template = try? JSONDecoder().decode(WorkoutTemplate.self, from: data) {
            print("[Sync] workoutStarted received origin=\(origin.rawValue) template=\(template.name)")
            onWorkoutStarted?(template, origin)
            return
        }
        // 실시간 상태
        if let data = msg[LiveSyncKeys.liveState] as? Data,
           let state = try? JSONDecoder().decode(LiveWorkoutState.self, from: data) {
            print("[Sync] liveState received origin=\(state.origin.rawValue) label=\(state.segmentLabel) finished=\(state.isFinished)")
            onLiveStateReceived?(state)
            return
        }
        // 운동 종료
        if msg[LiveSyncKeys.workoutFinished] as? Bool == true {
            onWorkoutFinished?(origin)
            return
        }
        // 원격 명령 (워치 → 폰)
        if let cmdRaw = msg[LiveSyncKeys.command] as? String,
           let cmd = WorkoutCommand(rawValue: cmdRaw) {
            onReceiveCommand?(cmd)
            return
        }
        // HR 릴레이 (워치 → 폰)
        if let data = msg[LiveSyncKeys.heartRateRelay] as? Data,
           let relay = try? JSONDecoder().decode(HeartRateRelay.self, from: data) {
            onHeartRateRelayReceived?(relay)
            return
        }
        // 완료 워크아웃 즉시 동기화 (워치 → 폰, reachable 시 fast path)
        if let data = msg[LiveSyncKeys.completedWorkoutData] as? Data {
            do {
                let envelope = try JSONDecoder().decode(SyncEnvelope.self, from: data)
                let workout = try SyncEnvelopeCoder.decodeCompletedWorkout(envelope)
                try persistence.upsertCompletedWorkout(workout)
                onReceiveCompletedWorkout?(workout)
            } catch {
                print("[Sync] completedWorkoutData decode/save failed: \(error)")
            }
            return
        }
    }

    private func parseOrigin(_ msg: [String: Any]) -> WorkoutOrigin {
        if let raw = msg[LiveSyncKeys.workoutOrigin] as? String,
           let origin = WorkoutOrigin(rawValue: raw) {
            return origin
        }
        return .watch // 하위 호환: origin 없으면 워치
    }

    @MainActor
    private func handleFileData(_ data: Data) {
        do {
            let envelope = try JSONDecoder().decode(SyncEnvelope.self, from: data)
            let workout = try SyncEnvelopeCoder.decodeCompletedWorkout(envelope)
            try persistence.upsertCompletedWorkout(workout)
            onReceiveCompletedWorkout?(workout)
        } catch {
            print("[Sync] Receive file failed: \(error)")
        }
    }
}
