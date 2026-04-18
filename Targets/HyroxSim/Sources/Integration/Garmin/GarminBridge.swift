//
//  GarminBridge.swift
//  HyroxSim
//
//  Created by bbdyno on 4/19/26.
//
//  Lifecycle wrapper around `ConnectIQ.framework`. Responsible for:
//    - SDK init / URL scheme handling
//    - Device discovery & pairing persistence
//    - Message send/receive routing
//
//  File compiles to an empty unit when ConnectIQ.xcframework is not
//  dropped into `Frameworks/`. See `Frameworks/README.md` for drop-in
//  procedure. Downstream call sites must also use `#if canImport`.

import Foundation

#if canImport(ConnectIQ)
import ConnectIQ

public final class GarminBridge: NSObject {

    public static let shared = GarminBridge()

    public private(set) var connectedDevice: IQDevice?

    public var onMessageReceived: (([String: Any]) -> Void)?
    public var onDeviceStatusChanged: ((IQDeviceStatus) -> Void)?

    private let sdk = ConnectIQ.sharedInstance()
    private let deviceStore = GarminDeviceStore()
    private var trackedApp: IQApp?

    private override init() {
        super.init()
    }

    /// Call from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    /// Passing a URL scheme registers us with the Garmin Connect Mobile app.
    public func bootstrap(urlScheme: String) {
        sdk?.initialize(
            withUrlScheme: urlScheme,
            uiOverrideDelegate: nil
        )
        restoreLastDevice()
    }

    /// Delegate this from `application(_:open:options:)`.
    public func handle(url: URL) -> Bool {
        guard let devices = sdk?.parseDeviceSelectionResponse(from: url) else {
            return false
        }
        if let device = devices.first {
            connect(to: device)
        }
        return true
    }

    /// Opens Garmin Connect Mobile for device picker. User returns via URL scheme.
    public func requestDeviceSelection() {
        sdk?.showDeviceSelection()
    }

    public func connect(to device: IQDevice) {
        connectedDevice = device
        sdk?.register(forDeviceEvents: device, delegate: self)
        deviceStore.save(device: device)
        trackedApp = makeApp(for: device)
        if let app = trackedApp {
            sdk?.register(forAppMessages: app, delegate: self)
        }
    }

    public func sendEnvelope(_ envelope: [String: Any]) {
        guard let app = trackedApp else { return }
        sdk?.sendMessage(
            envelope,
            to: app,
            progress: nil,
            completion: nil
        )
    }

    // MARK: - Private

    private func restoreLastDevice() {
        guard let device = deviceStore.loadDevice(sdk: sdk) else { return }
        connect(to: device)
    }

    private func makeApp(for device: IQDevice) -> IQApp? {
        // Must match the applicationId in HyroxSim-Garmin/manifest.xml
        guard let uuid = UUID(
            uuidString: "AB20831C-3CC3-A8F6-B692-02DD7E0CA823"
        ) else { return nil }
        return IQApp(uuid: uuid, store: UUID(), device: device)
    }
}

extension GarminBridge: IQDeviceEventDelegate {
    public func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        onDeviceStatusChanged?(status)
    }
}

extension GarminBridge: IQAppMessageDelegate {
    public func receivedMessage(_ message: Any, from app: IQApp) {
        guard let dict = message as? [String: Any] else { return }
        onMessageReceived?(dict)
    }
}

#else

/// Stub exposed when ConnectIQ.xcframework is not present. Prevents call-site
/// compilation errors; runtime calls are no-ops that log a warning once.
public final class GarminBridge {
    public static let shared = GarminBridge()
    public var onMessageReceived: (([String: Any]) -> Void)?

    private init() {}
    public func bootstrap(urlScheme: String) {
        print("⚠️ GarminBridge: ConnectIQ.xcframework not linked. See Frameworks/README.md")
    }
    public func handle(url: URL) -> Bool { false }
    public func requestDeviceSelection() {}
    public func sendEnvelope(_ envelope: [String: Any]) {}
}

#endif
