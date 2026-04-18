//
//  GarminGoalSyncService.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//

import Foundation
import HyroxCore

/// Pushes target times to the Garmin watch right before a workout starts.
/// The watch stores them in `Application.Storage` under `GoalStore.KEY` so
/// the delta badge is live from the first tick.
public final class GarminGoalSyncService {

    public static let shared = GarminGoalSyncService()

    private let bridge: GarminBridge

    public init(bridge: GarminBridge = .shared) {
        self.bridge = bridge
    }

    /// Sends a goal. `targetSegmentsMs` should have one entry per segment
    /// in the template (typically 31 for the HYROX preset). If the caller
    /// only has an aggregate time, pass `targetTotalMs` and let the watch
    /// fall back to its `PaceReference` split.
    public func sendGoal(
        division: HyroxDivision,
        templateName: String,
        targetTotalMs: Int64,
        targetSegmentsMs: [Int64]
    ) {
        let envelope = GarminMessageCodec.encodeGoalSet(
            division: division,
            templateName: templateName,
            targetTotalMs: targetTotalMs,
            targetSegmentsMs: targetSegmentsMs
        )
        bridge.sendEnvelope(envelope)
    }
}
