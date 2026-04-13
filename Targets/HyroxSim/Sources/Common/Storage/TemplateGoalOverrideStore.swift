//
//  TemplateGoalOverrideStore.swift
//  HyroxSim
//
//  Created by bbdyno on 4/13/26.
//

import Foundation
import HyroxCore

@MainActor
final class TemplateGoalOverrideStore {

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func resolvedTemplate(from template: WorkoutTemplate) -> WorkoutTemplate {
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

    func save(_ template: WorkoutTemplate) {
        guard
            template.isBuiltIn,
            let division = template.division,
            let data = try? encoder.encode(template)
        else {
            return
        }

        defaults.set(data, forKey: storageKey(for: division))
    }

    private func storageKey(for division: HyroxDivision) -> String {
        "com.hyroxsim.templateGoalOverride.\(division.rawValue)"
    }
}
