//
//  WatchConnectivitySyncCoordinator.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import WatchConnectivity
import HyroxCore
import HyroxPersistenceApple

extension Notification.Name {
    /// Posted on the watch after a custom (non-built-in) template arrives via sync
    /// and is persisted. HomeView observes this to refresh the saved-templates list.
    public static let hyroxCustomTemplatesUpdated = Notification.Name("com.hyroxsim.customTemplatesUpdated")

    /// Posted on the watch after a completed workout arrives via sync and is persisted.
    /// WatchHistoryView observes this to refresh its list in real time.
    public static let hyroxCompletedWorkoutsUpdated = Notification.Name("com.hyroxsim.completedWorkoutsUpdated")

    /// Posted on the watch after a race target arrives from the phone and is persisted.
    /// HomeView observes this to refresh its D-day strip.
    public static let hyroxRaceTargetUpdated = Notification.Name("com.hyroxsim.raceTargetUpdated")
}

/// watchOS-side WatchConnectivity sync coordinator.
/// 양방향 실시간 운동 동기화 + 템플릿/워크아웃 백그라운드 동기화.
@MainActor
public final class WatchConnectivitySyncCoordinator: NSObject, SyncCoordinator, @unchecked Sendable {
    private let session: WCSession
    private let persistence: PersistenceController
    private let goalOverrideStore = TemplateGoalOverrideStore()

    // MARK: - Background sync callbacks
    public var onReceiveTemplate: ((WorkoutTemplate) -> Void)?
    public var onReceiveCompletedWorkout: ((CompletedWorkout) -> Void)?
    public var onReceiveTemplateDeleted: ((UUID) -> Void)?
    public var onReceiveCompletedWorkoutDeleted: ((UUID) -> Void)?
    public var onReceiveRaceTarget: ((RaceTarget) -> Void)?

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

        // 워치 히스토리에서 스와이프 삭제해도 화면 코드 수정 없이 폰까지 전파되도록
        // persistence 삭제 알림을 구독한다.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocalCompletedWorkoutDeleted(_:)),
            name: .hyroxCompletedWorkoutDeleted,
            object: nil
        )
    }

    public var isSupported: Bool { WCSession.isSupported() }
    public var isPaired: Bool { true } // Always true from watch perspective
    public var isReachable: Bool { session.isReachable }

    public func activate() {
        guard isSupported else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Background sync (transferUserInfo / transferFile)

    /// Watch doesn't create templates — noop.
    public func sendTemplate(_ template: WorkoutTemplate) throws {}

    public func sendCompletedWorkout(_ workout: CompletedWorkout) throws {
        let envelope = try SyncEnvelopeCoder.encode(workout, kind: .completedWorkout)
        let data = try JSONEncoder().encode(envelope)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workout-\(workout.id).json")
        try data.write(to: url)
        session.transferFile(url, metadata: nil)

        // 빠른 경로: reachable + 페이로드 작으면 sendMessage 로 즉시 전송. 실패해도 transferFile 이 대체.
        // WCSession sendMessage 신뢰 상한 ~65kB. 여유있게 48kB 컷.
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

    /// 기록 삭제를 폰에 알린다. 폰은 tombstone을 남겨 되살리지 않는다.
    public func sendCompletedWorkoutDeleted(id: UUID) throws {
        let envelope = try SyncEnvelopeCoder.encode(id, kind: .completedWorkoutDeleted)
        let dict = try SyncEnvelopeCoder.toDictionary(envelope)
        session.transferUserInfo(dict)
    }

    @objc private func handleLocalCompletedWorkoutDeleted(_ note: Notification) {
        guard
            isSupported,
            session.activationState == .activated,
            let id = note.userInfo?[PersistenceController.deletedWorkoutIdKey] as? UUID
        else { return }
        try? sendCompletedWorkoutDeleted(id: id)
    }

    /// 워치에 저장된 모든 완료 워크아웃을 폰으로 전송 (기존 히스토리 동기화).
    /// 사용자가 지운 기록(tombstone)은 제외 — 재전송이 삭제를 되돌리면 안 된다.
    public func syncAllCompletedWorkouts() {
        guard let workouts = try? persistence.fetchAllCompletedWorkouts() else { return }
        let deletedIds = persistence.deletedCompletedWorkoutIds()
        for workout in workouts where !deletedIds.contains(workout.id) {
            try? sendCompletedWorkout(workout)
        }
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
        guard session.isReachable else { return }
        guard let data = try? JSONEncoder().encode(relay) else { return }
        session.sendMessage([LiveSyncKeys.heartRateRelay: data], replyHandler: nil, errorHandler: nil)
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

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.onReachabilityChanged?(session.isReachable)
        }
    }

    /// 폰에서 보낸 실시간 메시지 수신 (양방향)
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
                // 빌트인 프리셋은 코드에서 제공하므로 persistence에 저장하지 않고
                // 사용자 goal override만 division 키로 따로 기록한다.
                if t.isBuiltIn {
                    goalOverrideStore.save(t)
                } else {
                    try persistence.upsertTemplate(t)
                    NotificationCenter.default.post(name: .hyroxCustomTemplatesUpdated, object: nil)
                }
                onReceiveTemplate?(t)
            case .completedWorkout:
                let w = try SyncEnvelopeCoder.decodeCompletedWorkout(envelope)
                guard try persistence.upsertCompletedWorkout(w) else { return } // 삭제된 기록
                NotificationCenter.default.post(name: .hyroxCompletedWorkoutsUpdated, object: nil)
                onReceiveCompletedWorkout?(w)
            case .templateDeleted:
                let id = try SyncEnvelopeCoder.decodeDeletedId(envelope)
                try? persistence.deleteTemplate(id: id)
                NotificationCenter.default.post(name: .hyroxCustomTemplatesUpdated, object: nil)
                onReceiveTemplateDeleted?(id)
            case .completedWorkoutDeleted:
                let id = try SyncEnvelopeCoder.decodeDeletedId(envelope)
                let removed = (try? persistence.applyRemoteCompletedWorkoutDeletion(
                    id: id,
                    deletedAt: envelope.createdAt
                )) ?? false
                if removed {
                    NotificationCenter.default.post(name: .hyroxCompletedWorkoutsUpdated, object: nil)
                }
                onReceiveCompletedWorkoutDeleted?(id)
            case .raceTarget:
                // 폰이 유일한 편집 주체다. 워치는 받아서 보여 주기만 한다.
                let target = try SyncEnvelopeCoder.decodeRaceTarget(envelope)
                try persistence.upsertRaceTarget(target)
                NotificationCenter.default.post(name: .hyroxRaceTargetUpdated, object: nil)
                onReceiveRaceTarget?(target)
            case .unrecognized:
                break // 신버전이 보낸 모르는 종류 — 무시
            }
        } catch {
            print("[Sync] Receive dict failed: \(error)")
        }
    }

    @MainActor
    private func handleLiveMessage(_ msg: [String: Any]) {
        let origin = parseOrigin(msg)

        // 템플릿 즉시 동기화 (폰 → 워치, reachable 시 fast path)
        if let data = msg[LiveSyncKeys.templateSync] as? Data,
           let template = try? JSONDecoder().decode(WorkoutTemplate.self, from: data) {
            if template.isBuiltIn {
                goalOverrideStore.save(template)
            } else {
                try? persistence.upsertTemplate(template)
                NotificationCenter.default.post(name: .hyroxCustomTemplatesUpdated, object: nil)
            }
            onReceiveTemplate?(template)
            return
        }

        // 완료 워크아웃 즉시 동기화 (폰 → 워치, reachable 시 fast path)
        if let data = msg[LiveSyncKeys.completedWorkoutData] as? Data {
            do {
                let envelope = try JSONDecoder().decode(SyncEnvelope.self, from: data)
                let workout = try SyncEnvelopeCoder.decodeCompletedWorkout(envelope)
                guard try persistence.upsertCompletedWorkout(workout) else { return } // 삭제된 기록
                NotificationCenter.default.post(name: .hyroxCompletedWorkoutsUpdated, object: nil)
                onReceiveCompletedWorkout?(workout)
            } catch {
                print("[Sync] completedWorkoutData decode/save failed: \(error)")
            }
            return
        }

        // 운동 시작 알림 (폰 → 워치)
        if msg[LiveSyncKeys.workoutStarted] as? Bool == true,
           let data = msg[LiveSyncKeys.templateData] as? Data,
           let template = try? JSONDecoder().decode(WorkoutTemplate.self, from: data) {
            onWorkoutStarted?(template, origin)
            return
        }
        // 실시간 상태 (폰 → 워치)
        if let data = msg[LiveSyncKeys.liveState] as? Data,
           let state = try? JSONDecoder().decode(LiveWorkoutState.self, from: data) {
            onLiveStateReceived?(state)
            return
        }
        // 운동 종료 (폰 → 워치)
        if msg[LiveSyncKeys.workoutFinished] as? Bool == true {
            onWorkoutFinished?(origin)
            return
        }
        // 원격 명령 (폰 → 워치)
        if let cmdRaw = msg[LiveSyncKeys.command] as? String,
           let cmd = WorkoutCommand(rawValue: cmdRaw) {
            onReceiveCommand?(cmd)
            return
        }
    }

    private func parseOrigin(_ msg: [String: Any]) -> WorkoutOrigin {
        if let raw = msg[LiveSyncKeys.workoutOrigin] as? String,
           let origin = WorkoutOrigin(rawValue: raw) {
            return origin
        }
        return .phone // 하위 호환: origin 없으면 폰 (워치 관점)
    }

    @MainActor
    private func handleFileData(_ data: Data) {
        do {
            let envelope = try JSONDecoder().decode(SyncEnvelope.self, from: data)
            let workout = try SyncEnvelopeCoder.decodeCompletedWorkout(envelope)
            guard try persistence.upsertCompletedWorkout(workout) else { return } // 삭제된 기록
            NotificationCenter.default.post(name: .hyroxCompletedWorkoutsUpdated, object: nil)
            onReceiveCompletedWorkout?(workout)
        } catch {
            print("[Sync] Receive file failed: \(error)")
        }
    }
}
