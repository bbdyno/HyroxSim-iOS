//
//  LocalizedDecimalFormatterTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 7/20/26.
//

import HyroxCore
import XCTest
@testable import HyroxSim

final class LocalizedDecimalFormatterTests: XCTestCase {

    func testParsesSwedishDecimalSeparator() {
        let value = LocalizedDecimalFormatter.value(
            from: "12,5",
            locale: Locale(identifier: "sv_SE")
        )

        XCTAssertEqual(value, 12.5)
    }

    func testParsesEnglishDecimalSeparator() {
        let value = LocalizedDecimalFormatter.value(
            from: "12.5",
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(value, 12.5)
    }

    func testAcceptsDotAsFallbackInSwedishLocale() {
        let value = LocalizedDecimalFormatter.value(
            from: "12.5",
            locale: Locale(identifier: "sv_SE")
        )

        XCTAssertEqual(value, 12.5)
    }

    func testRejectsInvalidValue() {
        XCTAssertNil(
            LocalizedDecimalFormatter.value(
                from: "not a number",
                locale: Locale(identifier: "sv_SE")
            )
        )
    }

    func testFormatsUsingLocaleDecimalSeparator() {
        XCTAssertEqual(
            LocalizedDecimalFormatter.string(
                from: 12.5,
                locale: Locale(identifier: "sv_SE")
            ),
            "12,5"
        )
    }

    // MARK: - 극단값 방어 (오버플로 크래시 회귀 방지)

    func testFiniteValueRejectsNonFiniteInput() {
        let locale = Locale(identifier: "en_US")
        XCTAssertNil(LocalizedDecimalFormatter.finiteValue(from: "inf", locale: locale))
        XCTAssertNil(LocalizedDecimalFormatter.finiteValue(from: "infinity", locale: locale))
        XCTAssertNil(LocalizedDecimalFormatter.finiteValue(from: "nan", locale: locale))
        XCTAssertEqual(LocalizedDecimalFormatter.finiteValue(from: "1234", locale: locale), 1234)
    }

    func testHugeInputParsesButFallsOutsideInputLimits() throws {
        let value = try XCTUnwrap(
            LocalizedDecimalFormatter.finiteValue(
                from: "99999999999999999999",
                locale: Locale(identifier: "en_US")
            )
        )

        XCTAssertFalse(NumericInputLimits.distanceMeters.contains(value))
        XCTAssertFalse(NumericInputLimits.reps.contains(value))
        XCTAssertFalse(NumericInputLimits.durationSeconds.contains(value))
    }

    func testClampedKeepsValueInsideRange() {
        XCTAssertEqual(LocalizedDecimalFormatter.clamped(1e19, to: NumericInputLimits.distanceMeters), 100_000)
        XCTAssertEqual(LocalizedDecimalFormatter.clamped(-5, to: NumericInputLimits.distanceMeters), 1)
        XCTAssertEqual(LocalizedDecimalFormatter.clamped(.nan, to: NumericInputLimits.durationSeconds), 0)
        XCTAssertEqual(LocalizedDecimalFormatter.clamped(90_000, to: NumericInputLimits.durationSeconds), 86_400)
        XCTAssertEqual(LocalizedDecimalFormatter.clamped(1_500, to: NumericInputLimits.distanceMeters), 1_500)
    }

    func testSafeIntClampsInsteadOfTrapping() {
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(.nan), 0)
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(.infinity), Int.max)
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(-.infinity), 0)
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(1e19), Int.max)
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(1234.9), 1234)
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(-5, lowerBound: Int.min), -5)
    }
}

// MARK: - Pace Data Remote Update
//
// Everything below drives the competition-record refresh through a stubbed HTTP
// client and a throwaway cache directory. No test here touches the network.

/// Answers requests from a routing table keyed by URL, and records what was asked for.
final class StubPaceDataHTTPClient: PaceDataHTTPFetching, @unchecked Sendable {

    enum Reply {
        case notModified
        case payload(Data, etag: String?)
        case failure(any Error)
    }

    private let lock = NSLock()
    private var replies: [String: Reply] = [:]
    private var log: [(url: URL, etag: String?)] = []

    func stub(_ url: URL, with reply: Reply) {
        lock.lock()
        replies[url.absoluteString] = reply
        lock.unlock()
    }

    func clearStubs() {
        lock.lock()
        replies.removeAll()
        lock.unlock()
    }

    func clearLog() {
        lock.lock()
        log.removeAll()
        lock.unlock()
    }

    var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return log.map(\.url)
    }

    var sentETags: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return log.map(\.etag)
    }

    /// Synchronous so the lock is never taken from `fetch`'s async context.
    private func record(_ request: PaceDataRequest) -> Reply? {
        lock.lock()
        defer { lock.unlock() }
        log.append((request.url, request.etag))
        return replies[request.url.absoluteString]
    }

    func fetch(_ request: PaceDataRequest) async throws -> PaceDataHTTPResult {
        switch record(request) {
        case .notModified:
            return .notModified
        case .payload(let data, let etag):
            return .payload(data: data, etag: etag)
        case .failure(let error):
            throw error
        case nil:
            // Nothing stubbed for this URL: behave like the server would.
            throw PaceDataHTTPError.unacceptableStatus(404)
        }
    }
}

/// Builds a catalogue and nine division files that are byte-for-byte checkable.
///
/// The published tables are reused as the payload, with only `dataset_version`
/// rewritten, so the fixtures stay as real as the data the app actually ships and no
/// hand-written table can drift away from the schema.
enum PaceDataFixtures {

    struct Payloads {
        let manifest: Data
        let files: [HyroxDivision: Data]
        let entries: [PaceDataManifestFile]
    }

    static func payloads(
        version: String,
        schemaVersion: Int = 4,
        revoked: [String] = []
    ) throws -> Payloads {
        let currentVersion = try PaceReferenceLoader.loadBundledManifest().datasetVersion
        XCTAssertNotEqual(version, currentVersion, "fixture version must differ from the bundled one")

        var files: [HyroxDivision: Data] = [:]
        var entries: [PaceDataManifestFile] = []

        for division in HyroxDivision.allCases {
            let original = try PaceReferenceLoader.bundledDatasetData(for: division)
            let rewritten = String(decoding: original, as: UTF8.self)
                .replacingOccurrences(of: "\"\(currentVersion)\"", with: "\"\(version)\"")
            let data = Data(rewritten.utf8)

            files[division] = data
            entries.append(
                PaceDataManifestFile(
                    name: "v4/\(version)/\(division.rawValue).json",
                    sha256: PaceDataUpdater.sha256Hex(data),
                    bytes: data.count
                )
            )
        }

        let manifest = PaceDataManifest(
            manifestVersion: 1,
            publishedAt: "2099-01-01",
            datasetVersion: version,
            schemaVersion: schemaVersion,
            files: entries,
            revoked: revoked
        )

        return Payloads(
            manifest: try JSONEncoder().encode(manifest),
            files: files,
            entries: entries
        )
    }
}

final class PaceDataRemoteUpdateTests: XCTestCase {

    private var cacheDirectory: URL!
    private var client: StubPaceDataHTTPClient!
    private var configuration: PaceDataConfiguration!
    private var bundledVersion: String!

    private static let manifestURL = URL(string: "https://example.test/pace/manifest.json")!
    private static let futureVersion = "9999.01.01"

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaceDataTests-\(UUID().uuidString)", isDirectory: true)
        client = StubPaceDataHTTPClient()
        configuration = PaceDataConfiguration(manifestURL: Self.manifestURL)
        bundledVersion = try PaceReferenceLoader.loadBundledManifest().datasetVersion
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeRepository(
        configuration: PaceDataConfiguration? = nil,
        client: (any PaceDataHTTPFetching)? = nil
    ) -> PaceDataRepository {
        PaceDataRepository(
            configuration: configuration ?? self.configuration,
            cache: PaceDataCacheStore(directory: cacheDirectory),
            client: client ?? self.client
        )
    }

    @discardableResult
    private func stubCatalogue(
        version: String = PaceDataRemoteUpdateTests.futureVersion,
        schemaVersion: Int = 4,
        revoked: [String] = [],
        etag: String? = "etag-1",
        corrupting corrupted: HyroxDivision? = nil,
        truncating truncated: HyroxDivision? = nil
    ) throws -> PaceDataFixtures.Payloads {
        let payloads = try PaceDataFixtures.payloads(
            version: version,
            schemaVersion: schemaVersion,
            revoked: revoked
        )

        client.stub(Self.manifestURL, with: .payload(payloads.manifest, etag: etag))

        for entry in payloads.entries {
            guard let division = entry.division,
                  var data = payloads.files[division],
                  let url = configuration.fileURL(for: entry) else { continue }

            if division == corrupted, !data.isEmpty {
                // Same length, different bytes: the checksum must catch it before the
                // JSON parser ever sees it.
                data[data.count - 1] = 0x20
            }
            if division == truncated, data.count > 1 {
                data = data.dropLast()
            }
            client.stub(url, with: .payload(data, etag: nil))
        }

        return payloads
    }

    private var installedDirectory: URL {
        cacheDirectory.appendingPathComponent("current", isDirectory: true)
    }

    private var hasInstalledSnapshot: Bool {
        FileManager.default.fileExists(atPath: installedDirectory.path)
    }

    // MARK: - Happy path

    func testStartsOnTheBundledSnapshot() throws {
        let repository = makeRepository()

        XCTAssertEqual(repository.origin, .bundled)
        XCTAssertEqual(repository.datasetVersion, bundledVersion)
        XCTAssertNotNil(repository.dataset(for: .menOpenSingle))
        XCTAssertFalse(hasInstalledSnapshot)
    }

    func testInstallsANewerSnapshotAndSwapsItIn() async throws {
        let repository = makeRepository()
        XCTAssertEqual(repository.origin, .bundled)

        try stubCatalogue()
        let outcome = await repository.refresh(force: true)

        XCTAssertEqual(outcome, .updated(version: Self.futureVersion))
        XCTAssertEqual(repository.datasetVersion, Self.futureVersion)
        XCTAssertEqual(repository.origin, .cached)
        XCTAssertTrue(hasInstalledSnapshot)

        let dataset = try XCTUnwrap(repository.dataset(for: .womenProDouble))
        XCTAssertEqual(dataset.datasetVersion, Self.futureVersion)
        XCTAssertEqual(dataset.division, .womenProDouble)
        // 10 requests: the catalogue plus one file per division.
        XCTAssertEqual(client.requestedURLs.count, 1 + HyroxDivision.allCases.count)
    }

    /// The atomic swap has to leave something a fresh process can read straight back.
    func testARestartReadsTheInstalledSnapshotFromDisk() async throws {
        try stubCatalogue()
        let outcome = await makeRepository().refresh(force: true)
        XCTAssertEqual(outcome, .updated(version: Self.futureVersion))

        let restarted = PaceDataRepository(
            configuration: configuration,
            cache: PaceDataCacheStore(directory: cacheDirectory),
            client: StubPaceDataHTTPClient()
        )

        XCTAssertEqual(restarted.origin, .cached)
        XCTAssertEqual(restarted.datasetVersion, Self.futureVersion)
        for division in HyroxDivision.allCases {
            XCTAssertEqual(restarted.dataset(for: division)?.datasetVersion, Self.futureVersion, division.rawValue)
        }
    }

    func testDoesNotInstallACatalogueThatIsNotNewer() async throws {
        let repository = makeRepository()
        try stubCatalogue(version: "1970.01.01")

        let outcome = await repository.refresh(force: true)

        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(repository.datasetVersion, bundledVersion)
        XCTAssertFalse(hasInstalledSnapshot)
        // Only the catalogue was fetched; no division file was downloaded.
        XCTAssertEqual(client.requestedURLs.count, 1)
    }

    // MARK: - Rejected updates

    func testAChecksumMismatchKeepsTheDataAlreadyInUse() async throws {
        let repository = makeRepository()
        try stubCatalogue(corrupting: .menProSingle)

        let outcome = await repository.refresh(force: true)

        guard case .failed(let reason) = outcome else {
            return XCTFail("expected a failure, got \(outcome)")
        }
        XCTAssertTrue(reason.contains("hashes to"), reason)
        XCTAssertEqual(repository.origin, .bundled)
        XCTAssertEqual(repository.datasetVersion, bundledVersion)
        XCTAssertFalse(hasInstalledSnapshot, "a rejected update must not leave anything installed")
    }

    func testAByteCountMismatchIsRejectedBeforeHashing() async throws {
        let repository = makeRepository()
        try stubCatalogue(truncating: .womenOpenDouble)

        let outcome = await repository.refresh(force: true)

        guard case .failed(let reason) = outcome else {
            return XCTFail("expected a failure, got \(outcome)")
        }
        XCTAssertTrue(reason.contains("bytes, manifest says"), reason)
        XCTAssertEqual(repository.datasetVersion, bundledVersion)
        XCTAssertFalse(hasInstalledSnapshot)
    }

    func testASchemaVersionThisBuildCannotReadIsRefused() async throws {
        let repository = makeRepository()
        try stubCatalogue(schemaVersion: 5)

        let outcome = await repository.refresh(force: true)

        guard case .failed(let reason) = outcome else {
            return XCTFail("expected a failure, got \(outcome)")
        }
        XCTAssertTrue(reason.contains("schema_version 5"), reason)
        XCTAssertEqual(repository.datasetVersion, bundledVersion)
        XCTAssertFalse(hasInstalledSnapshot)
        // Refused from the catalogue alone — nothing was downloaded.
        XCTAssertEqual(client.requestedURLs.count, 1)
    }

    func testAnUnreachableServerLeavesEverythingAsItWas() async throws {
        let repository = makeRepository()
        client.stub(Self.manifestURL, with: .failure(URLError(.notConnectedToInternet)))

        let outcome = await repository.refresh(force: true)

        guard case .failed = outcome else {
            return XCTFail("expected a failure, got \(outcome)")
        }
        XCTAssertEqual(repository.origin, .bundled)
        XCTAssertEqual(repository.datasetVersion, bundledVersion)
    }

    func testAMissingDivisionFileAbandonsTheWholeUpdate() async throws {
        let repository = makeRepository()
        let payloads = try stubCatalogue()

        // Drop one file from the routing table so the server 404s for it.
        client.clearStubs()
        client.stub(Self.manifestURL, with: .payload(payloads.manifest, etag: "etag-1"))
        for entry in payloads.entries where entry.division != .mixedDouble {
            guard let division = entry.division,
                  let data = payloads.files[division],
                  let url = configuration.fileURL(for: entry) else { continue }
            client.stub(url, with: .payload(data, etag: nil))
        }

        let outcome = await repository.refresh(force: true)

        guard case .failed = outcome else {
            return XCTFail("expected a failure, got \(outcome)")
        }
        XCTAssertEqual(repository.datasetVersion, bundledVersion)
        XCTAssertFalse(hasInstalledSnapshot, "eight good divisions must not be installed without the ninth")
    }

    // MARK: - Kill switch

    func testARevokedVersionDropsBackToTheBundledSnapshot() async throws {
        let repository = makeRepository()

        try stubCatalogue()
        let installed = await repository.refresh(force: true)
        XCTAssertEqual(installed, .updated(version: Self.futureVersion))
        XCTAssertEqual(repository.origin, .cached)

        client.clearStubs()
        try stubCatalogue(revoked: [Self.futureVersion], etag: "etag-2")

        let outcome = await repository.refresh(force: true)

        XCTAssertEqual(outcome, .revertedToBundled(version: bundledVersion))
        XCTAssertEqual(repository.origin, .bundled)
        XCTAssertEqual(repository.datasetVersion, bundledVersion)
        XCTAssertFalse(hasInstalledSnapshot)
    }

    // MARK: - Check cadence

    func testChecksAtMostOncePerDay() async throws {
        let repository = makeRepository()
        try stubCatalogue(version: "1970.01.01")

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let firstCheck = await repository.refresh(now: start)
        XCTAssertEqual(firstCheck, .unchanged)

        let soon = start.addingTimeInterval(60 * 60)
        guard case .notDue = await repository.refresh(now: soon) else {
            return XCTFail("a second check an hour later must be skipped")
        }
        XCTAssertEqual(client.requestedURLs.count, 1)

        let nextDay = start.addingTimeInterval(25 * 60 * 60)
        let nextDayCheck = await repository.refresh(now: nextDay)
        XCTAssertEqual(nextDayCheck, .unchanged)
        XCTAssertEqual(client.requestedURLs.count, 2)
    }

    func testAFailedCheckRetriesLongBeforeTheNextDay() async throws {
        let configuration = PaceDataConfiguration(
            manifestURL: Self.manifestURL,
            minimumRefreshInterval: 24 * 60 * 60,
            failureRetryInterval: 60 * 60
        )
        let repository = makeRepository(configuration: configuration)
        client.stub(Self.manifestURL, with: .failure(URLError(.timedOut)))

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        guard case .failed = await repository.refresh(now: start) else {
            return XCTFail("expected a failure")
        }

        guard case .notDue = await repository.refresh(now: start.addingTimeInterval(30 * 60)) else {
            return XCTFail("a retry half an hour later must still be skipped")
        }

        guard case .failed = await repository.refresh(now: start.addingTimeInterval(2 * 60 * 60)) else {
            return XCTFail("a retry two hours later must go out")
        }
        XCTAssertEqual(client.requestedURLs.count, 2)
    }

    func testAClockJumpForwardDoesNotFreezeTheDataForever() async throws {
        let repository = makeRepository()
        try stubCatalogue(version: "1970.01.01")

        let future = Date(timeIntervalSince1970: 4_000_000_000)
        let atFutureClock = await repository.refresh(now: future)
        XCTAssertEqual(atFutureClock, .unchanged)

        // Device clock corrected backwards: the stored "not before" is now years out,
        // which must not be honoured.
        let corrected = Date(timeIntervalSince1970: 1_700_000_000)
        let afterCorrection = await repository.refresh(now: corrected)
        XCTAssertEqual(afterCorrection, .unchanged)
        XCTAssertEqual(client.requestedURLs.count, 2)
    }

    // MARK: - Conditional requests

    func testA304LeavesTheLoadedTablesAlone() async throws {
        let repository = makeRepository()
        client.stub(Self.manifestURL, with: .notModified)

        let outcome = await repository.refresh(force: true)

        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(repository.datasetVersion, bundledVersion)
        XCTAssertEqual(client.requestedURLs.count, 1)
    }

    func testSendsTheStoredETagOnTheFollowingCheck() async throws {
        let repository = makeRepository()
        try stubCatalogue(version: "1970.01.01", etag: "W/\"abc123\"")

        let firstCheck = await repository.refresh(force: true)

        XCTAssertEqual(firstCheck, .unchanged)
        XCTAssertEqual(client.sentETags, [nil])

        let secondCheck = await repository.refresh(force: true)

        XCTAssertEqual(secondCheck, .unchanged)
        XCTAssertEqual(client.sentETags.last, "W/\"abc123\"")
    }

    /// After a rollback the stored ETag describes a catalogue that no longer matches
    /// what is loaded, so reusing it would let a 304 hide the update we want.
    func testDropsTheStoredETagAfterARevocation() async throws {
        let repository = makeRepository()

        try stubCatalogue()
        let installed = await repository.refresh(force: true)
        XCTAssertEqual(installed, .updated(version: Self.futureVersion))

        client.clearStubs()
        try stubCatalogue(revoked: [Self.futureVersion], etag: "etag-2")
        let reverted = await repository.refresh(force: true)
        XCTAssertEqual(reverted, .revertedToBundled(version: bundledVersion))

        client.clearLog()
        client.clearStubs()
        client.stub(Self.manifestURL, with: .notModified)
        _ = await repository.refresh(force: true)

        XCTAssertEqual(client.sentETags, [nil])
    }

    // MARK: - Corrupted cache

    func testAnUnreadableCacheFallsBackToTheBundledSnapshot() async throws {
        try stubCatalogue()
        let installed = await makeRepository().refresh(force: true)
        XCTAssertEqual(installed, .updated(version: Self.futureVersion))

        let victim = installedDirectory.appendingPathComponent("menOpenSingle.json")
        try Data("{ not json".utf8).write(to: victim, options: .atomic)

        let restarted = PaceDataRepository(
            configuration: configuration,
            cache: PaceDataCacheStore(directory: cacheDirectory),
            client: StubPaceDataHTTPClient()
        )

        XCTAssertEqual(restarted.origin, .bundled)
        XCTAssertEqual(restarted.datasetVersion, bundledVersion)
        XCTAssertFalse(hasInstalledSnapshot, "a cache that cannot be read is dropped rather than retried forever")
    }

    func testStagingLeftoversAreSweptUpOnLaunch() throws {
        let leftover = cacheDirectory.appendingPathComponent("staging-abandoned", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: leftover.appendingPathComponent("menOpenSingle.json"))

        _ = PaceDataCacheStore(directory: cacheDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
    }

    func testCacheStateRoundTrips() {
        let store = PaceDataCacheStore(directory: cacheDirectory)
        let moment = Date(timeIntervalSince1970: 1_700_000_000)

        store.save(
            PaceDataCacheState(
                manifestETag: "etag-9",
                etagDatasetVersion: "9999.01.01",
                lastCheckedAt: moment,
                nextCheckNotBefore: moment.addingTimeInterval(86_400)
            )
        )

        let reloaded = PaceDataCacheStore(directory: cacheDirectory).loadState()
        XCTAssertEqual(reloaded.manifestETag, "etag-9")
        XCTAssertEqual(reloaded.etagDatasetVersion, "9999.01.01")
        XCTAssertEqual(reloaded.lastCheckedAt, moment)
    }
}

// MARK: - Endpoint Resolution

final class PaceDataEndpointTests: XCTestCase {

    private var testBundle: Bundle { Bundle(for: PaceDataEndpointTests.self) }

    func testDefaultsToTheHostedCatalogue() {
        let url = PaceDataEndpoint.manifestURL(bundle: testBundle, environment: [:])
        XCTAssertEqual(url.absoluteString, PaceDataEndpoint.defaultManifestURLString)
    }

    func testAnEnvironmentOverrideWins() {
        let url = PaceDataEndpoint.manifestURL(
            bundle: testBundle,
            environment: [PaceDataEndpoint.environmentKey: "https://staging.example.com/pace/manifest.json"]
        )
        XCTAssertEqual(url.absoluteString, "https://staging.example.com/pace/manifest.json")
    }

    /// A plaintext catalogue could be rewritten in flight, which would make every
    /// checksum in it meaningless.
    func testRejectsANonHTTPSOverride() {
        let url = PaceDataEndpoint.manifestURL(
            bundle: testBundle,
            environment: [PaceDataEndpoint.environmentKey: "http://staging.example.com/pace/manifest.json"]
        )
        XCTAssertEqual(url.absoluteString, PaceDataEndpoint.defaultManifestURLString)
    }

    func testResolvesFileURLsRelativeToTheCatalogue() throws {
        let configuration = PaceDataConfiguration(
            manifestURL: URL(string: "https://example.test/pace/manifest.json")!
        )
        let file = PaceDataManifestFile(
            name: "v4/2026.09.15/menOpenSingle.json",
            sha256: String(repeating: "a", count: 64),
            bytes: 100
        )

        let url = try XCTUnwrap(configuration.fileURL(for: file))
        XCTAssertEqual(url.absoluteString, "https://example.test/pace/v4/2026.09.15/menOpenSingle.json")
    }

    func testRefusesToBuildAURLForAnUnsafeName() {
        let configuration = PaceDataConfiguration(
            manifestURL: URL(string: "https://example.test/pace/manifest.json")!
        )
        let file = PaceDataManifestFile(
            name: "../../secrets.json",
            sha256: String(repeating: "a", count: 64),
            bytes: 100
        )

        XCTAssertNil(configuration.fileURL(for: file))
    }
}
