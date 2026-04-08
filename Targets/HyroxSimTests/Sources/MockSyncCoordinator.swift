//
//  MockSyncCoordinator.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/8/26.
//

import Foundation
@testable import HyroxKit

@MainActor
final class MockSyncCoordinator: SyncCoordinator {
    var isSupported: Bool = true
    var isPaired: Bool = true
    var isReachable: Bool = true

    func activate() {}

    // MARK: - Sent message tracking

    var sentTemplates: [WorkoutTemplate] = []
    var sentCompletedWorkouts: [CompletedWorkout] = []
    var sentDeletedIds: [UUID] = []
    var sentWorkoutStarted: [(template: WorkoutTemplate, origin: WorkoutOrigin)] = []
    var sentLiveStates: [LiveWorkoutState] = []
    var sentWorkoutFinished: [WorkoutOrigin] = []
    var sentCommands: [WorkoutCommand] = []
    var sentHeartRateRelays: [HeartRateRelay] = []

    // MARK: - Background sync

    func sendTemplate(_ template: WorkoutTemplate) throws {
        sentTemplates.append(template)
    }

    func sendCompletedWorkout(_ workout: CompletedWorkout) throws {
        sentCompletedWorkouts.append(workout)
    }

    func sendTemplateDeleted(id: UUID) throws {
        sentDeletedIds.append(id)
    }

    // MARK: - Live workout sync

    func sendWorkoutStarted(template: WorkoutTemplate, origin: WorkoutOrigin) {
        sentWorkoutStarted.append((template, origin))
    }

    func sendLiveState(_ state: LiveWorkoutState) {
        sentLiveStates.append(state)
    }

    func sendWorkoutFinished(origin: WorkoutOrigin) {
        sentWorkoutFinished.append(origin)
    }

    func sendCommand(_ command: WorkoutCommand) {
        sentCommands.append(command)
    }

    func sendHeartRateRelay(_ relay: HeartRateRelay) {
        sentHeartRateRelays.append(relay)
    }

    // MARK: - Callbacks

    var onReceiveTemplate: ((WorkoutTemplate) -> Void)?
    var onReceiveCompletedWorkout: ((CompletedWorkout) -> Void)?
    var onReceiveTemplateDeleted: ((UUID) -> Void)?
    var onWorkoutStarted: ((WorkoutTemplate, WorkoutOrigin) -> Void)?
    var onLiveStateReceived: ((LiveWorkoutState) -> Void)?
    var onWorkoutFinished: ((WorkoutOrigin) -> Void)?
    var onReceiveCommand: ((WorkoutCommand) -> Void)?
    var onHeartRateRelayReceived: ((HeartRateRelay) -> Void)?
    var onReachabilityChanged: ((Bool) -> Void)?
}
