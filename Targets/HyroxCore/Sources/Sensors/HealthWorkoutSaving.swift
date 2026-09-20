//
//  HealthWorkoutSaving.swift
//  HyroxCore
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

/// 운동을 실내에서 했는지 실외에서 했는지.
/// HealthKit 쪽에서는 `HKWorkoutConfiguration.locationType` 과
/// `HKMetadataKeyIndoorWorkout` 으로 매핑된다.
public enum WorkoutEnvironment: String, Codable, Hashable, Sendable {
    case indoor
    case outdoor

    public var isIndoor: Bool { self == .indoor }
}

/// 건강 앱 운동에 붙는 요약 메타데이터.
/// HyroxCore 는 HealthKit 을 import 하지 않으므로 키·값만 들고 있고,
/// 실제 `HKMetadataKey...` 변환은 각 앱 타겟의 어댑터가 담당한다.
public struct HealthWorkoutMetadata: Hashable, Sendable {
    public let templateName: String
    public let division: HyroxDivision?
    public let environment: WorkoutEnvironment

    public init(
        templateName: String,
        division: HyroxDivision? = nil,
        environment: WorkoutEnvironment
    ) {
        self.templateName = templateName
        self.division = division
        self.environment = environment
    }

    public var isIndoor: Bool { environment.isIndoor }

    /// HYROX 고유 문자열 메타데이터. 실내 여부는 HealthKit 표준 키를 써야 해서 여기 포함하지 않는다.
    public var customValues: [String: String] {
        var values: [String: String] = [
            HealthWorkoutMetadataKey.templateName: templateName
        ]
        if let division {
            values[HealthWorkoutMetadataKey.division] = division.rawValue
            values[HealthWorkoutMetadataKey.divisionDisplayName] = division.displayName
        }
        return values
    }
}

/// 건강 앱에 남기는 HYROX 고유 메타데이터 키.
/// HealthKit 커스텀 키는 앱 밖에서도 읽히므로, 다른 앱 키와 겹치지 않게 접두사를 붙인다.
public enum HealthWorkoutMetadataKey {
    public static let templateName = "HyroxTemplateName"
    public static let division = "HyroxDivision"
    public static let divisionDisplayName = "HyroxDivisionName"
    public static let origin = "HyroxWorkoutOrigin"
    public static let workoutId = "HyroxWorkoutID"
    public static let segmentTitle = "HyroxSegmentTitle"
    public static let segmentType = "HyroxSegmentType"
}

/// 건강 앱에 남길 운동 한 건을 플랫폼 중립으로 기술한 값.
public struct HealthWorkoutExport: Hashable, Sendable {

    /// 구간 하나. HealthKit 에서는 `HKWorkoutEvent(type: .segment)` 가 되어
    /// 피트니스 앱의 스플릿 목록으로 보인다.
    public struct SegmentEvent: Hashable, Sendable {
        public let startedAt: Date
        public let endedAt: Date
        /// 스플릿에 노출될 이름 ("RUN 1", "ROX ZONE", "SkiErg").
        public let title: String
        public let type: SegmentType

        public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

        public var metadata: [String: String] {
            [
                HealthWorkoutMetadataKey.segmentTitle: title,
                HealthWorkoutMetadataKey.segmentType: type.rawValue
            ]
        }

        public init(startedAt: Date, endedAt: Date, title: String, type: SegmentType) {
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.title = title
            self.type = type
        }

        /// 완료된 구간 기록에서 이벤트를 만든다.
        /// 길이가 0 이하면 nil — HealthKit 이 빈 구간 이벤트를 받지 않는다.
        public init?(record: SegmentRecord, title: String) {
            guard record.endedAt > record.startedAt else { return nil }
            self.init(
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                title: title,
                type: record.type
            )
        }
    }

    public let workoutId: UUID
    public let startedAt: Date
    public let finishedAt: Date
    /// 이 운동을 실제로 기록한 기기. 저장은 기록한 기기에서만 한다(중복 기록 방지).
    public let origin: WorkoutOrigin
    public let metadata: HealthWorkoutMetadata
    public let segmentEvents: [SegmentEvent]

    public var templateName: String { metadata.templateName }
    public var division: HyroxDivision? { metadata.division }
    public var environment: WorkoutEnvironment { metadata.environment }
    public var isIndoor: Bool { metadata.isIndoor }
    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

    public init(
        workoutId: UUID,
        startedAt: Date,
        finishedAt: Date,
        origin: WorkoutOrigin,
        metadata: HealthWorkoutMetadata,
        segmentEvents: [SegmentEvent]
    ) {
        self.workoutId = workoutId
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.origin = origin
        self.metadata = metadata
        self.segmentEvents = segmentEvents
    }

    /// 완료된 운동에서 건강 앱 저장용 값을 만든다.
    /// 길이가 0 이하인 운동은 HealthKit 이 받지 않으므로 nil.
    ///
    /// 구간 이벤트는 운동 시작~종료 범위 안으로 잘라 넣고, 잘라 낸 뒤 길이가 0 이 되는 구간은 뺀다.
    /// (HealthKit 은 운동 범위를 벗어나거나 길이가 0 인 이벤트를 거부한다.)
    public init?(
        workout: CompletedWorkout,
        origin: WorkoutOrigin,
        environment: WorkoutEnvironment
    ) {
        guard workout.finishedAt > workout.startedAt else { return nil }

        let ordered = workout.segments.sorted { $0.index < $1.index }
        var events: [SegmentEvent] = []
        events.reserveCapacity(ordered.count)

        for record in ordered {
            let start = max(record.startedAt, workout.startedAt)
            let end = min(record.endedAt, workout.finishedAt)
            guard end > start else { continue }
            events.append(
                SegmentEvent(
                    startedAt: start,
                    endedAt: end,
                    title: HealthWorkoutSegmentTitle.make(for: record, in: workout),
                    type: record.type
                )
            )
        }

        self.init(
            workoutId: workout.id,
            startedAt: workout.startedAt,
            finishedAt: workout.finishedAt,
            origin: origin,
            metadata: HealthWorkoutMetadata(
                templateName: workout.templateName,
                division: workout.division,
                environment: environment
            ),
            segmentEvents: events
        )
    }

    /// 운동 전체에 붙는 문자열 메타데이터.
    public var customMetadata: [String: String] {
        var values = metadata.customValues
        values[HealthWorkoutMetadataKey.origin] = origin.rawValue
        values[HealthWorkoutMetadataKey.workoutId] = workoutId.uuidString
        return values
    }
}

/// 피트니스 앱 스플릿에 쓸 구간 이름을 만든다.
/// Run 은 템플릿 안의 순번을 붙여 "RUN 3" 처럼, Station 은 스테이션 이름을 쓴다.
public enum HealthWorkoutSegmentTitle {

    public static let roxZone = "ROX ZONE"
    public static let fallbackStation = "STATION"

    /// 진행 중인 운동용 — 템플릿 세그먼트 배열을 기준으로 순번을 센다.
    public static func make(for record: SegmentRecord, in segments: [WorkoutSegment]) -> String {
        switch record.type {
        case .run:
            let upperBound = min(max(record.index + 1, 0), segments.count)
            let ordinal = segments[..<upperBound].filter { $0.type == .run }.count
            return runTitle(ordinal: max(ordinal, 1))
        case .roxZone:
            return roxZone
        case .station:
            if let name = record.stationDisplayName, !name.isEmpty { return name }
            if segments.indices.contains(record.index),
               let kind = segments[record.index].stationKind {
                return kind.displayName
            }
            return fallbackStation
        }
    }

    /// 완료된 운동용 — 기록된 구간 순서를 기준으로 순번을 센다.
    public static func make(for record: SegmentRecord, in workout: CompletedWorkout) -> String {
        switch record.type {
        case .run:
            let ordinal = workout.segments
                .filter { $0.type == .run && $0.index <= record.index }
                .count
            return runTitle(ordinal: max(ordinal, 1))
        case .roxZone:
            return roxZone
        case .station:
            return workout.resolvedStationDisplayName(for: record) ?? fallbackStation
        }
    }

    private static func runTitle(ordinal: Int) -> String { "RUN \(ordinal)" }
}

/// 실내/실외 판정. 순수 함수라 HealthKit 없이 단위 테스트할 수 있다.
///
/// 판정 근거는 "GPS 로 실제 이동이 확인되었는가" 하나다.
/// HYROX 는 런 거리가 고정(1 km × 8)이라 계획 거리와 실측 거리를 비교하면
/// 트레드밀·실내 트랙(제자리 이동 없음)과 야외 러닝이 깔끔하게 갈린다.
public enum WorkoutEnvironmentClassifier {

    /// 계획 거리 대비 이 비율 이상 실측되면 실외로 본다.
    public static let outdoorDistanceRatio: Double = 0.5
    /// 계획 거리가 없는 템플릿에서 실외로 인정할 최소 실측 거리(m).
    public static let minimumOutdoorDistanceMeters: Double = 200

    /// 운동 시작 시점 추정. 실측 거리가 아직 없으므로 위치 권한과 템플릿으로만 판단한다.
    /// `HKWorkoutConfiguration.locationType` 은 세션 생성 뒤 바꿀 수 없어서 워치가 이 값을 쓴다.
    public static func plannedEnvironment(
        template: WorkoutTemplate,
        locationAuthorization: SensorAuthorizationStatus
    ) -> WorkoutEnvironment {
        let plannedDistance = template.segments
            .filter { $0.type.tracksLocation }
            .compactMap(\.distanceMeters)
            .reduce(0, +)
        guard plannedDistance > 0 else { return .indoor }
        return locationAuthorization == .authorized ? .outdoor : .indoor
    }

    /// 운동 종료 후 실측 기반 최종 판정.
    /// - Parameter isLocationTrackingActive: GPS 스트림이 실제로 살아 있었는지.
    ///   권한 거부·시작 실패로 이동을 확인할 수 없으면 실내로 기록한다.
    ///   (`.outdoor` 로 남기면 피트니스 앱이 경로·GPS 기반 지표를 기대하는데 우리에겐 없다.)
    public static func classify(
        workout: CompletedWorkout,
        isLocationTrackingActive: Bool
    ) -> WorkoutEnvironment {
        guard isLocationTrackingActive else { return .indoor }

        let movingSegments = workout.segments.filter { $0.type.tracksLocation }
        let measured = movingSegments.reduce(0.0) { $0 + $1.distanceMeters }
        let planned = movingSegments.compactMap(\.plannedDistanceMeters).reduce(0, +)

        if planned > 0 {
            return measured >= planned * outdoorDistanceRatio ? .outdoor : .indoor
        }
        return measured >= minimumOutdoorDistanceMeters ? .outdoor : .indoor
    }
}

/// 같은 운동이 건강 앱에 두 번 남지 않게 하는 규칙.
public enum HealthWorkoutSavePolicy {
    /// 운동을 **실제로 기록한 기기만** 건강 앱에 저장한다.
    ///
    /// 워치 운동은 워치의 `HKWorkoutSession` 이 이미 저장하고, 그 결과가 폰으로 동기화된다.
    /// 폰이 동기화 받은 기록을 또 저장하면 건강 앱에 같은 운동이 두 번 남는다.
    public static func shouldSave(origin: WorkoutOrigin, recordedOn device: WorkoutOrigin) -> Bool {
        origin == device
    }
}

/// 건강 앱 저장 실패 사유.
public enum HealthWorkoutSaveError: Error, Hashable, Sendable {
    /// 이 기기에서 건강 데이터를 쓸 수 없음.
    case unavailable
    /// 쓰기 권한 없음(거부 또는 미결정).
    case notAuthorized
    /// 이 기기에서 기록한 운동이 아님 — 저장하면 중복이 된다.
    case originMismatch
    /// 길이가 0 이하라 HealthKit 이 받지 않는 운동.
    case emptyWorkout
    /// HealthKit 이 반환한 실패.
    case saveFailed(reason: String)
}

/// 완료된 운동을 건강 앱에 저장하는 추상화.
/// HyroxCore 는 HealthKit 을 import 하지 않는다 — 구현은 앱 타겟의 어댑터가 담당한다.
public protocol HealthWorkoutSaving: AnyObject, Sendable {
    /// 이 기기에서 건강 데이터를 쓸 수 있는지.
    var isAvailable: Bool { get }

    /// 운동 쓰기 권한을 요청한다.
    /// - Returns: 저장해도 되면 true. 거부·불가면 false — 호출자는 조용히 건너뛴다.
    func requestAuthorization() async -> Bool

    /// 완료된 운동을 건강 앱에 저장한다. 실패는 throw 하며, 호출자는 로그만 남기고 진행한다.
    func save(_ export: HealthWorkoutExport) async throws
}
