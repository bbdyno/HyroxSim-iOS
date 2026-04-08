//
//  SyncMessage.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// Types of sync messages between iPhone and Apple Watch
public enum SyncMessageKind: String, Codable, Sendable {
    /// Custom workout template (phone → watch)
    case template
    /// Completed workout result (watch → phone, or phone → watch)
    case completedWorkout
    /// Template deletion notification (bidirectional, payload = UUID)
    case templateDeleted
}

/// Envelope wrapping a sync payload for WatchConnectivity transfer
public struct SyncEnvelope: Codable, Sendable {
    public let kind: SyncMessageKind
    public let payload: Data
    public let createdAt: Date

    public init(kind: SyncMessageKind, payload: Data, createdAt: Date = Date()) {
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
    }
}

/// Encodes/decodes sync envelopes for WatchConnectivity transport.
/// WCSession APIs accept `[String: Any]` — this coder bridges between
/// typed envelopes and dictionary representations.
public enum SyncEnvelopeCoder {

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: - Encode

    public static func encode<T: Encodable>(_ value: T, kind: SyncMessageKind) throws -> SyncEnvelope {
        guard let payload = try? encoder.encode(value) else {
            throw SyncError.encodingFailed
        }
        return SyncEnvelope(kind: kind, payload: payload)
    }

    // MARK: - Decode

    public static func decodeTemplate(_ envelope: SyncEnvelope) throws -> WorkoutTemplate {
        guard let t = try? decoder.decode(WorkoutTemplate.self, from: envelope.payload) else {
            throw SyncError.decodingFailed
        }
        return t
    }

    public static func decodeCompletedWorkout(_ envelope: SyncEnvelope) throws -> CompletedWorkout {
        guard let w = try? decoder.decode(CompletedWorkout.self, from: envelope.payload) else {
            throw SyncError.decodingFailed
        }
        return w
    }

    public static func decodeDeletedId(_ envelope: SyncEnvelope) throws -> UUID {
        guard let id = try? decoder.decode(UUID.self, from: envelope.payload) else {
            throw SyncError.decodingFailed
        }
        return id
    }

    // MARK: - Dictionary conversion (for WCSession transferUserInfo)

    private static let envelopeKey = "syncEnvelope"

    public static func toDictionary(_ envelope: SyncEnvelope) throws -> [String: Any] {
        guard let data = try? encoder.encode(envelope) else {
            throw SyncError.encodingFailed
        }
        return [envelopeKey: data]
    }

    public static func fromDictionary(_ dict: [String: Any]) throws -> SyncEnvelope {
        guard let data = dict[envelopeKey] as? Data else {
            throw SyncError.decodingFailed
        }
        guard let envelope = try? decoder.decode(SyncEnvelope.self, from: data) else {
            throw SyncError.decodingFailed
        }
        return envelope
    }
}
