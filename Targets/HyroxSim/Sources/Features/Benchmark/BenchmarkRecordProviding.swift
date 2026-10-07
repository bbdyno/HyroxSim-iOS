//
//  BenchmarkRecordProviding.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import Foundation
import HyroxCore

/// 벤치마크 화면이 기록을 읽는 통로.
///
/// 화면을 띄우는 쪽(대회 화면)은 저장소를 직접 들고 있지 않다. 델리게이트가 이 프로토콜을
/// 따르면 저장된 기록에서 최근 PFT 를 찾아 주고, 따르지 않으면 화면은 수동 입력만으로도
/// 그대로 동작한다 — 기록 접근이 없다고 화면이 열리지 않아서는 안 된다.
@MainActor
protocol BenchmarkRecordProviding: AnyObject {
    func benchmarkCompletedWorkouts() -> [CompletedWorkout]
}

extension BenchmarkRecordProviding {

    /// 저장된 기록 중 가장 최근 PFT.
    func latestPFTRecord() -> CompletedWorkout? {
        PFTBenchmark.mostRecentRecord(in: benchmarkCompletedWorkouts())
    }
}

/// 앱에서는 코디네이터가 저장소를 들고 있다.
///
/// `AppCoordinator.swift` 를 건드리지 않고 여기서 준수만 더한다 — 그 파일은 다른 작업이
/// 진행 중이고, 이 기능이 필요한 것은 "기록 목록을 한 번 읽는" 능력뿐이다.
extension AppCoordinator: BenchmarkRecordProviding {

    func benchmarkCompletedWorkouts() -> [CompletedWorkout] {
        (try? persistence.fetchAllCompletedWorkouts()) ?? []
    }
}
