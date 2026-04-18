//
//  GarminMessageCodec.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//

import Foundation
import HyroxCore

/// Encodes/decodes the v1 phone-watch protocol. Mirrors
/// `HyroxSim-Garmin/source/Sync/MessageProtocol.mc` — keep in sync when
/// the shared `docs/MESSAGE_PROTOCOL.md` changes.
public enum GarminMessageCodec {

    // MARK: - Envelope keys (must match watch-side constants)

    public enum Key {
        public static let version = "v"
        public static let type = "t"
        public static let id = "id"
        public static let payload = "payload"
    }

    public enum MessageType {
        public static let hello              = "hello"
        public static let helloAck           = "hello.ack"
        public static let goalSet            = "goal.set"
        public static let workoutCompleted   = "workout.completed"
        public static let ack                = "ack"
    }

    public static let currentVersion = 1

    // MARK: - Encoding

    public static func makeEnvelope(
        type: String,
        id: String = UUID().uuidString,
        payload: [String: Any]? = nil
    ) -> [String: Any] {
        var env: [String: Any] = [
            Key.version: currentVersion,
            Key.type: type,
            Key.id: id
        ]
        if let payload { env[Key.payload] = payload }
        return env
    }

    public static func encodeGoalSet(
        division: HyroxDivision,
        templateName: String,
        targetTotalMs: Int64,
        targetSegmentsMs: [Int64]
    ) -> [String: Any] {
        makeEnvelope(
            type: MessageType.goalSet,
            payload: [
                "division": division.rawValue,
                "templateName": templateName,
                "targetTotalMs": targetTotalMs,
                "targetSegmentsMs": targetSegmentsMs
            ]
        )
    }

    // MARK: - Decoding

    /// Parses a `workout.completed` envelope into a `CompletedWorkout`.
    /// Returns nil if the payload is malformed — callers should surface
    /// a soft error rather than crash.
    public static func decodeWorkoutCompleted(_ envelope: [String: Any]) -> CompletedWorkout? {
        guard
            (envelope[Key.type] as? String) == MessageType.workoutCompleted,
            let payload = envelope[Key.payload] as? [String: Any],
            let idString = payload["id"] as? String,
            let id = UUID(uuidString: idString) ?? UUID().uuidStringStable,
            let templateName = payload["templateName"] as? String,
            let startedAtMs = payload["startedAtMs"] as? Int64,
            let finishedAtMs = payload["finishedAtMs"] as? Int64,
            let rawSegments = payload["segments"] as? [[String: Any]]
        else { return nil }

        let division = (payload["division"] as? String).flatMap(HyroxDivision.init(rawValue:))
        let segments = rawSegments.compactMap(decodeSegment(_:))

        return CompletedWorkout(
            id: id,
            templateName: templateName,
            division: division,
            startedAt: Date(timeIntervalSince1970: TimeInterval(startedAtMs) / 1000.0),
            finishedAt: Date(timeIntervalSince1970: TimeInterval(finishedAtMs) / 1000.0),
            segments: segments
        )
    }

    private static func decodeSegment(_ dict: [String: Any]) -> SegmentRecord? {
        guard
            let index = dict["index"] as? Int,
            let typeRaw = dict["type"] as? String,
            let type = SegmentType(rawValue: typeRaw),
            let startedAtMs = dict["startedAtMs"] as? Int64,
            let endedAtMs = dict["endedAtMs"] as? Int64
        else { return nil }

        let pausedMs = (dict["pausedDurationMs"] as? Int64) ?? 0
        let hrRaw = dict["heartRateSamples"] as? [[String: Any]] ?? []
        let hrSamples = hrRaw.compactMap { sample -> HeartRateSample? in
            guard let tMs = sample["tMs"] as? Int64,
                  let bpm = sample["bpm"] as? Int else { return nil }
            return HeartRateSample(
                timestamp: Date(timeIntervalSince1970: TimeInterval(tMs) / 1000.0),
                bpm: bpm
            )
        }
        let measurements = SegmentMeasurements(
            locationSamples: [],
            heartRateSamples: hrSamples
        )

        return SegmentRecord(
            id: UUID(),
            segmentId: UUID(),
            index: index,
            type: type,
            startedAt: Date(timeIntervalSince1970: TimeInterval(startedAtMs) / 1000.0),
            endedAt: Date(timeIntervalSince1970: TimeInterval(endedAtMs) / 1000.0),
            pausedDuration: TimeInterval(pausedMs) / 1000.0,
            measurements: measurements,
            stationDisplayName: dict["stationDisplayName"] as? String,
            plannedDistanceMeters: dict["plannedDistanceMeters"] as? Double,
            goalDurationSeconds: dict["goalDurationSeconds"] as? Double
        )
    }
}

private extension UUID {
    static var uuidStringStable: UUID? { UUID() }
}
