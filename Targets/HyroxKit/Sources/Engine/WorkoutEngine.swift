import Foundation

/// A pure state machine that manages workout progression.
///
/// All time values are injected via `Date` parameters — the engine never
/// calls `Date()` or `Date.now` internally, ensuring deterministic behavior
/// and full testability.
@MainActor
public final class WorkoutEngine {

    // MARK: - Public State

    public private(set) var template: WorkoutTemplate
    public private(set) var state: EngineState
    public private(set) var records: [SegmentRecord]

    // MARK: - Internal Bookkeeping

    /// Accumulated paused duration for the current segment
    private var currentSegmentPausedDuration: TimeInterval = 0

    /// Measurement buffer for the current in-progress segment.
    /// Flushed into the SegmentRecord on `advance` or `finish`.
    private var liveMeasurements = SegmentMeasurements()

    // MARK: - Init

    public init(template: WorkoutTemplate) {
        self.template = template
        self.state = .idle
        self.records = []
    }

    // MARK: - Queries

    /// The segment currently being executed (nil if idle or finished)
    public var currentSegment: WorkoutSegment? {
        guard let index = currentSegmentIndex else { return nil }
        return template.segments[index]
    }

    /// Index of the current segment (nil if idle or finished)
    public var currentSegmentIndex: Int? {
        switch state {
        case .running(let index, _, _): return index
        case .paused(let index, _, _): return index
        case .idle, .finished: return nil
        }
    }

    /// The next segment after the current one (nil if at last or not running)
    public var nextSegment: WorkoutSegment? {
        guard let index = currentSegmentIndex,
              index + 1 < template.segments.count else { return nil }
        return template.segments[index + 1]
    }

    /// Whether the current segment is the last one in the template
    public var isLastSegment: Bool {
        guard let index = currentSegmentIndex else { return false }
        return index == template.segments.count - 1
    }

    /// Whether the workout has finished
    public var isFinished: Bool {
        if case .finished = state { return true }
        return false
    }

    /// Elapsed time for the current segment
    public func segmentElapsed(at now: Date) -> TimeInterval {
        switch state {
        case .running(_, let segmentStartedAt, _):
            return now.timeIntervalSince(segmentStartedAt)
        case .paused(_, let segmentElapsed, _):
            return segmentElapsed
        case .idle, .finished:
            return 0
        }
    }

    /// Total elapsed time for the entire workout
    public func totalElapsed(at now: Date) -> TimeInterval {
        switch state {
        case .running(_, _, let workoutStartedAt):
            return now.timeIntervalSince(workoutStartedAt)
        case .paused(_, _, let totalElapsed):
            return totalElapsed
        case .finished(let workoutStartedAt, let finishedAt):
            return finishedAt.timeIntervalSince(workoutStartedAt)
        case .idle:
            return 0
        }
    }

    // MARK: - Actions

    /// Start the workout. Only valid from `idle`.
    public func start(at now: Date) throws {
        guard case .idle = state else {
            throw EngineError.invalidTransition(from: stateLabel, action: "start")
        }
        guard !template.segments.isEmpty else {
            throw EngineError.emptyTemplate
        }
        currentSegmentPausedDuration = 0
        liveMeasurements = SegmentMeasurements()
        state = .running(currentIndex: 0, segmentStartedAt: now, workoutStartedAt: now)
    }

    /// Advance to the next segment (or finish if at the last one). Only valid from `running`.
    public func advance(at now: Date) throws {
        guard case .running(let index, let segmentStartedAt, let workoutStartedAt) = state else {
            throw EngineError.invalidTransition(from: stateLabel, action: "advance")
        }

        let segment = template.segments[index]
        let record = SegmentRecord(
            segmentId: segment.id,
            index: index,
            type: segment.type,
            startedAt: segmentStartedAt,
            endedAt: now,
            pausedDuration: currentSegmentPausedDuration,
            measurements: liveMeasurements,
            stationDisplayName: segment.stationKind?.displayName,
            plannedDistanceMeters: segment.distanceMeters
        )
        records.append(record)

        let nextIndex = index + 1
        if nextIndex < template.segments.count {
            currentSegmentPausedDuration = 0
            liveMeasurements = SegmentMeasurements()
            state = .running(currentIndex: nextIndex, segmentStartedAt: now, workoutStartedAt: workoutStartedAt)
        } else {
            // Last segment completed — finish the workout
            currentSegmentPausedDuration = 0
            liveMeasurements = SegmentMeasurements()
            state = .finished(workoutStartedAt: workoutStartedAt, finishedAt: now)
        }
    }

    /// Undo the last completed segment. Valid from `running` or `finished`.
    /// Reverts the index; does not rewind wall-clock time.
    /// Note: measurement data from the undone period is discarded (not recoverable).
    public func undo(at now: Date) throws {
        switch state {
        case .running(_, _, let workoutStartedAt):
            guard let lastRecord = records.popLast() else {
                throw EngineError.nothingToUndo
            }
            currentSegmentPausedDuration = 0
            liveMeasurements = SegmentMeasurements()
            state = .running(
                currentIndex: lastRecord.index,
                segmentStartedAt: lastRecord.startedAt,
                workoutStartedAt: workoutStartedAt
            )

        case .finished(let workoutStartedAt, _):
            guard let lastRecord = records.popLast() else {
                throw EngineError.nothingToUndo
            }
            currentSegmentPausedDuration = 0
            liveMeasurements = SegmentMeasurements()
            state = .running(
                currentIndex: lastRecord.index,
                segmentStartedAt: lastRecord.startedAt,
                workoutStartedAt: workoutStartedAt
            )

        default:
            throw EngineError.invalidTransition(from: stateLabel, action: "undo")
        }
    }

    /// Pause the workout. Only valid from `running`.
    public func pause(at now: Date) throws {
        guard case .running(let index, let segmentStartedAt, let workoutStartedAt) = state else {
            throw EngineError.invalidTransition(from: stateLabel, action: "pause")
        }
        let segElapsed = now.timeIntervalSince(segmentStartedAt)
        let totElapsed = now.timeIntervalSince(workoutStartedAt)
        state = .paused(currentIndex: index, segmentElapsed: segElapsed, totalElapsed: totElapsed)
    }

    /// Resume the workout from a paused state. Only valid from `paused`.
    ///
    /// Recalculates start timestamps by back-dating them from `now` using the
    /// frozen elapsed values. This effectively excludes paused duration from all
    /// subsequent `segmentElapsed` / `totalElapsed` calculations.
    ///
    /// Because timestamps are shifted forward, `SegmentRecord.duration` already
    /// reflects active time only — `pausedDuration` stays 0.
    public func resume(at now: Date) throws {
        guard case .paused(let index, let segElapsed, let totElapsed) = state else {
            throw EngineError.invalidTransition(from: stateLabel, action: "resume")
        }
        let segmentStartedAt = now.addingTimeInterval(-segElapsed)
        let workoutStartedAt = now.addingTimeInterval(-totElapsed)
        currentSegmentPausedDuration = 0
        state = .running(currentIndex: index, segmentStartedAt: segmentStartedAt, workoutStartedAt: workoutStartedAt)
    }

    /// Force-finish the workout. Valid from `running` or `paused`.
    public func finish(at now: Date) throws {
        switch state {
        case .running(let index, let segmentStartedAt, let workoutStartedAt):
            let segment = template.segments[index]
            let record = SegmentRecord(
                segmentId: segment.id,
                index: index,
                type: segment.type,
                startedAt: segmentStartedAt,
                endedAt: now,
                pausedDuration: currentSegmentPausedDuration,
                measurements: liveMeasurements,
                stationDisplayName: segment.stationKind?.displayName,
                plannedDistanceMeters: segment.distanceMeters
            )
            records.append(record)
            currentSegmentPausedDuration = 0
            liveMeasurements = SegmentMeasurements()
            state = .finished(workoutStartedAt: workoutStartedAt, finishedAt: now)

        case .paused(let index, let segElapsed, let totElapsed):
            let segment = template.segments[index]
            let effectiveStartedAt = now.addingTimeInterval(-segElapsed)
            let workoutStartedAt = now.addingTimeInterval(-totElapsed)
            let record = SegmentRecord(
                segmentId: segment.id,
                index: index,
                type: segment.type,
                startedAt: effectiveStartedAt,
                endedAt: now,
                pausedDuration: 0,
                measurements: liveMeasurements,
                stationDisplayName: segment.stationKind?.displayName,
                plannedDistanceMeters: segment.distanceMeters
            )
            records.append(record)
            currentSegmentPausedDuration = 0
            liveMeasurements = SegmentMeasurements()
            state = .finished(workoutStartedAt: workoutStartedAt, finishedAt: now)

        default:
            throw EngineError.invalidTransition(from: stateLabel, action: "finish")
        }
    }

    // MARK: - Sample Ingestion

    /// Adds a location sample to the current in-progress segment.
    /// Silently ignored if not in `running` state, or if the current segment
    /// does not track location (e.g., station segments).
    public func ingest(locationSample: LocationSample) {
        guard case .running = state,
              let segment = currentSegment,
              segment.type.tracksLocation else { return }
        liveMeasurements.locationSamples.append(locationSample)
    }

    /// Adds a heart rate sample to the current in-progress segment.
    /// Silently ignored if not in `running` state.
    public func ingest(heartRateSample: HeartRateSample) {
        guard case .running = state else { return }
        liveMeasurements.heartRateSamples.append(heartRateSample)
    }

    // MARK: - Live Measurements

    /// Read-only snapshot of the current in-progress segment's measurements.
    /// Returns an empty value if not in a running state.
    public var liveMeasurementsSnapshot: SegmentMeasurements {
        liveMeasurements
    }

    // MARK: - CompletedWorkout

    /// Creates a `CompletedWorkout` from the engine's finished state.
    /// - Throws: `EngineError.invalidTransition` if the engine is not finished.
    public func makeCompletedWorkout() throws -> CompletedWorkout {
        guard case .finished(let workoutStartedAt, let finishedAt) = state else {
            throw EngineError.invalidTransition(from: stateLabel, action: "makeCompletedWorkout")
        }
        return CompletedWorkout(
            templateName: template.name,
            division: template.division,
            startedAt: workoutStartedAt,
            finishedAt: finishedAt,
            segments: records
        )
    }

    // MARK: - Private

    private var stateLabel: String {
        switch state {
        case .idle: return "idle"
        case .running: return "running"
        case .paused: return "paused"
        case .finished: return "finished"
        }
    }
}
