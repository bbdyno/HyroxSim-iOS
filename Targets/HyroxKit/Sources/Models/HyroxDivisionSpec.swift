//
//  HyroxDivisionSpec.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// Specification for a single station in a HYROX division
public struct HyroxStationSpec: Hashable, Sendable {
    public let kind: StationKind
    public let target: StationTarget
    public let weightKg: Double?
    public let weightNote: String?

    public init(
        kind: StationKind,
        target: StationTarget,
        weightKg: Double? = nil,
        weightNote: String? = nil
    ) {
        self.kind = kind
        self.target = target
        self.weightKg = weightKg
        self.weightNote = weightNote
    }
}

// MARK: - HYROX Official Spec (verify against current rulebook)

/// Station specifications per HYROX division.
/// Weights and rep counts are reference values based on commonly known HYROX rules.
/// These may be adjusted between seasons — verify against the official rulebook.
public enum HyroxDivisionSpec {

    /// Returns the 8 station specs for a given division, in official order:
    /// SkiErg → Sled Push → Sled Pull → Burpee Broad Jumps → Rowing → Farmers Carry → Sandbag Lunges → Wall Balls
    public static func stations(for division: HyroxDivision) -> [HyroxStationSpec] {
        switch division {
        case .menOpenSingle, .menOpenDouble:
            return menOpenSpecs
        case .menProSingle, .menProDouble:
            return menProSpecs
        case .womenOpenSingle, .womenOpenDouble:
            return womenOpenSpecs
        case .womenProSingle, .womenProDouble:
            return womenProSpecs
        case .mixedDouble:
            // 혼성 룰 변경 가능성 있음 — 현재 Men's Open 스펙으로 구현
            return menOpenSpecs
        }
    }

    // MARK: - Men's Open (Single & Double identical)

    private static let menOpenSpecs: [HyroxStationSpec] = [
        HyroxStationSpec(kind: .skiErg, target: .distance(meters: 1000)),
        HyroxStationSpec(kind: .sledPush, target: .distance(meters: 50), weightKg: 152, weightNote: "sled total"),
        HyroxStationSpec(kind: .sledPull, target: .distance(meters: 50), weightKg: 103, weightNote: "sled total"),
        HyroxStationSpec(kind: .burpeeBroadJumps, target: .distance(meters: 80)),
        HyroxStationSpec(kind: .rowing, target: .distance(meters: 1000)),
        HyroxStationSpec(kind: .farmersCarry, target: .distance(meters: 200), weightKg: 24, weightNote: "per hand"),
        HyroxStationSpec(kind: .sandbagLunges, target: .distance(meters: 100), weightKg: 20),
        HyroxStationSpec(kind: .wallBalls, target: .reps(count: 100), weightKg: 6),
    ]

    // MARK: - Men's Pro (Single & Double identical)

    private static let menProSpecs: [HyroxStationSpec] = [
        HyroxStationSpec(kind: .skiErg, target: .distance(meters: 1000)),
        HyroxStationSpec(kind: .sledPush, target: .distance(meters: 50), weightKg: 202, weightNote: "sled total"),
        HyroxStationSpec(kind: .sledPull, target: .distance(meters: 50), weightKg: 153, weightNote: "sled total"),
        HyroxStationSpec(kind: .burpeeBroadJumps, target: .distance(meters: 80)),
        HyroxStationSpec(kind: .rowing, target: .distance(meters: 1000)),
        HyroxStationSpec(kind: .farmersCarry, target: .distance(meters: 200), weightKg: 32, weightNote: "per hand"),
        HyroxStationSpec(kind: .sandbagLunges, target: .distance(meters: 100), weightKg: 30),
        HyroxStationSpec(kind: .wallBalls, target: .reps(count: 100), weightKg: 9),
    ]

    // MARK: - Women's Open (Single & Double identical)

    private static let womenOpenSpecs: [HyroxStationSpec] = [
        HyroxStationSpec(kind: .skiErg, target: .distance(meters: 1000)),
        HyroxStationSpec(kind: .sledPush, target: .distance(meters: 50), weightKg: 102, weightNote: "sled total"),
        HyroxStationSpec(kind: .sledPull, target: .distance(meters: 50), weightKg: 78, weightNote: "sled total"),
        HyroxStationSpec(kind: .burpeeBroadJumps, target: .distance(meters: 80)),
        HyroxStationSpec(kind: .rowing, target: .distance(meters: 1000)),
        HyroxStationSpec(kind: .farmersCarry, target: .distance(meters: 200), weightKg: 16, weightNote: "per hand"),
        HyroxStationSpec(kind: .sandbagLunges, target: .distance(meters: 100), weightKg: 10),
        HyroxStationSpec(kind: .wallBalls, target: .reps(count: 75), weightKg: 4),
    ]

    // MARK: - Women's Pro (Single & Double identical)

    private static let womenProSpecs: [HyroxStationSpec] = [
        HyroxStationSpec(kind: .skiErg, target: .distance(meters: 1000)),
        HyroxStationSpec(kind: .sledPush, target: .distance(meters: 50), weightKg: 152, weightNote: "sled total"),
        HyroxStationSpec(kind: .sledPull, target: .distance(meters: 50), weightKg: 103, weightNote: "sled total"),
        HyroxStationSpec(kind: .burpeeBroadJumps, target: .distance(meters: 80)),
        HyroxStationSpec(kind: .rowing, target: .distance(meters: 1000)),
        HyroxStationSpec(kind: .farmersCarry, target: .distance(meters: 200), weightKg: 24, weightNote: "per hand"),
        HyroxStationSpec(kind: .sandbagLunges, target: .distance(meters: 100), weightKg: 20),
        HyroxStationSpec(kind: .wallBalls, target: .reps(count: 100), weightKg: 6),
    ]
}
