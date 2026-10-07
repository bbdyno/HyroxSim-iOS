//
//  PaceDataUpdater.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import CryptoKit
import Foundation
import HyroxCore

/// What one catalogue check concluded.
struct PaceDataUpdateResult: Sendable {

    enum Kind: String, Sendable {
        /// Server answered 304 — the catalogue has not changed since the ETag was issued.
        case notModified
        /// Catalogue fetched, but it is not newer than what is already installed.
        case alreadyCurrent
        /// The catalogue revokes its own dataset version; nothing is installed.
        case revoked
        /// New tables verified and swapped in.
        case installed
    }

    let kind: Kind
    let datasetVersion: String?
    let snapshot: PaceDataSnapshot?
    let etag: String?
    /// True when the fetched catalogue lists the version the app is running on as
    /// revoked — the caller must drop back to the bundled snapshot.
    let revokesInstalledVersion: Bool

    init(
        kind: Kind,
        datasetVersion: String? = nil,
        snapshot: PaceDataSnapshot? = nil,
        etag: String? = nil,
        revokesInstalledVersion: Bool = false
    ) {
        self.kind = kind
        self.datasetVersion = datasetVersion
        self.snapshot = snapshot
        self.etag = etag
        self.revokesInstalledVersion = revokesInstalledVersion
    }
}

/// Why a download could not be installed.
///
/// Distinct from `PaceDataManifestError` and `PaceDatasetValidationError`: those say
/// the published data is wrong, these say the bytes that arrived are not the bytes the
/// catalogue promised.
enum PaceDataUpdateError: Error, Hashable, Sendable {
    case unsafeFileName(String)
    case unexpectedNotModified(String)
    case byteCountMismatch(name: String, expected: Int, found: Int)
    case checksumMismatch(name: String, expected: String, found: String)
}

extension PaceDataUpdateError: CustomStringConvertible {
    var description: String {
        switch self {
        case .unsafeFileName(let name):
            return "manifest entry '\(name)' is not a safe relative path"
        case .unexpectedNotModified(let name):
            return "server answered 304 for '\(name)', which was requested unconditionally"
        case .byteCountMismatch(let name, let expected, let found):
            return "'\(name)' is \(found) bytes, manifest says \(expected)"
        case .checksumMismatch(let name, let expected, let found):
            return "'\(name)' hashes to \(found), manifest says \(expected)"
        }
    }
}

extension PaceDataUpdateError: LocalizedError {
    var errorDescription: String? { description }
}

/// Fetches the catalogue, verifies every file it points at, and installs the set.
///
/// Nothing here is partial: either all nine divisions arrive, hash correctly, decode
/// and pass validation — in which case they are swapped in together — or the whole
/// update is abandoned and the previously installed (or bundled) tables stay in use.
/// Mixing versions across divisions would make two athletes' percentiles
/// incomparable, which is worse than being a few weeks out of date.
struct PaceDataUpdater: Sendable {

    private let configuration: PaceDataConfiguration
    private let client: any PaceDataHTTPFetching
    private let cache: PaceDataCacheStore

    init(
        configuration: PaceDataConfiguration,
        client: any PaceDataHTTPFetching,
        cache: PaceDataCacheStore
    ) {
        self.configuration = configuration
        self.client = client
        self.cache = cache
    }

    /// - Parameters:
    ///   - currentVersion: Dataset version in use right now, cached or bundled.
    ///   - etag: `ETag` of the catalogue that produced `currentVersion`, when the two
    ///     are known to belong together. Pass `nil` to force an unconditional fetch.
    func run(currentVersion: String, etag: String?) async throws -> PaceDataUpdateResult {

        let manifestResult = try await client.fetch(
            PaceDataRequest(url: configuration.manifestURL, etag: etag)
        )

        guard case .payload(let manifestData, let manifestETag) = manifestResult else {
            return PaceDataUpdateResult(kind: .notModified)
        }

        let manifest = try PaceReferenceLoader.decodeManifest(
            from: manifestData,
            resourceName: "manifest.json"
        )

        let revokesInstalled = manifest.revoked.contains(currentVersion)

        // Kill switch: a version the publisher has pulled is never installed, and if it
        // is the one already running the caller is told to fall back.
        guard !manifest.revoked.contains(manifest.datasetVersion) else {
            return PaceDataUpdateResult(
                kind: .revoked,
                datasetVersion: manifest.datasetVersion,
                etag: manifestETag,
                revokesInstalledVersion: revokesInstalled
            )
        }

        let entries = try manifest.validatedFiles(
            supportedSchemaVersions: configuration.supportedSchemaVersions,
            maximumFileBytes: configuration.maximumFileBytes
        )

        guard PaceDataVersion.isNewer(manifest.datasetVersion, than: currentVersion) else {
            return PaceDataUpdateResult(
                kind: .alreadyCurrent,
                datasetVersion: manifest.datasetVersion,
                etag: manifestETag,
                revokesInstalledVersion: revokesInstalled
            )
        }

        var datasets: [HyroxDivision: PaceDataset] = [:]
        var payloads: [HyroxDivision: Data] = [:]

        for division in entries.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let file = entries[division] else { continue }
            let (dataset, data) = try await download(file, for: division, datasetVersion: manifest.datasetVersion)
            datasets[division] = dataset
            payloads[division] = data
        }

        // Validates every table once more as a set, this time against the version the
        // catalogue promised, before anything is written.
        let snapshot = try PaceDataSnapshot(
            datasetVersion: manifest.datasetVersion,
            origin: .cached,
            datasets: datasets
        )

        try cache.install(manifestData: manifestData, datasetFiles: payloads)

        return PaceDataUpdateResult(
            kind: .installed,
            datasetVersion: manifest.datasetVersion,
            snapshot: snapshot,
            etag: manifestETag,
            revokesInstalledVersion: false
        )
    }

    // MARK: - Private

    private func download(
        _ file: PaceDataManifestFile,
        for division: HyroxDivision,
        datasetVersion: String
    ) async throws -> (PaceDataset, Data) {

        guard let url = configuration.fileURL(for: file) else {
            throw PaceDataUpdateError.unsafeFileName(file.name)
        }

        let result = try await client.fetch(PaceDataRequest(url: url))
        guard case .payload(let data, _) = result else {
            throw PaceDataUpdateError.unexpectedNotModified(file.name)
        }

        guard data.count == file.bytes else {
            throw PaceDataUpdateError.byteCountMismatch(
                name: file.name,
                expected: file.bytes,
                found: data.count
            )
        }

        // Checked before decoding, so a payload that is not what was published never
        // reaches the JSON parser in the first place.
        let digest = Self.sha256Hex(data)
        guard digest == file.sha256 else {
            throw PaceDataUpdateError.checksumMismatch(
                name: file.name,
                expected: file.sha256,
                found: digest
            )
        }

        let dataset = try PaceReferenceLoader.decodeDataset(from: data, resourceName: file.name)
        try PaceDatasetValidator.validate(
            dataset,
            expecting: division,
            datasetVersion: datasetVersion
        )

        return (dataset, data)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
