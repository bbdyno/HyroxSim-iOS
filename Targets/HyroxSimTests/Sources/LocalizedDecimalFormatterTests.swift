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
}
