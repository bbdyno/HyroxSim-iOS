//
//  HyroxSchemaVersions.swift
//  HyroxPersistenceApple
//
//  Created by bbdyno on 9/18/26.
//
//  ─────────────────────────────────────────────────────────────────────────
//  스키마 버전 올리는 절차
//  ─────────────────────────────────────────────────────────────────────────
//  1. 새 `HyroxSchemaVn` 을 이 파일에 추가한다. `versionIdentifier` 는 n.0.0,
//     `models` 는 그 버전이 담는 엔티티 전부(바뀌지 않는 것도 모두 나열).
//  2. `HyroxMigrationPlan.schemas` 끝에 새 버전을 추가하고, `stages` 에
//     이전 버전 → 새 버전 단계를 추가한다.
//       - 엔티티/옵셔널 속성 "추가"만 → `.lightweight`
//       - 이름 변경·타입 변경·값 재계산 → `.custom(willMigrate:didMigrate:)`
//  3. `HyroxModelContainerFactory.currentVersionedSchema` 를 새 버전으로 바꾼다.
//  4. `PersistenceControllerTests` 의 마이그레이션 테스트에 "직전 버전으로 만든
//     스토어를 새 스키마로 연다" 케이스를 추가한다.
//
//  ⚠️ 기존 엔티티의 "속성"을 바꾸는 마이그레이션을 만들 때는, 과거 버전이
//  `models` 로 지금 살아 있는 클래스를 그대로 가리키면 안 된다. 과거 버전의 모양이
//  현재 클래스 정의를 따라 같이 변해버려서 마이그레이션이 no-op 이 된다. 그때는
//  해당 클래스를 과거 버전 네임스페이스 안에 스냅샷(복사)해 두고 그 복사본을
//  가리켜야 한다. 지금까지는 "엔티티 추가"뿐이라 클래스를 공유해도 안전하다.
//
//  ⚠️ 버전 식별자를 바꾸면 기존 사용자 스토어는 반드시 마이그레이션 단계를 거친다.
//  단계가 비어 있으면 앱은 컨테이너 생성 실패로 뜨지 않는다(빈 화면/무한 로딩).
//

import Foundation
import SwiftData

/// v1 — 출시된 상태의 스키마.
///
/// `StoredTemplate.usesRoxZone`(옵셔널) 과 `StoredWorkoutTombstone` 이 추가되기
/// 전의 스토어도 SwiftData 자동 경량 마이그레이션으로 이 버전에 흡수된다.
/// (버전을 명시하지 않고 만든 스토어의 기본 버전이 1.0.0 이라 식별자가 일치한다.)
public enum HyroxSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            StoredWorkout.self,
            StoredSegment.self,
            StoredTemplate.self,
            StoredWorkoutTombstone.self
        ]
    }
}

/// v2 — 대회 목표(`StoredRaceTarget`) 추가. 기존 엔티티는 그대로다.
public enum HyroxSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            StoredWorkout.self,
            StoredSegment.self,
            StoredTemplate.self,
            StoredWorkoutTombstone.self,
            StoredRaceTarget.self
        ]
    }
}
