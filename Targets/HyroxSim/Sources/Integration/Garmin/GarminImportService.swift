//
//  GarminImportService.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//

import Foundation
import HyroxCore
import HyroxPersistenceApple

/// Receives `workout.completed` envelopes from the Garmin watch and persists
/// them into the shared SwiftData store via `PersistenceController`.
///
/// Idempotency: the envelope carries a stable `id`; repeated transmissions
/// (e.g. after the watch retries due to a flaky Bluetooth link) are
/// deduplicated by `saveCompletedWorkout`'s upsert-by-id path.
///
/// `source` is tracked by `WorkoutSource.garmin` but requires the
/// `StoredWorkout` migration described in the repo handoff to persist —
/// until then the record is saved with default `source=.watch`.
public final class GarminImportService {

    private let bridge: GarminBridge
    private let makePersistence: () -> PersistenceController

    public init(
        bridge: GarminBridge = .shared,
        makePersistence: @escaping () -> PersistenceController = { PersistenceController() }
    ) {
        self.bridge = bridge
        self.makePersistence = makePersistence
    }

    public func start() {
        bridge.onMessageReceived = { [weak self] envelope in
            self?.handle(envelope: envelope)
        }
    }

    // MARK: - Handling

    func handle(envelope: [String: Any]) {
        guard let type = envelope[GarminMessageCodec.Key.type] as? String else { return }
        switch type {
        case GarminMessageCodec.MessageType.workoutCompleted:
            handleWorkoutCompleted(envelope: envelope)
        default:
            break
        }
    }

    private func handleWorkoutCompleted(envelope: [String: Any]) {
        guard let completed = GarminMessageCodec.decodeWorkoutCompleted(envelope) else {
            print("⚠️ GarminImportService: malformed workout.completed envelope")
            return
        }
        let id = (envelope[GarminMessageCodec.Key.id] as? String) ?? UUID().uuidString
        do {
            try makePersistence().saveCompletedWorkout(completed)
            bridge.sendEnvelope(
                GarminMessageCodec.makeEnvelope(
                    type: GarminMessageCodec.MessageType.ack,
                    id: id
                )
            )
        } catch {
            print("⚠️ GarminImportService: persist failed \(error.localizedDescription)")
        }
    }
}
