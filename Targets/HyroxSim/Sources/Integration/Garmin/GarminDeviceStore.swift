//
//  GarminDeviceStore.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//

import Foundation

#if canImport(ConnectIQ)
import ConnectIQ

/// Persists the UUID of the last-paired Garmin device so we can silently
/// reconnect on app launch. Garmin Connect Mobile owns the actual device
/// handle — we just remember which one to rebind to.
struct GarminDeviceStore {
    private let defaults: UserDefaults
    private let deviceUUIDKey = "garmin.lastDeviceUUID"
    private let deviceNameKey = "garmin.lastDeviceName"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(device: IQDevice) {
        defaults.set(device.uuid.uuidString, forKey: deviceUUIDKey)
        defaults.set(device.friendlyName, forKey: deviceNameKey)
    }

    func loadDevice(sdk: ConnectIQ?) -> IQDevice? {
        guard
            let uuidString = defaults.string(forKey: deviceUUIDKey),
            let uuid = UUID(uuidString: uuidString),
            let name = defaults.string(forKey: deviceNameKey)
        else { return nil }
        // Reconstructing from UUID alone requires SDK internals; for now we
        // return a minimal IQDevice and rely on SDK re-population on connect.
        return IQDevice(id: uuid, modelName: name, friendlyName: name)
    }

    func clear() {
        defaults.removeObject(forKey: deviceUUIDKey)
        defaults.removeObject(forKey: deviceNameKey)
    }

    var lastKnownName: String? {
        defaults.string(forKey: deviceNameKey)
    }
}

#endif
