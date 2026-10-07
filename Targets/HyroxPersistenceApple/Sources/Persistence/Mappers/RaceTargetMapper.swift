//
//  RaceTargetMapper.swift
//  HyroxPersistenceApple
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore

/// `RaceTarget`(도메인) ↔ `StoredRaceTarget`(SwiftData) 변환.
///
/// 직렬화한 블롭이 없어서 실패할 구석이 없다. 그래서 다른 매퍼와 달리 throw 하지 않는다.
/// 모르는 디비전 문자열(더 새 버전에서 온 값 등)은 `nil` 로 떨어뜨려 레코드 전체를
/// 버리지 않는다.
public enum RaceTargetMapper {

    /// 도메인 `RaceTarget` → 저장용 `StoredRaceTarget`.
    public static func toStored(_ target: RaceTarget) -> StoredRaceTarget {
        StoredRaceTarget(
            id: target.id,
            eventName: target.eventName,
            city: target.city,
            date: target.date,
            divisionRaw: target.division?.rawValue,
            goalDurationSeconds: target.goalDurationSeconds,
            note: target.note,
            createdAt: target.createdAt,
            updatedAt: target.updatedAt
        )
    }

    /// 저장된 `StoredRaceTarget` → 도메인 `RaceTarget`.
    public static func toDomain(_ stored: StoredRaceTarget) -> RaceTarget {
        RaceTarget(
            id: stored.id,
            eventName: stored.eventName,
            city: stored.city,
            date: stored.date,
            division: stored.divisionRaw.flatMap { HyroxDivision(rawValue: $0) },
            goalDurationSeconds: stored.goalDurationSeconds,
            note: stored.note,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt
        )
    }
}
