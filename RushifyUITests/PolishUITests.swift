import XCTest

final class SecurityUITests: RushifyUITestCase {
    func testAFailedFaceIDKeepsTheAppLockedUntilTheOwnerTriesAgain() {
        launch("locked")
        waitFor(el("lock_screen"))
        assertText("Couldn't confirm it's you. Try again.")     // the automatic Face ID attempt failed
        XCTAssertFalse(el("net_worth").exists, "nothing behind the lock is reachable")
        waitFor(el("unlock_button")).tap()
        waitFor(el("net_worth")); assertGone(el("lock_screen"))
    }

    func testTheLockIsOffUntilTurnedOnAndThenOffersATimeout() {
        launch(); tapTab("More")
        let toggle = el("toggle_lock"); scrollTo(toggle)
        XCTAssertFalse(el("lock_timeout").exists, "no timeout choice while the lock is off")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        waitFor(el("lock_timeout"))
    }

    func testAppSwitcherCoverIsAnOption() {
        launch(); tapTab("More")
        let toggle = el("toggle_shield"); scrollTo(toggle)
        XCTAssertEqual(toggle.value as? String, "1", "on by default")
    }

    func testHideBalancesButtonOnHomeMasksAndRestoresAmounts() {
        launch(); assertText("£337,002.06")
        waitFor(el("hide_toggle")).tap()
        assertText("••••"); XCTAssertFalse(text("£337,002.06").exists)
        el("hide_toggle").tap(); assertText("£337,002.06")
    }
}

final class LayoutUITests: RushifyUITestCase {
    func testTabRootsUseLargeTitles() {
        launch(); waitFor(app.navigationBars["Home"])
        tapTab("Pulse"); waitFor(app.navigationBars["Pulse"])
        tapTab("More"); waitFor(app.navigationBars["More"])
    }

    func testInsecureConnectionIsAQuietPillNotABanner() {
        launch(); waitFor(el("http_chip"))
        XCTAssertFalse(text("Not encrypted (http) — avoid public Wi-Fi").exists)
    }

    func testPushedScreensGetTheWholeScreenByHidingTheTabBar() {
        launch(); openFromMore("Add holding"); waitFor(el("add_manual"))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "the tab bar is hidden on pushed screens")
        app.navigationBars.buttons.firstMatch.tap(); waitFor(app.tabBars.buttons["More"])
    }

    func testFormFieldsShowAHintNotTheLabelAsPlaceholder() {
        launch(); openFromMore("Add holding")
        let date = waitFor(el("f_date"))
        XCTAssertEqual(date.placeholderValue, "YYYY-MM-DD")
    }
}
