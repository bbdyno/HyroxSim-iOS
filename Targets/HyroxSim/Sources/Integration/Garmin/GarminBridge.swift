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
import os

#if canImport(ConnectIQ)
import ConnectIQ
import UIKit

public final class GarminBridge: NSObject {

    public static let shared = GarminBridge()

    /// hello 를 다시 보내기까지의 최소 간격. 연결 상태가 바뀌면 이 간격을
    /// 무시하고 즉시 보낸다(상태 변화가 더 강한 신호이므로).
    public static let helloMinimumInterval: TimeInterval = 60

    private let logger = Logger(subsystem: "com.bbdyno.app.HyroxSim", category: "Garmin")

    public private(set) var connectedDevice: IQDevice?

    /// True once a device has been connected. Used as a precondition by
    /// sync services that refuse to transmit until the user has completed
    /// pairing in Garmin Connect Mobile.
    ///
    /// ⚠️ "기기를 고른 적이 있다" 는 뜻이지 "지금 통신할 수 있다" 가 아니다.
    /// 실제 통신 가능 여부는 `connectionState.isConnected` 를 봐야 한다.
    public var isPaired: Bool { connectedDevice != nil }
    public var connectedDeviceName: String? { connectedDevice?.friendlyName }
    /// 기기를 해제한 뒤에도 마지막 이름을 기억한다(설정 화면 표시용).
    public var lastKnownDeviceName: String? { connectedDevice?.friendlyName ?? deviceStore.lastKnownName }

    /// 지금의 실제 연결 상태. `IQDeviceStatus` 를 프레임워크 의존 없는 값으로 옮긴 것.
    public private(set) var connectionState: GarminConnectionState = .notPaired

    public var onMessageReceived: (([String: Any]) -> Void)?
    public var onDeviceStatusChanged: ((IQDeviceStatus) -> Void)?
    /// 연결 상태가 바뀔 때마다. 설정 화면이 실시간으로 갱신되도록.
    public var onConnectionStateChanged: ((GarminConnectionState) -> Void)?
    /// Fired whenever the connected device changes (pairing success, user
    /// unpairs, etc.). `nil` device = disconnected.
    public var onConnectedDeviceChanged: ((IQDevice?) -> Void)?
    /// Fired when the watch responds with `hello.ack`. This is the only
    /// signal we have that the watch app is actually running and has
    /// processed our hello — use it to (re)push state the watch needs but
    /// can have missed: existing custom templates, the active goal, etc.
    public var onHelloAck: (() -> Void)?

    private let sdk = ConnectIQ.sharedInstance()
    private let deviceStore = GarminDeviceStore()
    private var trackedApp: IQApp?

    private var lastHelloSentAt: Date?
    private var lastHelloState: GarminConnectionState?

    private override init() {
        super.init()
    }

    /// Call from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    /// Passing a URL scheme registers us with the Garmin Connect Mobile app.
    public func bootstrap(urlScheme: String) {
        // CFBundleDisplayName is mandatory — the SDK embeds it into the
        // gcm-ciq:// URL as `hostDisplayName`. Empty/missing value causes
        // GCM to silently reject the device-selection request (picker never
        // appears). Assert on debug builds so regressions are caught early.
        let displayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? ""
        assert(!displayName.isEmpty, "CFBundleDisplayName must be set for Garmin device selection to work")
        // Use the 3-arg variant that sets a CBCentralManager restoration
        // identifier. The official Garmin example always uses this form;
        // the 2-arg variant skips BLE state restoration and can leave the
        // device picker unresponsive on iOS 17+.
        sdk?.initialize(
            withUrlScheme: urlScheme,
            uiOverrideDelegate: self,
            stateRestorationIdentifier: "HyroxSimCIQ"
        )
        restoreLastDevice()
    }

    /// Delegate this from `application(_:open:options:)` or SceneDelegate's
    /// openURLContexts. Returns `true` when the URL was a ConnectIQ
    /// device-selection response (regardless of whether a device was chosen).
    public func handle(url: URL) -> Bool {
        guard let devices = sdk?.parseDeviceSelectionResponse(from: url) else {
            return false
        }
        if let device = devices.first as? IQDevice {
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
        onConnectedDeviceChanged?(device)
        // 등록 직후의 실제 상태를 즉시 반영한다. 첫 status 콜백을 기다리는
        // 동안 화면이 "연결됨" 으로 거짓말하지 않도록.
        let status = sdk?.getDeviceStatus(device) ?? .notConnected
        updateConnectionState(GarminConnectionState(status))
        logger.info("registered device=\(device.friendlyName ?? "?", privacy: .public) status=\(status.rawValue) — waiting for characteristics discovery")
    }

    /// 사용자가 설정에서 기기를 해제했다. 등록을 풀고 저장소를 비운다.
    /// 밀려 있던 전송 큐도 버린다 — 다음 기기가 남의 큐를 물려받으면 안 된다.
    public func disconnectDevice() {
        let name = connectedDevice?.friendlyName ?? "?"
        if let device = connectedDevice {
            sdk?.unregister(forDeviceEvents: device, delegate: self)
        }
        if let app = trackedApp {
            sdk?.unregister(forAppMessages: app, delegate: self)
        }
        connectedDevice = nil
        trackedApp = nil
        deviceStore.clear()
        lastHelloSentAt = nil
        lastHelloState = nil
        onConnectedDeviceChanged?(nil)
        updateConnectionState(.notPaired)
        logger.info("disconnected device=\(name, privacy: .public)")
        Task { @MainActor in
            GarminSyncDispatcher.shared.reset(reason: "device-disconnected")
            GarminSyncStateStore().reset()
        }
    }

    /// hello 를 보낸다.
    ///
    /// 디바운스: 마지막 hello 이후 `helloMinimumInterval` 이 지나지 않았고
    /// 연결 상태도 그대로면 건너뛴다. 예전에는 앱이 포그라운드로 올라올
    /// 때마다 무조건 보냈고, 매 ack 마다 전체 재동기화가 뒤따랐다.
    /// - Parameter force: 간격을 무시하고 보낸다(사용자가 직접 요청한 경우).
    public func sendHello(force: Bool = false, reason: String = "manual") {
        let state = connectionState
        if !force,
           let last = lastHelloSentAt,
           lastHelloState == state,
           Date().timeIntervalSince(last) < Self.helloMinimumInterval {
            logger.debug("hello skipped reason=\(reason, privacy: .public) state=\(state.rawValue, privacy: .public)")
            return
        }
        lastHelloSentAt = Date()
        lastHelloState = state

        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        logger.info("hello reason=\(reason, privacy: .public) state=\(state.rawValue, privacy: .public)")
        sendEnvelope(GarminMessageCodec.makeEnvelope(
            type: GarminMessageCodec.MessageType.hello,
            payload: ["phone_os": "ios", "app_version": appVersion]
        ))
    }

    /// 결과를 보지 않는 즉시 전송. `ack`/`nack`/`hello` 처럼 재전송할 가치가
    /// 없는 메시지 전용이다. 상태 메시지는 `GarminSyncDispatcher` 를 써야 한다.
    public func sendEnvelope(_ envelope: [String: Any]) {
        transmit(envelope) { _ in }
    }

    public func transmit(_ envelope: [String: Any], completion: @escaping (GarminSendOutcome) -> Void) {
        guard let app = trackedApp else {
            logger.warning("transmit dropped — no paired device")
            completion(.failed(reason: "no-device"))
            return
        }
        let type = (envelope[GarminMessageCodec.Key.type] as? String) ?? "?"
        logger.info("TX t=\(type, privacy: .public)")
        sdk?.sendMessage(
            envelope,
            to: app,
            progress: nil,
            completion: { result in
                // ConnectIQ 는 워치 앱이 닫혀 있으면 AppNotFound /
                // DeviceNotAvailable 로 실패를 준다. 즉 success 는 "워치 앱이
                // 실제로 받았다" 에 가깝고, outbox 의 제거 신호로 쓸 수 있다.
                completion(result == .success
                    ? .delivered
                    : .failed(reason: "\(NSStringFromSendMessageResult(result) ?? "unknown")(\(result.rawValue))"))
            }
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

    fileprivate func updateConnectionState(_ state: GarminConnectionState) {
        guard state != connectionState else { return }
        connectionState = state
        onConnectionStateChanged?(state)
        Task { @MainActor in
            GarminSyncDispatcher.shared.connectionDidChange(to: state)
        }
    }
}

// MARK: - Transport

extension GarminBridge: GarminEnvelopeTransport, GarminReplySender {
    public var garminConnectionState: GarminConnectionState { connectionState }
}

extension GarminBridge: IQDeviceEventDelegate {
    public func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        logger.info("device status \(device.friendlyName ?? "?", privacy: .public)=\(status.rawValue)")
        onDeviceStatusChanged?(status)
        updateConnectionState(GarminConnectionState(status))
        // `deviceCharacteristicsDiscovered` only fires once per BLE session,
        // and CIQ does not queue app messages while the watch app is closed.
        // Resending hello on every reconnect gives the watch a fresh chance
        // to record pairing once the user opens the app on their watch.
        if status == .connected {
            sendHello(reason: "status-connected")
        }
    }

    public func deviceCharacteristicsDiscovered(_ device: IQDevice) {
        logger.info("characteristics discovered \(device.friendlyName ?? "?", privacy: .public) — sending hello")
        sendHello(reason: "characteristics")
    }
}

extension GarminBridge: IQUIOverrideDelegate {
    public func needsToInstallConnectMobile() {
        sdk?.showAppStoreForConnectMobile()
    }
}

extension GarminBridge: IQAppMessageDelegate {
    public func receivedMessage(_ message: Any, from app: IQApp) {
        guard let dict = message as? [String: Any] else {
            logger.warning("RX dropped — non-dict payload")
            return
        }
        let type = (dict[GarminMessageCodec.Key.type] as? String) ?? "?"
        let messageId = dict[GarminMessageCodec.Key.id] as? String
        logger.info("RX t=\(type, privacy: .public)")
        // Both signals mean "watch app is alive and ready to receive
        // state". hello.ack is the response to our outbound hello;
        // sync.request is the watch's unsolicited boot ping for the
        // case where iOS was already foreground+BLE-connected and never
        // emitted a hello in the first place.
        if type == GarminMessageCodec.MessageType.helloAck
                || type == GarminMessageCodec.MessageType.syncRequest {
            // 큐에 밀려 있던 것부터 먼저 내보낸다. `onHelloAck` 의 변경분
            // 재동기화는 그 뒤에 붙는다.
            Task { @MainActor in GarminSyncDispatcher.shared.watchDidBecomeReachable() }
            onHelloAck?()
        }
        // 워치가 우리 상태 메시지를 받았다는 확인. 큐에서 지운다.
        if type == GarminMessageCodec.MessageType.ack, let messageId {
            Task { @MainActor in GarminSyncDispatcher.shared.acknowledge(messageId: messageId) }
        }
        onMessageReceived?(dict)
    }
}

extension GarminConnectionState {
    init(_ status: IQDeviceStatus) {
        switch status {
        case .invalidDevice: self = .notPaired
        case .bluetoothNotReady: self = .bluetoothOff
        case .notFound: self = .notFound
        case .notConnected: self = .disconnected
        case .connected: self = .connected
        @unknown default: self = .disconnected
        }
    }
}

#else

/// Stub exposed when ConnectIQ.xcframework is not present. Prevents call-site
/// compilation errors; runtime calls are no-ops that log a warning once.
public final class GarminBridge {
    public static let shared = GarminBridge()
    public static let helloMinimumInterval: TimeInterval = 60

    public var onMessageReceived: (([String: Any]) -> Void)?
    public var onConnectedDeviceChanged: ((Any?) -> Void)?
    public var onConnectionStateChanged: ((GarminConnectionState) -> Void)?
    public var onHelloAck: (() -> Void)?
    public var isPaired: Bool { false }
    public var connectedDeviceName: String? { nil }
    public var lastKnownDeviceName: String? { nil }
    public var connectionState: GarminConnectionState { .notPaired }

    private init() {}
    public func bootstrap(urlScheme: String) {
        print("⚠️ GarminBridge: ConnectIQ.xcframework not linked. See Frameworks/README.md")
    }
    public func handle(url: URL) -> Bool { false }
    public func requestDeviceSelection() {}
    public func disconnectDevice() {}
    public func sendHello(force: Bool = false, reason: String = "manual") {}
    public func sendEnvelope(_ envelope: [String: Any]) {}
    public func transmit(_ envelope: [String: Any], completion: @escaping (GarminSendOutcome) -> Void) {
        completion(.failed(reason: "connectiq-not-linked"))
    }
}

extension GarminBridge: GarminEnvelopeTransport, GarminReplySender {
    public var garminConnectionState: GarminConnectionState { .notPaired }
}

#endif
