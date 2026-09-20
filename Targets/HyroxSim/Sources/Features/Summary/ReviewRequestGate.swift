//
//  ReviewRequestGate.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore

/// 리뷰 요청 조건. 저장소도 시계도 모르는 순수 판단만 한다.
///
/// 판단을 타입으로 떼어 놓은 이유는 단위 테스트 때문이다. `SKStoreReviewController` 는
/// 시뮬레이터에서 호출해도 아무 일이 일어나지 않아, 조건을 눈으로 확인할 방법이 없다.
struct ReviewRequestPolicy: Sendable {

    /// 리뷰를 물어보기 전에 최소한 완료해야 하는 운동 수.
    static let minimumCompletedWorkouts = 3
    /// 한 번 물어본 뒤 다시 물어보지 않는 기간(일).
    static let cooldownDays = 120

    /// 판단에 필요한 상태 전부.
    struct Snapshot: Hashable, Sendable {
        /// 지금까지 앱에서 완료한 운동 수(이번 것 포함).
        let completedWorkoutCount: Int
        /// 이번 기록이 개인 기록을 갱신했는지 여부.
        let didSetPersonalRecord: Bool
        /// 마지막으로 리뷰를 요청한 시각. 물어본 적이 없으면 nil.
        let lastRequestedAt: Date?
    }

    var minimumCompletedWorkouts: Int = ReviewRequestPolicy.minimumCompletedWorkouts
    var cooldownDays: Int = ReviewRequestPolicy.cooldownDays

    /// 지금 리뷰를 요청해도 되는지.
    ///
    /// 세 조건을 모두 만족해야 한다: 운동 3회 이상, 개인 기록 갱신, 마지막 요청 후 120일 경과.
    func shouldRequest(_ snapshot: Snapshot, now: Date) -> Bool {
        guard snapshot.completedWorkoutCount >= minimumCompletedWorkouts else { return false }
        guard snapshot.didSetPersonalRecord else { return false }

        if let lastRequestedAt = snapshot.lastRequestedAt {
            let cooldown = TimeInterval(cooldownDays) * 24 * 60 * 60
            guard now.timeIntervalSince(lastRequestedAt) >= cooldown else { return false }
        }

        return true
    }
}

/// 완료한 운동 수·개인 기록·마지막 리뷰 요청 시각을 `UserDefaults` 에 쌓고,
/// `ReviewRequestPolicy` 로 리뷰 요청 여부를 판단한다.
@MainActor
final class ReviewRequestGate {

    private enum Key {
        static let completedCount = "review.completedWorkoutCount"
        static let bestDurations = "review.bestDurationSeconds"
        static let recordedWorkoutIDs = "review.recordedWorkoutIDs"
        static let lastRequestedAt = "review.lastRequestedAt"
    }

    /// 중복 집계를 막기 위해 기억해 두는 최근 기록 ID 수.
    private static let recordedIDLimit = 20

    /// 이 시간 안에 끝난 기록만 "방금 완료한 운동"으로 센다.
    /// 요약 화면은 기록 목록에서도 열리기 때문에, 이 창이 없으면 과거 기록을 훑기만 해도
    /// 카운터가 올라가고 엉뚱한 시점에 리뷰 얼럿이 뜬다.
    private static let freshnessWindow: TimeInterval = 15 * 60

    private let defaults: UserDefaults
    private let policy: ReviewRequestPolicy

    init(defaults: UserDefaults = .standard, policy: ReviewRequestPolicy = ReviewRequestPolicy()) {
        self.defaults = defaults
        self.policy = policy
    }

    /// 방금 끝난 기록을 반영하고, 지금 리뷰를 요청해야 하는지 답한다.
    ///
    /// 같은 기록으로 두 번 불러도 카운터는 한 번만 올라가고 두 번째는 `false` 를 돌려준다.
    /// (요약 화면이 공유 시트 등을 닫으면서 다시 나타날 수 있다.)
    func evaluate(_ workout: CompletedWorkout, now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(workout.finishedAt) <= Self.freshnessWindow,
              workout.finishedAt <= now.addingTimeInterval(Self.freshnessWindow) else { return false }

        var recordedIDs = defaults.stringArray(forKey: Key.recordedWorkoutIDs) ?? []
        let workoutID = workout.id.uuidString
        guard !recordedIDs.contains(workoutID) else { return false }

        recordedIDs.append(workoutID)
        if recordedIDs.count > Self.recordedIDLimit {
            recordedIDs.removeFirst(recordedIDs.count - Self.recordedIDLimit)
        }
        defaults.set(recordedIDs, forKey: Key.recordedWorkoutIDs)

        let count = defaults.integer(forKey: Key.completedCount) + 1
        defaults.set(count, forKey: Key.completedCount)

        let didSetPersonalRecord = updatePersonalRecord(for: workout)

        return policy.shouldRequest(
            ReviewRequestPolicy.Snapshot(
                completedWorkoutCount: count,
                didSetPersonalRecord: didSetPersonalRecord,
                lastRequestedAt: lastRequestedAt
            ),
            now: now
        )
    }

    /// 리뷰 시트를 실제로 띄운 뒤에만 호출한다.
    func markRequested(at date: Date = Date()) {
        defaults.set(date.timeIntervalSinceReferenceDate, forKey: Key.lastRequestedAt)
    }

    var lastRequestedAt: Date? {
        guard defaults.object(forKey: Key.lastRequestedAt) != nil else { return nil }
        return Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Key.lastRequestedAt))
    }

    var completedWorkoutCount: Int {
        defaults.integer(forKey: Key.completedCount)
    }

    // MARK: - Personal record

    /// 개인 기록을 갱신했는지 판단하고 최고 기록을 갱신한다.
    ///
    /// 비교 대상이 없던 첫 기록은 갱신으로 보지 않는다. "처음이라 제일 빠른 기록"에
    /// 리뷰를 물어보는 건 성취가 아니기 때문이다.
    private func updatePersonalRecord(for workout: CompletedWorkout) -> Bool {
        let key = Self.personalRecordKey(for: workout)
        let duration = workout.totalDuration
        guard duration > 0 else { return false }

        var bests = defaults.dictionary(forKey: Key.bestDurations) as? [String: Double] ?? [:]
        let previousBest = bests[key]

        if let previousBest {
            guard duration < previousBest else { return false }
            bests[key] = duration
            defaults.set(bests, forKey: Key.bestDurations)
            return true
        }

        bests[key] = duration
        defaults.set(bests, forKey: Key.bestDurations)
        return false
    }

    /// 기록끼리 비교할 수 있는 단위를 키로 삼는다.
    ///
    /// 공식 코스는 디비전별로, 커스텀 코스는 템플릿별로 최고 기록을 따로 센다.
    /// 구성이 다른 운동을 같은 저울에 올리면 "기록 갱신"이 의미를 잃는다.
    private static func personalRecordKey(for workout: CompletedWorkout) -> String {
        if workout.isStandardHyroxCourse, let division = workout.division {
            return "division.\(division.rawValue)"
        }
        return "template.\(workout.templateName)"
    }
}
