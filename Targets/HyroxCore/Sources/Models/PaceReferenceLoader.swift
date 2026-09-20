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
    private static let plannerCache = PaceReferenceCache<PacePlanner>()

    /// Same deal for the v4 snapshot: 9 files, ~110 KB, decoded and validated once.
    private static let bundledSnapshotCache = PaceReferenceCache<PaceDataSnapshot>()
    private static let bundledManifestCache = PaceReferenceCache<PaceDataManifest>()

    /// Load the pace planner bucket data, decoding the bundled JSON at most once.
    /// - Throws: `PaceReferenceError` when the resource is missing or corrupt.
    ///   Every failure is logged before it is rethrown, so a `try?` at a call site
    ///   still leaves a trace.
    public static func loadPacePlanner() throws -> PacePlanner {
        try plannerCache.value(loading: decodePacePlanner)
    }

    /// Drops the decoded copies. Test-only seam.
    static func resetCache() {
        plannerCache.reset()
        bundledSnapshotCache.reset()
        bundledManifestCache.reset()
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

// MARK: - v4 Datasets

extension PaceReferenceLoader {

    /// Decode one `schema_version` 4 division file.
    ///
    /// The single place JSON becomes a ``PaceDataset``: the bundled snapshot, the
    /// on-disk cache and a fresh download all come through here, so they cannot drift
    /// apart in how they read a file or report a bad one.
    ///
    /// - Note: Decoding alone proves nothing about the numbers. Run
    ///   ``PaceDatasetValidator/validate(_:expecting:datasetVersion:)`` before use, or
    ///   build a ``PaceDataSnapshot``, which validates for you.
    public static func decodeDataset(from data: Data, resourceName: String) throws -> PaceDataset {
        do {
            return try JSONDecoder().decode(PaceDataset.self, from: data)
        } catch {
            throw PaceDataError.decodingFailed(
                resource: resourceName,
                reason: String(describing: error)
            )
        }
    }

    /// Decode a catalogue file (`manifest.json`).
    public static func decodeManifest(from data: Data, resourceName: String) throws -> PaceDataManifest {
        do {
            return try JSONDecoder().decode(PaceDataManifest.self, from: data)
        } catch {
            throw PaceDataError.decodingFailed(
                resource: resourceName,
                reason: String(describing: error)
            )
        }
    }

    /// The catalogue that describes the snapshot shipped inside the app.
    public static func loadBundledManifest() throws -> PaceDataManifest {
        try bundledManifestCache.value(loading: decodeBundledManifest)
    }

    /// The validated v4 snapshot shipped inside the app.
    ///
    /// This is the floor the app always has: it works offline, on a first run, and
    /// whenever a download or the on-disk cache turns out to be unusable.
    public static func loadBundledPaceData() throws -> PaceDataSnapshot {
        try bundledSnapshotCache.value(loading: decodeBundledSnapshot)
    }

    /// Raw bytes of one bundled division file, exactly as they sit in the bundle.
    ///
    /// Exposed so a test can check them against the bundled manifest's SHA-256 —
    /// that is what catches a snapshot refresh that copied the tables but forgot the
    /// manifest, which would otherwise only surface as a wrong "current version".
    public static func bundledDatasetData(for division: HyroxDivision) throws -> Data {
        let name = division.rawValue
        guard let url = bundledV4URL(named: name) else {
            throw PaceDataError.resourceMissing("\(name).json")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw PaceDataError.decodingFailed(
                resource: "\(name).json",
                reason: String(describing: error)
            )
        }
    }

    // MARK: - Private

    private static func decodeBundledManifest() throws -> PaceDataManifest {
        guard let url = bundledV4URL(named: "manifest") else {
            logger.error("v4 manifest.json is missing from the HyroxCore bundle")
            throw PaceDataError.resourceMissing("manifest.json")
        }
        do {
            let data = try Data(contentsOf: url)
            return try decodeManifest(from: data, resourceName: "manifest.json")
        } catch let error as PaceDataError {
            logger.error("bundled v4 manifest is unusable: \(error.description, privacy: .public)")
            throw error
        } catch {
            logger.error("bundled v4 manifest could not be read: \(String(describing: error), privacy: .public)")
            throw PaceDataError.decodingFailed(
                resource: "manifest.json",
                reason: String(describing: error)
            )
        }
    }

    private static func decodeBundledSnapshot() throws -> PaceDataSnapshot {
        let manifest = try loadBundledManifest()
        let entries = try manifest.validatedFiles()

        var datasets: [HyroxDivision: PaceDataset] = [:]
        for division in entries.keys {
            let data = try bundledDatasetData(for: division)
            datasets[division] = try decodeDataset(from: data, resourceName: "\(division.rawValue).json")
        }

        do {
            return try PaceDataSnapshot(
                datasetVersion: manifest.datasetVersion,
                origin: .bundled,
                datasets: datasets
            )
        } catch {
            logger.error("bundled v4 snapshot failed validation: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Locate a bundled v4 resource.
    ///
    /// Tuist registers the files under `Resources/PaceReference/v4`, but the Xcode
    /// resources phase flattens plain file references into the bundle root. Which of
    /// the two layouts a given generation produces is not worth depending on, so both
    /// are tried.
    private static func bundledV4URL(named name: String) -> URL? {
        let bundle = Bundle.module
        return bundle.url(forResource: name, withExtension: "json", subdirectory: "PaceReference/v4")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "v4")
            ?? bundle.url(forResource: name, withExtension: "json")
    }
}

// MARK: - Cache

/// Holds one decoded value. The value itself is `Sendable`, so the only state needing
/// protection is the slot holding it. A lock keeps the loader callable from any thread
/// without pinning it to the main actor.
private final class PaceReferenceCache<Value: Sendable>: @unchecked Sendable {

    private let lock = NSLock()
    private var cached: Value?

    func value(loading load: () throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }
        let value = try load()
        cached = value
        return value
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
    }
}
