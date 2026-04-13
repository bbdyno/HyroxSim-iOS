import Foundation

public enum ScreenshotFixtures {
    public static let referenceDate = Date(timeIntervalSince1970: 1_775_600_000)

    public static let customTemplate = WorkoutTemplate(
        name: "Downtown Race Rehearsal",
        segments: [
            .run(distanceMeters: 1000),
            .roxZone(),
            .station(.skiErg, target: .distance(meters: 1000)),
            .run(distanceMeters: 1000),
            .roxZone(),
            .station(.sledPush, target: .distance(meters: 50), weightKg: 152, weightNote: "total")
        ],
        createdAt: referenceDate.addingTimeInterval(-259_200)
    )

    public static let summaryWorkout = CompletedWorkout(
        templateName: "HYROX Race Simulation",
        division: .menProSingle,
        startedAt: referenceDate.addingTimeInterval(-4_612),
        finishedAt: referenceDate,
        segments: [
            runRecord(index: 0, startedAtOffset: -4_612, duration: 338, distanceMeters: 1_000, heartRates: [149, 154, 158, 161], goalDuration: 345),
            roxRecord(index: 1, startedAtOffset: -4_274, duration: 24, heartRates: [159, 160], goalDuration: 25),
            stationRecord(index: 2, startedAtOffset: -4_250, duration: 236, kind: .skiErg, heartRates: [162, 166, 168], goalDuration: 240),
            runRecord(index: 3, startedAtOffset: -4_014, duration: 345, distanceMeters: 1_000, heartRates: [164, 167, 170, 172], goalDuration: 342),
            roxRecord(index: 4, startedAtOffset: -3_669, duration: 25, heartRates: [170, 171], goalDuration: 24),
            stationRecord(index: 5, startedAtOffset: -3_644, duration: 221, kind: .sledPush, heartRates: [171, 174, 176], goalDuration: 235),
            runRecord(index: 6, startedAtOffset: -3_423, duration: 351, distanceMeters: 1_000, heartRates: [168, 171, 173, 175], goalDuration: 346),
            roxRecord(index: 7, startedAtOffset: -3_072, duration: 26, heartRates: [172, 173], goalDuration: 24),
            stationRecord(index: 8, startedAtOffset: -3_046, duration: 198, kind: .burpeeBroadJumps, heartRates: [174, 178, 181], goalDuration: 210),
            runRecord(index: 9, startedAtOffset: -2_848, duration: 362, distanceMeters: 1_000, heartRates: [170, 173, 176, 178], goalDuration: 350),
            roxRecord(index: 10, startedAtOffset: -2_486, duration: 24, heartRates: [176, 177], goalDuration: 24),
            stationRecord(index: 11, startedAtOffset: -2_462, duration: 412, kind: .rowing, heartRates: [172, 175, 177], goalDuration: 390),
            runRecord(index: 12, startedAtOffset: -2_050, duration: 355, distanceMeters: 1_000, heartRates: [169, 171, 174, 176], goalDuration: 348),
            roxRecord(index: 13, startedAtOffset: -1_695, duration: 21, heartRates: [173, 174], goalDuration: 24),
            stationRecord(index: 14, startedAtOffset: -1_674, duration: 168, kind: .wallBalls, heartRates: [175, 179, 183], goalDuration: 180)
        ]
    )

    public static let liveMirrorTemplate = WorkoutTemplate(
        name: "Simulator Mirror Workout",
        segments: [
            .run(distanceMeters: 1000),
            .roxZone(),
            .station(.skiErg, target: .distance(meters: 1000))
        ]
    )

    public static let liveMirrorState = LiveWorkoutState(
        segmentLabel: "RUN 3 / 8",
        segmentSubLabel: "Strong pace",
        currentDisplayTitle: "RUNNING 3",
        nextDisplayTitle: nil,
        segmentElapsedText: "04:28",
        totalElapsedText: "0:27:41",
        paceText: "4'13\" /km",
        distanceText: "910 m",
        heartRateText: "172",
        heartRateZoneRaw: HeartRateZone.z4.rawValue,
        goalText: "05:00",
        goalDeltaText: "-0:32",
        isOverGoal: false,
        stationNameText: nil,
        stationTargetText: nil,
        accentKindRaw: "run",
        isPaused: false,
        isFinished: false,
        isLastSegment: false,
        gpsStrong: true,
        gpsActive: true,
        templateName: liveMirrorTemplate.name,
        totalSegmentCount: liveMirrorTemplate.segments.count,
        currentSegmentIndex: 0,
        origin: .watch
    )

    public static let watchSummaryWorkout = summaryWorkout

    private static func runRecord(index: Int, startedAtOffset: TimeInterval, duration: TimeInterval, distanceMeters: Double, heartRates: [Int], goalDuration: TimeInterval) -> SegmentRecord {
        let startedAt = referenceDate.addingTimeInterval(startedAtOffset)
        return SegmentRecord(
            segmentId: UUID(),
            index: index,
            type: .run,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            measurements: SegmentMeasurements(
                locationSamples: locationSamples(startedAt: startedAt, duration: duration, distanceMeters: distanceMeters),
                heartRateSamples: heartRateSamples(startedAt: startedAt, duration: duration, values: heartRates)
            ),
            plannedDistanceMeters: distanceMeters,
            goalDurationSeconds: goalDuration
        )
    }

    private static func roxRecord(index: Int, startedAtOffset: TimeInterval, duration: TimeInterval, heartRates: [Int], goalDuration: TimeInterval) -> SegmentRecord {
        let startedAt = referenceDate.addingTimeInterval(startedAtOffset)
        return SegmentRecord(
            segmentId: UUID(),
            index: index,
            type: .roxZone,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            measurements: SegmentMeasurements(
                heartRateSamples: heartRateSamples(startedAt: startedAt, duration: duration, values: heartRates)
            ),
            goalDurationSeconds: goalDuration
        )
    }

    private static func stationRecord(index: Int, startedAtOffset: TimeInterval, duration: TimeInterval, kind: StationKind, heartRates: [Int], goalDuration: TimeInterval) -> SegmentRecord {
        let startedAt = referenceDate.addingTimeInterval(startedAtOffset)
        return SegmentRecord(
            segmentId: UUID(),
            index: index,
            type: .station,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            measurements: SegmentMeasurements(
                heartRateSamples: heartRateSamples(startedAt: startedAt, duration: duration, values: heartRates)
            ),
            stationDisplayName: kind.displayName,
            goalDurationSeconds: goalDuration
        )
    }

    private static func heartRateSamples(startedAt: Date, duration: TimeInterval, values: [Int]) -> [HeartRateSample] {
        guard !values.isEmpty else { return [] }
        let step = duration / Double(values.count)
        return values.enumerated().map { index, bpm in
            HeartRateSample(timestamp: startedAt.addingTimeInterval(Double(index) * step), bpm: bpm)
        }
    }

    private static func locationSamples(startedAt: Date, duration: TimeInterval, distanceMeters: Double) -> [LocationSample] {
        let stepDistance = distanceMeters / 3
        let stepSeconds = duration / 3
        let baseLatitude = 37.5665
        let baseLongitude = 126.9780
        let delta = stepDistance / 111_111

        return [
            LocationSample(timestamp: startedAt, latitude: baseLatitude, longitude: baseLongitude, horizontalAccuracy: 5, speed: 4.0),
            LocationSample(timestamp: startedAt.addingTimeInterval(stepSeconds), latitude: baseLatitude + delta, longitude: baseLongitude, horizontalAccuracy: 5, speed: 4.1),
            LocationSample(timestamp: startedAt.addingTimeInterval(stepSeconds * 2), latitude: baseLatitude + delta * 2, longitude: baseLongitude, horizontalAccuracy: 5, speed: 4.2),
            LocationSample(timestamp: startedAt.addingTimeInterval(stepSeconds * 3), latitude: baseLatitude + delta * 3, longitude: baseLongitude, horizontalAccuracy: 5, speed: 4.0)
        ]
    }
}
