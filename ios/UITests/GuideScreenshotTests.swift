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
        let clearButton = app.buttons["clearTripButton"]
        XCTAssertTrue(clearButton.isEnabled)
        clearButton.tap()
        XCTAssertEqual(fromField.value as? String, "Address or place")
        XCTAssertEqual(findTripsButton.isEnabled, false)

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
        app.buttons["Done"].tap()

        let alerts = app.buttons["alertsButton"]
        XCTAssertTrue(alerts.waitForExistence(timeout: 5))
        alerts.tap()
        if app.navigationBars["MBTA Alerts"].waitForExistence(timeout: 5) {
            attach(app, named: "Tony Phone - Alerts")
        }
    }

    @MainActor
    func testCaptureHowToImages() throws {
        let app = XCUIApplication()
        app.launch()
        if app.navigationBars["How to use"].waitForExistence(timeout: 3) { app.buttons["Done"].tap() }

        let gear = app.buttons["moreButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()
        let edit = app.buttons["editFavoriteLinesLink"]
        for _ in 0..<8 {
            if edit.exists && edit.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.navigationBars["Favorite lines"].waitForExistence(timeout: 5))
        for name in ["Red Line", "Orange Line"] {
            let toggle = app.switches[name]
            for _ in 0..<12 {
                if toggle.exists && toggle.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), name)
            if (toggle.value as? String) == "0" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        }
        attach(app, named: "howto-prefs")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        sleep(8)
        attach(app, named: "howto-map")

        let station = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Station ")).firstMatch
        if station.waitForExistence(timeout: 15) {
            station.tap()
            sleep(4)
            attach(app, named: "howto-station")
            app.buttons["Done"].tap()
        }

        let alerts = app.buttons["alertsButton"]
        if alerts.waitForExistence(timeout: 5) {
            alerts.tap()
            sleep(2)
            attach(app, named: "howto-alerts")
            app.buttons["Done"].tap()
        }

        app.buttons["plannerSummaryButton"].tap()
        XCTAssertTrue(app.navigationBars["Trip planner"].waitForExistence(timeout: 10))
        attach(app, named: "howto-planner")
        app.buttons["Done"].tap()

        gear.tap()
        for _ in 0..<8 {
            if app.switches.firstMatch.exists { break }
            app.swipeUp()
        }
        attach(app, named: "howto-triptracking")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
