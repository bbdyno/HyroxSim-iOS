//
//  HomeViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import Observation
import HyroxKit

@Observable
@MainActor
public final class HomeViewModel {
    public private(set) var presets: [WorkoutTemplate] = []
    public private(set) var customTemplates: [WorkoutTemplate] = []
    public private(set) var recentWorkouts: [CompletedWorkout] = []

    private let persistence: PersistenceController

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public func load() {
        presets = HyroxPresets.all
        customTemplates = (try? persistence.fetchAllTemplates()) ?? []
        recentWorkouts = (try? persistence.fetchAllCompletedWorkouts()) ?? []
    }

    public var mostRecentWorkout: CompletedWorkout? { recentWorkouts.first }
}
