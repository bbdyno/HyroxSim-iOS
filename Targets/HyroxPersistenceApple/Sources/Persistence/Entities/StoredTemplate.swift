//
//  StoredTemplate.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import HyroxCore
import SwiftData

/// SwiftData entity for persisting user-created custom workout templates.
/// Built-in presets (`HyroxPresets`) are NOT stored — they live in code.
@Model
public final class StoredTemplate {
    @Attribute(.unique) public var id: UUID
    public var name: String
    /// `HyroxDivision.rawValue` or nil
    public var divisionRaw: String?
    public var createdAt: Date

    /// `[WorkoutSegment]` serialized as JSON Data
    public var segmentsData: Data

    /// `WorkoutTemplate.usesRoxZone`.
    ///
    /// Optional on purpose: rows written before this attribute existed decode as
    /// `nil` (SwiftData lightweight migration) and `WorkoutTemplateMapper` then
    /// infers the flag from the stored segments, so a template saved with ROX OFF
    /// no longer comes back as ON.
    public var usesRoxZone: Bool?

    public init(
        id: UUID,
        name: String,
        divisionRaw: String?,
        createdAt: Date,
        segmentsData: Data,
        usesRoxZone: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.divisionRaw = divisionRaw
        self.createdAt = createdAt
        self.segmentsData = segmentsData
        self.usesRoxZone = usesRoxZone
    }
}
