//
//  PaceDataRepository.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore
import os

/// What one refresh attempt did.
enum PaceDataRefreshOutcome: Sendable, Equatable {
    /// Skipped: the previous check is still good.
    case notDue(nextCheck: Date)
    /// Checked, nothing to install.
    case unchanged
    case updated(version: String)
    /// The catalogue revoked what was installed; the app is back on the bundled snapshot.
    case revertedToBundled(version: String)
    /// Something went wrong. The previously loaded tables are still in use.
    case failed(String)
}

/// The app's single source of competition-record tables.
///
/// Reads are synchronous and never fail over to nothing: the bundled snapshot ships in
/// the binary, so there is always a table to answer with. A downloaded snapshot simply
/// replaces it once it has been verified end to end.
///
/// Nothing in here is allowed to interrupt an athlete. A refresh that fails — offline,
/// a 500, a bad checksum, a schema this build cannot read — leaves the loaded tables
/// exactly as they were and writes one line to the log. There is no error to surface
/// and nothing for the user to do about it.
final class PaceDataRepository: @unchecked Sendable {

    private static let logger = Logger(
        subsystem: "com.bbdyno.app.HyroxSim",
        category: "PaceData"
    )

    private let configuration: PaceDataConfiguration
    private let cache: PaceDataCacheStore
    private let client: any PaceDataHTTPFetching
    private let bundledProvider: @Sendable () throws -> PaceDataSnapshot

    private let lock = NSLock()
    private var provider: (any PaceDataProviding)?
    private var didResolveProvider = false
    private var inFlight: Task<PaceDataRefreshOutcome, Never>?

    init(
        configuration: PaceDataConfiguration = .default,
        cache: PaceDataCacheStore = PaceDataCacheStore(),
        client: (any PaceDataHTTPFetching)? = nil,
        bundledProvider: @escaping @Sendable () throws -> PaceDataSnapshot = {
            try PaceReferenceLoader.loadBundledPaceData()
        }
    ) {
        self.configuration = configuration
        self.cache = cache
        self.client = client ?? PaceDataURLSessionClient(
            timeout: configuration.requestTimeout,
            maximumPayloadBytes: configuration.maximumFileBytes
        )
        self.bundledProvider = bundledProvider
    }

    // MARK: - Reading

    /// The tables in use. Resolved from disk on first call, then held in memory.
    ///
    /// `nil` only if the bundled snapshot is itself unreadable, which a unit test
    /// catches long before a build ships.
    func currentProvider() -> (any PaceDataProviding)? {
        lock.lock()
        if didResolveProvider {
            defer { lock.unlock() }
            return provider
        }
        lock.unlock()

        let resolved = resolveProvider()

        lock.lock()
        defer { lock.unlock() }
        // A refresh that landed while we were reading disk wins: it is strictly newer.
        if didResolveProvider { return provider }
        provider = resolved
        didResolveProvider = true
        return resolved
    }

    func dataset(for division: HyroxDivision) -> PaceDataset? {
        try? currentProvider()?.dataset(for: division)
    }

    var datasetVersion: String? { currentProvider()?.datasetVersion }

    var origin: PaceDataOrigin? { currentProvider()?.origin }

    /// Decodes the tables off the main thread so the first reader does not pay for it.
    func warmUp() {
        Task.detached(priority: .utility) { [weak self] in
            _ = self?.currentProvider()
        }
    }

    // MARK: - Refreshing

    /// Fire-and-forget entry point for app lifecycle hooks.
    func refreshInBackground(force: Bool = false) {
        Task.detached(priority: .utility) { [weak self] in
            await self?.refresh(force: force)
        }
    }

    /// Checks the catalogue and installs a newer snapshot if there is one.
    ///
    /// Concurrent callers share one attempt: the app can become active several times in
    /// a few seconds, and nine downloads per activation would be nine too many.
    @discardableResult
    func refresh(force: Bool = false, now: Date = Date()) async -> PaceDataRefreshOutcome {
        await refreshTask(force: force, now: now).value
    }

    // MARK: - Private

    /// Returns the attempt already running, or starts one.
    ///
    /// Synchronous on purpose: taking a lock from an async function suspends nothing
    /// and blocks a cooperative thread, so the bookkeeping stays outside `async` code
    /// and only the `await` on the task's value happens there.
    private func refreshTask(force: Bool, now: Date) -> Task<PaceDataRefreshOutcome, Never> {
        lock.lock()
        defer { lock.unlock() }

        if let existing = inFlight { return existing }

        let created = Task { [weak self] () -> PaceDataRefreshOutcome in
            guard let self else { return .unchanged }
            defer { self.clearInFlight() }
            return await self.performRefresh(force: force, now: now)
        }
        inFlight = created
        return created
    }

    private func clearInFlight() {
        lock.lock()
        inFlight = nil
        lock.unlock()
    }

    private func performRefresh(force: Bool, now: Date) async -> PaceDataRefreshOutcome {
        let currentVersion = currentProvider()?.datasetVersion ?? ""
        var state = cache.loadState()

        if !force, let notBefore = state.nextCheckNotBefore, isStillWaiting(until: notBefore, now: now) {
            return .notDue(nextCheck: notBefore)
        }

        // Only conditional when the catalogue we last saw described exactly what is
        // loaded now. After a rollback or a cleared cache the pairing no longer holds,
        // and a 304 would hide an update we actually want.
        let etag = state.etagDatasetVersion == currentVersion ? state.manifestETag : nil

        let updater = PaceDataUpdater(configuration: configuration, client: client, cache: cache)

        do {
            let result = try await updater.run(currentVersion: currentVersion, etag: etag)

            state.lastCheckedAt = now
            state.nextCheckNotBefore = now.addingTimeInterval(configuration.minimumRefreshInterval)

            switch result.kind {
            case .notModified:
                cache.save(state)
                Self.logger.debug("pace catalogue unchanged (304), staying on \(currentVersion, privacy: .public)")
                return .unchanged

            case .installed:
                state.manifestETag = result.etag
                state.etagDatasetVersion = result.datasetVersion
                cache.save(state)

                if let snapshot = result.snapshot {
                    setProvider(snapshot)
                }
                let version = result.datasetVersion ?? ""
                Self.logger.notice("installed pace dataset \(version, privacy: .public)")
                return .updated(version: version)

            case .alreadyCurrent, .revoked:
                if result.revokesInstalledVersion {
                    // Whatever is on disk is withdrawn; the bundled snapshot is the
                    // only thing left that the publisher still stands behind.
                    cache.clearSnapshot()
                    state.manifestETag = result.etag
                    state.etagDatasetVersion = nil
                    cache.save(state)

                    let fallback = reloadFromBundle()
                    Self.logger.notice(
                        "pace dataset \(currentVersion, privacy: .public) was revoked, fell back to \(fallback ?? "none", privacy: .public)"
                    )
                    return .revertedToBundled(version: fallback ?? "")
                }

                state.manifestETag = result.etag
                state.etagDatasetVersion = currentVersion
                cache.save(state)

                if result.kind == .revoked {
                    Self.logger.notice(
                        "published pace dataset \(result.datasetVersion ?? "", privacy: .public) is revoked, ignoring"
                    )
                }
                return .unchanged
            }
        } catch {
            state.lastCheckedAt = now
            state.nextCheckNotBefore = now.addingTimeInterval(configuration.failureRetryInterval)
            cache.save(state)

            let reason = String(describing: error)
            Self.logger.error("pace data refresh failed, keeping \(currentVersion, privacy: .public): \(reason, privacy: .public)")
            return .failed(reason)
        }
    }

    /// A `nextCheckNotBefore` further out than one whole interval can only come from a
    /// clock that has since moved back. Honouring it would freeze the data permanently,
    /// so it is treated as due instead.
    private func isStillWaiting(until notBefore: Date, now: Date) -> Bool {
        guard notBefore > now else { return false }
        return notBefore <= now.addingTimeInterval(configuration.minimumRefreshInterval)
    }

    private func setProvider(_ snapshot: PaceDataSnapshot) {
        lock.lock()
        provider = snapshot
        didResolveProvider = true
        lock.unlock()
    }

    @discardableResult
    private func reloadFromBundle() -> String? {
        guard let bundled = try? bundledProvider() else {
            Self.logger.error("bundled pace snapshot is unreadable")
            return nil
        }
        setProvider(bundled)
        return bundled.datasetVersion
    }

    /// Picks the newest trustworthy snapshot: the download if it beats the binary,
    /// otherwise what shipped with the app.
    private func resolveProvider() -> (any PaceDataProviding)? {
        let bundled = try? bundledProvider()
        if bundled == nil {
            Self.logger.error("bundled pace snapshot is unreadable")
        }

        do {
            if let cached = try cache.loadSnapshot() {
                if let bundled, !PaceDataVersion.isNewer(cached.datasetVersion, than: bundled.datasetVersion) {
                    // An app update shipped tables at least as new as the cached ones,
                    // so the download is dead weight now.
                    cache.clearSnapshot()
                    return bundled
                }
                return cached
            }
        } catch {
            // Installed but unreadable: drop it rather than retrying a bad file on
            // every launch, and let the next refresh fetch it again.
            Self.logger.error(
                "cached pace data is unusable, falling back to the bundled snapshot: \(String(describing: error), privacy: .public)"
            )
            cache.clearSnapshot()
        }

        return bundled
    }
}
