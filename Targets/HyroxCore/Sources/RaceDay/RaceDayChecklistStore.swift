//
//  RaceDayChecklistStore.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

/// 체크리스트 상태 저장소.
///
/// 대회 하나짜리 준비물 목록이라 동기화도 마이그레이션도 필요 없다 — `UserDefaults` 면 충분하다.
/// 다만 사람은 대회를 여러 번 나가므로 **대회 단위(`raceKey`)로 분리**해 저장한다.
/// 지난 대회의 체크가 다음 대회 화면에 그대로 남아 있으면 안 되기 때문이다.
///
/// 저장 형식: `[raceKey: [itemId]]`. 읽을 때 현재 카탈로그에 없는 ID 는 걸러내
/// 항목이 바뀌어도 죽은 값이 남지 않는다.
///
/// `UserDefaults` 가 `Sendable` 이 아니라 이 타입도 `Sendable` 로 선언하지 않는다.
/// 체크리스트는 화면에서만 읽고 쓰므로 스레드를 넘길 일이 없다.
public struct RaceDayChecklistStore {

    /// 등록된 대회가 없을 때 쓰는 기본 키.
    public static let defaultRaceKey = "default"

    private static let storageKey = "raceDay.checklist.checkedItems.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 읽기

    /// 해당 대회에서 체크된 항목 ID. 카탈로그에 없는 ID 는 제외된다.
    public func checkedItemIds(raceKey: String = defaultRaceKey) -> Set<String> {
        let stored = storage()[raceKey] ?? []
        return Set(stored).intersection(RaceDayChecklist.allIds)
    }

    public func isChecked(_ itemId: String, raceKey: String = defaultRaceKey) -> Bool {
        checkedItemIds(raceKey: raceKey).contains(itemId)
    }

    /// 분류별 진행 상황 (완료 수, 전체 수).
    public func progress(
        in category: RaceDayChecklistCategory,
        raceKey: String = defaultRaceKey
    ) -> (done: Int, total: Int) {
        let items = RaceDayChecklist.items(in: category)
        let checked = checkedItemIds(raceKey: raceKey)
        return (items.filter { checked.contains($0.id) }.count, items.count)
    }

    // MARK: - 쓰기

    public func setChecked(_ isChecked: Bool, itemId: String, raceKey: String = defaultRaceKey) {
        guard RaceDayChecklist.allIds.contains(itemId) else { return }
        var all = storage()
        var current = Set(all[raceKey] ?? [])
        if isChecked {
            current.insert(itemId)
        } else {
            current.remove(itemId)
        }
        if current.isEmpty {
            all.removeValue(forKey: raceKey)
        } else {
            all[raceKey] = current.sorted()
        }
        write(all)
    }

    /// 체크 상태를 뒤집고 바뀐 뒤의 값을 돌려준다.
    @discardableResult
    public func toggle(itemId: String, raceKey: String = defaultRaceKey) -> Bool {
        let next = !isChecked(itemId, raceKey: raceKey)
        setChecked(next, itemId: itemId, raceKey: raceKey)
        return next
    }

    /// 한 대회의 체크를 모두 지운다. 대회가 끝난 뒤 다음 대회를 위해 비우는 용도.
    public func reset(raceKey: String = defaultRaceKey) {
        var all = storage()
        guard all.removeValue(forKey: raceKey) != nil else { return }
        write(all)
    }

    /// 모든 대회의 체크를 지운다.
    public func resetAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - 저장소 접근

    private func storage() -> [String: [String]] {
        defaults.dictionary(forKey: Self.storageKey) as? [String: [String]] ?? [:]
    }

    private func write(_ value: [String: [String]]) {
        if value.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(value, forKey: Self.storageKey)
        }
    }
}

// MARK: - 대회 키

public extension RaceDayChecklistStore {

    /// 대회 목표에서 저장 키를 만든다. 등록된 대회가 없으면 기본 키.
    static func raceKey(for target: RaceTarget?) -> String {
        target?.id.uuidString ?? defaultRaceKey
    }
}
