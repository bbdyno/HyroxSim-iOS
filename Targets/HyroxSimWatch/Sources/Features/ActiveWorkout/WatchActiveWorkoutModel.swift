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

    enum AccentKind { case run, roxZone, station }

    // MARK: - Dependencies
    private let engine: WorkoutEngine
    private let workoutSession: WatchWorkoutSession
    private let locationAdapter: CoreLocationAdapter
    private let persistence: PersistenceController
    private let syncCoordinator: (any SyncCoordinator)?
    private let maxHeartRate: Int

    private var displayTimer: Timer?
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
        } catch {
            errorHandler?(error)
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

        if let lastHR = live.heartRateSamples.last {
            heartRateText = "\(lastHR.bpm)"
            heartRateZone = HeartRateZone.zone(forHeartRate: lastHR.bpm, maxHeartRate: maxHeartRate)
        } else {
            heartRateText = "—"
            heartRateZone = nil
        }

        isFinished = engine.isFinished
    }

    private func startDisplayTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func finishAndSave() async {
        cleanup()
        workoutSession.stop()
        do {
            let completed = try engine.makeCompletedWorkout()
            try persistence.saveCompletedWorkout(completed)
            try? syncCoordinator?.sendCompletedWorkout(completed)
            isFinished = true
            finishHandler?(completed)
        } catch {
            errorHandler?(error)
        }
    }

    private func cleanup() {
        displayTimer?.invalidate()
        displayTimer = nil
        locationTask?.cancel()
        heartRateTask?.cancel()
        locationAdapter.stop()
    }
}
