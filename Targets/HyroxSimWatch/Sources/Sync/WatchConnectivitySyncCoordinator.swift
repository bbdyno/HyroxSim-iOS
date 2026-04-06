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
}

// MARK: - WCSessionDelegate

extension WatchConnectivitySyncCoordinator: WCSessionDelegate {

    nonisolated public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

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
