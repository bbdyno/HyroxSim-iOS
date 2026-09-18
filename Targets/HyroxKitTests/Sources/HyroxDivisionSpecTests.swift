//
//  HyroxDivisionSpecTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

final class HyroxDivisionSpecTests: XCTestCase {

    private let expectedOrder: [StationKind] = [
        .skiErg, .sledPush, .sledPull, .burpeeBroadJumps,
        .rowing, .farmersCarry, .sandbagLunges, .wallBalls
    ]

    func testAllDivisionsReturn8Stations() {
        for division in HyroxDivision.allCases {
            let specs = HyroxDivisionSpec.stations(for: division)
            XCTAssertEqual(specs.count, 8, "\(division) should have 8 stations")
        }
    }

    func testStationOrderIsCorrect() {
        for division in HyroxDivision.allCases {
            let specs = HyroxDivisionSpec.stations(for: division)
            let kinds = specs.map(\.kind)
            XCTAssertEqual(kinds, expectedOrder, "\(division) station order mismatch")
        }
    }

    func testMenOpenSledPushWeight() {
        let specs = HyroxDivisionSpec.stations(for: .menOpenSingle)
        let sledPush = specs.first { $0.kind == .sledPush }
        XCTAssertEqual(sledPush?.weightKg, 152)
    }

    /// 24/25 · 25/26 · 26/27 rulebooks all list Women Open wall balls as 4kg · 100 reps.
    func testWomenOpenWallBallsRepsAndWeight() {
        for division in [HyroxDivision.womenOpenSingle, .womenOpenDouble] {
            let specs = HyroxDivisionSpec.stations(for: division)
            let wallBalls = specs.first { $0.kind == .wallBalls }
            XCTAssertEqual(wallBalls?.target, .reps(count: 100), "\(division) wall balls reps")
            XCTAssertEqual(wallBalls?.weightKg, 4, "\(division) wall balls weight")
        }
    }

    func testEveryDivisionHas100WallBalls() {
        for division in HyroxDivision.allCases {
            let wallBalls = HyroxDivisionSpec.stations(for: division).first { $0.kind == .wallBalls }
            XCTAssertEqual(wallBalls?.target, .reps(count: 100), "\(division) wall balls reps")
        }
    }

    func testMenProSandbagLungesWeight() {
        let specs = HyroxDivisionSpec.stations(for: .menProSingle)
        let lunges = specs.first { $0.kind == .sandbagLunges }
        XCTAssertEqual(lunges?.weightKg, 30)
    }

    func testMixedDoubleUsesMenuOpenSpec() {
        let mixed = HyroxDivisionSpec.stations(for: .mixedDouble)
        let menOpen = HyroxDivisionSpec.stations(for: .menOpenSingle)
        XCTAssertEqual(mixed, menOpen)
    }
}
