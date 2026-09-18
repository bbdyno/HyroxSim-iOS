//
//  PaceReferenceLoader.swift
//  HyroxCore
//
//  Created by bbdyno on 4/17/26.
//

import Foundation
import os

public enum PaceReferenceLoader {

    private static let logger = Logger(
        subsystem: "com.bbdyno.app.HyroxSim.core",
        category: "PaceReference"
    )

    /// The bundled table is ~90 KB of JSON and never changes at runtime, so it is
    /// decoded once and handed out to every planner screen afterwards.
    private static let cache = PlannerCache()

    /// Load the pace planner bucket data, decoding the bundled JSON at most once.
    /// - Throws: `PaceReferenceError` when the resource is missing or corrupt.
    ///   Every failure is logged before it is rethrown, so a `try?` at a call site
    ///   still leaves a trace.
    public static func loadPacePlanner() throws -> PacePlanner {
        try cache.planner(loading: decodePacePlanner)
    }

    /// Drops the decoded copy. Test-only seam.
    static func resetCache() {
        cache.reset()
    }

    private static func decodePacePlanner() throws -> PacePlanner {
        guard let url = Bundle.module.url(forResource: "pace_planner", withExtension: "json") else {
            logger.error("pace_planner.json is missing from the HyroxCore bundle")
            throw PaceReferenceError.fileNotFound
        }

        do {
            let data = try Data(contentsOf: url)
            let plannerData = try JSONDecoder().decode(PacePlannerData.self, from: data)
            return PacePlanner(data: plannerData)
        } catch {
            logger.error("pace_planner.json could not be decoded: \(String(describing: error), privacy: .public)")
            throw PaceReferenceError.decodingFailed(String(describing: error))
        }
    }
}

public enum PaceReferenceError: Error, Sendable {
    case fileNotFound
    case decodingFailed(String)
}

// MARK: - Cache

/// `PacePlanner` is a `Sendable` value, so the only state needing protection is the
/// slot holding it. A lock keeps the loader callable from any thread without pinning
/// it to the main actor.
private final class PlannerCache: @unchecked Sendable {

    private let lock = NSLock()
    private var cached: PacePlanner?

    func planner(loading load: () throws -> PacePlanner) rethrows -> PacePlanner {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }
        let planner = try load()
        cached = planner
        return planner
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
    }
}
