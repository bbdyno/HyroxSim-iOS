//
//  WatchActiveWorkoutModel.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import Observation
import HyroxKit

/// Watch-specific workout model. Similar to iOS ActiveWorkoutViewModel but uses
/// WatchWorkoutSession (HKWorkoutSession host) for heart rate and CoreLocationAdapter for GPS.
/// Code overlap with iOS is intentional — shared refresh logic could be extracted to HyroxKit later.
@Observable
@MainActor
final class WatchActiveWorkoutModel {

    // MARK: - UI State
    private(set) var segmentLabel: String = ""
    private(set) var segmentSubLabel: String?
    private(set) var segmentElapsedText: String = "00:00"
    private(set) var totalElapsedText: String = "0:00:00"
    private(set) var paceText: String = "—"
    private(set) var distanceText: String = "0 m"
    private(set) var heartRateText: String = "—"
    private(set) var heartRateZone: HeartRateZone?
    private(set) var stationNameText: String?
    private(set) var stationTargetText: String?
    private(set) var accentKind: AccentKind = .run
    private(set) var isPaused: Bool = false
    private(set) var isFinished: Bool = false
    private(set) var isLastSegment: Bool = false
    private(set) var gpsStrong: Bool = false  // simple on/off for watch (compact)
    private(set) var gpsActive: Bool = true

    enum AccentKind { case run, roxZone, station }

    private var lastKnownBpm: Int?

    // MARK: - Dependencies
    private let engine: WorkoutEngine
    private let workoutSession: WatchWorkoutSession
    private let locationAdapter: CoreLocationAdapter
    private let persistence: PersistenceController
    private let syncCoordinator: (any SyncCoordinator)?
    private let maxHeartRate: Int

    private var displayTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var heartRateTask: Task<Void, Never>?

    var finishHandler: ((CompletedWorkout) -> Void)?
    var errorHandler: ((Error) -> Void)?

    init(
        template: WorkoutTemplate,
        persistence: PersistenceController,
        syncCoordinator: (any SyncCoordinator)? = nil,
        maxHeartRate: Int = 190
    ) {
        self.engine = WorkoutEngine(template: template)
        self.workoutSession = WatchWorkoutSession()
        self.locationAdapter = CoreLocationAdapter()
        self.persistence = persistence
        self.syncCoordinator = syncCoordinator
        self.maxHeartRate = maxHeartRate
    }

    /// TimelineView에서 매 틱마다 호출 — UI 갱신용
    @discardableResult
    func triggerRefresh() -> Bool {
        refresh()
        return true
    }

    // MARK: - Lifecycle

    func start() async {
        do {
            try engine.start(at: Date())
            try await workoutSession.start()
            try await locationAdapter.start()
            heartRateTask = engine.attachHeartRateStream(workoutSession)
            locationTask = engine.attachLocationStream(locationAdapter)
            startDisplayTimer()
            refresh()

            // 폰에 운동 시작 알림 + 원격 명령 수신 설정
            if let sync = syncCoordinator as? WatchConnectivitySyncCoordinator {
                sync.sendWorkoutStarted(template: engine.template)
                sync.onReceiveCommand = { [weak self] cmd in
                    self?.handleRemoteCommand(cmd)
                }
            }
        } catch {
            errorHandler?(error)
        }
    }

    /// 폰에서 보낸 원격 명령 처리
    private func handleRemoteCommand(_ cmd: WorkoutCommand) {
        switch cmd {
        case .advance: advance()
        case .pause: if !isPaused { togglePause() }
        case .resume: if isPaused { togglePause() }
        case .end: endWorkout()
        }
    }

    func advance() {
        do {
            try engine.advance(at: Date())
            refresh()
            if engine.isFinished {
                Task { await finishAndSave() }
            }
        } catch { errorHandler?(error) }
    }

    func togglePause() {
        do {
            if isPaused {
                workoutSession.resume()
                try engine.resume(at: Date())
            } else {
                workoutSession.pause()
                try engine.pause(at: Date())
            }
            isPaused.toggle()
            refresh()
        } catch { errorHandler?(error) }
    }

    func endWorkout() {
        do {
            try engine.finish(at: Date())
            Task { await finishAndSave() }
        } catch { errorHandler?(error) }
    }

    // MARK: - Refresh

    private func refresh() {
        let now = Date()
        segmentElapsedText = DurationFormatter.ms(engine.segmentElapsed(at: now))
        totalElapsedText = DurationFormatter.hms(engine.totalElapsed(at: now))

        guard let current = engine.currentSegment, let index = engine.currentSegmentIndex else {
            isFinished = engine.isFinished
            return
        }

        let live = engine.liveMeasurementsSnapshot
        let segElapsed = engine.segmentElapsed(at: now)

        switch current.type {
        case .run:
            let runIdx = engine.template.segments[..<(index + 1)].filter { $0.type == .run }.count
            let runTotal = engine.template.segments.filter { $0.type == .run }.count
            segmentLabel = "RUN \(runIdx) / \(runTotal)"
            segmentSubLabel = nil
            accentKind = .run
            distanceText = DistanceFormatter.short(live.distanceMeters)
            paceText = DurationFormatter.pace(live.averagePaceSecondsPerKm(activeDuration: segElapsed))
            stationNameText = nil
            stationTargetText = nil

        case .roxZone:
            segmentLabel = "ROX ZONE"
            if let next = engine.nextSegment, next.type == .station, let kind = next.stationKind {
                segmentSubLabel = "→ \(kind.displayName)"
            } else {
                segmentSubLabel = nil
            }
            accentKind = .roxZone
            distanceText = DistanceFormatter.short(live.distanceMeters)
            paceText = DurationFormatter.pace(live.averagePaceSecondsPerKm(activeDuration: segElapsed))
            stationNameText = nil
            stationTargetText = nil

        case .station:
            let stIdx = engine.template.segments[..<(index + 1)].filter { $0.type == .station }.count
            let stTotal = engine.template.segments.filter { $0.type == .station }.count
            segmentLabel = "STATION \(stIdx) / \(stTotal)"
            segmentSubLabel = nil
            accentKind = .station
            stationNameText = current.stationKind?.displayName
            stationTargetText = current.stationTarget?.formatted
            paceText = "—"
            distanceText = "—"
        }

        // HR persists across segments
        if let lastHR = live.heartRateSamples.last { lastKnownBpm = lastHR.bpm }
        if let bpm = lastKnownBpm {
            heartRateText = "\(bpm)"
            heartRateZone = HeartRateZone.zone(forHeartRate: bpm, maxHeartRate: maxHeartRate)
        } else {
            heartRateText = "—"
            heartRateZone = nil
        }

        // GPS status (simple for watch)
        gpsActive = current.type != .station
        if gpsActive, let lastLoc = live.locationSamples.last {
            gpsStrong = lastLoc.horizontalAccuracy < 15
        }

        isFinished = engine.isFinished
        isLastSegment = engine.isLastSegment

        // 폰에 실시간 상태 전송
        broadcastLiveState()
    }

    private func broadcastLiveState() {
        guard let sync = syncCoordinator as? WatchConnectivitySyncCoordinator else { return }
        let state = LiveWorkoutState(
            segmentLabel: segmentLabel, segmentSubLabel: segmentSubLabel,
            segmentElapsedText: segmentElapsedText, totalElapsedText: totalElapsedText,
            paceText: paceText, distanceText: distanceText,
            heartRateText: heartRateText, heartRateZoneRaw: heartRateZone?.rawValue,
            stationNameText: stationNameText, stationTargetText: stationTargetText,
            accentKindRaw: { switch accentKind { case .run: "run"; case .roxZone: "roxZone"; case .station: "station" } }(),
            isPaused: isPaused, isFinished: isFinished, isLastSegment: isLastSegment,
            gpsStrong: gpsStrong, gpsActive: gpsActive,
            templateName: engine.template.name,
            totalSegmentCount: engine.template.segments.count,
            currentSegmentIndex: engine.currentSegmentIndex ?? 0
        )
        sync.sendLiveState(state)
    }

    /// UI 갱신은 TimelineView가 담당. 이 타이머는 백그라운드 브로드캐스트 전용.
    /// TimelineView가 보이지 않을 때도 폰에 실시간 전송을 유지하기 위해 필요.
    private func startDisplayTimer() {
        displayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { self?.broadcastLiveState() }
            }
        }
    }

    private func finishAndSave() async {
        cleanup()
        workoutSession.stop()
        do {
            let completed = try engine.makeCompletedWorkout()
            try persistence.saveCompletedWorkout(completed)
            try? syncCoordinator?.sendCompletedWorkout(completed)
            (syncCoordinator as? WatchConnectivitySyncCoordinator)?.sendWorkoutFinished()
            isFinished = true
            finishHandler?(completed)
        } catch {
            errorHandler?(error)
        }
    }

    private func cleanup() {
        displayTask?.cancel()
        displayTask = nil
        locationTask?.cancel()
        heartRateTask?.cancel()
        locationAdapter.stop()
    }
}
