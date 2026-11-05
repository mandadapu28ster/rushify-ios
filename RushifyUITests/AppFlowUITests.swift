import XCTest

final class AppFlowUITests: RushifyUITestCase {
    func testFreshInstallConnectsSignsInAndLandsOnHome() {
        launch("signedout")
        let server = waitFor(el("server_url")); server.tap(); server.typeText("http://uitest.local:8040")
        waitFor(el("test_connection")).tap()
        waitFor(app.alerts["Traffic is not encrypted"]).buttons["Connect anyway"].tap()
        waitFor(el("username")).tap(); app.typeText("TestUser")
        el("password").tap(); app.typeText("secret")
        waitFor(el("sign_in")).tap()
        waitFor(el("net_worth"))
        assertText("Home")
    }

    func testWrongPasswordShowsTheServerMessage() {
        launch("signedout")
        let server = waitFor(el("server_url")); server.tap(); server.typeText("http://uitest.local:8040")
        el("test_connection").tap(); waitFor(app.alerts["Traffic is not encrypted"]).buttons["Connect anyway"].tap()
        waitFor(el("username")).tap(); app.typeText("TestUser")
        el("password").tap(); app.typeText("wrong")
        el("sign_in").tap()
        assertText("Login failure try again.")
        XCTAssertFalse(el("net_worth").exists)
    }

    func testBadServerAddressIsExplained() {
        launch("signedout")
        let server = waitFor(el("server_url")); server.tap(); server.typeText("90.255.245.88:8040")
        el("test_connection").tap()
        assertText("Start with http:// or https://")
    }

    func testAnExpiredSessionReturnsToSignInWithANotice() {
        launch("expired")
        waitFor(el("username"))
        assertText("Your session expired. Please sign in again.")
    }

    func testBottomBarHasThreeTabs() {
        launch()
        waitFor(el("net_worth"))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        for t in ["Home", "Pulse", "More"] { XCTAssertTrue(app.tabBars.buttons[t].exists, t) }
    }

    func testSignOutReturnsToSignIn() {
        launch()
        tapTab("More")
        scrollTo(el("sign_out")); waitFor(el("sign_out")).tap()
        waitFor(el("username"))
    }
}
