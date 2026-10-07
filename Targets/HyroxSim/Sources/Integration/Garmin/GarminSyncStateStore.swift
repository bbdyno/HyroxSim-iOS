//
//  GarminSyncStateStore.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import os

/// "무엇을 마지막으로 언제 워치에 보냈는지" 를 기억한다.
///
/// 예전에는 `hello.ack` 이 올 때마다 커스텀 템플릿 전체 + 프리셋 목표 9건을
/// 통째로 다시 보냈다. 앱을 포그라운드로 올릴 때마다 hello 를 보냈으니,
/// 바뀐 것이 하나도 없어도 수십 건이 BLE 로 나갔다.
///
/// 이제는 대상별로 **내용 지문(fingerprint)** 을 남겨 두고, 지문이 달라진
/// 것만 보낸다. `WorkoutTemplate` 에는 수정 시각이 없어서(생성 시각만 있다)
/// 시각 대신 내용 해시를 변경 판정에 쓴다 — 이름만 고쳐도 잡힌다.
@MainActor
public final class GarminSyncStateStore {

    private let logger = Logger(subsystem: "com.bbdyno.app.HyroxSim", category: "GarminSync")
    private let defaults: UserDefaults
    private let fingerprintsKey = "garmin.sync.fingerprints"
    private let lastSyncedAtKey = "garmin.sync.lastSyncedAt"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 마지막으로 무언가를 성공적으로 큐에 올린 시각. 진단용.
    public var lastSyncedAt: Date? {
        defaults.object(forKey: lastSyncedAtKey) as? Date
    }

    private var fingerprints: [String: String] {
        get { defaults.dictionary(forKey: fingerprintsKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: fingerprintsKey) }
    }

    /// 이 대상의 내용이 마지막 동기화 이후 바뀌었는지.
    public func hasChanged(key: String, fingerprint: String) -> Bool {
        fingerprints[key] != fingerprint
    }

    /// 대상을 "보냄" 으로 표시한다. 큐에 넣는 데 성공한 직후 호출한다.
    public func markSynced(key: String, fingerprint: String, at date: Date = Date()) {
        var map = fingerprints
        map[key] = fingerprint
        fingerprints = map
        defaults.set(date, forKey: lastSyncedAtKey)
    }

    /// 대상을 잊는다. 삭제한 템플릿이 같은 id 로 되살아나면 다시 보내야 하므로.
    public func forget(key: String) {
        var map = fingerprints
        guard map.removeValue(forKey: key) != nil else { return }
        fingerprints = map
    }

    /// 전부 잊는다. 기기를 해제하면 다음 기기는 처음부터 받아야 한다.
    public func reset() {
        logger.info("sync fingerprints reset")
        defaults.removeObject(forKey: fingerprintsKey)
        defaults.removeObject(forKey: lastSyncedAtKey)
    }
}
