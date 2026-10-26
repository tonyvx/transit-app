import XCTest

final class GuideScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureCurrentGuideScreens() throws {
        let app = XCUIApplication()
        app.launch()

        attach(app, named: "Tony Phone - Live map")

        let stationButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Station ")
        ).firstMatch
        if stationButton.waitForExistence(timeout: 10) {
            stationButton.tap()
            if app.buttons["Done"].waitForExistence(timeout: 5) {
                attach(app, named: "Tony Phone - Station sheet")
                app.buttons["Done"].tap()
            }
        }

        let plannerButton = app.buttons["plannerSummaryButton"]
        XCTAssertTrue(plannerButton.waitForExistence(timeout: 10))
        plannerButton.tap()
        XCTAssertTrue(app.navigationBars["Trip planner"].waitForExistence(timeout: 10))
        attach(app, named: "Tony Phone - Trip planner")

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        let preferences = app.buttons["preferencesButton"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 5))
        preferences.tap()
        XCTAssertTrue(app.navigationBars["My Preferences"].waitForExistence(timeout: 5))
        attach(app, named: "Tony Phone - Preferences")
        for _ in 0..<5 {
            if app.staticTexts["Trip tracking"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Trip tracking"].waitForExistence(timeout: 5))
        attach(app, named: "Tony Phone - Trip tracking preferences")
        app.buttons["Save"].tap()

        let alerts = app.buttons["alertsButton"]
        XCTAssertTrue(alerts.waitForExistence(timeout: 5))
        alerts.tap()
        if app.navigationBars["MBTA Alerts"].waitForExistence(timeout: 5) {
            attach(app, named: "Tony Phone - Alerts")
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
