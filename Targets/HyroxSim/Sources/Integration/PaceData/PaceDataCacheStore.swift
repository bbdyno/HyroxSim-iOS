//
//  PaceDataCacheStore.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore
import os

/// What the app remembers between launches about its last catalogue check.
///
/// Deliberately does *not* record which dataset version is installed: that lives in
/// `current/manifest.json`, which is written as part of the same atomic swap as the
/// tables it describes. Keeping the version in a second file would open a window where
/// a crash between the swap and the state write leaves the two disagreeing.
struct PaceDataCacheState: Codable, Hashable, Sendable {
    /// `ETag` of the catalogue that produced the installed tables.
    var manifestETag: String?
    /// Dataset version that ETag described, so a stale pairing is never sent as
    /// `If-None-Match` after the cache has been cleared or rolled back.
    var etagDatasetVersion: String?
    var lastCheckedAt: Date?
    /// Earliest time the next check may run.
    var nextCheckNotBefore: Date?

    init(
        manifestETag: String? = nil,
        etagDatasetVersion: String? = nil,
        lastCheckedAt: Date? = nil,
        nextCheckNotBefore: Date? = nil
    ) {
        self.manifestETag = manifestETag
        self.etagDatasetVersion = etagDatasetVersion
        self.lastCheckedAt = lastCheckedAt
        self.nextCheckNotBefore = nextCheckNotBefore
    }
}

/// The downloaded snapshot on disk, and the bookkeeping around it.
///
/// Layout under Application Support:
/// ```
/// PaceData/
///   state.json
///   current/
///     manifest.json
///     menOpenSingle.json … mixedDouble.json
/// ```
///
/// Files are stored by division base name, not by the nested `name` the catalogue
/// uses. A catalogue is remote input; never letting its paths reach the file system
/// means a traversal attempt cannot escape this directory even if the name checks in
/// `PaceDataManifest` were ever loosened.
final class PaceDataCacheStore: @unchecked Sendable {

    private static let logger = Logger(
        subsystem: "com.bbdyno.app.HyroxSim",
        category: "PaceData"
    )

    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.bbdyno.app.HyroxSim.pace-data-cache")

    let rootURL: URL

    private var currentURL: URL { rootURL.appendingPathComponent("current", isDirectory: true) }
    private var stateURL: URL { rootURL.appendingPathComponent("state.json") }

    /// - Parameter directory: Where the cache lives. Defaults to Application Support;
    ///   tests pass a temporary directory.
    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = directory ?? Self.defaultRoot(fileManager: fileManager)
        self.rootURL = base
        queue.sync {
            prepareRoot()
            discardStagingLeftovers()
        }
    }

    private static func defaultRoot(fileManager: FileManager) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("PaceData", isDirectory: true)
    }

    // MARK: - State

    func loadState() -> PaceDataCacheState {
        queue.sync {
            guard let data = try? Data(contentsOf: stateURL) else { return PaceDataCacheState() }
            do {
                return try Self.decoder().decode(PaceDataCacheState.self, from: data)
            } catch {
                // A state file we cannot read only costs one extra check.
                return PaceDataCacheState()
            }
        }
    }

    func save(_ state: PaceDataCacheState) {
        queue.sync {
            do {
                prepareRoot()
                let data = try Self.encoder().encode(state)
                try data.write(to: stateURL, options: .atomic)
            } catch {
                Self.logger.error(
                    "pace data state could not be written: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    // MARK: - Snapshot

    /// The installed snapshot, already validated.
    /// - Returns: `nil` when nothing is installed.
    /// - Throws: when something *is* installed but cannot be trusted — the caller logs
    ///   it, clears the cache and falls back to the bundled snapshot.
    func loadSnapshot() throws -> PaceDataSnapshot? {
        try queue.sync {
            let manifestURL = currentURL.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }

            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try PaceReferenceLoader.decodeManifest(
                from: manifestData,
                resourceName: "cache/manifest.json"
            )
            let entries = try manifest.validatedFiles()

            var datasets: [HyroxDivision: PaceDataset] = [:]
            for division in entries.keys {
                let name = "\(division.rawValue).json"
                let url = currentURL.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: url.path) else {
                    throw PaceDataError.resourceMissing("cache/\(name)")
                }
                let data = try Data(contentsOf: url)
                datasets[division] = try PaceReferenceLoader.decodeDataset(
                    from: data,
                    resourceName: "cache/\(name)"
                )
            }

            return try PaceDataSnapshot(
                datasetVersion: manifest.datasetVersion,
                origin: .cached,
                datasets: datasets
            )
        }
    }

    /// Writes a verified snapshot into a fresh directory and swaps it in atomically.
    ///
    /// Everything lands in `staging-<uuid>` first; only once all ten files are on disk
    /// is the directory exchanged with `current`. A crash at any point before that
    /// leaves the previously installed snapshot untouched, and a crash after it leaves
    /// the new one complete — there is no state in between where the app would read a
    /// half-replaced set of tables.
    ///
    /// - Parameter datasetFiles: Raw downloaded bytes, keyed by division. Stored
    ///   verbatim rather than re-encoded so the SHA-256 in the catalogue keeps
    ///   describing what is actually on disk.
    func install(manifestData: Data, datasetFiles: [HyroxDivision: Data]) throws {
        try queue.sync {
            prepareRoot()

            let staging = rootURL.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

            do {
                try manifestData.write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
                for (division, data) in datasetFiles {
                    let url = staging.appendingPathComponent("\(division.rawValue).json")
                    try data.write(to: url, options: .atomic)
                }

                if fileManager.fileExists(atPath: currentURL.path) {
                    _ = try fileManager.replaceItemAt(currentURL, withItemAt: staging)
                } else {
                    try fileManager.moveItem(at: staging, to: currentURL)
                }
            } catch {
                try? fileManager.removeItem(at: staging)
                throw error
            }
        }
    }

    /// Drops the installed snapshot. Used when it fails validation or its version is revoked.
    func clearSnapshot() {
        queue.sync {
            guard fileManager.fileExists(atPath: currentURL.path) else { return }
            do {
                try fileManager.removeItem(at: currentURL)
            } catch {
                Self.logger.error(
                    "cached pace data could not be removed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    // MARK: - Private

    /// Creates the directory and keeps it out of iCloud and iTunes backups.
    ///
    /// The snapshot is a verbatim copy of something the app can fetch again in seconds,
    /// so backing it up would only inflate every restore.
    private func prepareRoot() {
        var url = rootURL
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                Self.logger.error(
                    "pace data cache directory could not be created: \(String(describing: error), privacy: .public)"
                )
                return
            }
        }

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Removes staging directories a previous run died inside.
    private func discardStagingLeftovers() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents where url.lastPathComponent.hasPrefix("staging-") {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
