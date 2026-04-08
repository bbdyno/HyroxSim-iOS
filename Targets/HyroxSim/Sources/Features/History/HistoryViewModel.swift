//
//  HistoryViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import Observation
import HyroxCore
import HyroxPersistenceApple

@Observable
@MainActor
public final class HistoryViewModel {
    public private(set) var workouts: [CompletedWorkout] = []

    private let persistence: PersistenceController

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public func load() {
        workouts = (try? persistence.fetchAllCompletedWorkouts()) ?? []
    }

    public func delete(at index: Int) {
        guard index < workouts.count else { return }
        let workout = workouts[index]
        try? persistence.deleteCompletedWorkout(id: workout.id)
        workouts.remove(at: index)
    }
}
