import Foundation

/// Errors thrown by `WorkoutEngine` for invalid state transitions
public enum EngineError: Error, Hashable, Sendable {
    /// The requested action is not valid in the current state
    case invalidTransition(from: String, action: String)
    /// The workout template has no segments
    case emptyTemplate
    /// There are no completed segments to undo
    case nothingToUndo
}
