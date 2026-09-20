//
//  PaceDataProviding.swift
//  HyroxCore
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

// MARK: - Provider

/// Where a set of datasets came from.
///
/// Only useful for logs and diagnostics: a cached set and a bundled set are read the
/// same way, and callers must never branch on this to decide whether to trust a number.
public enum PaceDataOrigin: String, Codable, Hashable, Sendable {
    /// The snapshot shipped inside the app binary.
    case bundled
    /// A newer snapshot downloaded earlier and kept on disk.
    case cached
}

/// A complete, already validated set of division tables.
///
/// `HyroxCore` deliberately owns no networking. The bundled snapshot and whatever the
/// app downloaded both arrive here, so every reader works the same against either.
public protocol PaceDataProviding: Sendable {
    /// `YYYY.MM.DD` stamp shared by every dataset in the set.
    var datasetVersion: String { get }
    var origin: PaceDataOrigin { get }
    var availableDivisions: [HyroxDivision] { get }
    func dataset(for division: HyroxDivision) throws -> PaceDataset
}

/// Why a provider could not hand back a table.
public enum PaceDataError: Error, Hashable, Sendable {
    case divisionUnavailable(HyroxDivision)
    case resourceMissing(String)
    case decodingFailed(resource: String, reason: String)
    case validationFailed(resource: String, reason: String)
}

extension PaceDataError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .divisionUnavailable(let division):
            return "no pace dataset for division '\(division.rawValue)'"
        case .resourceMissing(let name):
            return "pace data resource '\(name)' is missing"
        case .decodingFailed(let resource, let reason):
            return "pace data resource '\(resource)' could not be decoded: \(reason)"
        case .validationFailed(let resource, let reason):
            return "pace data resource '\(resource)' failed validation: \(reason)"
        }
    }
}

extension PaceDataError: LocalizedError {
    public var errorDescription: String? { description }
}

/// An in-memory set of validated datasets.
///
/// Building one is the only way a dataset reaches a reader, and
/// ``init(datasetVersion:origin:datasets:)`` is the choke point where validation
/// happens — so an unchecked table cannot be served by construction.
public struct PaceDataSnapshot: PaceDataProviding, Hashable, Sendable {

    public let datasetVersion: String
    public let origin: PaceDataOrigin
    private let datasets: [HyroxDivision: PaceDataset]

    /// - Throws: ``PaceDatasetValidationError`` for the first table that fails its
    ///   invariants. A partially good set is never published: one broken division
    ///   means the whole update is rejected and the previous set stays in use.
    public init(
        datasetVersion: String,
        origin: PaceDataOrigin,
        datasets: [HyroxDivision: PaceDataset]
    ) throws {
        for division in datasets.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let dataset = datasets[division] else { continue }
            try PaceDatasetValidator.validate(
                dataset,
                expecting: division,
                datasetVersion: datasetVersion
            )
        }
        self.datasetVersion = datasetVersion
        self.origin = origin
        self.datasets = datasets
    }

    public var availableDivisions: [HyroxDivision] {
        HyroxDivision.allCases.filter { datasets[$0] != nil }
    }

    /// Whether every division this build knows about has a table.
    public var isComplete: Bool {
        availableDivisions.count == HyroxDivision.allCases.count
    }

    public func dataset(for division: HyroxDivision) throws -> PaceDataset {
        guard let dataset = datasets[division] else {
            throw PaceDataError.divisionUnavailable(division)
        }
        return dataset
    }
}

// MARK: - Manifest

/// The catalogue the app polls to learn whether newer tables exist.
///
/// Mirrors `docs/pace/manifest.json`. `files` carries a SHA-256 and a byte count for
/// each division file so a download can be checked before it is decoded, let alone
/// installed.
public struct PaceDataManifest: Codable, Hashable, Sendable {

    public let manifestVersion: Int
    /// Date the catalogue was published, `YYYY-MM-DD`.
    public let publishedAt: String
    public let datasetVersion: String
    public let schemaVersion: Int
    public let generator: PaceDataGenerator
    public let files: [PaceDataManifestFile]
    /// Catalogue-wide coverage. Kept verbatim: it is descriptive, and its shape grows
    /// as the pipeline learns to report more.
    public let coverage: [String: PaceJSONValue]
    /// Kill switch. Dataset versions listed here are never installed, and one already
    /// installed is dropped back to the bundled snapshot.
    public let revoked: [String]

    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case publishedAt = "published_at"
        case datasetVersion = "dataset_version"
        case schemaVersion = "schema_version"
        case generator
        case files
        case coverage
        case revoked
    }

    public init(
        manifestVersion: Int,
        publishedAt: String = "",
        datasetVersion: String,
        schemaVersion: Int,
        generator: PaceDataGenerator = PaceDataGenerator(script: "", version: ""),
        files: [PaceDataManifestFile],
        coverage: [String: PaceJSONValue] = [:],
        revoked: [String] = []
    ) {
        self.manifestVersion = manifestVersion
        self.publishedAt = publishedAt
        self.datasetVersion = datasetVersion
        self.schemaVersion = schemaVersion
        self.generator = generator
        self.files = files
        self.coverage = coverage
        self.revoked = revoked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt) ?? ""
        datasetVersion = try container.decode(String.self, forKey: .datasetVersion)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generator = try container.decodeIfPresent(PaceDataGenerator.self, forKey: .generator)
            ?? PaceDataGenerator(script: "", version: "")
        files = try container.decode([PaceDataManifestFile].self, forKey: .files)
        coverage = try container.decodeIfPresent([String: PaceJSONValue].self, forKey: .coverage) ?? [:]
        revoked = try container.decodeIfPresent([String].self, forKey: .revoked) ?? []
    }

    /// Season range the tables were built from, e.g. `S6-S9`.
    public var seasonLabel: String? { coverage["season_label"]?.stringValue }
    /// Events the tables were built from.
    public var events: Int? { coverage["events"]?.intValue }
    /// Athletes behind the published numbers, after cleaning.
    public var athletesPublished: Int? { coverage["athletes_published"]?.intValue }
}

/// One downloadable file in the catalogue.
public struct PaceDataManifestFile: Codable, Hashable, Sendable {
    /// Path relative to the manifest, e.g. `v4/2026.09.15/menOpenSingle.json`.
    public let name: String
    /// Lowercase hex SHA-256 of the exact bytes served at `name`.
    public let sha256: String
    public let bytes: Int

    public init(name: String, sha256: String, bytes: Int) {
        self.name = name
        self.sha256 = sha256
        self.bytes = bytes
    }

    /// The division this file holds, taken from its base name.
    public var division: HyroxDivision? {
        let base = (name as NSString).lastPathComponent
        guard base.hasSuffix(".json") else { return nil }
        return HyroxDivision(rawValue: String(base.dropLast(".json".count)))
    }
}

/// Why a catalogue cannot be acted on.
public enum PaceDataManifestError: Error, Hashable, Sendable {
    case unsupportedManifestVersion(found: Int, supported: ClosedRange<Int>)
    case unsupportedSchemaVersion(found: Int, supported: ClosedRange<Int>)
    case emptyDatasetVersion
    case revokedDatasetVersion(String)
    case unsafeFileName(String)
    case invalidChecksum(name: String)
    case fileTooLarge(name: String, bytes: Int, limit: Int)
    case duplicateDivisionFile(String)
    case missingDivisionFile(String)
}

extension PaceDataManifestError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unsupportedManifestVersion(let found, let supported):
            return "manifest_version \(found) is outside the supported range \(supported.lowerBound)-\(supported.upperBound)"
        case .unsupportedSchemaVersion(let found, let supported):
            return "schema_version \(found) is outside the supported range \(supported.lowerBound)-\(supported.upperBound)"
        case .emptyDatasetVersion:
            return "dataset_version is empty"
        case .revokedDatasetVersion(let version):
            return "dataset_version '\(version)' is listed as revoked"
        case .unsafeFileName(let name):
            return "file name '\(name)' is not a safe relative path"
        case .invalidChecksum(let name):
            return "file '\(name)' has a malformed sha256"
        case .fileTooLarge(let name, let bytes, let limit):
            return "file '\(name)' declares \(bytes) bytes, over the \(limit) byte limit"
        case .duplicateDivisionFile(let division):
            return "manifest lists division '\(division)' more than once"
        case .missingDivisionFile(let division):
            return "manifest is missing division '\(division)'"
        }
    }
}

extension PaceDataManifestError: LocalizedError {
    public var errorDescription: String? { description }
}

extension PaceDataManifest {

    public static let supportedManifestVersions: ClosedRange<Int> = 1...1

    /// Checks the catalogue and returns exactly one file per division.
    ///
    /// `name` comes off the network, and it is later joined onto a base URL and onto a
    /// cache directory path. A name such as `../../etc/passwd` or an absolute path must
    /// therefore never survive this call — hence the component-by-component check
    /// rather than a suffix test.
    ///
    /// - Parameters:
    ///   - supportedSchemaVersions: Dataset schema versions the caller can decode.
    ///   - maximumFileBytes: Refuses a file the caller is not willing to download.
    ///   - requireAllDivisions: A partial catalogue is rejected by default, because
    ///     installing it would leave some divisions on old numbers and others on new ones.
    @discardableResult
    public func validatedFiles(
        supportedSchemaVersions: ClosedRange<Int> = PaceDatasetValidator.supportedSchemaVersions,
        maximumFileBytes: Int = 2 * 1024 * 1024,
        requireAllDivisions: Bool = true
    ) throws -> [HyroxDivision: PaceDataManifestFile] {

        guard Self.supportedManifestVersions.contains(manifestVersion) else {
            throw PaceDataManifestError.unsupportedManifestVersion(
                found: manifestVersion,
                supported: Self.supportedManifestVersions
            )
        }
        guard supportedSchemaVersions.contains(schemaVersion) else {
            throw PaceDataManifestError.unsupportedSchemaVersion(
                found: schemaVersion,
                supported: supportedSchemaVersions
            )
        }
        guard !datasetVersion.isEmpty else {
            throw PaceDataManifestError.emptyDatasetVersion
        }
        guard !revoked.contains(datasetVersion) else {
            throw PaceDataManifestError.revokedDatasetVersion(datasetVersion)
        }

        var byDivision: [HyroxDivision: PaceDataManifestFile] = [:]
        for file in files {
            guard Self.isSafeRelativePath(file.name) else {
                throw PaceDataManifestError.unsafeFileName(file.name)
            }
            guard Self.isHexChecksum(file.sha256) else {
                throw PaceDataManifestError.invalidChecksum(name: file.name)
            }
            guard file.bytes > 0, file.bytes <= maximumFileBytes else {
                throw PaceDataManifestError.fileTooLarge(
                    name: file.name,
                    bytes: file.bytes,
                    limit: maximumFileBytes
                )
            }
            // A file for a division this build does not know is simply skipped: a
            // future catalogue may add one, and that is not a reason to stay on old data.
            guard let division = file.division else { continue }
            guard byDivision[division] == nil else {
                throw PaceDataManifestError.duplicateDivisionFile(division.rawValue)
            }
            byDivision[division] = file
        }

        if requireAllDivisions {
            for division in HyroxDivision.allCases where byDivision[division] == nil {
                throw PaceDataManifestError.missingDivisionFile(division.rawValue)
            }
        }

        return byDivision
    }

    /// True for a relative path with no traversal, no absolute root and a `.json` leaf.
    ///
    /// Public because the app joins these names onto a base URL, and that join must be
    /// able to re-check rather than trust that validation already ran.
    public static func isSafeRelativePath(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("\\") else { return false }
        guard name.hasSuffix(".json") else { return false }
        guard !name.contains("://") else { return false }

        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count <= 8 else { return false }
        for component in components {
            if component.isEmpty || component == "." || component == ".." { return false }
            if component.contains("\\") { return false }
        }
        return true
    }

    static func isHexChecksum(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        return value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

// MARK: - Version Ordering

/// Orders `YYYY.MM.DD` dataset stamps.
///
/// Compared component by component as numbers so `2026.9.7` still sorts before
/// `2026.09.15`, which a plain string comparison gets wrong. Non-numeric components
/// fall back to a string comparison rather than being treated as equal.
public enum PaceDataVersion {

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let right = rhs.split(separator: ".", omittingEmptySubsequences: false).map(String.init)

        for index in 0..<max(left.count, right.count) {
            let lhsPart = index < left.count ? left[index] : ""
            let rhsPart = index < right.count ? right[index] : ""
            if lhsPart == rhsPart { continue }

            if let lhsNumber = Int(lhsPart), let rhsNumber = Int(rhsPart) {
                return lhsNumber < rhsNumber ? .orderedAscending : .orderedDescending
            }
            return lhsPart < rhsPart ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    /// Whether `candidate` is strictly newer than `current`.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }
}
