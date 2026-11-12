import XCTest

final class GuideScreenshotTests: XCTestCase {
    @MainActor
    func testHowToGuideDisplaysBulletedInstructions() {
        let app = XCUIApplication()
        app.launch()
        if app.navigationBars["How to use"].waitForExistence(timeout: 3) {
            app.navigationBars["How to use"].buttons["Done"].tap()
        }
        XCTAssertTrue(app.buttons["moreButton"].waitForExistence(timeout: 10))
        app.buttons["moreButton"].tap()
        let guide = app.buttons["openGuideLink"]
        for _ in 0..<8 where !guide.isHittable { app.swipeUp() }
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        guide.tap()
        XCTAssertTrue(app.navigationBars["How to use"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1. Choose your favorite lines"].exists)
        XCTAssertTrue(app.staticTexts["Tap a route on the map to see its name, directions and endpoints, or use the star to favorite it."].exists)
        for _ in 0..<12 {
            if app.staticTexts["5. Plan a trip"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["5. Plan a trip"].exists)
        XCTAssertTrue(app.staticTexts["Expand Saved trips to see saved journeys and reminders."].exists)
    }

    @MainActor
    func testPlannerModeControlsAndLocationBlur() throws {
        let app = XCUIApplication()
        app.launch()
        if app.navigationBars["How to use"].waitForExistence(timeout: 3) {
            app.navigationBars["How to use"].buttons["Done"].tap()
        }
        XCTAssertTrue(app.buttons["plannerSummaryButton"].waitForExistence(timeout: 10))
        app.buttons["plannerSummaryButton"].tap()
        XCTAssertTrue(app.navigationBars["Trip planner"].waitForExistence(timeout: 10))
        let go = app.buttons["findTripsButton"]
        XCTAssertEqual(go.label, "GO")
        XCTAssertLessThan(go.frame.width, app.windows.firstMatch.frame.width / 2)
        let savedTrips = app.buttons["savedTripsDisclosure"]
        XCTAssertTrue(savedTrips.waitForExistence(timeout: 5))
        XCTAssertTrue(savedTrips.label.contains("Saved trips ("))
        if savedTrips.label.contains("(0)") {
            XCTAssertFalse(app.staticTexts["No saved trips yet"].exists)
            savedTrips.tap()
            XCTAssertTrue(app.staticTexts["No saved trips yet"].waitForExistence(timeout: 5))
            savedTrips.tap()
        }
        for mode in ["walk", "car", "scooter", "bike"] {
            XCTAssertTrue(app.buttons["stationMode-\(mode)"].exists)
        }
        XCTAssertLessThan(savedTrips.frame.minY, app.buttons["stationMode-walk"].frame.minY)
        app.buttons["stationMode-bike"].tap()
        let fromMode = app.buttons["fromModeMenu"]
        let toMode = app.buttons["toModeMenu"]
        XCTAssertTrue(fromMode.waitForExistence(timeout: 5))
        XCTAssertTrue(toMode.exists)
        XCTAssertEqual(fromMode.value as? String, "Bike")
        XCTAssertEqual(toMode.value as? String, "Bike")
        fromMode.tap()
        app.buttons["Drive"].tap()
        XCTAssertEqual(fromMode.value as? String, "Drive")
        XCTAssertEqual(toMode.value as? String, "Bike")
        let fromLocation = app.buttons["fromCurrentLocationButton"]
        let fromPin = app.buttons["fromPinButton"]
        let toLocation = app.buttons["toCurrentLocationButton"]
        let toPin = app.buttons["toPinButton"]
        let from = app.textFields["fromAddressField"]
        let to = app.textFields["toAddressField"]
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        XCTAssertTrue(to.exists)
        XCTAssertLessThan(from.frame.maxX, fromLocation.frame.minX)
        XCTAssertLessThan(fromLocation.frame.maxX, fromPin.frame.minX)
        XCTAssertLessThan(fromPin.frame.maxX, fromMode.frame.minX)
        XCTAssertLessThan(to.frame.maxX, toLocation.frame.minX)
        XCTAssertLessThan(toLocation.frame.maxX, toPin.frame.minX)
        XCTAssertLessThan(toPin.frame.maxX, toMode.frame.minX)
        XCTAssertLessThan(to.frame.midY - from.frame.midY, 70)
        attach(app, named: "Trip planner layout")
        from.tap()
        from.typeText("South Station Boston")
        to.tap()
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (from.value as? String) != "South Station Boston" ||
            app.staticTexts["Search failed. Check your connection."].exists ||
            app.staticTexts["No match for South Station Boston."].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 20), .completed)
        toPin.tap()
        XCTAssertTrue(app.staticTexts["Tap the map to set destination"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Trip planner"].waitForExistence(timeout: 5))
    }

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
        XCTAssertEqual(findTripsButton.label, "GO")
        XCTAssertTrue(findTripsButton.isHittable)
        for mode in ["walk", "car", "scooter", "bike"] {
            XCTAssertTrue(app.buttons["stationMode-\(mode)"].exists)
        }
        let fromField = app.textFields["fromAddressField"]
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
        XCTAssertEqual(fromField.value as? String, "")
        XCTAssertEqual(findTripsButton.isEnabled, false)

        let done = app.navigationBars["Trip planner"].buttons["Done"]
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
        app.navigationBars["Terms & Policy"].buttons["Done"].tap()
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
        if app.navigationBars["How to use"].waitForExistence(timeout: 3) { app.navigationBars["How to use"].buttons["Done"].tap() }

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
        XCTAssertTrue(station.waitForExistence(timeout: 30))
        station.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        sleep(4)
        attach(app, named: "howto-station")
        app.buttons["Done"].tap()

        let alerts = app.buttons["alertsButton"]
        XCTAssertTrue(alerts.waitForExistence(timeout: 5))
        alerts.tap()
        XCTAssertTrue(app.navigationBars["MBTA Alerts"].waitForExistence(timeout: 5))
        sleep(2)
        attach(app, named: "howto-alerts")
        app.navigationBars["MBTA Alerts"].buttons["Done"].tap()

        app.buttons["plannerSummaryButton"].tap()
        XCTAssertTrue(app.navigationBars["Trip planner"].waitForExistence(timeout: 10))
        attach(app, named: "howto-planner")
        app.buttons["Done"].tap()

        gear.tap()
        let tracking = app.switches["Allow background trip updates"]
        for _ in 0..<8 {
            if tracking.exists && tracking.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(tracking.exists && tracking.isHittable)
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
