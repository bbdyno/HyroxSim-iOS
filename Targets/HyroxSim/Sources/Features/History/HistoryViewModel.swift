import Foundation
import Observation
import HyroxKit

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
