//
//  EngineState.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// Represents the current state of a workout engine
public enum EngineState: Hashable, Sendable {
    /// Workout has not started yet
    case idle
    /// Workout is actively running
    case running(currentIndex: Int, segmentStartedAt: Date, workoutStartedAt: Date)
    /// Workout is paused (stores accumulated elapsed times, not wall-clock timestamps)
    case paused(currentIndex: Int, segmentElapsed: TimeInterval, totalElapsed: TimeInterval)
    /// Workout has completed
    case finished(workoutStartedAt: Date, finishedAt: Date)
}
