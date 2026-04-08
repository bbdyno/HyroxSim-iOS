//
//  HyroxPresetsTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

final class HyroxPresetsTests: XCTestCase {

    func testAllPresetsCount() {
        XCTAssertEqual(HyroxPresets.all.count, 9)
    }

    func testEachPresetHas31Segments() {
        for preset in HyroxPresets.all {
            XCTAssertEqual(preset.segments.count, 31, "\(preset.name) should have 31 segments")
        }
    }

    func testLastSegmentIsWallBallsStation() {
        for preset in HyroxPresets.all {
            let last = preset.segments.last
            XCTAssertEqual(last?.type, .station, "\(preset.name) last segment should be station")
            XCTAssertEqual(last?.stationKind, .wallBalls, "\(preset.name) last station should be Wall Balls")
        }
    }

    func testMenProSingleWallBallsWeight() {
        let template = HyroxPresets.template(for: .menProSingle)
        let wallBalls = template.segments.last
        XCTAssertEqual(wallBalls?.weightKg, 9)
    }

    func testWomenOpenSingleWallBallsReps() {
        let template = HyroxPresets.template(for: .womenOpenSingle)
        let wallBalls = template.segments.last
        XCTAssertEqual(wallBalls?.stationTarget, .reps(count: 75))
    }

    func testAllPresetsAreBuiltIn() {
        for preset in HyroxPresets.all {
            XCTAssertTrue(preset.isBuiltIn, "\(preset.name) should be built-in")
        }
    }

    func testAllPresetsHaveDivision() {
        for preset in HyroxPresets.all {
            XCTAssertNotNil(preset.division, "\(preset.name) should have a division")
        }
    }

    func testTemplateForDivisionReturnsCorrectDivision() {
        for division in HyroxDivision.allCases {
            let template = HyroxPresets.template(for: division)
            XCTAssertEqual(template.division, division)
        }
    }

    func testAllPresetsValidate() {
        for preset in HyroxPresets.all {
            XCTAssertNoThrow(try preset.validate(), "\(preset.name) should pass validation")
        }
    }
}
