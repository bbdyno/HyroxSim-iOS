//
//  LocalizedDecimalFormatterTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 7/20/26.
//

import XCTest
@testable import HyroxSim

final class LocalizedDecimalFormatterTests: XCTestCase {

    func testParsesSwedishDecimalSeparator() {
        let value = LocalizedDecimalFormatter.value(
            from: "12,5",
            locale: Locale(identifier: "sv_SE")
        )

        XCTAssertEqual(value, 12.5)
    }

    func testParsesEnglishDecimalSeparator() {
        let value = LocalizedDecimalFormatter.value(
            from: "12.5",
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(value, 12.5)
    }

    func testAcceptsDotAsFallbackInSwedishLocale() {
        let value = LocalizedDecimalFormatter.value(
            from: "12.5",
            locale: Locale(identifier: "sv_SE")
        )

        XCTAssertEqual(value, 12.5)
    }

    func testRejectsInvalidValue() {
        XCTAssertNil(
            LocalizedDecimalFormatter.value(
                from: "not a number",
                locale: Locale(identifier: "sv_SE")
            )
        )
    }

    func testFormatsUsingLocaleDecimalSeparator() {
        XCTAssertEqual(
            LocalizedDecimalFormatter.string(
                from: 12.5,
                locale: Locale(identifier: "sv_SE")
            ),
            "12,5"
        )
    }

    // MARK: - 극단값 방어 (오버플로 크래시 회귀 방지)

    func testFiniteValueRejectsNonFiniteInput() {
        let locale = Locale(identifier: "en_US")
        XCTAssertNil(LocalizedDecimalFormatter.finiteValue(from: "inf", locale: locale))
        XCTAssertNil(LocalizedDecimalFormatter.finiteValue(from: "infinity", locale: locale))
        XCTAssertNil(LocalizedDecimalFormatter.finiteValue(from: "nan", locale: locale))
        XCTAssertEqual(LocalizedDecimalFormatter.finiteValue(from: "1234", locale: locale), 1234)
    }

    func testHugeInputParsesButFallsOutsideInputLimits() throws {
        let value = try XCTUnwrap(
            LocalizedDecimalFormatter.finiteValue(
                from: "99999999999999999999",
                locale: Locale(identifier: "en_US")
            )
        )

        XCTAssertFalse(NumericInputLimits.distanceMeters.contains(value))
        XCTAssertFalse(NumericInputLimits.reps.contains(value))
        XCTAssertFalse(NumericInputLimits.durationSeconds.contains(value))
    }

    func testClampedKeepsValueInsideRange() {
        XCTAssertEqual(LocalizedDecimalFormatter.clamped(1e19, to: NumericInputLimits.distanceMeters), 100_000)
        XCTAssertEqual(LocalizedDecimalFormatter.clamped(-5, to: NumericInputLimits.distanceMeters), 1)
        XCTAssertEqual(LocalizedDecimalFormatter.clamped(.nan, to: NumericInputLimits.durationSeconds), 0)
        XCTAssertEqual(LocalizedDecimalFormatter.clamped(90_000, to: NumericInputLimits.durationSeconds), 86_400)
        XCTAssertEqual(LocalizedDecimalFormatter.clamped(1_500, to: NumericInputLimits.distanceMeters), 1_500)
    }

    func testSafeIntClampsInsteadOfTrapping() {
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(.nan), 0)
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(.infinity), Int.max)
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(-.infinity), 0)
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(1e19), Int.max)
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(1234.9), 1234)
        XCTAssertEqual(LocalizedDecimalFormatter.safeInt(-5, lowerBound: Int.min), -5)
    }
}
