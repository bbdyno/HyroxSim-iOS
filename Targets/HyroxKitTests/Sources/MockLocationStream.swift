//
//  MockLocationStream.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
@testable import HyroxKit

/// Mock LocationStreaming for testing engine attachment.
final class MockLocationStream: LocationStreaming, @unchecked Sendable {
    private var continuation: AsyncStream<LocationSample>.Continuation?
    let samples: AsyncStream<LocationSample>
    private(set) var authorizationStatus: SensorAuthorizationStatus = .authorized

    /// Samples that will be yielded on `start()`.
    private let pendingSamples: [LocationSample]

    init(samples pendingSamples: [LocationSample] = []) {
        self.pendingSamples = pendingSamples
        var cont: AsyncStream<LocationSample>.Continuation!
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

    /// Manually yield a sample (for fine-grained test control).
    func yield(_ sample: LocationSample) {
        continuation?.yield(sample)
    }

    func finish() {
        continuation?.finish()
    }
}
