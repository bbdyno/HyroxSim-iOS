//
//  TemplateGoalOverrideStore.swift
//  HyroxCore
//
//  Created by bbdyno on 4/17/26.
//

import Foundation

extension Notification.Name {
    /// Posted after a built-in preset's goal override is saved locally.
    /// Observers (e.g. watchOS HomeView/ConfirmStartView) can refresh derived UI.
    public static let hyroxTemplateGoalOverrideUpdated = Notification.Name("com.hyroxsim.templateGoalOverrideUpdated")
}

/// What the user may change on a built-in preset: per-segment goal times and the
/// ROX Zone toggle. Everything else (weights, rep/distance targets, station order)
/// is deliberately *not* stored, so a preset always renders with the current
/// `HyroxDivisionSpec` — a rulebook correction reaches users who already saved a goal.
public struct TemplateGoalOverride: Codable, Hashable, Sendable {

    public static let currentVersion = 1

    public var version: Int
    /// Goal seconds for each logical (non-ROX) segment, in template order.
    public var logicalGoalSeconds: [TimeInterval?]
    /// Goal seconds for each ROX Zone segment, in template order.
    /// Kept across a ROX OFF → ON round trip.
    public var roxGoalSeconds: [TimeInterval?]
    public var usesRoxZone: Bool
    public var updatedAt: Date

    public init(
        version: Int = TemplateGoalOverride.currentVersion,
        logicalGoalSeconds: [TimeInterval?],
        roxGoalSeconds: [TimeInterval?],
        usesRoxZone: Bool,
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.logicalGoalSeconds = logicalGoalSeconds
        self.roxGoalSeconds = roxGoalSeconds
        self.usesRoxZone = usesRoxZone
        self.updatedAt = updatedAt
    }
}

/// Stores user-defined goal overrides for built-in HYROX preset templates.
/// Keyed by `HyroxDivision` so the same override is recalled whenever that preset is opened.
/// Shared between iOS and watchOS so pace-planner goals set on the phone can be mirrored on the watch.
///
/// Only the goal delta is persisted. Earlier builds stored the whole
/// `WorkoutTemplate`, which froze the weights and rep counts of the build that
/// wrote it — those blobs are still readable and are converted on the fly.
@MainActor
public final class TemplateGoalOverrideStore {

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Merges the stored goal delta onto `template`, which must stay the source of
    /// truth for weights and targets. Returns `template` untouched when there is no
    /// override, or when the stored delta no longer matches the preset's shape.
    public func resolvedTemplate(from template: WorkoutTemplate) -> WorkoutTemplate {
        guard
            template.isBuiltIn,
            let division = template.division,
            let override = loadOverride(for: division)
        else {
            return template
        }

        return merged(template, with: override)
    }

    public func save(_ template: WorkoutTemplate) {
        guard template.isBuiltIn, let division = template.division else { return }

        var roxGoals = template.segments
            .filter { $0.type == .roxZone }
            .map(\.goalDurationSeconds)
        if roxGoals.isEmpty, let previous = loadOverride(for: division) {
            // ROX OFF: no ROX segments to read goals from — keep the previous ones
            // so turning the switch back on restores the user's transition times.
            roxGoals = previous.roxGoalSeconds
        }

        let override = TemplateGoalOverride(
            logicalGoalSeconds: template.logicalSegments.map(\.goalDurationSeconds),
            roxGoalSeconds: roxGoals,
            usesRoxZone: template.usesRoxZone
        )

        guard let data = try? encoder.encode(override) else { return }

        defaults.set(data, forKey: storageKey(for: division))
        NotificationCenter.default.post(
            name: .hyroxTemplateGoalOverrideUpdated,
            object: nil,
            userInfo: ["division": division.rawValue]
        )
    }

    // MARK: - Private

    private func merged(_ template: WorkoutTemplate, with override: TemplateGoalOverride) -> WorkoutTemplate {
        var logical = template.logicalSegments
        // Segment count changed (preset reshaped by an app update) → discard the override.
        guard override.logicalGoalSeconds.count == logical.count else { return template }

        for index in logical.indices {
            logical[index].goalDurationSeconds = override.logicalGoalSeconds[index]
        }

        var roxSegments = template.segments.filter { $0.type == .roxZone }
        if override.roxGoalSeconds.count == roxSegments.count {
            for index in roxSegments.indices {
                roxSegments[index].goalDurationSeconds = override.roxGoalSeconds[index]
            }
        }

        var resolved = template
        resolved.usesRoxZone = override.usesRoxZone
        resolved.segments = WorkoutTemplate.materializedSegments(
            from: logical,
            usesRoxZone: override.usesRoxZone,
            preservedRoxSegments: roxSegments
        )
        return resolved
    }

    private func loadOverride(for division: HyroxDivision) -> TemplateGoalOverride? {
        guard let data = defaults.data(forKey: storageKey(for: division)) else { return nil }

        if let override = try? decoder.decode(TemplateGoalOverride.self, from: data) {
            return override
        }

        // Legacy format: the full preset template. Convert to a delta in memory —
        // the stored blob is rewritten in the new format on the next `save`.
        if let legacy = try? decoder.decode(WorkoutTemplate.self, from: data) {
            return TemplateGoalOverride(
                logicalGoalSeconds: legacy.logicalSegments.map(\.goalDurationSeconds),
                roxGoalSeconds: legacy.segments.filter { $0.type == .roxZone }.map(\.goalDurationSeconds),
                usesRoxZone: legacy.usesRoxZone,
                updatedAt: legacy.createdAt
            )
        }

        return nil
    }

    private func storageKey(for division: HyroxDivision) -> String {
        "com.hyroxsim.templateGoalOverride.\(division.rawValue)"
    }
}
