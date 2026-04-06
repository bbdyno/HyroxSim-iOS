//
//  MockHeartRateStream.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
@testable import HyroxKit

/// Mock HeartRateStreaming for testing engine attachment.
final class MockHeartRateStream: HeartRateStreaming, @unchecked Sendable {
    private var continuation: AsyncStream<HeartRateSample>.Continuation?
    let samples: AsyncStream<HeartRateSample>
    private(set) var authorizationStatus: SensorAuthorizationStatus = .authorized

    private let pendingSamples: [HeartRateSample]

    init(samples pendingSamples: [HeartRateSample] = []) {
        self.pendingSamples = pendingSamples
        var cont: AsyncStream<HeartRateSample>.Continuation!
        self.samples = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    func start() async throws {
        for sample in pendingSamples {
            continuation?.yield(sample)
        }
    }

    func stop() {
        continuation?.finish()
    }

    func yield(_ sample: HeartRateSample) {
        continuation?.yield(sample)
    }

    func finish() {
        continuation?.finish()
    }
}
