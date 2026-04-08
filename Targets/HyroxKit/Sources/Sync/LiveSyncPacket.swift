//
//  LiveSyncPacket.swift
//  HyroxKit
//
//  Created by Codex on 4/8/26.
//

import Foundation

/// Typed payload exchanged over HealthKit mirrored workout sessions.
public enum LiveSyncPacket: Codable, Sendable {
    case workoutStarted(template: WorkoutTemplate, origin: WorkoutOrigin)
    case liveState(LiveWorkoutState)
    case workoutFinished(origin: WorkoutOrigin)
    case command(WorkoutCommand)
    case heartRateRelay(HeartRateRelay)
}

public enum LiveSyncPacketCoder {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ packet: LiveSyncPacket) throws -> Data {
        guard let data = try? encoder.encode(packet) else {
            throw SyncError.encodingFailed
        }
        return data
    }

    public static func decode(_ data: Data) throws -> LiveSyncPacket {
        guard let packet = try? decoder.decode(LiveSyncPacket.self, from: data) else {
            throw SyncError.decodingFailed
        }
        return packet
    }
}
