//
//  PaceDataConfiguration.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore

/// Where the competition-record catalogue lives.
///
/// 공개본은 `docs/` 를 그대로 서빙하는 GitHub Pages 가 기본이다. main 에 푸시하면
/// 바로 반영되므로 별도 배포 단계가 없다. Firebase Hosting(`firebase.json`)도 같은
/// 디렉토리를 서빙하고 `/pace/manifest.json` 5분 · `/pace/v*/**` immutable 캐시 헤더를
/// 주므로, `firebase deploy` 를 돌리는 운영으로 바꾸면 아래 상수만 그 도메인으로 되돌리면 된다.
/// 데이터 파일 경로는 버전이 들어간 불변 경로라 어느 쪽이든 오래된 값이 섞이지 않는다.
enum PaceDataEndpoint {

    static let defaultManifestURLString = "https://bbdyno.github.io/HyroxSim-iOS/pace/manifest.json"

    /// Optional `Info.plist` override, for pointing a build at a staging catalogue.
    static let infoPlistKey = "PaceDataManifestURL"

    /// Optional process-environment override, for UI tests and local debugging.
    static let environmentKey = "HYROX_PACE_MANIFEST_URL"

    /// Resolves the catalogue URL: environment, then `Info.plist`, then the default.
    ///
    /// Only `https` is accepted. The catalogue decides which files the app downloads
    /// and installs, so letting a plaintext origin supply it would hand that decision
    /// to anyone on the network path — the SHA-256 checks in the manifest are
    /// worthless if the manifest itself can be rewritten in flight.
    static func manifestURL(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let candidates = [
            environment[environmentKey],
            bundle.object(forInfoDictionaryKey: infoPlistKey) as? String,
            defaultManifestURLString
        ]

        for candidate in candidates {
            guard let candidate, !candidate.isEmpty,
                  let url = URL(string: candidate),
                  url.scheme?.lowercased() == "https",
                  url.host?.isEmpty == false else { continue }
            return url
        }

        // Unreachable unless the literal above is edited into something invalid.
        return URL(string: defaultManifestURLString)!
    }
}

/// Knobs for the remote refresh.
struct PaceDataConfiguration: Sendable {

    /// Catalogue to poll.
    var manifestURL: URL

    /// How long a successful check is good for. The tables change a few times a season,
    /// so a day is already far more often than the data moves.
    var minimumRefreshInterval: TimeInterval

    /// How long to wait after a failed check. Deliberately much shorter than
    /// `minimumRefreshInterval`: a dropped connection should not cost a whole day.
    var failureRetryInterval: TimeInterval

    /// Per-request timeout. Cellular is allowed — the payload is ~110 KB.
    var requestTimeout: TimeInterval

    /// Dataset schema versions this build can decode.
    var supportedSchemaVersions: ClosedRange<Int>

    /// Refuses to download a file the catalogue declares larger than this.
    /// Today's files are ~12 KB each, so this only exists to bound a bad catalogue.
    var maximumFileBytes: Int

    init(
        manifestURL: URL,
        minimumRefreshInterval: TimeInterval = 24 * 60 * 60,
        failureRetryInterval: TimeInterval = 60 * 60,
        requestTimeout: TimeInterval = 15,
        supportedSchemaVersions: ClosedRange<Int> = PaceDatasetValidator.supportedSchemaVersions,
        maximumFileBytes: Int = 2 * 1024 * 1024
    ) {
        self.manifestURL = manifestURL
        self.minimumRefreshInterval = minimumRefreshInterval
        self.failureRetryInterval = failureRetryInterval
        self.requestTimeout = requestTimeout
        self.supportedSchemaVersions = supportedSchemaVersions
        self.maximumFileBytes = maximumFileBytes
    }

    static var `default`: PaceDataConfiguration {
        PaceDataConfiguration(manifestURL: PaceDataEndpoint.manifestURL())
    }

    /// Absolute URL of one catalogue entry.
    ///
    /// Components are appended one at a time rather than joining the whole `name`,
    /// so a name that somehow still holds a separator cannot reshape the path.
    /// `PaceDataManifest.validatedFiles()` has already rejected traversal and absolute
    /// names by the time this runs; this is the second of the two locks.
    func fileURL(for file: PaceDataManifestFile) -> URL? {
        guard PaceDataManifest.isSafeRelativePath(file.name) else { return nil }
        var url = manifestURL.deletingLastPathComponent()
        for component in file.name.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        return url
    }
}
