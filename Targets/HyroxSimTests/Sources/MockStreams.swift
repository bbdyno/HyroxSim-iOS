//
//  MockStreams.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import HyroxCore

final class MockLocationStream: LocationStreaming, @unchecked Sendable {
    private var continuation: AsyncStream<LocationSample>.Continuation?
    let samples: AsyncStream<LocationSample>
    private(set) var authorizationStatus: SensorAuthorizationStatus = .authorized

    init() {
        var cont: AsyncStream<LocationSample>.Continuation!
        self.samples = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    func start() async throws {}
    func stop() { continuation?.finish() }
}

final class MockHeartRateStream: HeartRateStreaming, @unchecked Sendable {
    private var continuation: AsyncStream<HeartRateSample>.Continuation?
    let samples: AsyncStream<HeartRateSample>
    private(set) var authorizationStatus: SensorAuthorizationStatus = .authorized

    init() {
        var cont: AsyncStream<HeartRateSample>.Continuation!
        self.samples = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    func start() async throws {}
    func stop() { continuation?.finish() }
}
