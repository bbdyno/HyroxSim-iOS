//
//  GarminWorkoutPartAssembler.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 워치가 나눠 보낸 기록 조각(`workout.completed.part`)을 모아 하나의
/// `workout.completed` 봉투로 되돌린다.
///
/// 31개 구간짜리 기록은 Connect IQ 메시지 한 통에 들어가지 않는다. 워치는
/// 구간 목록을 여러 조각으로 잘라 순서대로 보내고, 0번 조각에만 머리 정보
/// (id·템플릿·시각)를 싣는다. 조각이 다 모이기 전에는 아무것도 돌려주지
/// 않으므로 ack 도 나가지 않고, 워치는 다음 연결 때 전체를 다시 보낸다.
struct GarminWorkoutPartAssembler {

    private struct Pending {
        var count: Int
        var parts: [Int: [String: Any]]
    }

    /// 동시에 붙들고 있을 기록 수. 중간에 끊긴 전송이 계속 쌓이지 않게 한다.
    private static let maxPending = 4

    private var pending: [String: Pending] = [:]
    private var order: [String] = []

    /// 조각 하나를 받는다. 그 기록의 조각이 모두 모였으면 합친 봉투를 돌려준다.
    mutating func add(_ envelope: [String: Any]) -> [String: Any]? {
        guard
            let id = envelope[GarminMessageCodec.Key.id] as? String,
            let chunk = envelope[GarminMessageCodec.Key.chunk] as? [String: Any],
            let index = (chunk["i"] as? NSNumber)?.intValue,
            let count = (chunk["n"] as? NSNumber)?.intValue,
            let payload = envelope[GarminMessageCodec.Key.payload] as? [String: Any],
            count > 0, count <= 64, index >= 0, index < count
        else { return nil }

        // 조각 수가 달라졌거나 0번이 다시 오면 새 전송이다. 지난번에 끊긴 조각은 버린다.
        // (0번이 처음 오는 경우는 버리지 않는다 — 도착 순서가 뒤바뀌어도 모이게.)
        var entry = pending[id] ?? Pending(count: count, parts: [:])
        if entry.count != count || (index == 0 && entry.parts[0] != nil) {
            entry = Pending(count: count, parts: [:])
        }
        entry.parts[index] = payload
        pending[id] = entry
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > Self.maxPending {
            pending[order.removeFirst()] = nil
        }

        guard entry.parts.count == count, var merged = entry.parts[0] else { return nil }
        var segments: [Any] = []
        for i in 0..<count {
            guard let part = entry.parts[i], let partSegments = part["segments"] as? [Any] else {
                return nil
            }
            segments.append(contentsOf: partSegments)
        }
        merged["segments"] = segments
        pending[id] = nil
        order.removeAll { $0 == id }

        var out = envelope
        out[GarminMessageCodec.Key.type] = GarminMessageCodec.MessageType.workoutCompleted
        out[GarminMessageCodec.Key.payload] = merged
        out[GarminMessageCodec.Key.chunk] = nil
        return out
    }
}
