//
//  GarminGoalSyncService.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//

import Foundation
import os
import HyroxCore

/// Pushes target times to the Garmin watch right before a workout starts.
/// The watch stores them in `Application.Storage` under `GoalStore.KEY` so
/// the delta badge is live from the first tick.
///
/// 전송은 `GarminSyncDispatcher`(영속 outbox)를 거친다. 기기가 지금 꺼져
/// 있어도 목표는 큐에 남았다가 다음 연결에서 나간다 — 예전에는 `isPaired`
/// 가 false 면 그냥 버렸다.
@MainActor
public final class GarminGoalSyncService {

    public static let shared = GarminGoalSyncService()

    private let logger = Logger(subsystem: "com.bbdyno.app.HyroxSim", category: "GarminSync")
    private let dispatcher: GarminSyncDispatcher

    public init(dispatcher: GarminSyncDispatcher? = nil) {
        // 기본 인자 자리에서 `.shared` 를 읽으면 nonisolated 컨텍스트라
        // Swift 6 모드에서 에러가 된다.
        self.dispatcher = dispatcher ?? .shared
    }

    /// Sends a goal. `targetSegmentsMs` should have one entry per segment
    /// in the template (typically 31 for the HYROX preset). If the caller
    /// only has an aggregate time, pass `targetTotalMs` and let the watch
    /// fall back to its `PaceReference` split.
    public enum Result: Equatable {
        /// 지금 연결돼 있어 즉시 전송을 시작했다.
        case sent
        /// 기기가 없거나 끊겨 있어 큐에 넣었다. 다음 연결에서 나간다.
        case queued
        /// 봉투를 만들 수 없어 보내지 못했다.
        case failed
    }

    @discardableResult
    public func sendGoal(
        division: HyroxDivision,
        templateName: String,
        targetTotalMs: Int64,
        targetSegmentsMs: [Int64]
    ) -> Result {
        let envelope = GarminMessageCodec.encodeGoalSet(
            division: division,
            templateName: templateName,
            targetTotalMs: targetTotalMs,
            targetSegmentsMs: targetSegmentsMs
        )
        let wasConnected = dispatcher.isConnected
        guard dispatcher.send(
            envelope,
            dedupeKey: GarminSyncDispatcher.DedupeKey.goal(division: division.rawValue)
        ) else {
            logger.error("goal.set failed to queue division=\(division.rawValue, privacy: .public)")
            return .failed
        }
        logger.info(
            "goal.set \(wasConnected ? "sent" : "queued", privacy: .public) division=\(division.rawValue, privacy: .public)"
        )
        return wasConnected ? .sent : .queued
    }
}
