import Foundation

/// Abstraction over WatchConnectivity sync.
/// Implemented by platform-specific coordinators in each app target.
/// HyroxKit does NOT import WatchConnectivity.
@MainActor
public protocol SyncCoordinator: AnyObject {
    var isSupported: Bool { get }
    var isPaired: Bool { get }
    var isReachable: Bool { get }

    func activate()

    /// Send a custom template to the counterpart (phone → watch).
    func sendTemplate(_ template: WorkoutTemplate) throws

    /// Send a completed workout to the counterpart (watch → phone).
    func sendCompletedWorkout(_ workout: CompletedWorkout) throws

    /// Notify counterpart that a template was deleted.
    func sendTemplateDeleted(id: UUID) throws

    // MARK: - Receive callbacks
    var onReceiveTemplate: ((WorkoutTemplate) -> Void)? { get set }
    var onReceiveCompletedWorkout: ((CompletedWorkout) -> Void)? { get set }
    var onReceiveTemplateDeleted: ((UUID) -> Void)? { get set }
}
