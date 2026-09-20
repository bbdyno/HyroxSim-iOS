//
//  HealthKitWorkoutSaver.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import HealthKit
import HyroxCore
import os

/// 폰에서 진행한 운동을 건강 앱에 저장하는 어댑터.
///
/// 워치는 `HKWorkoutSession` + `HKLiveWorkoutBuilder` 로 실시간 수집하며 저장하지만,
/// 폰에는 워크아웃 세션이 없으므로 운동이 끝난 뒤 `HKWorkoutBuilder` 로 한 번에 기록한다.
///
/// 저장하는 것:
/// - 활동 유형 `.functionalStrengthTraining` (워치와 동일)
/// - 구간마다 `HKWorkoutEvent(type: .segment)` — 피트니스 앱 스플릿
/// - 메타데이터: 템플릿 이름·디비전·실내 여부
///
/// 심박·거리 샘플은 넣지 않는다. 폰의 심박은 워치가 이미 건강 앱에 쓴 샘플을 읽어 온 것이라
/// 다시 쓰면 같은 측정이 두 번 남는다.
public final class HealthKitWorkoutSaver: HealthWorkoutSaving, @unchecked Sendable {

    /// 이 어댑터가 동작하는 기기. 폰에서 기록한 운동만 저장한다.
    private static let recordingDevice: WorkoutOrigin = .phone

    private static let logger = Logger(
        subsystem: "com.bbdyno.app.HyroxSim",
        category: "HealthWorkout"
    )

    private let healthStore = HKHealthStore()

    public init() {}

    // MARK: - HealthWorkoutSaving

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAuthorization() async -> Bool {
        guard isAvailable else {
            Self.logger.notice("건강 데이터를 쓸 수 없는 기기 — 운동 저장을 건너뜁니다.")
            return false
        }

        let workoutType = HKObjectType.workoutType()
        do {
            // 심박 읽기까지 같이 요청해 권한 시트를 한 번만 띄운다.
            // `HealthKitHeartRateAdapter` 가 뒤이어 같은 타입을 요청해도 이미 결정된 상태라 시트가 다시 뜨지 않는다.
            try await healthStore.requestAuthorization(
                toShare: [workoutType],
                read: [HKQuantityType(.heartRate)]
            )
        } catch {
            Self.logger.error("건강 앱 쓰기 권한 요청 실패: \(error.localizedDescription, privacy: .public)")
            return false
        }

        // 읽기 권한과 달리 쓰기 권한은 상태를 그대로 조회할 수 있다.
        let status = healthStore.authorizationStatus(for: workoutType)
        guard status == .sharingAuthorized else {
            Self.logger.notice("건강 앱 쓰기 권한 없음(status=\(status.rawValue, privacy: .public)) — 운동 저장을 건너뜁니다.")
            return false
        }
        return true
    }

    public func save(_ export: HealthWorkoutExport) async throws {
        guard isAvailable else { throw HealthWorkoutSaveError.unavailable }

        // 워치에서 기록해 폰으로 동기화된 운동은 워치가 이미 저장했다 — 여기서 또 저장하면 중복.
        guard HealthWorkoutSavePolicy.shouldSave(
            origin: export.origin,
            recordedOn: Self.recordingDevice
        ) else {
            Self.logger.notice(
                "폰에서 시작한 운동이 아니라 건강 앱 저장을 건너뜁니다(origin=\(export.origin.rawValue, privacy: .public))."
            )
            throw HealthWorkoutSaveError.originMismatch
        }

        guard export.duration > 0 else { throw HealthWorkoutSaveError.emptyWorkout }
        guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            throw HealthWorkoutSaveError.notAuthorized
        }

        let configuration = HKWorkoutConfiguration()
        // HYROX 전용 활동 유형이 없어 워치와 같은 값을 쓴다 — 기록이 한 종류로 모인다.
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = export.isIndoor ? .indoor : .outdoor

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )

        do {
            try await builder.beginCollection(at: export.startedAt)

            let events = export.segmentEvents.compactMap(Self.makeWorkoutEvent)
            if !events.isEmpty {
                try await builder.addWorkoutEvents(events)
            }

            try await builder.addMetadata(Self.makeMetadata(for: export))
            try await builder.endCollection(at: export.finishedAt)
            _ = try await builder.finishWorkout()
        } catch {
            // 실패한 빌더는 남겨 두지 않는다 — 다음 운동이 같은 store 를 쓴다.
            builder.discardWorkout()
            Self.logger.error("건강 앱 운동 저장 실패: \(error.localizedDescription, privacy: .public)")
            throw HealthWorkoutSaveError.saveFailed(reason: error.localizedDescription)
        }

        Self.logger.info(
            "건강 앱에 운동 저장 완료 (구간 \(export.segmentEvents.count, privacy: .public)개, 실내=\(export.isIndoor, privacy: .public))"
        )
    }

    // MARK: - Mapping

    static func makeWorkoutEvent(from event: HealthWorkoutExport.SegmentEvent) -> HKWorkoutEvent? {
        guard event.duration > 0 else { return nil }
        return HKWorkoutEvent(
            type: .segment,
            dateInterval: DateInterval(start: event.startedAt, end: event.endedAt),
            metadata: event.metadata
        )
    }

    static func makeMetadata(for export: HealthWorkoutExport) -> [String: Any] {
        var metadata: [String: Any] = export.customMetadata
        // 피트니스 앱이 실내/실외를 읽는 표준 키.
        metadata[HKMetadataKeyIndoorWorkout] = NSNumber(value: export.isIndoor)
        return metadata
    }
}
