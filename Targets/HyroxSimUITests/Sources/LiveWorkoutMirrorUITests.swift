//
//  LiveWorkoutMirrorUITests.swift
//  HyroxSimUITests
//
//  Created by bbdyno on 4/8/26.
//

import XCTest

final class LiveWorkoutMirrorUITests: XCTestCase {
    private static let realWatchE2EFlagPath = "/tmp/hyrox-real-watch-e2e.flag"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWatchMirrorScreenRendersLiveState() {
        let app = XCUIApplication()
        app.launchArguments += ["UITestWatchMirror"]
        app.launch()

        let header = app.staticTexts["liveMirror.headerLabel"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.label, "RUN 1 / 1")

        let badge = app.staticTexts["liveMirror.watchBadge"]
        XCTAssertEqual(badge.label, "⌚ LIVE FROM APPLE WATCH")
        XCTAssertTrue(app.buttons["liveMirror.nextButton"].isEnabled)
        XCTAssertTrue(app.buttons["liveMirror.pauseButton"].isEnabled)
        XCTAssertTrue(app.buttons["liveMirror.endButton"].isEnabled)
    }

    func testDisconnectedMirrorDisablesRemoteControls() {
        let app = XCUIApplication()
        app.launchArguments += ["UITestWatchMirror", "UITestWatchMirrorDisconnected"]
        app.launch()

        let badge = app.staticTexts["liveMirror.watchBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(badge.label, "⌚ WATCH DISCONNECTED")
        XCTAssertFalse(app.buttons["liveMirror.nextButton"].isEnabled)
        XCTAssertFalse(app.buttons["liveMirror.pauseButton"].isEnabled)
        XCTAssertFalse(app.buttons["liveMirror.endButton"].isEnabled)
    }

    func testRealWatchWorkoutMirrorsToPhoneAndDismisses() throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: Self.realWatchE2EFlagPath)
        )

        let app = XCUIApplication()
        app.launch()

        let header = app.staticTexts["liveMirror.headerLabel"]
        XCTAssertTrue(header.waitForExistence(timeout: 20))

        let endButton = app.buttons["liveMirror.endButton"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        endButton.tap()

        let confirmButton = app.buttons["종료"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        let disappears = NSPredicate(format: "exists == false")
        expectation(for: disappears, evaluatedWith: header)
        waitForExpectations(timeout: 20)
    }
}
