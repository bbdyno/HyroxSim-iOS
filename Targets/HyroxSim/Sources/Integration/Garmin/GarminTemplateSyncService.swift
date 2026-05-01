//
//  GarminTemplateSyncService.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//

import Foundation
import HyroxCore

/// Pushes user-built `WorkoutTemplate`s (including `usesRoxZone=false`
/// variants) to the Garmin watch's `TemplateStore`. Call after the user
/// saves/edits a template via the in-app builder — the watch persists by
/// `template.id` so repeated pushes are idempotent.
///
/// The bridge is injected so tests can pass a stub. Pairing with the watch
/// is a precondition — if `GarminBridge` reports no connected device the
/// push is silently dropped and the watch simply won't know about this
/// template until the user retries from settings.
public final class GarminTemplateSyncService {

    private let bridge: GarminBridge

    public init(bridge: GarminBridge = .shared) {
        self.bridge = bridge
    }

    public func push(_ template: WorkoutTemplate) {
        let envelope = GarminMessageCodec.encodeTemplateUpsert(template)
        bridge.sendEnvelope(envelope)
        pushGoal(for: template)
    }

    public func pushAll(_ templates: [WorkoutTemplate]) {
        for template in templates {
            push(template)
        }
    }

    public func delete(id: UUID) {
        let envelope = GarminMessageCodec.encodeTemplateDelete(id: id)
        bridge.sendEnvelope(envelope)
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
    public func pushGoal(for template: WorkoutTemplate) {
        guard let division = template.division else { return }
        let segGoalsMs: [Int64] = template.segments.map { seg in
            Int64((seg.goalDurationSeconds ?? 0) * 1000)
        }
        let totalMs = segGoalsMs.reduce(0, +)
        // All-zero goals = the user never set a target. Skip to avoid
        // overwriting a previously synced goal with a meaningless one.
        guard totalMs > 0 else { return }
        let envelope = GarminMessageCodec.encodeGoalSet(
            division: division,
            templateName: template.name,
            targetTotalMs: totalMs,
            targetSegmentsMs: segGoalsMs
        )
        bridge.sendEnvelope(envelope)
    }
}
