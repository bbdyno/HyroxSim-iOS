//
//  SyncCoordinatorProtocol.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

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

    // MARK: - Background sync (transferUserInfo / transferFile)

    /// Send a custom template to the counterpart (phone → watch).
    func sendTemplate(_ template: WorkoutTemplate) throws

    /// Send a completed workout to the counterpart (watch → phone).
    func sendCompletedWorkout(_ workout: CompletedWorkout) throws

    /// Notify counterpart that a template was deleted.
    func sendTemplateDeleted(id: UUID) throws

    // MARK: - Background sync callbacks
    var onReceiveTemplate: ((WorkoutTemplate) -> Void)? { get set }
    var onReceiveCompletedWorkout: ((CompletedWorkout) -> Void)? { get set }
    var onReceiveTemplateDeleted: ((UUID) -> Void)? { get set }

    // MARK: - Live workout sync (양방향 sendMessage)

    /// 상대 기기에 운동 시작 알림
    func sendWorkoutStarted(template: WorkoutTemplate, origin: WorkoutOrigin)

    /// 실시간 운동 상태 전송 (매 0.5초)
    func sendLiveState(_ state: LiveWorkoutState)

    /// 상대 기기에 운동 종료 알림
    func sendWorkoutFinished(origin: WorkoutOrigin)

    /// 상대 기기에 원격 명령 전송
    func sendCommand(_ command: WorkoutCommand)

    /// 워치 HR 릴레이 (워치 → 폰, 폰 운동 시)
    func sendHeartRateRelay(_ relay: HeartRateRelay)

    // MARK: - Live workout callbacks
    var onWorkoutStarted: ((WorkoutTemplate, WorkoutOrigin) -> Void)? { get set }
    var onLiveStateReceived: ((LiveWorkoutState) -> Void)? { get set }
    var onWorkoutFinished: ((WorkoutOrigin) -> Void)? { get set }
    var onReceiveCommand: ((WorkoutCommand) -> Void)? { get set }
    var onHeartRateRelayReceived: ((HeartRateRelay) -> Void)? { get set }

    // MARK: - Connection state
    var onReachabilityChanged: ((Bool) -> Void)? { get set }
}
