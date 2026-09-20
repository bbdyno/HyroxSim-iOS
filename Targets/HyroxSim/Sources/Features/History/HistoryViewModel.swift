//
//  HistoryViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import Observation
import os
import HyroxCore
import HyroxPersistenceApple

@Observable
@MainActor
public final class HistoryViewModel {
    public private(set) var workouts: [CompletedWorkout] = []

    /// 마지막 조회가 실패했는지. 손상된 기록 하나 때문에 목록 전체가 비어
    /// 보이던 문제와 구분하기 위해 남긴다.
    public private(set) var lastLoadFailed = false

    /// 알림으로 목록이 갱신됐을 때 호출된다. 화면이 테이블을 다시 그린다.
    public var onWorkoutsChanged: (() -> Void)?

    /// 알림이 몰려 들어와도 한 번만 새로고침하기 위한 지연.
    /// 워치가 여러 기록을 연달아 보내면 알림도 연달아 온다.
    public var reloadDebounce: Duration = .milliseconds(250)

    @ObservationIgnored private let logger = Logger(subsystem: "com.bbdyno.app.HyroxSim", category: "History")
    @ObservationIgnored private let persistence: PersistenceController
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    public init(
        persistence: PersistenceController,
        notificationCenter: NotificationCenter = .default
    ) {
        self.persistence = persistence
        self.notificationCenter = notificationCenter
    }

    deinit {
        reloadTask?.cancel()
        let center = notificationCenter
        for token in observers { center.removeObserver(token) }
    }

    // MARK: - Observing

    /// 기록이 도착하거나(워치·가민) 삭제될 때 목록을 자동으로 갱신한다.
    /// 예전에는 화면에 다시 들어와야만 반영됐다.
    public func startObserving() {
        guard observers.isEmpty else { return }
        let names: [Notification.Name] = [
            // 워치/가민에서 기록이 도착했을 때 (AppCoordinator, GarminImportService)
            .syncDataUpdated,
            // 이 기기에서 기록을 지웠을 때 (PersistenceController)
            .hyroxCompletedWorkoutDeleted
        ]
        observers = names.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
        }
    }

    public func stopObserving() {
        for token in observers { notificationCenter.removeObserver(token) }
        observers.removeAll()
        reloadTask?.cancel()
        reloadTask = nil
    }

    /// 디바운스된 새로고침. 연달아 불러도 마지막 한 번만 수행한다.
    public func scheduleReload() {
        reloadTask?.cancel()
        let delay = reloadDebounce
        reloadTask = Task { @MainActor [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            self.load()
            self.onWorkoutsChanged?()
        }
    }

    // MARK: - Data

    public func load() {
        do {
            workouts = try persistence.fetchAllCompletedWorkouts()
            lastLoadFailed = false
        } catch {
            // `fetchAllCompletedWorkouts` 는 기록 하나만 깨져도 전체가 throw 한다
            // (`CompletedWorkoutMapper.toDomain` 을 `try map` 으로 돌린다).
            // 그때 목록을 비우면 멀쩡한 기록까지 사라진 것처럼 보이므로,
            // 직전 목록을 그대로 두고 실패만 기록한다.
            lastLoadFailed = true
            logger.error("history fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 기록을 지운다. 실패하면 목록을 건드리지 않고 에러를 올린다 —
    /// 예전에는 `try?` 라 저장이 실패해도 행만 사라졌다가 다음 진입에 되살아났다.
    public func delete(at index: Int) throws {
        guard workouts.indices.contains(index) else { return }
        let workout = workouts[index]
        try persistence.deleteCompletedWorkout(id: workout.id)
        // 삭제가 성공한 뒤에만 목록에서 뺀다.
        if let current = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts.remove(at: current)
        }
    }
}
