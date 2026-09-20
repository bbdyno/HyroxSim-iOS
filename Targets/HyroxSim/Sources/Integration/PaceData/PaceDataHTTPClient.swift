//
//  PaceDataHTTPClient.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

/// One conditional GET.
struct PaceDataRequest: Sendable {
    let url: URL
    /// Sent as `If-None-Match` when present.
    let etag: String?

    init(url: URL, etag: String? = nil) {
        self.url = url
        self.etag = etag
    }
}

enum PaceDataHTTPResult: Sendable {
    /// Server answered 304: what we already hold is current.
    case notModified
    case payload(data: Data, etag: String?)
}

enum PaceDataHTTPError: Error, Hashable, Sendable {
    case invalidResponse
    case unacceptableStatus(Int)
    case payloadTooLarge(bytes: Int, limit: Int)
}

extension PaceDataHTTPError: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidResponse:
            return "response was not HTTP"
        case .unacceptableStatus(let code):
            return "HTTP \(code)"
        case .payloadTooLarge(let bytes, let limit):
            return "payload of \(bytes) bytes is over the \(limit) byte limit"
        }
    }
}

/// The seam the updater is written against, so tests never touch the network.
protocol PaceDataHTTPFetching: Sendable {
    func fetch(_ request: PaceDataRequest) async throws -> PaceDataHTTPResult
}

/// `URLSession` on a default configuration.
///
/// The session's own cache is switched off on purpose. With a `URLCache` in play,
/// URLSession answers a conditional request by quietly replaying a stored 200, and the
/// updater would never see the 304 it uses to skip nine downloads. Freshness is
/// handled here instead, with an ETag the updater stores next to the data it describes.
struct PaceDataURLSessionClient: PaceDataHTTPFetching {

    private let session: URLSession
    private let timeout: TimeInterval
    private let maximumPayloadBytes: Int

    init(timeout: TimeInterval = 15, maximumPayloadBytes: Int = 2 * 1024 * 1024) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        // The whole payload is ~110 KB and only fetched once a day, so there is no
        // reason to make the athlete wait for Wi-Fi.
        configuration.allowsCellularAccess = true
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]

        self.session = URLSession(configuration: configuration)
        self.timeout = timeout
        self.maximumPayloadBytes = maximumPayloadBytes
    }

    /// Test seam for a `URLProtocol`-backed session.
    init(session: URLSession, timeout: TimeInterval = 15, maximumPayloadBytes: Int = 2 * 1024 * 1024) {
        self.session = session
        self.timeout = timeout
        self.maximumPayloadBytes = maximumPayloadBytes
    }

    func fetch(_ request: PaceDataRequest) async throws -> PaceDataHTTPResult {
        var urlRequest = URLRequest(
            url: request.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        urlRequest.httpMethod = "GET"
        if let etag = request.etag, !etag.isEmpty {
            urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw PaceDataHTTPError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            guard data.count <= maximumPayloadBytes else {
                throw PaceDataHTTPError.payloadTooLarge(bytes: data.count, limit: maximumPayloadBytes)
            }
            return .payload(data: data, etag: http.value(forHTTPHeaderField: "Etag"))
        case 304:
            return .notModified
        default:
            throw PaceDataHTTPError.unacceptableStatus(http.statusCode)
        }
    }
}
