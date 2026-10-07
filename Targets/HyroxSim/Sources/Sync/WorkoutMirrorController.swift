//
//  WorkoutMirrorController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/8/26.
//

import ActivityKit
import HealthKit
import HyroxCore
import HyroxLiveActivityApple

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

    /// Live Activity 가 멈춘 채로 잠금화면에 남지 않도록 하는 stale 여유 시간.
    private static let activityStaleInterval: TimeInterval = 4 * 60

    func activate() {
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirroredSession in
            Task { @MainActor in
                self?.attachMirroredSession(mirroredSession)
            }
        }
    }

    /// 미러 운동을 외부(코디네이터의 무수신 워치독 등)에서 강제로 정리한다.
    /// `onWorkoutFinished` 는 호출하지 않는다 — 화면 정리는 호출 측이 이어서 한다.
    func abandonActiveWorkout() {
        guard hasActiveWorkout || isConnected else { return }
        mirroredSession?.delegate = nil
        mirroredSession = nil
        currentTemplate = nil
        currentState = nil
        isConnected = false
        endLiveActivity()
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
        // 미러 세션이 끊겼는데 template/state 를 붙들고 있으면 `hasActiveWorkout` 이
        // 영원히 true 로 고정되어, WatchConnectivity 로 상태가 계속 들어와도
        // 재연결 처리(`onReachabilityChanged`)가 전부 무시된다. 세션이 죽으면
        // 미러 소유권도 같이 내려놓고 WC 경로가 이어받게 한다.
        currentTemplate = nil
        currentState = nil
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

        // staleDate 를 매 업데이트마다 "현재 + 수 분"으로 갱신한다.
        // 워치/앱이 죽어 업데이트가 끊기면 시스템이 stale 로 표시해 주므로
        // 멈춘 시계가 잠금화면에 계속 살아 있는 것처럼 보이지 않는다.
        let content = ActivityContent(
            state: makeActivityState(from: state),
            staleDate: Date().addingTimeInterval(Self.activityStaleInterval)
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
