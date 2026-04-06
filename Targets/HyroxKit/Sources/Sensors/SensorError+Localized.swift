//
//  SensorError+Localized.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

extension SensorError {
    /// A user-facing message suitable for display in alerts.
    /// Localization is deferred to a future stage.
    public var userFacingMessage: String {
        switch self {
        case .authorizationDenied:
            return "Permission denied. Please enable in Settings."
        case .unavailable:
            return "This sensor is not available on your device."
        case .startFailed(let reason):
            return "Failed to start sensor: \(reason)"
        }
    }
}
