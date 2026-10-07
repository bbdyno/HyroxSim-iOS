//
//  GarminConnectionState.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

/// ConnectIQ 의 `IQDeviceStatus` 를 앱 전체에서 쓸 수 있는 형태로 옮긴 값.
///
/// `IQDeviceStatus` 는 `ConnectIQ.xcframework` 가 링크된 빌드에서만 존재하므로,
/// 설정 화면처럼 프레임워크 유무와 무관하게 컴파일돼야 하는 코드는 이 타입만 본다.
///
/// `isPaired`(= 기기를 한 번이라도 고른 적 있음) 와 `connected`(= 지금 통신 가능)
/// 를 구분하는 것이 핵심이다. 예전 설정 화면은 전자를 "Connected" 로 표시해서
/// 블루투스가 꺼져 있어도 연결된 것처럼 보였다.
public enum GarminConnectionState: String, Sendable, CaseIterable {
    /// 기기를 고른 적이 없거나 사용자가 해제했다.
    case notPaired
    /// 기기는 등록돼 있지만 iOS 블루투스가 꺼졌거나 리셋 중이다.
    case bluetoothOff
    /// iOS 가 기기를 찾지 못한다(가민 커넥트에서 제거됐을 가능성).
    case notFound
    /// 기기는 알고 있지만 지금은 연결돼 있지 않다.
    case disconnected
    /// 연결됐고 메시지를 보낼 수 있다.
    case connected

    /// 지금 메시지를 실제로 전달할 수 있는지. outbox flush 의 유일한 판단 기준.
    public var isConnected: Bool { self == .connected }

    /// 기기를 고른 적이 있는지. 해제 행 노출 여부를 정할 때 쓴다.
    public var hasSelectedDevice: Bool { self != .notPaired }
}

/// `GarminEnvelopeTransport.transmit` 의 결과.
///
/// ConnectIQ 는 워치 앱이 닫혀 있으면 `AppNotFound` / `DeviceNotAvailable` 로
/// 실패를 돌려준다. 즉 `delivered` 는 "워치 앱이 실제로 받았다" 에 가깝고,
/// 그래서 outbox 는 이 결과를 큐 제거 신호로 쓸 수 있다.
public enum GarminSendOutcome: Sendable, Equatable {
    case delivered
    case failed(reason: String)
}

/// outbox 가 메시지를 내보낼 때 쓰는 최소 인터페이스.
/// `GarminBridge` 가 구현하고, 테스트는 가짜 구현을 끼운다.
///
/// 전역 액터를 붙이지 않는다. `GarminBridge` 는 ConnectIQ 델리게이트 콜백을
/// 임의 큐에서 받는 `NSObject` 라서 클래스를 메인 액터에 묶을 수 없다.
/// 대신 호출자(`GarminSyncDispatcher`)가 `completion` 안에서 메인으로 넘어간다.
public protocol GarminEnvelopeTransport: AnyObject {
    var garminConnectionState: GarminConnectionState { get }
    func transmit(_ envelope: [String: Any], completion: @escaping (GarminSendOutcome) -> Void)
}

/// 받은 메시지에 대한 즉답(`ack` / `nack`)을 보내는 최소 인터페이스.
///
/// 즉답은 outbox 를 타지 않는다. 못 보내면 워치가 기록을 지우지 않고 다시
/// 보내오고, 수신 쪽은 upsert 라 중복이 생기지 않기 때문이다. 큐에 쌓아 두면
/// 이미 정리된 기록에 대한 ack 만 늘어난다.
public protocol GarminReplySender: AnyObject {
    func sendEnvelope(_ envelope: [String: Any])
}
