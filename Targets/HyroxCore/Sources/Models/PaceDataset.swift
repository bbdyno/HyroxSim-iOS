//
//  PaceDataset.swift
//  HyroxCore
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

// MARK: - Verbatim JSON

/// A JSON value carried through without being modelled.
///
/// The provenance blocks (`cleaning.merges`, `cleaning.component_rescales`, …) are
/// audit records whose shape changes whenever a cleaning rule is added upstream.
/// Modelling them field by field would make a brand new rule fail to decode, which
/// would block a data update for a reason that has nothing to do with the numbers
/// the app reads. They are kept verbatim instead.
public enum PaceJSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([PaceJSONValue])
    case object([String: PaceJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([PaceJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: PaceJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(exactly: value.rounded())
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    public var arrayValue: [PaceJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: PaceJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

// MARK: - Dataset

/// One division's competition-record reference table (`schema_version` 4).
///
/// Mirrors `docs/pace/v4/<dataset_version>/<division>.json`, which the build script
/// `tools/pace-data/build_pace_data.py` produces. The numeric payload — `gridP`,
/// `overallS`, `components`, `ageGroups` — is modelled exactly; the descriptive
/// blocks are modelled leniently so an upstream addition never costs a data update.
///
/// A decoded value is not trustworthy on its own: run it through
/// ``PaceDatasetValidator`` before handing it to a caller.
public struct PaceDataset: Codable, Hashable, Sendable {

    /// Schema of the file this was decoded from. Only 4 is understood today.
    public let schemaVersion: Int
    /// Publication stamp, `YYYY.MM.DD`. Ordered by ``PaceDataVersion``.
    public let datasetVersion: String
    /// `HyroxDivision.rawValue` as written in the file. Kept as a string so an
    /// unknown division fails in the validator with a readable error instead of
    /// producing an opaque `DecodingError`.
    public let divisionKey: String
    /// Division label in the upstream source (e.g. `MEN`, `PRO WOMEN DOUBLES`).
    public let sourceDivision: String
    public let generator: PaceDataGenerator
    /// Smallest sample size any published cell was built from.
    public let minCellN: Int
    public let coverage: PaceDatasetCoverage
    public let sources: [PaceDatasetSource]
    public let cleaning: PaceDatasetCleaning
    public let method: PaceDatasetMethod
    /// Percentile grid, strictly increasing, 0 < p <= 100. Faster finishes first.
    public let gridP: [Double]
    /// Finish time in seconds at each `gridP` entry. Strictly increasing.
    public let overallS: [Int]
    public let components: PaceDatasetComponents
    /// Per age group finish-time curves. Only groups with enough athletes are published.
    public let ageGroups: [PaceDatasetAgeGroup]

    /// The division this table describes, or `nil` when the file names a division
    /// this build does not know.
    public var division: HyroxDivision? { HyroxDivision(rawValue: divisionKey) }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case datasetVersion = "dataset_version"
        case divisionKey = "division"
        case sourceDivision = "source_division"
        case generator
        case minCellN = "min_cell_n"
        case coverage
        case sources
        case cleaning
        case method
        case gridP = "grid_p"
        case overallS = "overall_s"
        case components
        case ageGroups = "age_groups"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        datasetVersion = try container.decode(String.self, forKey: .datasetVersion)
        divisionKey = try container.decode(String.self, forKey: .divisionKey)
        sourceDivision = try container.decodeIfPresent(String.self, forKey: .sourceDivision) ?? ""
        generator = try container.decodeIfPresent(PaceDataGenerator.self, forKey: .generator)
            ?? PaceDataGenerator(script: "", version: "")
        minCellN = try container.decodeIfPresent(Int.self, forKey: .minCellN) ?? 0
        coverage = try container.decodeIfPresent(PaceDatasetCoverage.self, forKey: .coverage)
            ?? PaceDatasetCoverage()
        sources = try container.decodeIfPresent([PaceDatasetSource].self, forKey: .sources) ?? []
        cleaning = try container.decodeIfPresent(PaceDatasetCleaning.self, forKey: .cleaning)
            ?? PaceDatasetCleaning()
        method = try container.decodeIfPresent(PaceDatasetMethod.self, forKey: .method)
            ?? PaceDatasetMethod()
        gridP = try container.decode([Double].self, forKey: .gridP)
        overallS = try container.decode([Int].self, forKey: .overallS)
        components = try container.decode(PaceDatasetComponents.self, forKey: .components)
        ageGroups = try container.decodeIfPresent([PaceDatasetAgeGroup].self, forKey: .ageGroups) ?? []
    }

    /// Test seam. Production code only ever decodes a dataset from JSON.
    init(
        schemaVersion: Int,
        datasetVersion: String,
        divisionKey: String,
        sourceDivision: String = "",
        generator: PaceDataGenerator = PaceDataGenerator(script: "", version: ""),
        minCellN: Int = 0,
        coverage: PaceDatasetCoverage = PaceDatasetCoverage(),
        sources: [PaceDatasetSource] = [],
        cleaning: PaceDatasetCleaning = PaceDatasetCleaning(),
        method: PaceDatasetMethod = PaceDatasetMethod(),
        gridP: [Double],
        overallS: [Int],
        components: PaceDatasetComponents,
        ageGroups: [PaceDatasetAgeGroup] = []
    ) {
        self.schemaVersion = schemaVersion
        self.datasetVersion = datasetVersion
        self.divisionKey = divisionKey
        self.sourceDivision = sourceDivision
        self.generator = generator
        self.minCellN = minCellN
        self.coverage = coverage
        self.sources = sources
        self.cleaning = cleaning
        self.method = method
        self.gridP = gridP
        self.overallS = overallS
        self.components = components
        self.ageGroups = ageGroups
    }
}

/// Which script wrote a dataset or manifest.
public struct PaceDataGenerator: Codable, Hashable, Sendable {
    public let script: String
    public let version: String

    public init(script: String, version: String) {
        self.script = script
        self.version = version
    }
}

/// What the published numbers were computed from.
///
/// Every field is optional: coverage is descriptive, and a missing entry must never
/// reject an otherwise sound dataset.
public struct PaceDatasetCoverage: Codable, Hashable, Sendable {
    public let division: String?
    public let sourceDivision: String?
    public let seasons: [Int]
    public let seasonLabel: String?
    public let events: Int?
    public let eventsWithDivision: Int?
    public let athletesUpstream: Int?
    public let athletesInBuckets: Int?
    public let athletesWithFinishTime: Int?
    public let buckets: Int?
    /// `[slowestPublishedMinutes, fastestPublishedMinutes]` of the source buckets.
    public let bucketRangeMin: [Int]
    public let upstreamVersion: String?
    public let upstreamGenerated: String?

    enum CodingKeys: String, CodingKey {
        case division
        case sourceDivision = "source_division"
        case seasons
        case seasonLabel = "season_label"
        case events
        case eventsWithDivision = "events_with_division"
        case athletesUpstream = "athletes_upstream"
        case athletesInBuckets = "athletes_in_buckets"
        case athletesWithFinishTime = "athletes_with_finish_time"
        case buckets
        case bucketRangeMin = "bucket_range_min"
        case upstreamVersion = "upstream_version"
        case upstreamGenerated = "upstream_generated"
    }

    public init(
        division: String? = nil,
        sourceDivision: String? = nil,
        seasons: [Int] = [],
        seasonLabel: String? = nil,
        events: Int? = nil,
        eventsWithDivision: Int? = nil,
        athletesUpstream: Int? = nil,
        athletesInBuckets: Int? = nil,
        athletesWithFinishTime: Int? = nil,
        buckets: Int? = nil,
        bucketRangeMin: [Int] = [],
        upstreamVersion: String? = nil,
        upstreamGenerated: String? = nil
    ) {
        self.division = division
        self.sourceDivision = sourceDivision
        self.seasons = seasons
        self.seasonLabel = seasonLabel
        self.events = events
        self.eventsWithDivision = eventsWithDivision
        self.athletesUpstream = athletesUpstream
        self.athletesInBuckets = athletesInBuckets
        self.athletesWithFinishTime = athletesWithFinishTime
        self.buckets = buckets
        self.bucketRangeMin = bucketRangeMin
        self.upstreamVersion = upstreamVersion
        self.upstreamGenerated = upstreamGenerated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        division = try container.decodeIfPresent(String.self, forKey: .division)
        sourceDivision = try container.decodeIfPresent(String.self, forKey: .sourceDivision)
        seasons = try container.decodeIfPresent([Int].self, forKey: .seasons) ?? []
        seasonLabel = try container.decodeIfPresent(String.self, forKey: .seasonLabel)
        events = try container.decodeIfPresent(Int.self, forKey: .events)
        eventsWithDivision = try container.decodeIfPresent(Int.self, forKey: .eventsWithDivision)
        athletesUpstream = try container.decodeIfPresent(Int.self, forKey: .athletesUpstream)
        athletesInBuckets = try container.decodeIfPresent(Int.self, forKey: .athletesInBuckets)
        athletesWithFinishTime = try container.decodeIfPresent(Int.self, forKey: .athletesWithFinishTime)
        buckets = try container.decodeIfPresent(Int.self, forKey: .buckets)
        bucketRangeMin = try container.decodeIfPresent([Int].self, forKey: .bucketRangeMin) ?? []
        upstreamVersion = try container.decodeIfPresent(String.self, forKey: .upstreamVersion)
        upstreamGenerated = try container.decodeIfPresent(String.self, forKey: .upstreamGenerated)
    }
}

/// One upstream feed the numbers were derived from, and which of its fields were read.
public struct PaceDatasetSource: Codable, Hashable, Sendable {
    public let name: String
    public let url: String?
    public let usedFields: [String]
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case usedFields = "used_fields"
        case note
    }

    public init(name: String, url: String? = nil, usedFields: [String] = [], note: String? = nil) {
        self.name = name
        self.url = url
        self.usedFields = usedFields
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url)
        usedFields = try container.decodeIfPresent([String].self, forKey: .usedFields) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

/// What the build script had to repair before publishing, and how often.
///
/// `rules` and `counts` are stable enough to type. The per-record arrays are audit
/// trails; they are kept as ``PaceJSONValue`` so a new rule cannot break decoding.
public struct PaceDatasetCleaning: Codable, Hashable, Sendable {
    public let minCellN: Int?
    public let denseMinN: Int?
    /// Rule id (`R0_incomplete`, …) to its human description.
    public let rules: [String: String]
    /// Rule id to how many times it fired.
    public let counts: [String: Int]
    public let dropped: [PaceJSONValue]
    public let stationSpikesRepaired: [PaceJSONValue]
    public let merges: [PaceJSONValue]
    public let gapsBridged: [PaceJSONValue]
    public let componentRescales: [PaceJSONValue]
    public let isotonicAdjustments: [PaceJSONValue]

    enum CodingKeys: String, CodingKey {
        case minCellN = "min_cell_n"
        case denseMinN = "dense_min_n"
        case rules
        case counts
        case dropped
        case stationSpikesRepaired = "station_spikes_repaired"
        case merges
        case gapsBridged = "gaps_bridged"
        case componentRescales = "component_rescales"
        case isotonicAdjustments = "isotonic_adjustments"
    }

    public init(
        minCellN: Int? = nil,
        denseMinN: Int? = nil,
        rules: [String: String] = [:],
        counts: [String: Int] = [:],
        dropped: [PaceJSONValue] = [],
        stationSpikesRepaired: [PaceJSONValue] = [],
        merges: [PaceJSONValue] = [],
        gapsBridged: [PaceJSONValue] = [],
        componentRescales: [PaceJSONValue] = [],
        isotonicAdjustments: [PaceJSONValue] = []
    ) {
        self.minCellN = minCellN
        self.denseMinN = denseMinN
        self.rules = rules
        self.counts = counts
        self.dropped = dropped
        self.stationSpikesRepaired = stationSpikesRepaired
        self.merges = merges
        self.gapsBridged = gapsBridged
        self.componentRescales = componentRescales
        self.isotonicAdjustments = isotonicAdjustments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minCellN = try container.decodeIfPresent(Int.self, forKey: .minCellN)
        denseMinN = try container.decodeIfPresent(Int.self, forKey: .denseMinN)
        rules = try container.decodeIfPresent([String: String].self, forKey: .rules) ?? [:]
        counts = try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        dropped = try container.decodeIfPresent([PaceJSONValue].self, forKey: .dropped) ?? []
        stationSpikesRepaired = try container
            .decodeIfPresent([PaceJSONValue].self, forKey: .stationSpikesRepaired) ?? []
        merges = try container.decodeIfPresent([PaceJSONValue].self, forKey: .merges) ?? []
        gapsBridged = try container.decodeIfPresent([PaceJSONValue].self, forKey: .gapsBridged) ?? []
        componentRescales = try container
            .decodeIfPresent([PaceJSONValue].self, forKey: .componentRescales) ?? []
        isotonicAdjustments = try container
            .decodeIfPresent([PaceJSONValue].self, forKey: .isotonicAdjustments) ?? []
    }
}

/// Plain-language description of how each block was computed.
public struct PaceDatasetMethod: Codable, Hashable, Sendable {
    public let overallS: String?
    public let components: String?
    public let ageGroups: String?
    public let componentScale: PaceComponentScale?

    enum CodingKeys: String, CodingKey {
        case overallS = "overall_s"
        case components
        case ageGroups = "age_groups"
        case componentScale = "component_scale"
    }

    public init(
        overallS: String? = nil,
        components: String? = nil,
        ageGroups: String? = nil,
        componentScale: PaceComponentScale? = nil
    ) {
        self.overallS = overallS
        self.components = components
        self.ageGroups = ageGroups
        self.componentScale = componentScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overallS = try container.decodeIfPresent(String.self, forKey: .overallS)
        components = try container.decodeIfPresent(String.self, forKey: .components)
        ageGroups = try container.decodeIfPresent(String.self, forKey: .ageGroups)
        componentScale = try container.decodeIfPresent(PaceComponentScale.self, forKey: .componentScale)
    }
}

/// How far the component totals had to be stretched to meet `overall_s`.
/// A value far from 1.0 means the two upstream sources disagree.
public struct PaceComponentScale: Codable, Hashable, Sendable {
    public let min: Double?
    public let max: Double?
    public let note: String?

    public init(min: Double? = nil, max: Double? = nil, note: String? = nil) {
        self.min = min
        self.max = max
        self.note = note
    }
}

/// Finish time split into running (including ROX Zone transitions) and the 8 stations.
///
/// Every array is parallel to ``PaceDataset/gridP``, and at each index
/// `runRoxS + sum(stationsS) == overallS`. ``PaceDatasetValidator`` enforces that.
public struct PaceDatasetComponents: Codable, Hashable, Sendable {
    /// Combined run + ROX Zone seconds.
    public let runRoxS: [Int]
    /// Seconds per station, keyed by `StationKind.dataKey`.
    public let stationsS: [String: [Int]]

    enum CodingKeys: String, CodingKey {
        case runRoxS = "run_rox_s"
        case stationsS = "stations_s"
    }

    public init(runRoxS: [Int], stationsS: [String: [Int]]) {
        self.runRoxS = runRoxS
        self.stationsS = stationsS
    }

    /// Seconds curve for one of the 8 official stations, or `nil` for a custom station.
    public func seconds(for station: StationKind) -> [Int]? {
        guard let key = station.dataKey else { return nil }
        return stationsS[key]
    }
}

/// A finish-time curve for one age group, on its own (coarser) percentile grid.
public struct PaceDatasetAgeGroup: Codable, Hashable, Sendable {
    /// Upstream label, e.g. `16-24`, `50-54`.
    public let ageGroup: String
    /// Athletes the curve was built from.
    public let n: Int
    public let gridP: [Double]
    public let overallS: [Int]

    enum CodingKeys: String, CodingKey {
        case ageGroup = "age_group"
        case n
        case gridP = "grid_p"
        case overallS = "overall_s"
    }

    public init(ageGroup: String, n: Int, gridP: [Double], overallS: [Int]) {
        self.ageGroup = ageGroup
        self.n = n
        self.gridP = gridP
        self.overallS = overallS
    }
}

// MARK: - Lookup Result

/// A finish time broken into its parts at one percentile.
///
/// The parts always add up to ``overallSeconds`` exactly — the interpolated fractions
/// are apportioned by largest remainder, the same way the build script rounds them.
public struct PaceComponentSplit: Hashable, Sendable {
    /// Percentile the split was read at, after clamping to the covered range.
    public let percentile: Double
    public let overallSeconds: Int
    /// Combined run + ROX Zone seconds.
    public let runRoxSeconds: Int
    /// Seconds per station, keyed by `StationKind.dataKey`.
    public let stationSeconds: [String: Int]

    public init(
        percentile: Double,
        overallSeconds: Int,
        runRoxSeconds: Int,
        stationSeconds: [String: Int]
    ) {
        self.percentile = percentile
        self.overallSeconds = overallSeconds
        self.runRoxSeconds = runRoxSeconds
        self.stationSeconds = stationSeconds
    }

    /// Sum of the 8 official stations only — never whatever else a dictionary holds.
    public var stationTotalSeconds: Int {
        StationKind.standardDataKeys.reduce(0) { $0 + (stationSeconds[$1] ?? 0) }
    }

    public func seconds(for station: StationKind) -> Int? {
        guard let key = station.dataKey else { return nil }
        return stationSeconds[key]
    }
}

// MARK: - Lookups

extension PaceDataset {

    /// Percentiles the table covers. Lower is faster.
    public var percentileRange: ClosedRange<Double> {
        guard let first = gridP.first, let last = gridP.last, first <= last else { return 0...0 }
        return first...last
    }

    /// Finish times the table covers, in seconds.
    public var goalSecondsRange: ClosedRange<Int> {
        guard let first = overallS.first, let last = overallS.last, first <= last else { return 0...0 }
        return first...last
    }

    /// Whether `seconds` sits inside the published curve rather than past either end.
    public func coversGoalSeconds(_ seconds: Int) -> Bool {
        goalSecondsRange.contains(seconds)
    }

    /// Percentile rank of a finish time. Lower is faster.
    ///
    /// A time outside ``goalSecondsRange`` is pinned to the nearest end of the curve —
    /// check ``coversGoalSeconds(_:)`` first when that difference matters.
    public func percentile(forGoalSeconds seconds: Int) -> Double {
        PaceInterpolation.interpolate(
            Double(seconds),
            xs: overallS.map(Double.init),
            ys: gridP
        )
    }

    /// Finish time at a percentile, in seconds. Clamped to ``percentileRange``.
    public func goalSeconds(atPercentile percentile: Double) -> Int {
        let value = PaceInterpolation.interpolate(
            percentile,
            xs: gridP,
            ys: overallS.map(Double.init)
        )
        return Int(value.rounded())
    }

    /// Run/ROX and per-station seconds at a percentile.
    ///
    /// The parts are apportioned so they add up to the interpolated finish time exactly.
    public func components(atPercentile percentile: Double) -> PaceComponentSplit {
        let keys = StationKind.standardDataKeys
        let clamped = min(max(percentile, percentileRange.lowerBound), percentileRange.upperBound)

        let overallExact = PaceInterpolation.interpolate(
            clamped,
            xs: gridP,
            ys: overallS.map(Double.init)
        )
        let total = Int(overallExact.rounded())

        var exact: [Double] = [
            PaceInterpolation.interpolate(clamped, xs: gridP, ys: components.runRoxS.map(Double.init))
        ]
        for key in keys {
            let curve = components.stationsS[key] ?? []
            exact.append(PaceInterpolation.interpolate(clamped, xs: gridP, ys: curve.map(Double.init)))
        }

        let apportioned = PaceInterpolation.apportion(exact, total: total)
        var stations: [String: Int] = [:]
        for (offset, key) in keys.enumerated() where offset + 1 < apportioned.count {
            stations[key] = apportioned[offset + 1]
        }

        return PaceComponentSplit(
            percentile: clamped,
            overallSeconds: total,
            runRoxSeconds: apportioned.first ?? 0,
            stationSeconds: stations
        )
    }

    /// Run/ROX and per-station seconds for a target finish time.
    public func components(forGoalSeconds seconds: Int) -> PaceComponentSplit {
        components(atPercentile: percentile(forGoalSeconds: seconds))
    }

    /// Age-group labels this division publishes, fastest-eligible first as written upstream.
    public var ageGroupIdentifiers: [String] { ageGroups.map(\.ageGroup) }

    public func ageGroup(_ identifier: String) -> PaceDatasetAgeGroup? {
        ageGroups.first { $0.ageGroup == identifier }
    }

    /// Percentile rank of a finish time within one age group.
    /// - Returns: `nil` when the division does not publish that age group — most often
    ///   because too few athletes in it finished for the sample to stay anonymous.
    public func ageGroupPercentile(forGoalSeconds seconds: Int, ageGroup identifier: String) -> Double? {
        guard let group = ageGroup(identifier) else { return nil }
        return PaceInterpolation.interpolate(
            Double(seconds),
            xs: group.overallS.map(Double.init),
            ys: group.gridP
        )
    }

    /// Finish time at a percentile within one age group, in seconds.
    /// - Returns: `nil` when the division does not publish that age group.
    public func ageGroupGoalSeconds(atPercentile percentile: Double, ageGroup identifier: String) -> Int? {
        guard let group = ageGroup(identifier) else { return nil }
        let value = PaceInterpolation.interpolate(
            percentile,
            xs: group.gridP,
            ys: group.overallS.map(Double.init)
        )
        return Int(value.rounded())
    }
}

// MARK: - Interpolation

/// Piecewise-linear reads off a strictly increasing grid.
///
/// Both axes of a validated dataset are strictly increasing, so plain linear
/// interpolation between neighbours is itself monotone: a later finish time can never
/// map to an earlier percentile. Queries past either end return that end's value
/// rather than extrapolating a number no athlete ever ran.
enum PaceInterpolation {

    /// Reads `ys` at `x` along `xs`. Both arrays must be the same length and `xs`
    /// must be strictly increasing — ``PaceDatasetValidator`` guarantees both.
    static func interpolate(_ x: Double, xs: [Double], ys: [Double]) -> Double {
        guard xs.count == ys.count, let firstX = xs.first, let firstY = ys.first else { return 0 }
        guard xs.count > 1, let lastX = xs.last, let lastY = ys.last else { return firstY }

        if x <= firstX { return firstY }
        if x >= lastX { return lastY }

        let index = segmentIndex(for: x, in: xs)
        let span = xs[index + 1] - xs[index]
        guard span > 0 else { return ys[index] }

        let t = (x - xs[index]) / span
        return ys[index] + (ys[index + 1] - ys[index]) * t
    }

    /// Largest index `i` in `0...xs.count - 2` with `xs[i] <= x`.
    private static func segmentIndex(for x: Double, in xs: [Double]) -> Int {
        var low = 0
        var high = xs.count - 2
        while low < high {
            let mid = (low + high + 1) / 2
            if xs[mid] <= x { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Rounds `values` to integers that sum to `total`, by largest remainder.
    ///
    /// Interpolating nine components independently and rounding each one drifts the
    /// sum by up to ±4 seconds, which would show a plan that does not add up to its
    /// own goal. Because the grid rows sum exactly, the interpolated doubles do too,
    /// so handing the rounding residue out by largest fractional part restores the
    /// total without moving any component more than a second.
    static func apportion(_ values: [Double], total: Int) -> [Int] {
        guard !values.isEmpty else { return [] }

        var result = values.map { Int($0.rounded(.down)) }
        var remaining = total - result.reduce(0, +)

        if remaining > 0 {
            let byRemainder = values.indices.sorted {
                (values[$0] - Double(result[$0])) > (values[$1] - Double(result[$1]))
            }
            for index in byRemainder where remaining > 0 {
                result[index] += 1
                remaining -= 1
            }
            // Only reachable if the caller passed a `total` the values cannot reach.
            if remaining > 0, let largest = values.indices.max(by: { values[$0] < values[$1] }) {
                result[largest] += remaining
            }
        } else if remaining < 0 {
            var deficit = -remaining
            let byMagnitude = values.indices.sorted { values[$0] > values[$1] }
            for index in byMagnitude where deficit > 0 {
                let take = min(deficit, max(0, result[index]))
                result[index] -= take
                deficit -= take
            }
        }

        return result
    }
}

// MARK: - Validation

/// Why a decoded dataset cannot be trusted.
///
/// Every case names the field and the index so a rejected remote update can be
/// diagnosed from a log line alone.
public enum PaceDatasetValidationError: Error, Hashable, Sendable {
    case unsupportedSchemaVersion(found: Int, supported: ClosedRange<Int>)
    case unknownDivision(String)
    case divisionMismatch(expected: String, found: String)
    case datasetVersionMismatch(expected: String, found: String)
    case emptyGrid(field: String)
    case lengthMismatch(field: String, expected: Int, found: Int)
    case notStrictlyIncreasing(field: String, index: Int)
    case percentileOutOfRange(field: String, index: Int, value: Double)
    case missingStation(String)
    case unexpectedStation(String)
    case nonPositiveValue(field: String, index: Int, value: Int)
    case negativeValue(field: String, index: Int, value: Int)
    case componentSumMismatch(index: Int, expected: Int, found: Int)
}

extension PaceDatasetValidationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let found, let supported):
            return "schema_version \(found) is outside the supported range \(supported.lowerBound)-\(supported.upperBound)"
        case .unknownDivision(let key):
            return "division '\(key)' is not a division this build knows"
        case .divisionMismatch(let expected, let found):
            return "expected division '\(expected)' but the file says '\(found)'"
        case .datasetVersionMismatch(let expected, let found):
            return "expected dataset_version '\(expected)' but the file says '\(found)'"
        case .emptyGrid(let field):
            return "\(field) is empty"
        case .lengthMismatch(let field, let expected, let found):
            return "\(field) has \(found) values, expected \(expected)"
        case .notStrictlyIncreasing(let field, let index):
            return "\(field) is not strictly increasing at index \(index)"
        case .percentileOutOfRange(let field, let index, let value):
            return "\(field)[\(index)] is \(value), outside 0 < p <= 100"
        case .missingStation(let key):
            return "components.stations_s is missing station '\(key)'"
        case .unexpectedStation(let key):
            return "components.stations_s holds unknown station '\(key)'"
        case .nonPositiveValue(let field, let index, let value):
            return "\(field)[\(index)] is \(value), expected a positive number of seconds"
        case .negativeValue(let field, let index, let value):
            return "\(field)[\(index)] is \(value), expected a non-negative number of seconds"
        case .componentSumMismatch(let index, let expected, let found):
            return "components at index \(index) sum to \(found) but overall_s says \(expected)"
        }
    }
}

extension PaceDatasetValidationError: LocalizedError {
    public var errorDescription: String? { description }
}

/// Checks the invariants every lookup in ``PaceDataset`` assumes.
///
/// A dataset arriving over the network is attacker-reachable input in the worst case
/// and simply a bad build in the ordinary case; either way nothing may reach a lookup
/// until it has passed through here. The checks are ordered cheapest first so a badly
/// wrong file is rejected before the per-index loops run.
public enum PaceDatasetValidator {

    /// Schema versions this build understands. Bump the upper bound together with the
    /// model, never on its own — a file from the future would decode into missing fields.
    public static let supportedSchemaVersions: ClosedRange<Int> = 4...4

    /// - Parameters:
    ///   - dataset: The decoded file.
    ///   - division: The division the caller asked for, when it already knows — for a
    ///     download this is the division the manifest file name promised, so a shuffled
    ///     or swapped payload is caught.
    ///   - expectedVersion: `dataset_version` the manifest promised, when known.
    public static func validate(
        _ dataset: PaceDataset,
        expecting division: HyroxDivision? = nil,
        datasetVersion expectedVersion: String? = nil
    ) throws {
        guard supportedSchemaVersions.contains(dataset.schemaVersion) else {
            throw PaceDatasetValidationError.unsupportedSchemaVersion(
                found: dataset.schemaVersion,
                supported: supportedSchemaVersions
            )
        }

        guard let decodedDivision = dataset.division else {
            throw PaceDatasetValidationError.unknownDivision(dataset.divisionKey)
        }

        if let division, division != decodedDivision {
            throw PaceDatasetValidationError.divisionMismatch(
                expected: division.rawValue,
                found: dataset.divisionKey
            )
        }

        if let expectedVersion, expectedVersion != dataset.datasetVersion {
            throw PaceDatasetValidationError.datasetVersionMismatch(
                expected: expectedVersion,
                found: dataset.datasetVersion
            )
        }

        let count = dataset.gridP.count
        guard count > 0 else { throw PaceDatasetValidationError.emptyGrid(field: "grid_p") }

        try validatePercentiles(dataset.gridP, field: "grid_p")
        try validateStrictlyIncreasingSeconds(dataset.overallS, field: "overall_s", expectedCount: count)

        try validateStations(dataset.components.stationsS, expectedCount: count)

        guard dataset.components.runRoxS.count == count else {
            throw PaceDatasetValidationError.lengthMismatch(
                field: "components.run_rox_s",
                expected: count,
                found: dataset.components.runRoxS.count
            )
        }
        for (index, value) in dataset.components.runRoxS.enumerated() where value < 0 {
            throw PaceDatasetValidationError.negativeValue(
                field: "components.run_rox_s",
                index: index,
                value: value
            )
        }

        try validateComponentSums(dataset, count: count)
        try validateAgeGroups(dataset.ageGroups)
    }

    // MARK: - Pieces

    private static func validatePercentiles(_ values: [Double], field: String) throws {
        for (index, value) in values.enumerated() {
            guard value > 0, value <= 100 else {
                throw PaceDatasetValidationError.percentileOutOfRange(
                    field: field,
                    index: index,
                    value: value
                )
            }
            if index > 0, values[index - 1] >= value {
                throw PaceDatasetValidationError.notStrictlyIncreasing(field: field, index: index)
            }
        }
    }

    private static func validateStrictlyIncreasingSeconds(
        _ values: [Int],
        field: String,
        expectedCount: Int
    ) throws {
        guard values.count == expectedCount else {
            throw PaceDatasetValidationError.lengthMismatch(
                field: field,
                expected: expectedCount,
                found: values.count
            )
        }
        for (index, value) in values.enumerated() {
            guard value > 0 else {
                throw PaceDatasetValidationError.nonPositiveValue(field: field, index: index, value: value)
            }
            if index > 0, values[index - 1] >= value {
                throw PaceDatasetValidationError.notStrictlyIncreasing(field: field, index: index)
            }
        }
    }

    private static func validateStations(_ stations: [String: [Int]], expectedCount: Int) throws {
        let standard = Set(StationKind.standardDataKeys)

        for key in stations.keys.sorted() where !standard.contains(key) {
            throw PaceDatasetValidationError.unexpectedStation(key)
        }

        for key in StationKind.standardDataKeys {
            guard let curve = stations[key] else {
                throw PaceDatasetValidationError.missingStation(key)
            }
            guard curve.count == expectedCount else {
                throw PaceDatasetValidationError.lengthMismatch(
                    field: "components.stations_s.\(key)",
                    expected: expectedCount,
                    found: curve.count
                )
            }
            for (index, value) in curve.enumerated() where value < 0 {
                throw PaceDatasetValidationError.negativeValue(
                    field: "components.stations_s.\(key)",
                    index: index,
                    value: value
                )
            }
        }
    }

    private static func validateComponentSums(_ dataset: PaceDataset, count: Int) throws {
        for index in 0..<count {
            var sum = dataset.components.runRoxS[index]
            for key in StationKind.standardDataKeys {
                sum += dataset.components.stationsS[key]?[index] ?? 0
            }
            guard sum == dataset.overallS[index] else {
                throw PaceDatasetValidationError.componentSumMismatch(
                    index: index,
                    expected: dataset.overallS[index],
                    found: sum
                )
            }
        }
    }

    private static func validateAgeGroups(_ groups: [PaceDatasetAgeGroup]) throws {
        for group in groups {
            let field = "age_groups[\(group.ageGroup)]"
            guard !group.gridP.isEmpty else {
                throw PaceDatasetValidationError.emptyGrid(field: "\(field).grid_p")
            }
            try validatePercentiles(group.gridP, field: "\(field).grid_p")
            try validateStrictlyIncreasingSeconds(
                group.overallS,
                field: "\(field).overall_s",
                expectedCount: group.gridP.count
            )
        }
    }
}
