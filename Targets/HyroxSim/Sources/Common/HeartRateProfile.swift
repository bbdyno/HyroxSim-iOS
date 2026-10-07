//
//  HeartRateProfile.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore

/// 심박 존 계산에 쓰는 최대 심박을 기록해 둔다.
///
/// 앱에 프로필 설정이 없어서 예전에는 190 을 하드코딩했는데, 그러면 사용자마다
/// 존이 통째로 어긋난다. 대신 **지금까지 관측된 최고 심박**을 기억한다. 운동을
/// 한 번도 안 했거나 심박 데이터가 없으면 nil 이고, 그때는 존 표시를 생략한다.
@MainActor
public final class HeartRateProfile {

    private enum Key {
        static let observedMax = "com.hyroxsim.heartRate.observedMax"
    }

    /// 사람이 낼 수 없는 값(센서 튐)은 프로필에 남기지 않는다.
    private static let plausibleRange = 100...230

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 관측된 최대 심박. 기록이 없으면 nil.
    public var observedMax: Int? {
        let stored = defaults.integer(forKey: Key.observedMax)
        return stored > 0 ? stored : nil
    }

    /// 완료된 운동의 심박 샘플에서 최고값을 반영한다.
    @discardableResult
    public func record(_ workout: CompletedWorkout) -> Int? {
        let samples = workout.segments.flatMap { $0.measurements.heartRateSamples }
        guard let peak = samples.map(\.bpm).max(), Self.plausibleRange.contains(peak) else {
            return observedMax
        }
        if peak > (observedMax ?? 0) {
            defaults.set(peak, forKey: Key.observedMax)
            return peak
        }
        return observedMax
    }
}
