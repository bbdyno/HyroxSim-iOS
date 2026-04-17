//
//  ActiveWorkoutViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import ActivityKit
import Foundation
import Observation
import HyroxCore
import HyroxLiveActivityApple
import HyroxPersistenceApple

@Observable
@MainActor
public final class ActiveWorkoutViewModel {

    // MARK: - Public state (UI binding)
    public private(set) var segmentLabel: String = ""
    public private(set) var segmentSubLabel: String?
    public private(set) var currentDisplayTitle: String = ""
    public private(set) var nextDisplayTitle: String?
    public private(set) var segmentElapsedText: String = "00:00"
    public private(set) var totalElapsedText: String = "0:00:00"
    public private(set) var paceText: String = "—"
    public private(set) var distanceText: String = "0 m"
    public private(set) var heartRateText: String = "—"
    public private(set) var heartRateZone: HeartRateZone?
    public private(set) var goalText: String = "—"
    public private(set) var goalDeltaText: String = "—"
    public private(set) var isOverGoal: Bool = false
    public private(set) var stationNameText: String?
    public private(set) var stationTargetText: String?
    public private(set) var accentKind: AccentKind = .run
    public private(set) var isPaused: Bool = false
    public private(set) var isFinished: Bool = false
    public private(set) var isLastSegment: Bool = false
    public private(set) var gpsStatus: GPSStatus = .searching

    public enum AccentKind { case run, roxZone, station }

    /// GPS signal quality based on horizontalAccuracy of most recent sample
    public enum GPSStatus: Hashable {
        case off          // station segment, GPS not tracked
        case searching    // no samples yet
        case weak         // accuracy > 20m
        case fair         // accuracy 10-20m
        case strong       // accuracy < 10m
    }

    // MARK: - Dependencies
    private let engine: WorkoutEngine
    private let locationStream: any LocationStreaming
    private let heartRateStream: any HeartRateStreaming
    private let persistence: PersistenceController
    private let syncCoordinator: (any SyncCoordinator)?
    private let maxHeartRate: Int

    // MARK: - Internal
    private var displayTimer: Timer?
    private var locationTask: Task<Void, Never>?
    private var heartRateTask: Task<Void, Never>?
    private var lastKnownBpm: Int?
    private var liveActivity: Activity<WorkoutActivityAttributes>?
    private var alertedGoalSegmentId: UUID?

    // MARK: - Callbacks
    public var errorHandler: ((Error) -> Void)?
    public var finishHandler: ((CompletedWorkout) -> Void)?
    public var cancelHandler: (() -> Void)?
    public var goalAlertHandler: (() -> Void)?

    public init(
        template: WorkoutTemplate,
        locationStream: any LocationStreaming,
        heartRateStream: any HeartRateStreaming,
        persistence: PersistenceController,
        maxHeartRate: Int = 190,
        syncCoordinator: (any SyncCoordinator)? = nil
    ) {
        self.engine = WorkoutEngine(template: template)
        self.locationStream = locationStream
        self.heartRateStream = heartRateStream
        self.persistence = persistence
        self.maxHeartRate = maxHeartRate
        self.syncCoordinator = syncCoordinator
    }

    // MARK: - Lifecycle

    public func start() async {
        do {
            try engine.start(at: Date())
            try await locationStream.start()
            try await heartRateStream.start()
            locationTask = engine.attachLocationStream(locationStream)
            heartRateTask = engine.attachHeartRateStream(heartRateStream)
            startDisplayTimer()
            startLiveActivity()
            setupSyncCallbacks()
            syncCoordinator?.sendWorkoutStarted(template: engine.template, origin: .phone)
            refresh()
        } catch {
            errorHandler?(error)
        }
    }

    public func advance() {
        do {
            try engine.advance(at: Date())
            refresh()
            if engine.isFinished {
                Task { await finishAndSave() }
            }
        } catch { errorHandler?(error) }
    }

    public func undo() {
        do {
            try engine.undo(at: Date())
            refresh()
        } catch { errorHandler?(error) }
    }

    public func togglePause() {
        do {
            if isPaused {
                try engine.resume(at: Date())
            } else {
                try engine.pause(at: Date())
            }
            isPaused = !isPaused
            refresh()
        } catch { errorHandler?(error) }
    }

    public func endWorkout() {
        do {
            try engine.finish(at: Date())
            Task { await finishAndSave() }
        } catch { errorHandler?(error) }
    }

    public func cancelWorkout() {
        cleanup()
        cancelHandler?()
    }

    // MARK: - Sync (워치 양방향 연동)

    private func setupSyncCallbacks() {
        syncCoordinator?.onReceiveCommand = { [weak self] cmd in
            self?.handleRemoteCommand(cmd)
        }
        syncCoordinator?.onHeartRateRelayReceived = { [weak self] relay in
            self?.handleHeartRateRelay(relay)
        }
    }

    private func handleRemoteCommand(_ cmd: WorkoutCommand) {
        switch cmd {
        case .advance: advance()
        case .pause: if !isPaused { togglePause() }
        case .resume: if isPaused { togglePause() }
        case .end: endWorkout()
        }
    }

    private func handleHeartRateRelay(_ relay: HeartRateRelay) {
        let sample = HeartRateSample(timestamp: relay.timestamp, bpm: relay.bpm)
        engine.ingest(heartRateSample: sample)
    }

    private func broadcastLiveState() {
        guard let syncCoordinator else { return }
        let accentRaw: String = switch accentKind {
        case .run: "run"
        case .roxZone: "roxZone"
        case .station: "station"
        }
        let gpsStrong = gpsStatus == .strong
        let gpsActive = gpsStatus != .off
        let state = LiveWorkoutState(
            segmentLabel: segmentLabel, segmentSubLabel: segmentSubLabel,
            currentDisplayTitle: currentDisplayTitle, nextDisplayTitle: nextDisplayTitle,
            segmentElapsedText: segmentElapsedText, totalElapsedText: totalElapsedText,
            paceText: paceText, distanceText: distanceText,
            heartRateText: heartRateText, heartRateZoneRaw: heartRateZone?.rawValue,
            goalText: goalText, goalDeltaText: goalDeltaText, isOverGoal: isOverGoal,
            stationNameText: stationNameText, stationTargetText: stationTargetText,
            accentKindRaw: accentRaw, isPaused: isPaused, isFinished: isFinished, isLastSegment: isLastSegment,
            gpsStrong: gpsStrong, gpsActive: gpsActive,
            templateName: engine.template.name,
            totalSegmentCount: engine.template.segments.count,
            currentSegmentIndex: engine.currentSegmentIndex ?? 0,
            origin: .phone
        )
        syncCoordinator.sendLiveState(state)
    }

    // MARK: - Refresh

    func refresh() {
        let now = Date()
        let segElapsed = engine.segmentElapsed(at: now)
        let totalElapsed = engine.totalElapsed(at: now)
        segmentElapsedText = DurationFormatter.ms(segElapsed)
        totalElapsedText = DurationFormatter.hms(totalElapsed)

        guard let current = engine.currentSegment, let index = engine.currentSegmentIndex else {
            isFinished = engine.isFinished
            currentDisplayTitle = ""
            nextDisplayTitle = nil
            isOverGoal = false
            return
        }

        let total = engine.template.segments.count
        let live = engine.liveMeasurementsSnapshot
        currentDisplayTitle = displayTitle(for: current, at: index)
        nextDisplayTitle = nextDisplayTitle(after: index, currentType: current.type)

        // Delta calculation: Run/Rox uses combined Run+Rox goal vs cumulative elapsed.
        let goalInfo = resolveGoalAndDelta(currentIndex: index, segElapsed: segElapsed)
        goalText = goalInfo.goalText
        goalDeltaText = goalInfo.deltaText
        isOverGoal = goalInfo.isOver
        if isOverGoal, alertedGoalSegmentId != current.id {
            alertedGoalSegmentId = current.id
            goalAlertHandler?()
        }

        switch current.type {
        case .run:
            let runIndex = countOfType(.run, upTo: index + 1)
            let runTotal = countOfType(.run, upTo: total)
            segmentLabel = "RUN \(runIndex) / \(runTotal)"
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
            let stationIndex = countOfType(.station, upTo: index + 1)
            let stationTotal = countOfType(.station, upTo: total)
            segmentLabel = "STATION \(stationIndex) / \(stationTotal)"
            segmentSubLabel = current.stationKind?.displayName ?? "Station"
            accentKind = .station
            stationNameText = current.stationKind?.displayName
            stationTargetText = current.stationTarget?.formatted
            paceText = "—"
            distanceText = "—"
        }

        // Heart rate — persist across segments (don't reset on advance)
        // liveMeasurements buffer clears on advance, so we keep the last known value
        if let lastHR = live.heartRateSamples.last {
            lastKnownBpm = lastHR.bpm
        }
        if let bpm = lastKnownBpm {
            heartRateText = "\(bpm)"
            heartRateZone = HeartRateZone.zone(forHeartRate: bpm, maxHeartRate: maxHeartRate)
        } else {
            heartRateText = "—"
            heartRateZone = nil
        }

        // GPS status from latest location sample accuracy
        if current.type == .station {
            gpsStatus = .off
        } else if let lastLoc = live.locationSamples.last {
            let acc = lastLoc.horizontalAccuracy
            if acc < 10 { gpsStatus = .strong }
            else if acc < 20 { gpsStatus = .fair }
            else { gpsStatus = .weak }
        } else {
            gpsStatus = .searching
        }

        isFinished = engine.isFinished
        isLastSegment = engine.isLastSegment

        updateLiveActivity()
        broadcastLiveState()
    }

    /// For Run/Rox: delta is computed against combined Run+Rox goal.
    /// Run segment: goal = Run+Rox combined, delta = segElapsed vs goal.
    /// Rox segment: goal = Run+Rox combined, delta = (prevRunElapsed + roxElapsed) vs goal.
    /// Station: standard per-segment delta.
    private func resolveGoalAndDelta(
        currentIndex: Int, segElapsed: TimeInterval
    ) -> (goalText: String, deltaText: String, isOver: Bool) {
        let current = engine.template.segments[currentIndex]

        switch current.type {
        case .run:
            // Run goal already contains Run+Rox combined
            guard let goal = current.goalDurationSeconds, goal > 0 else {
                return ("—", "—", false)
            }
            let delta = segElapsed - goal
            return (DurationFormatter.ms(goal), DurationFormatter.signedMs(delta), delta >= 0)

        case .roxZone:
            // Rox delta = (prevRun actual + rox elapsed) vs combined Run+Rox goal
            if let prevRecord = findPrecedingRunRecord(before: currentIndex) {
                let combinedGoal = engine.template.segments[prevRecord.index].goalDurationSeconds ?? 0
                guard combinedGoal > 0 else { return ("—", "—", false) }

                let combinedActual = prevRecord.activeDuration + segElapsed
                let delta = combinedActual - combinedGoal
                return (DurationFormatter.ms(combinedGoal), DurationFormatter.signedMs(delta), delta >= 0)
            }
            return ("—", "—", false)

        case .station:
            guard let goal = current.goalDurationSeconds, goal > 0 else {
                return ("—", "—", false)
            }
            let delta = segElapsed - goal
            return (DurationFormatter.ms(goal), DurationFormatter.signedMs(delta), delta >= 0)
        }
    }

    private func findPrecedingRunRecord(before index: Int) -> SegmentRecord? {
        // Look backward through completed records for the most recent run
        for record in engine.records.reversed() {
            if record.type == .run && record.index < index { return record }
        }
        return nil
    }

    private func countOfType(_ type: SegmentType, upTo end: Int) -> Int {
        engine.template.segments[..<end].filter { $0.type == type }.count
    }

    private func displayTitle(for segment: WorkoutSegment, at index: Int) -> String {
        switch segment.type {
        case .run:
            return "RUNNING \(countOfType(.run, upTo: index + 1))"
        case .roxZone:
            return "ROX ZONE"
        case .station:
            return segment.stationKind?.displayName ?? "Station"
        }
    }

    private func nextDisplayTitle(after currentIndex: Int, currentType: SegmentType) -> String? {
        if engine.template.usesRoxZone {
            guard currentType == .roxZone else { return nil }
        } else {
            guard currentType == .run else { return nil }
        }
        let nextIndex = currentIndex + 1
        guard engine.template.segments.indices.contains(nextIndex) else { return nil }
        let nextSegment = engine.template.segments[nextIndex]
        return displayTitle(for: nextSegment, at: nextIndex)
    }

    // MARK: - Timer

    private func startDisplayTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Finish

    private func finishAndSave() async {
        cleanup()
        do {
            let completed = try engine.makeCompletedWorkout()
            try persistence.saveCompletedWorkout(completed)
            syncCoordinator?.sendWorkoutFinished(origin: .phone)
            isFinished = true
            finishHandler?(completed)
        } catch {
            errorHandler?(error)
        }
    }

    private func cleanup() {
        stopDisplayTimer()
        endLiveActivity()
        locationTask?.cancel()
        heartRateTask?.cancel()
        locationTask = nil
        heartRateTask = nil
        locationStream.stop()
        heartRateStream.stop()
        syncCoordinator?.onReceiveCommand = nil
        syncCoordinator?.onHeartRateRelayReceived = nil
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(
            templateName: engine.template.name,
            totalSegments: engine.template.segments.count
        )
        let state = makeActivityState()
        let content = ActivityContent(state: state, staleDate: nil)
        liveActivity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    private func updateLiveActivity() {
        guard let liveActivity else { return }
        let state = makeActivityState()
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await liveActivity.update(content) }
    }

    private func endLiveActivity() {
        guard let liveActivity else { return }
        let state = makeActivityState()
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await liveActivity.end(content, dismissalPolicy: .immediate) }
        self.liveActivity = nil
    }

    /// 앱 시작 시 이전 세션에서 남은 Live Activity 정리
    public static func endStaleActivities() {
        Task {
            for activity in Activity<WorkoutActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func makeActivityState() -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            segmentLabel: segmentLabel,
            segmentSubLabel: segmentSubLabel,
            segmentElapsed: segmentElapsedText,
            totalElapsed: totalElapsedText,
            heartRate: heartRateText,
            accentKind: { switch accentKind { case .run: "run"; case .roxZone: "roxZone"; case .station: "station" } }(),
            isPaused: isPaused,
            isLastSegment: isLastSegment
        )
    }
}
