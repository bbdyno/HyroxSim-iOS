import Foundation

/// Built-in HYROX workout presets for all official divisions
public enum HyroxPresets {

    public static let menOpenSingle = buildTemplate(division: .menOpenSingle)
    public static let menOpenDouble = buildTemplate(division: .menOpenDouble)
    public static let menProSingle = buildTemplate(division: .menProSingle)
    public static let menProDouble = buildTemplate(division: .menProDouble)
    public static let womenOpenSingle = buildTemplate(division: .womenOpenSingle)
    public static let womenOpenDouble = buildTemplate(division: .womenOpenDouble)
    public static let womenProSingle = buildTemplate(division: .womenProSingle)
    public static let womenProDouble = buildTemplate(division: .womenProDouble)
    public static let mixedDouble = buildTemplate(division: .mixedDouble)

    /// All 9 built-in presets
    public static let all: [WorkoutTemplate] = [
        menOpenSingle, menOpenDouble,
        menProSingle, menProDouble,
        womenOpenSingle, womenOpenDouble,
        womenProSingle, womenProDouble,
        mixedDouble
    ]

    /// Returns the preset template for a given division
    public static func template(for division: HyroxDivision) -> WorkoutTemplate {
        switch division {
        case .menOpenSingle: return menOpenSingle
        case .menOpenDouble: return menOpenDouble
        case .menProSingle: return menProSingle
        case .menProDouble: return menProDouble
        case .womenOpenSingle: return womenOpenSingle
        case .womenOpenDouble: return womenOpenDouble
        case .womenProSingle: return womenProSingle
        case .womenProDouble: return womenProDouble
        case .mixedDouble: return mixedDouble
        }
    }

    // MARK: - Builder

    /// Builds a standard HYROX workout template for a division.
    /// Structure: 8 rounds of (Run 1 km → ROX Zone → Station) = 24 segments.
    /// Last station (Wall Balls) has no trailing ROX Zone — it's the finish.
    private static func buildTemplate(division: HyroxDivision) -> WorkoutTemplate {
        let specs = HyroxDivisionSpec.stations(for: division)
        var segments: [WorkoutSegment] = []

        for spec in specs {
            segments.append(.run())
            segments.append(.roxZone())
            segments.append(.station(
                spec.kind,
                target: spec.target,
                weightKg: spec.weightKg,
                weightNote: spec.weightNote
            ))
        }

        return WorkoutTemplate(
            name: division.displayName,
            division: division,
            segments: segments,
            isBuiltIn: true
        )
    }
}
