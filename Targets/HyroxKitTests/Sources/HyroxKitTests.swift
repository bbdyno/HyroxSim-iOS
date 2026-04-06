//
//  HyroxKitTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxKit

final class HyroxKitTests: XCTestCase {
    func testVersion() throws {
        XCTAssertEqual(HyroxKit.version, "0.1.0")
    }
}
