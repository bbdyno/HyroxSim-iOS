//
//  RaceDayPreferences.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

/// 레이스 데이 표시 설정.
///
/// 레이스 모드는 대회 당일 내내 켜 두는 값이다. 운동을 한 번 끝냈다고 꺼지면
/// 다음 운동에서 다시 켜야 하므로 기기에 저장한다. 기록에는 영향을 주지 않는다.
final class RaceDayPreferences {

    static let shared = RaceDayPreferences()

    private enum Key {
        static let raceMode = "raceDay.isRaceModeEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isRaceModeEnabled: Bool {
        get { defaults.bool(forKey: Key.raceMode) }
        set { defaults.set(newValue, forKey: Key.raceMode) }
    }
}
