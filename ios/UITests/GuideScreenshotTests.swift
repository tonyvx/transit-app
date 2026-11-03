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
        let findTripsButton = app.buttons["findTripsButton"]
        XCTAssertTrue(findTripsButton.waitForExistence(timeout: 5))
        XCTAssertTrue(findTripsButton.isHittable)
        let fromField = app.textFields["Address or place"].firstMatch
        XCTAssertTrue(fromField.waitForExistence(timeout: 5))
        fromField.tap()
        fromField.typeText("South Station")
        let searchLocationButton = app.buttons["searchFromLocationButton"]
        XCTAssertTrue(searchLocationButton.waitForExistence(timeout: 5))
        XCTAssertTrue(searchLocationButton.isHittable)
        XCTAssertTrue(findTripsButton.isHittable)
        attach(app, named: "Tony Phone - Trip planner")

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        let preferences = app.buttons["moreButton"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 5))
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Boston Transit"].waitForExistence(timeout: 5))
        attach(app, named: "Tony Phone - Settings")
        for _ in 0..<8 {
            if app.links["reportBugLink"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.links["reportBugLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["requestFeatureLink"].exists)
        let termsButton = app.buttons["termsPrivacyButton"]
        XCTAssertTrue(termsButton.exists)
        termsButton.tap()
        XCTAssertTrue(app.navigationBars["Terms & Policy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "independent app")
        ).firstMatch.exists)
        app.buttons["Done"].tap()
        for _ in 0..<8 {
            if app.links["MBTA website"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.links["MBTA website"].waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if app.buttons["editFavoriteLinesLink"].exists { break }
            app.swipeDown()
        }
        XCTAssertTrue(app.buttons["editFavoriteLinesLink"].waitForExistence(timeout: 5))
        attach(app, named: "Tony Phone - Favorite lines settings")
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
