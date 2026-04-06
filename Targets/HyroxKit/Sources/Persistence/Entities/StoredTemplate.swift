import Foundation
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

    public init(
        id: UUID,
        name: String,
        divisionRaw: String?,
        createdAt: Date,
        segmentsData: Data
    ) {
        self.id = id
        self.name = name
        self.divisionRaw = divisionRaw
        self.createdAt = createdAt
        self.segmentsData = segmentsData
    }
}
