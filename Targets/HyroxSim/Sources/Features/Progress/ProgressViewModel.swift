//
//  ProgressViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import Foundation
import Observation
import os
import HyroxCore
import HyroxPersistenceApple

/// 진척 화면의 상태. 저장된 기록을 읽어 `ProgressAnalyzer` 에 넘기는 것이 전부다.
///
/// 계산은 전부 `HyroxCore` 의 순수 함수에 있다. 여기서는 데이터를 가져오고,
/// 못 가져왔을 때를 화면에 알려 주는 일만 한다.
@Observable
@MainActor
public final class ProgressViewModel {

    public private(set) var report: ProgressReport = .empty

    /// 마지막 조회가 실패했는지. 기록이 없는 상태와 읽지 못한 상태를 구분해서 보여 준다.
    public private(set) var lastLoadFailed = false

    /// 퍼센타일을 어느 스냅샷에서 읽었는지(`YYYY.MM.DD`). v4 표가 없으면 nil.
    public let datasetVersion: String?

    @ObservationIgnored private let logger = Logger(
        subsystem: "com.bbdyno.app.HyroxSim",
        category: "Progress"
    )
    @ObservationIgnored private let persistence: PersistenceController
    @ObservationIgnored private let analyzer: ProgressAnalyzer
    @ObservationIgnored private let division: HyroxDivision?

    /// - Parameters:
    ///   - paceData: v4 퍼센타일 표. 앱에서는 `AppServices.paceData.currentProvider()`.
    ///     nil 이면 번들 v3 버킷으로 떨어진다.
    ///   - division: 비교할 디비전. 생략하면 가장 최근 기록의 디비전을 쓴다.
    public init(
        persistence: PersistenceController,
        paceData: (any PaceDataProviding)? = nil,
        division: HyroxDivision? = nil
    ) {
        self.persistence = persistence
        self.division = division
        self.datasetVersion = paceData?.datasetVersion
        // v3 버킷은 한 번만 디코딩되고 이후엔 캐시에서 나온다(`PaceReferenceLoader`).
        self.analyzer = ProgressAnalyzer(
            paceData: paceData,
            fallbackPlanner: try? PaceReferenceLoader.loadPacePlanner()
        )
    }

    public func load() {
        do {
            report = analyzer.analyze(try persistence.fetchAllCompletedWorkouts(), division: division)
            lastLoadFailed = false
        } catch {
            logger.error("기록을 불러오지 못했습니다: \(String(describing: error), privacy: .public)")
            report = .empty
            lastLoadFailed = true
        }
    }
}
