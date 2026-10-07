//
//  StoredRaceTarget.swift
//  HyroxPersistenceApple
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore
import SwiftData

/// 사용자가 등록한 실제 대회 목표(`RaceTarget`)의 저장 형태.
///
/// 스키마 v2 에서 추가됐다. 도메인 ↔ 저장 변환은 `RaceTargetMapper` 가 맡고,
/// 여기에는 JSON 블롭이 없다 — 전부 1차 속성이라 나중에 날짜/디비전으로 쿼리하기 쉽다.
@Model
public final class StoredRaceTarget {
    @Attribute(.unique) public var id: UUID
    public var eventName: String
    public var city: String?
    /// 대회 일시. `PersistenceController.fetchUpcomingRaceTarget` 의 정렬·필터 기준.
    public var date: Date
    /// `HyroxDivision.rawValue` 또는 nil(미정)
    public var divisionRaw: String?
    public var goalDurationSeconds: TimeInterval?
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        eventName: String,
        city: String? = nil,
        date: Date,
        divisionRaw: String? = nil,
        goalDurationSeconds: TimeInterval? = nil,
        note: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.eventName = eventName
        self.city = city
        self.date = date
        self.divisionRaw = divisionRaw
        self.goalDurationSeconds = goalDurationSeconds
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
