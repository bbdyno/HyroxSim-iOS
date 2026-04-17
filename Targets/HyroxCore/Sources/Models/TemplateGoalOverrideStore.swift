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

/// Stores user-defined goal overrides for built-in HYROX preset templates.
/// Keyed by `HyroxDivision` so the same override is recalled whenever that preset is opened.
/// Shared between iOS and watchOS so pace-planner goals set on the phone can be mirrored on the watch.
@MainActor
public final class TemplateGoalOverrideStore {

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func resolvedTemplate(from template: WorkoutTemplate) -> WorkoutTemplate {
        guard
            template.isBuiltIn,
            let division = template.division,
            let data = defaults.data(forKey: storageKey(for: division)),
            let storedTemplate = try? decoder.decode(WorkoutTemplate.self, from: data)
        else {
            return template
        }

        return storedTemplate
    }

    public func save(_ template: WorkoutTemplate) {
        guard
            template.isBuiltIn,
            let division = template.division,
            let data = try? encoder.encode(template)
        else {
            return
        }

        defaults.set(data, forKey: storageKey(for: division))
        NotificationCenter.default.post(
            name: .hyroxTemplateGoalOverrideUpdated,
            object: nil,
            userInfo: ["division": division.rawValue]
        )
    }

    private func storageKey(for division: HyroxDivision) -> String {
        "com.hyroxsim.templateGoalOverride.\(division.rawValue)"
    }
}
