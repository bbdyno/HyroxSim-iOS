//
//  HyroxDivision.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// HYROX competition divisions
public enum HyroxDivision: String, Codable, Hashable, CaseIterable, Sendable {
    case menOpenSingle
    case menOpenDouble
    case menProSingle
    case menProDouble
    case womenOpenSingle
    case womenOpenDouble
    case womenProSingle
    case womenProDouble
    case mixedDouble

    /// Full display name (e.g., "Men's Open — Singles")
    public var displayName: String {
        switch self {
        case .menOpenSingle: return "Men's Open — Singles"
        case .menOpenDouble: return "Men's Open — Doubles"
        case .menProSingle: return "Men's Pro — Singles"
        case .menProDouble: return "Men's Pro — Doubles"
        case .womenOpenSingle: return "Women's Open — Singles"
        case .womenOpenDouble: return "Women's Open — Doubles"
        case .womenProSingle: return "Women's Pro — Singles"
        case .womenProDouble: return "Women's Pro — Doubles"
        case .mixedDouble: return "Mixed — Doubles"
        }
    }

    /// Short display name (e.g., "M Open", "Mixed 2x")
    public var shortName: String {
        switch self {
        case .menOpenSingle: return "M Open"
        case .menOpenDouble: return "M Open 2x"
        case .menProSingle: return "M Pro"
        case .menProDouble: return "M Pro 2x"
        case .womenOpenSingle: return "W Open"
        case .womenOpenDouble: return "W Open 2x"
        case .womenProSingle: return "W Pro"
        case .womenProDouble: return "W Pro 2x"
        case .mixedDouble: return "Mixed 2x"
        }
    }
}
