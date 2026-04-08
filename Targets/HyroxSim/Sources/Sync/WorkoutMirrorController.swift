//
//  WorkoutMirrorController.swift
//  HyroxSim
//
//  Created by Codex on 4/8/26.
//

import ActivityKit
import HealthKit
import HyroxKit

/// Receives HealthKit mirrored workout sessions created on Apple Watch and
/// keeps the iPhone UI/live activity in sync with the watch-hosted workout.
@MainActor
final class WorkoutMirrorController: NSObject {

    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?
    private var liveActivity: Activity<WorkoutActivityAttributes>?

    private(set) var currentTemplate: WorkoutTemplate?
    private(set) var currentState: LiveWorkoutState?
    private(set) var isConnected = false

    var hasActiveWorkout: Bool {
        currentTemplate != nil || currentState != nil || mirroredSession != nil
    }

    var onWorkoutStarted: ((WorkoutTemplate, WorkoutOrigin) -> Void)?
    var onLiveStateReceived: ((LiveWorkoutState) -> Void)?
    var onWorkoutFinished: ((WorkoutOrigin) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    func activate() {
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirroredSession in
            Task { @MainActor in
                self?.attachMirroredSession(mirroredSession)
            }
        }
    }

    func sendCommand(_ command: WorkoutCommand) {
        guard let mirroredSession else { return }
        Task {
            do {
                let data = try LiveSyncPacketCoder.encode(.command(command))
                try await mirroredSession.sendToRemoteWorkoutSession(data: data)
            } catch {
                print("[Mirror] Failed to send command: \(error)")
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutMirrorController: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }
        Task { @MainActor [weak self] in
            self?.finishMirroredWorkout(origin: .watch)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            print("[Mirror] Mirrored workout session failed: \(error)")
            self?.handleDisconnect(error: error)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        Task { @MainActor [weak self] in
            self?.handleIncomingPackets(data)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.handleDisconnect(error: error)
        }
    }
}

// MARK: - Private

private extension WorkoutMirrorController {

    func attachMirroredSession(_ session: HKWorkoutSession) {
        mirroredSession?.delegate = nil
        mirroredSession = session
        mirroredSession?.delegate = self
        isConnected = true
        onConnectionChanged?(true)
    }

    func handleIncomingPackets(_ packets: [Data]) {
        for data in packets {
            guard let packet = try? LiveSyncPacketCoder.decode(data) else {
                print("[Mirror] Failed to decode mirrored packet")
                continue
            }
            handle(packet)
        }
    }

    func handle(_ packet: LiveSyncPacket) {
        switch packet {
        case .workoutStarted(let template, let origin):
            guard origin == .watch else { return }
            print("[Mirror] workoutStarted received from watch: \(template.name)")
            currentTemplate = template
            onWorkoutStarted?(template, origin)

        case .liveState(let state):
            guard state.origin == .watch else { return }
            print("[Mirror] liveState received from watch: \(state.segmentLabel) \(state.segmentElapsedText)")
            currentState = state
            startOrUpdateLiveActivity(with: state)
            onLiveStateReceived?(state)

        case .workoutFinished(let origin):
            guard origin == .watch else { return }
            finishMirroredWorkout(origin: origin)

        case .command, .heartRateRelay:
            break
        }
    }

    func finishMirroredWorkout(origin: WorkoutOrigin) {
        guard hasActiveWorkout else { return }
        mirroredSession?.delegate = nil
        mirroredSession = nil
        currentTemplate = nil
        currentState = nil
        isConnected = false
        endLiveActivity()
        onWorkoutFinished?(origin)
    }

    func handleDisconnect(error: Error?) {
        guard hasActiveWorkout || isConnected else { return }
        mirroredSession?.delegate = nil
        mirroredSession = nil
        isConnected = false
        endLiveActivity()
        if let error {
            print("[Mirror] Mirrored session disconnected: \(error)")
        } else {
            print("[Mirror] Mirrored session disconnected")
        }
        onConnectionChanged?(false)
    }

    func startOrUpdateLiveActivity(with state: LiveWorkoutState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = ActivityContent(
            state: makeActivityState(from: state),
            staleDate: nil
        )

        if let liveActivity {
            Task { await liveActivity.update(content) }
            return
        }

        let attributes = WorkoutActivityAttributes(
            templateName: state.templateName,
            totalSegments: state.totalSegmentCount
        )
        liveActivity = try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    func endLiveActivity() {
        guard let liveActivity else { return }
        Task { await liveActivity.end(nil, dismissalPolicy: .immediate) }
        self.liveActivity = nil
    }

    func makeActivityState(from state: LiveWorkoutState) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            segmentLabel: state.segmentLabel,
            segmentSubLabel: state.segmentSubLabel,
            segmentElapsed: state.segmentElapsedText,
            totalElapsed: state.totalElapsedText,
            heartRate: state.heartRateText,
            accentKind: state.accentKindRaw,
            isPaused: state.isPaused,
            isLastSegment: state.isLastSegment
        )
    }
}
