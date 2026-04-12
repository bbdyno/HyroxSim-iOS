//
//  WorkoutTemplate.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// A reusable workout template defining the structure of a workout
public struct WorkoutTemplate: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// The HYROX division this template is for (nil for custom templates)
    public var division: HyroxDivision?
    public var segments: [WorkoutSegment]
    /// Whether ROX Zone transition segments should be present between run/station boundaries.
    public var usesRoxZone: Bool
    public var createdAt: Date
    /// Whether this is a built-in preset template
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        division: HyroxDivision? = nil,
        segments: [WorkoutSegment],
        usesRoxZone: Bool = true,
        createdAt: Date = Date(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.division = division
        self.segments = segments
        self.usesRoxZone = usesRoxZone
        self.createdAt = createdAt
        self.isBuiltIn = isBuiltIn
    }

    // MARK: - Computed Properties

    /// Total distance of all run segments in meters
    public var totalRunDistanceMeters: Double {
        segments
            .filter { $0.type == .run }
            .compactMap(\.distanceMeters)
            .reduce(0, +)
    }

    /// Number of station segments
    public var stationCount: Int {
        segments.filter { $0.type == .station }.count
    }

    /// Estimated total duration in seconds (rough estimate for display)
    public var estimatedDurationSeconds: TimeInterval {
        segments.reduce(0) { total, segment in
            total + (segment.goalDurationSeconds ?? WorkoutSegment.defaultGoalDurationSeconds(
                for: segment.type,
                distanceMeters: segment.distanceMeters
            ))
        }
    }

    /// Logical segments excluding synthesized ROX transitions.
    public var logicalSegments: [WorkoutSegment] {
        segments.filter { $0.type != .roxZone }
    }

    public func settingUsesRoxZone(
        _ enabled: Bool,
        preservedRoxSegments: [WorkoutSegment]? = nil
    ) -> WorkoutTemplate {
        var copy = self
        copy.usesRoxZone = enabled
        copy.segments = Self.materializedSegments(
            from: logicalSegments,
            usesRoxZone: enabled,
            preservedRoxSegments: preservedRoxSegments ?? segments.filter { $0.type == .roxZone }
        )
        return copy
    }

    public static func materializedSegments(
        from logicalSegments: [WorkoutSegment],
        usesRoxZone: Bool,
        preservedRoxSegments: [WorkoutSegment] = []
    ) -> [WorkoutSegment] {
        guard usesRoxZone else { return logicalSegments }

        var materialized: [WorkoutSegment] = []
        var roxIterator = preservedRoxSegments.makeIterator()

        for (index, segment) in logicalSegments.enumerated() {
            materialized.append(segment)
            guard index < logicalSegments.count - 1 else { continue }
            let next = logicalSegments[index + 1]
            if needsRoxZoneBetween(segment, next) {
                materialized.append(roxIterator.next() ?? .roxZone())
            }
        }

        return materialized
    }

    // MARK: - Validation

    public enum ValidationError: LocalizedError, Equatable {
        case emptySegments

        public var errorDescription: String? {
            switch self {
            case .emptySegments:
                return "Workout template must have at least one segment"
            }
        }
    }

    /// Validates the template structure and all contained segments
    public func validate() throws {
        if segments.isEmpty {
            throw ValidationError.emptySegments
        }
        for segment in segments {
            try segment.validate()
        }
    }

    private static func needsRoxZoneBetween(_ current: WorkoutSegment, _ next: WorkoutSegment) -> Bool {
        let pair = (current.type, next.type)
        switch pair {
        case (.run, .station), (.station, .run):
            return true
        default:
            return false
        }
    }
}
