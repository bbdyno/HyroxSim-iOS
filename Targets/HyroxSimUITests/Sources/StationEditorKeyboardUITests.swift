//
//  StationEditorKeyboardUITests.swift
//  HyroxSimUITests
//
//  Created by bbdyno on 7/20/26.
//

import XCTest

final class StationEditorKeyboardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSaveButtonRemainsHittableWhileEditingWeight() {
        let app = XCUIApplication()
        app.launchArguments += ["ScreenshotPhoneBuilder"]
        app.launch()

        let stationCell = app.cells["workoutBuilder.segment.3"]
        XCTAssertTrue(stationCell.waitForExistence(timeout: 5))
        makeHittable(stationCell, in: app)
        stationCell.tap()

        let weightField = app.textFields["stationEditor.weightField"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        makeHittable(weightField, in: app)
        weightField.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let saveButton = app.buttons["stationEditor.saveButton"]
        XCTAssertTrue(saveButton.exists)
        XCTAssertTrue(saveButton.isHittable)
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
