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
}
