//
//  CompletedWorkout+CourseShape.swift
//  HyroxCore
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

extension CompletedWorkout {

    /// 기록을 템플릿 모양으로 되돌린 값.
    ///
    /// `CompletedWorkout` 은 자기가 어떤 템플릿에서 나왔는지 들고 있지 않다(이름만 있다).
    /// 표준 코스 판정은 `WorkoutTemplate.isStandardHyroxCourse` 한 곳에서만 하기로 했으므로,
    /// 기록에 남은 계획값(`plannedDistanceMeters`, 스테이션 이름)으로 템플릿을 복원해 넘긴다.
    ///
    /// 계획 거리가 없는 구버전 기록은 거리 nil 인 채로 복원된다 → 표준으로 인정되지 않는다.
    /// GPS 실측 거리로 대신 채우면 1,000m 를 살짝 벗어난 실측값 때문에 판정이 흔들리고,
    /// 반대로 500m 러닝을 표준으로 오인할 수도 있어서 일부러 채우지 않는다.
    public var reconstructedTemplate: WorkoutTemplate {
        let usesRoxZone = segments.contains { $0.type == .roxZone }

        let templateSegments: [WorkoutSegment] = segments.map { record in
            switch record.type {
            case .run:
                return WorkoutSegment(
                    type: .run,
                    distanceMeters: record.plannedDistanceMeters,
                    goalDurationSeconds: record.goalDurationSeconds
                )

            case .roxZone:
                return WorkoutSegment(
                    type: .roxZone,
                    distanceMeters: record.plannedDistanceMeters,
                    goalDurationSeconds: record.goalDurationSeconds
                )

            case .station:
                return WorkoutSegment(
                    type: .station,
                    goalDurationSeconds: record.goalDurationSeconds,
                    stationKind: stationKind(for: record)
                )
            }
        }

        return WorkoutTemplate(
            name: templateName,
            division: division,
            segments: templateSegments,
            usesRoxZone: usesRoxZone,
            createdAt: startedAt
        )
    }

    /// 공식 코스(8 × 1km 러닝 + 공식 8개 스테이션) 그대로 완주한 기록인지 여부.
    ///
    /// 커스텀 템플릿(거리·스테이션·구성이 다른 경우)에는 참조 데이터가 맞지 않으므로
    /// 격차 분석을 제공하지 않는다.
    public var isStandardHyroxCourse: Bool {
        reconstructedTemplate.isStandardHyroxCourse
    }

    /// 스테이션 기록을 수행 순서대로 묶은 값. 표준 코스라면 공식 순서와 일치한다.
    public var orderedStationKinds: [StationKind] {
        stationSegments.map { stationKind(for: $0) ?? .custom(name: resolvedStationDisplayName(for: $0) ?? "Station") }
    }

    /// 기록에 남은 표시 이름을 공식 스테이션으로 되돌린다. 공식 이름이 아니면 nil.
    private func stationKind(for record: SegmentRecord) -> StationKind? {
        guard let name = resolvedStationDisplayName(for: record) else { return nil }
        return StationKind.standardOrder.first { $0.displayName == name }
    }
}
