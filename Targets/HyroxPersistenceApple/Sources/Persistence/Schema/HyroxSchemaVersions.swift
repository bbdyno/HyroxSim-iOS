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

/// v0 — **App Store 1.3.0 까지 실제로 출시된** 스키마의 스냅샷.
///
/// 1.3.0 스토어에는 엔티티가 3개뿐이고 `StoredTemplate.usesRoxZone` 도 없다.
/// 마이그레이션 계획에 이 모양이 없으면 SwiftData 는 1.3.0 스토어를 계획의 어느
/// 버전과도 맞추지 못해 `loadIssueModelContainer` 로 컨테이너 생성에 실패한다
/// (= 업데이트한 기존 사용자의 앱이 실행 즉시 종료).
///
/// 현재 클래스는 이미 모양이 바뀌었으므로, 당시 정의를 이 네임스페이스 안에
/// 그대로 복사해 둔다. **이 클래스들은 절대 수정하지 말 것.**
public enum HyroxSchemaV0: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(0, 1, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            StoredWorkout.self,
            StoredSegment.self,
            StoredTemplate.self
        ]
    }

    @Model
    public final class StoredWorkout {
        @Attribute(.unique) public var id: UUID
        public var templateName: String
        public var divisionRaw: String?
        public var startedAt: Date
        public var finishedAt: Date

        @Relationship(deleteRule: .cascade, inverse: \StoredSegment.workout)
        public var segments: [StoredSegment]

        public init(
            id: UUID,
            templateName: String,
            divisionRaw: String?,
            startedAt: Date,
            finishedAt: Date,
            segments: [StoredSegment] = []
        ) {
            self.id = id
            self.templateName = templateName
            self.divisionRaw = divisionRaw
            self.startedAt = startedAt
            self.finishedAt = finishedAt
            self.segments = segments
        }
    }

    @Model
    public final class StoredSegment {
        @Attribute(.unique) public var id: UUID
        public var segmentId: UUID
        public var index: Int
        public var typeRaw: String
        public var startedAt: Date
        public var endedAt: Date
        public var pausedDuration: TimeInterval
        public var stationDisplayName: String?
        public var plannedDistanceMeters: Double?
        public var goalDurationSeconds: TimeInterval?
        public var measurementsData: Data
        public var workout: StoredWorkout?

        public init(
            id: UUID,
            segmentId: UUID,
            index: Int,
            typeRaw: String,
            startedAt: Date,
            endedAt: Date,
            pausedDuration: TimeInterval,
            stationDisplayName: String? = nil,
            plannedDistanceMeters: Double? = nil,
            goalDurationSeconds: TimeInterval? = nil,
            measurementsData: Data,
            workout: StoredWorkout? = nil
        ) {
            self.id = id
            self.segmentId = segmentId
            self.index = index
            self.typeRaw = typeRaw
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.pausedDuration = pausedDuration
            self.stationDisplayName = stationDisplayName
            self.plannedDistanceMeters = plannedDistanceMeters
            self.goalDurationSeconds = goalDurationSeconds
            self.measurementsData = measurementsData
            self.workout = workout
        }
    }

    @Model
    public final class StoredTemplate {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var divisionRaw: String?
        public var createdAt: Date
        public var segmentsData: Data

        public init(
            id: UUID,
            name: String,
            divisionRaw: String?,
            createdAt: Date,
            segmentsData: Data
        ) {
            self.id = id
            self.name = name
            self.divisionRaw = divisionRaw
            self.createdAt = createdAt
            self.segmentsData = segmentsData
        }
    }
}

/// v1 — 1.3.0 이후 개발 빌드의 스키마(`usesRoxZone`, 툼스톤 추가). 스토어에는 출시되지 않았다.
///
/// 원래 주석(아래)은 "1.3.0 스토어가 자동으로 이 버전에 흡수된다"고 가정했지만,
/// 마이그레이션 계획을 쓰면 그렇게 되지 않는다. 1.3.0 스토어는 `HyroxSchemaV0` 가 받는다.
///
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
