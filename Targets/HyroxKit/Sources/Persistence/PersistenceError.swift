//
//  PersistenceError.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// Errors thrown by the persistence layer
public enum PersistenceError: Error, Hashable, Sendable {
    /// ModelContainer could not be created
    case modelContainerUnavailable
    /// Failed to encode domain model to stored format
    case encodingFailed
    /// Failed to decode stored data back to domain model
    case decodingFailed
    /// Entity with the given ID was not found
    case notFound(id: UUID)
}
