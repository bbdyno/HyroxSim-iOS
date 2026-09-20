//
//  HyroxMigrationPlan.swift
//  HyroxPersistenceApple
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import SwiftData

/// 스토어를 현재 스키마까지 끌어올리는 경로.
///
/// `schemas` 는 오래된 순서, `stages` 는 적용 순서다. SwiftData 는 스토어에 기록된
/// 버전 식별자를 보고 필요한 단계만 이어서 실행한다.
///
/// 버전을 올리는 절차는 `HyroxSchemaVersions.swift` 상단 주석 참고.
public enum HyroxMigrationPlan: SchemaMigrationPlan {

    public static var schemas: [any VersionedSchema.Type] {
        [
            HyroxSchemaV1.self,
            HyroxSchemaV2.self
        ]
    }

    public static var stages: [MigrationStage] {
        [
            // v1 → v2: `StoredRaceTarget` 엔티티 추가뿐이라 추론 가능(경량).
            // 기존 엔티티의 속성은 하나도 건드리지 않으므로 데이터 변환이 없다.
            .lightweight(fromVersion: HyroxSchemaV1.self, toVersion: HyroxSchemaV2.self)
        ]
    }
}
