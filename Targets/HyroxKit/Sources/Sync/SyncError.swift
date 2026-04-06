import Foundation

/// Errors from the sync layer
public enum SyncError: Error, Hashable, Sendable {
    case sessionUnavailable
    case counterpartUnreachable
    case encodingFailed
    case decodingFailed
    case fileTransferFailed(reason: String)
}
