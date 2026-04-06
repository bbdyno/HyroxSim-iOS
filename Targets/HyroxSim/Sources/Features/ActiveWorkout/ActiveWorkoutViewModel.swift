//
//  ActiveWorkoutViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import Observation
import HyroxKit

@Observable
@MainActor
public final class ActiveWorkoutViewModel {

    // MARK: - Public state (UI binding)
    public private(set) var segmentLabel: String = ""
    public private(set) var segmentSubLabel: String?
    public private(set) var segmentElapsedText: String = "00:00"
    public private(set) var totalElapsedText: String = "0:00:00"
    public private(set) var paceText: String = "—"
    public private(set) var distanceText: String = "0 m"
    public private(set) var heartRateText: String = "—"
    public private(set) var heartRateZone: HeartRateZone?
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
    private let maxHeartRate: Int

    // MARK: - Internal
    private var displayTimer: Timer?
    private var locationTask: Task<Void, Never>?
    private var heartRateTask: Task<Void, Never>?
    private var lastKnownBpm: Int?

    // MARK: - Callbacks
    public var errorHandler: ((Error) -> Void)?
    public var finishHandler: ((CompletedWorkout) -> Void)?
    public var cancelHandler: (() -> Void)?

    public init(
        template: WorkoutTemplate,
        locationStream: any LocationStreaming,
        heartRateStream: any HeartRateStreaming,
        persistence: PersistenceController,
        maxHeartRate: Int = 190
    ) {
        self.engine = WorkoutEngine(template: template)
        self.locationStream = locationStream
        self.heartRateStream = heartRateStream
        self.persistence = persistence
        self.maxHeartRate = maxHeartRate
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

    // MARK: - Refresh

    func refresh() {
        let now = Date()
        let segElapsed = engine.segmentElapsed(at: now)
        let totalElapsed = engine.totalElapsed(at: now)
        segmentElapsedText = DurationFormatter.ms(segElapsed)
        totalElapsedText = DurationFormatter.hms(totalElapsed)

        guard let current = engine.currentSegment, let index = engine.currentSegmentIndex else {
            isFinished = engine.isFinished
            return
        }

        let total = engine.template.segments.count
        let live = engine.liveMeasurementsSnapshot

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
            segmentSubLabel = nil
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
    }

    private func countOfType(_ type: SegmentType, upTo end: Int) -> Int {
        engine.template.segments[..<end].filter { $0.type == type }.count
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
            isFinished = true
            finishHandler?(completed)
        } catch {
            errorHandler?(error)
        }
    }

    private func cleanup() {
        stopDisplayTimer()
        locationTask?.cancel()
        heartRateTask?.cancel()
        locationTask = nil
        heartRateTask = nil
        locationStream.stop()
        heartRateStream.stop()
    }
}
