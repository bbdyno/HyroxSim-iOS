//
//  GarminMessageCodec.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//

import CryptoKit
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
        public static let syncRequest        = "sync.request"
        public static let goalSet            = "goal.set"
        public static let templateUpsert     = "template.upsert"
        public static let templateDelete     = "template.delete"
        public static let workoutCompleted   = "workout.completed"
        public static let ack                = "ack"
        /// 수신 거부. `ack` 를 보내지 않는 것만으로도 워치는 원본을 지우지
        /// 않지만, 왜 거부했는지 알려 주면 워치 로그에서 원인을 볼 수 있다.
        public static let nack               = "nack"
    }

    /// `nack` payload 의 `reason` 값.
    public enum RejectReason {
        public static let unsupportedVersion = "unsupported_version"
        public static let malformedPayload   = "malformed_payload"
        public static let malformedSegment   = "malformed_segment"
        public static let persistFailed      = "persist_failed"
    }

    public static let currentVersion = 1

    /// 우리가 처리할 수 있는 최소 버전. 이보다 낮으면 거부한다.
    public static let minimumSupportedVersion = 1

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

    /// Serialises a domain `WorkoutTemplate` into the v1 `template.upsert`
    /// payload shape expected by the watch. Keeps the wire format close to
    /// the Monkey C dictionary layout so the watch can round-trip it into
    /// `TemplateStore` without further transformation.
    public static func encodeTemplateUpsert(_ template: WorkoutTemplate) -> [String: Any] {
        // 세그먼트 딕셔너리도 payload 와 똑같이 nil 을 걷어낸다. 걷어내지 않으면
        // `Optional.none` 이 `Any` 에 담긴 채 남아 `JSONSerialization` 이
        // 거부하고, outbox 가 봉투를 저장하지 못한다.
        let segments: [[String: Any]] = template.segments.map { seg in
            let dict: [String: Any?] = [
                "id": seg.id.uuidString,
                "type": seg.type.rawValue,
                "distanceMeters": seg.distanceMeters,
                "goalDurationSeconds": seg.goalDurationSeconds,
                "stationKind": seg.stationKind.map(stationKindRaw),
                "stationTarget": seg.stationTarget.map(encodeStationTarget),
                "weightKg": seg.weightKg,
                "weightNote": seg.weightNote,
            ]
            return dict.compactMapValues { $0 }
        }
        let payload: [String: Any?] = [
            "id": template.id.uuidString,
            "name": template.name,
            "division": template.division?.rawValue,
            "segments": segments,
            "usesRoxZone": template.usesRoxZone,
            "createdAtMs": Int64(template.createdAt.timeIntervalSince1970 * 1000),
            "isBuiltIn": template.isBuiltIn,
        ]
        return makeEnvelope(
            type: MessageType.templateUpsert,
            payload: payload.compactMapValues { $0 }
        )
    }

    public static func encodeTemplateDelete(id: UUID) -> [String: Any] {
        makeEnvelope(
            type: MessageType.templateDelete,
            payload: ["id": id.uuidString]
        )
    }

    private static func stationKindRaw(_ kind: StationKind) -> String {
        switch kind {
        case .skiErg: return "skiErg"
        case .sledPush: return "sledPush"
        case .sledPull: return "sledPull"
        case .burpeeBroadJumps: return "burpeeBroadJumps"
        case .rowing: return "rowing"
        case .farmersCarry: return "farmersCarry"
        case .sandbagLunges: return "sandbagLunges"
        case .wallBalls: return "wallBalls"
        case .custom: return "custom"
        }
    }

    private static func encodeStationTarget(_ target: StationTarget) -> [String: Any] {
        switch target {
        case .distance(let meters):
            return ["kind": "distance", "meters": Int(meters)]
        case .reps(let count):
            return ["kind": "reps", "count": count]
        case .duration(let seconds):
            return ["kind": "duration", "seconds": Int(seconds)]
        case .none:
            return ["kind": "none"]
        }
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

    /// 수신 거부 봉투. `id` 는 거부하는 원본 메시지의 id 를 그대로 쓴다.
    public static func encodeReject(id: String, reason: String) -> [String: Any] {
        makeEnvelope(
            type: MessageType.nack,
            id: id,
            payload: ["reason": reason]
        )
    }

    // MARK: - Transport helpers

    /// 봉투를 JSON 으로 저장할 수 있는 형태로 정리한다.
    ///
    /// `[String: Any?]` 에서 온 `Optional.none`, `NSNull`, JSON 이 모르는 타입을
    /// 버린다. outbox 는 봉투를 디스크에 JSON 으로 남기므로 이 단계를 거치지
    /// 않으면 `JSONSerialization` 이 통째로 실패한다.
    public static func sanitizedForTransport(_ envelope: [String: Any]) -> [String: Any] {
        sanitizedDictionary(envelope)
    }

    private static func sanitizedDictionary(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            if let clean = sanitizedValue(value) { result[key] = clean }
        }
        return result
    }

    private static func sanitizedValue(_ value: Any) -> Any? {
        // `Any` 에 감싸인 Optional 을 벗겨 낸다. `Optional.none` 은 버린다.
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let unwrapped = mirror.children.first?.value else { return nil }
            return sanitizedValue(unwrapped)
        }
        switch value {
        case is NSNull:
            return nil
        case let dict as [String: Any]:
            return sanitizedDictionary(dict)
        case let array as [Any]:
            return array.compactMap(sanitizedValue)
        case let number as NSNumber:
            return number
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let int as Int64:
            return NSNumber(value: int)
        case let double as Double:
            return double.isFinite ? double : nil
        default:
            return nil
        }
    }

    /// 봉투의 payload 내용만 보고 만든 안정적인 지문.
    ///
    /// 봉투의 `id` 는 매번 새 UUID 라서 봉투 전체로는 "바뀌었는지" 를 알 수
    /// 없다. payload 를 키 정렬 JSON 으로 만든 뒤 SHA256 을 찍어, 프로세스가
    /// 바뀌어도 같은 내용이면 같은 값이 나오게 한다(`Hasher` 는 실행마다
    /// 시드가 달라 쓸 수 없다).
    public static func payloadFingerprint(of envelope: [String: Any]) -> String? {
        let safe = sanitizedForTransport(envelope)
        let subject = safe[Key.payload] ?? safe
        guard
            JSONSerialization.isValidJSONObject(subject),
            let data = try? JSONSerialization.data(withJSONObject: subject, options: [.sortedKeys])
        else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `(기록 id, 인덱스)` 로부터 늘 같은 UUID 를 만든다.
    ///
    /// 워치가 같은 기록을 두 번 보내도 세그먼트 id 가 매번 달라지면
    /// `StoredSegment.id` 의 unique 제약을 우회해 중복 행이 쌓인다.
    /// 해시 기반이라 기록 id 와 인덱스가 같으면 결과도 같다.
    public static func stableSegmentId(workoutId: UUID, index: Int, salt: String) -> UUID {
        let seed = "\(workoutId.uuidString):\(salt):\(index)"
        var bytes = [UInt8](SHA256.hash(data: Data(seed.utf8)).prefix(16))
        // RFC 4122 형식만 맞춘다 — 값 자체는 결정적이다.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - Decoding

    /// ConnectIQ 는 숫자를 NSNumber 로 넘기고, 테스트나 다른 경로는 Swift `Int`/`Double` 로 넘긴다.
    /// `as? Int64` 로만 받으면 타입이 조금만 달라도 기록 전체가 버려지므로 폭넓게 받는다.
    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let v as Int64: return v
        case let v as Int: return Int64(v)
        case let v as NSNumber: return v.int64Value
        case let v as Double where v.isFinite: return Int64(v)
        case let v as String: return Int64(v)
        default: return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        int64(value).flatMap { Int(exactly: $0) }
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let v as Double where v.isFinite: return v
        case let v as NSNumber where v.doubleValue.isFinite: return v.doubleValue
        case let v as String: return Double(v).flatMap { $0.isFinite ? $0 : nil }
        default: return nil
        }
    }

    /// `decodeWorkoutCompletedStrict` 가 거부한 이유. 그대로 `nack` 의 reason 이 된다.
    public enum DecodeFailure: String, Error, Sendable, Equatable {
        /// 봉투의 `v` 가 없거나 우리가 모르는 버전이다.
        case unsupportedVersion
        /// 타입이 다르거나 필수 필드가 빠졌다.
        case malformedPayload
        /// 세그먼트 하나 이상을 해석하지 못했다. 일부만 저장하면 기록이
        /// 조용히 망가지므로 통째로 거부한다.
        case malformedSegment

        public var rejectReason: String {
            switch self {
            case .unsupportedVersion: return RejectReason.unsupportedVersion
            case .malformedPayload: return RejectReason.malformedPayload
            case .malformedSegment: return RejectReason.malformedSegment
            }
        }
    }

    /// 봉투의 프로토콜 버전을 확인한다.
    public static func isSupportedVersion(_ envelope: [String: Any]) -> Bool {
        guard let version = int(envelope[Key.version]) else { return false }
        return version >= minimumSupportedVersion && version <= currentVersion
    }

    /// `workout.completed` 봉투를 `CompletedWorkout` 으로 해석한다.
    ///
    /// 버전과 세그먼트를 엄격히 검사하고 실패 이유를 돌려준다. 호출자는 그
    /// 이유로 `ack` 대신 `nack` 을 보낸다 — 워치는 ack 를 못 받으면 원본을
    /// 지우지 않으므로 기록이 유실되지 않는다.
    ///
    /// 세그먼트를 `compactMap` 으로 걸러 내던 예전 버전은 깨진 구간을 조용히
    /// 버리고 나머지만 저장해서, 사용자가 알아채지 못한 채 기록이 망가졌다.
    public static func decodeWorkoutCompletedStrict(
        _ envelope: [String: Any]
    ) -> Result<CompletedWorkout, DecodeFailure> {
        guard isSupportedVersion(envelope) else { return .failure(.unsupportedVersion) }
        guard
            (envelope[Key.type] as? String) == MessageType.workoutCompleted,
            let payload = envelope[Key.payload] as? [String: Any],
            let idString = payload["id"] as? String,
            let templateName = payload["templateName"] as? String,
            let startedAtMs = int64(payload["startedAtMs"]),
            let finishedAtMs = int64(payload["finishedAtMs"]),
            let rawSegments = payload["segments"] as? [[String: Any]]
        else { return .failure(.malformedPayload) }

        // 기록 id 가 UUID 가 아니면 매번 새 UUID 가 되어 재전송마다 중복이
        // 쌓인다. 무작위로 채우지 말고 거부한다.
        guard let id = UUID(uuidString: idString) else { return .failure(.malformedPayload) }

        let division = (payload["division"] as? String).flatMap(HyroxDivision.init(rawValue:))
        var segments: [SegmentRecord] = []
        segments.reserveCapacity(rawSegments.count)
        for raw in rawSegments {
            guard let segment = decodeSegment(raw, workoutId: id) else {
                return .failure(.malformedSegment)
            }
            segments.append(segment)
        }

        return .success(CompletedWorkout(
            id: id,
            templateName: templateName,
            division: division,
            startedAt: Date(timeIntervalSince1970: TimeInterval(startedAtMs) / 1000.0),
            finishedAt: Date(timeIntervalSince1970: TimeInterval(finishedAtMs) / 1000.0),
            segments: segments
        ))
    }

    private static func decodeSegment(_ dict: [String: Any], workoutId: UUID) -> SegmentRecord? {
        guard
            let index = int(dict["index"]),
            let typeRaw = dict["type"] as? String,
            let type = SegmentType(rawValue: typeRaw),
            let startedAtMs = int64(dict["startedAtMs"]),
            let endedAtMs = int64(dict["endedAtMs"])
        else { return nil }

        let pausedMs = int64(dict["pausedDurationMs"]) ?? 0
        let hrRaw = dict["heartRateSamples"] as? [[String: Any]] ?? []
        let hrSamples = hrRaw.compactMap { sample -> HeartRateSample? in
            guard let tMs = int64(sample["tMs"]),
                  let bpm = int(sample["bpm"]) else { return nil }
            return HeartRateSample(
                timestamp: Date(timeIntervalSince1970: TimeInterval(tMs) / 1000.0),
                bpm: bpm
            )
        }
        let measurements = SegmentMeasurements(
            locationSamples: [],
            heartRateSamples: hrSamples
        )

        // 세그먼트 id 는 (기록 id, 인덱스)에서 결정적으로 만든다. 워치가 같은
        // 기록을 다시 보내도 같은 id 가 나오므로 upsert 가 제자리를 덮어쓴다.
        return SegmentRecord(
            id: stableSegmentId(workoutId: workoutId, index: index, salt: "record"),
            segmentId: (dict["segmentId"] as? String).flatMap(UUID.init(uuidString:))
                ?? stableSegmentId(workoutId: workoutId, index: index, salt: "template"),
            index: index,
            type: type,
            startedAt: Date(timeIntervalSince1970: TimeInterval(startedAtMs) / 1000.0),
            endedAt: Date(timeIntervalSince1970: TimeInterval(endedAtMs) / 1000.0),
            pausedDuration: TimeInterval(pausedMs) / 1000.0,
            measurements: measurements,
            stationDisplayName: dict["stationDisplayName"] as? String,
            plannedDistanceMeters: double(dict["plannedDistanceMeters"]),
            goalDurationSeconds: double(dict["goalDurationSeconds"])
        )
    }
}
