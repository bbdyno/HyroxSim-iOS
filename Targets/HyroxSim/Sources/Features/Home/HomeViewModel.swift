//
//  HomeViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import Observation
import HyroxCore
import HyroxPersistenceApple

@Observable
@MainActor
public final class HomeViewModel {

    /// 홈 상단 대회 카드에 필요한 값만 추린 것.
    /// 남은 일수는 `RaceTarget` 이 달력을 주입받아 계산하므로, 기기 시간대가 달라도
    /// 화면과 테스트가 같은 값을 본다.
    public struct RaceCountdown {
        public let target: RaceTarget
        public let daysRemaining: Int

        /// 대회 당일인지.
        public var isRaceDay: Bool { daysRemaining == 0 }

        /// "D-7" / "D-DAY". 지난 대회는 홈에 올라오지 않으므로 음수 표기는 없다.
        public var dDayText: String {
            isRaceDay
                ? HyroxSimStrings.Localizable.Home.RaceTarget.dday
                : "D-\(daysRemaining)"
        }

        /// 목표 시간 표기. 목표가 없으면 nil.
        public var goalText: String? {
            target.goalDurationSeconds.map { DurationFormatter.hms($0) }
        }
    }

    /// 홈의 훈련 세션 카드 한 장.
    /// 세션 종류를 같이 들고 다녀야 카드에 설명·아이콘을 붙일 수 있다.
    public struct TrainingSessionItem {
        public let kind: TrainingSessionKind
        public let template: WorkoutTemplate
        public var id: UUID { template.id }
    }

    public private(set) var presets: [WorkoutTemplate] = []
    public private(set) var trainingSessions: [TrainingSessionItem] = []
    public private(set) var customTemplates: [WorkoutTemplate] = []
    public private(set) var recentWorkouts: [CompletedWorkout] = []
    /// 다가오는 대회. 지난 대회만 있거나 하나도 없으면 nil.
    public private(set) var raceCountdown: RaceCountdown?
    /// 훈련 세션 무게·횟수를 뽑은 디비전.
    public private(set) var trainingDivision: HyroxDivision = HomeViewModel.fallbackTrainingDivision

    /// 등록된 대회가 없을 때 훈련 세션 무게를 뽑을 디비전.
    /// 앱에 아직 사용자 프로필이 없어서 쓰는 임시 기준값이다.
    public static let fallbackTrainingDivision: HyroxDivision = .menOpenSingle

    /// 목표 override 가 바뀌었을 때 UIKit 화면에 알리는 훅.
    /// (`@Observable` 이지만 홈은 UIKit 이라 직접 구독하지 않는다.)
    @ObservationIgnored public var onDataChanged: (() -> Void)?

    private let persistence: PersistenceController
    private let goalOverrideStore: TemplateGoalOverrideStore
    private let calendar: Calendar
    private let now: () -> Date
    /// 관찰 대상이 아니다 — 알림 토큰이 바뀌었다고 화면을 다시 그릴 이유는 없다.
    @ObservationIgnored private var goalOverrideObserver: NotificationObserverBox?

    public init(
        persistence: PersistenceController,
        goalOverrideStore: TemplateGoalOverrideStore? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        // 기본 인자 자리에서 만들면 nonisolated 컨텍스트라 @MainActor 초기화가 막힌다.
        self.persistence = persistence
        self.goalOverrideStore = goalOverrideStore ?? TemplateGoalOverrideStore()
        self.calendar = calendar
        self.now = now
        observeGoalOverrides()
    }

    public func load() {
        raceCountdown = loadRaceCountdown()
        trainingDivision = resolveTrainingDivision()
        // 프리셋 카드도 사용자가 저장한 목표를 반영해야 한다. 예전에는 상세 화면만
        // override 를 적용해서, 홈의 "~90 min" 이 목표와 따로 놀았다.
        presets = HyroxPresets.all.map { goalOverrideStore.resolvedTemplate(from: $0) }
        trainingSessions = HyroxPresets
            .trainingSessions(for: trainingDivision, localizedName: TrainingSessionLocalization.name(for:))
            .compactMap { template in
                guard let kind = TrainingSessionKind.allCases.first(where: { $0.templateId == template.id })
                else { return nil }
                return TrainingSessionItem(kind: kind, template: template)
            }
        customTemplates = (try? persistence.fetchAllTemplates()) ?? []
        recentWorkouts = (try? persistence.fetchAllCompletedWorkouts()) ?? []
    }

    public var mostRecentWorkout: CompletedWorkout? { recentWorkouts.first }

    // MARK: - Private

    /// 훈련 세션 무게·횟수를 뽑을 디비전.
    /// 다가오는 대회 → (없으면) 가장 최근에 등록해 둔 대회 → 기본값 순으로 고른다.
    private func resolveTrainingDivision() -> HyroxDivision {
        if let division = raceCountdown?.target.division { return division }
        // `fetchRaceTargets()` 는 날짜 오름차순이라, 뒤에서부터 보면 가장 나중 대회다.
        let stored = (try? persistence.fetchRaceTargets()) ?? []
        if let division = stored.reversed().compactMap(\.division).first { return division }
        return Self.fallbackTrainingDivision
    }

    private func loadRaceCountdown() -> RaceCountdown? {
        let reference = now()
        guard
            let target = try? persistence.fetchUpcomingRaceTarget(now: reference, calendar: calendar)
        else { return nil }
        return RaceCountdown(
            target: target,
            daysRemaining: target.daysRemaining(asOf: reference, calendar: calendar)
        )
    }

    /// 페이스 플래너/상세 화면에서 목표를 바꾸거나, 워치에서 목표가 동기화돼 오면
    /// 홈 카드의 예상 시간도 같이 갱신한다.
    private func observeGoalOverrides() {
        let token = NotificationCenter.default.addObserver(
            forName: .hyroxTemplateGoalOverrideUpdated,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.load()
                self?.onDataChanged?()
            }
        }
        goalOverrideObserver = NotificationObserverBox(token: token)
    }
}

/// 블록 기반 알림 관찰자는 자동으로 해제되지 않는다. 토큰을 평범한 클래스에 얹어 두면
/// 메인액터 상태를 건드리지 않고도 소유자가 사라질 때 같이 정리된다.
/// (`AppServices` 의 `PaceDataForegroundObserver` 와 같은 패턴)
private final class NotificationObserverBox {

    private let token: NSObjectProtocol

    init(token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
