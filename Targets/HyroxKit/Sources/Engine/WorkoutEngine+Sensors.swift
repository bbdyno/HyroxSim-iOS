//
//  WorkoutEngine+Sensors.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

extension WorkoutEngine {

    /// Attaches a location stream to the engine.
    /// Returns a `Task` that continuously ingests location samples.
    /// The caller should retain the task and cancel it when the workout ends.
    public func attachLocationStream(_ stream: some LocationStreaming) -> Task<Void, Never> {
        Task { [weak self] in
            for await sample in stream.samples {
                guard !Task.isCancelled else { break }
                self?.ingest(locationSample: sample)
            }
        }
    }

    /// Attaches a heart rate stream to the engine.
    /// Returns a `Task` that continuously ingests heart rate samples.
    /// The caller should retain the task and cancel it when the workout ends.
    public func attachHeartRateStream(_ stream: some HeartRateStreaming) -> Task<Void, Never> {
        Task { [weak self] in
            for await sample in stream.samples {
                guard !Task.isCancelled else { break }
                self?.ingest(heartRateSample: sample)
            }
        }
    }
}
