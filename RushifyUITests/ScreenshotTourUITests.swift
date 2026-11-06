import XCTest

/// Not part of the normal run: walks through every screen and saves a PNG of each, for design review.
/// Run with TEST_RUNNER_RUSHIFY_TOUR=1 (optionally TEST_RUNNER_RUSHIFY_TOUR_DIR=/some/dir).
final class ScreenshotTourUITests: RushifyUITestCase {
    private var dir: String { ProcessInfo.processInfo.environment["RUSHIFY_TOUR_DIR"] ?? "/tmp/rushify-shots" }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUSHIFY_TOUR"] == "1", "design-review tour only")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    private func shot(_ name: String) {
        sleep(1)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
    private func more(_ title: String, _ name: String, settle: UInt32 = 2, extra: (() -> Void)? = nil) {
        launch(); openFromMore(title); sleep(settle); extra?(); shot(name)
    }
    private func openSection(_ id: String) { scrollTo(el("section_toggle_\(id)")); el("section_toggle_\(id)").tap() }

    func testTour() {
        // Connect + login
        launch("signedout"); waitFor(el("server_url")); shot("00_connect")
        el("server_url").tap(); el("server_url").typeText("http://uitest.local:8040"); el("test_connection").tap()
        waitFor(app.alerts.firstMatch); shot("01_http_warning"); app.alerts.firstMatch.buttons["Connect anyway"].tap()
        waitFor(el("username")); shot("02_login")

        launch("locked"); waitFor(el("lock_screen")); shot("03_lock_screen")

        // Home
        launch(); waitFor(el("net_worth")); shot("10_home_top")
        app.swipeUp(); shot("11_home_scrolled")
        el("section_toggle_investments").exists ? () : ()
        launch(); waitFor(el("net_worth")); openSection("alerts"); shot("12_home_alerts")
        launch(); waitFor(el("net_worth")); openSection("pies"); shot("13_home_pies")
        launch(); waitFor(el("net_worth")); openSection("positions"); shot("14_home_positions")
        launch(); waitFor(el("net_worth")); openSection("custodian"); shot("15_home_custodian")
        launch(); waitFor(el("net_worth")); openSection("wealth"); shot("16_home_wealth")

        // Pulse
        launch(); tapTab("Pulse"); waitFor(app.navigationBars["Pulse"]); sleep(2); shot("20_pulse_radar")
        app.swipeUp(); shot("21_pulse_radar_scrolled")
        launch(); tapTab("Pulse"); waitFor(el("pulse_tab_news")).tap(); sleep(2); shot("22_pulse_news")
        launch(); tapTab("Pulse"); waitFor(el("pulse_tab_watchlists")).tap(); sleep(2); shot("23_pulse_watchlists")

        // More + screens
        launch(); tapTab("More"); sleep(1); shot("30_more"); app.swipeUp(); sleep(1); shot("31_more_scrolled")
        launch(); tapTab("More"); let tl = el("toggle_lock"); scrollTo(tl); tl.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap(); sleep(1); shot("32_more_security")
        more("Holdings", "40_holdings") 
        launch(); openFromMore("Holdings"); waitFor(el("holdings_list")); let g = el("group_t212:isa"); scrollTo(g); g.tap(); sleep(1); shot("41_holdings_group_open")
        waitFor(text("Infosys")).tap(); waitFor(el("holding_detail")); sleep(1); shot("42_holding_detail")
        app.swipeUp(); shot("43_holding_detail_bottom")
        launch(); openFromMore("Holdings"); waitFor(el("holdings_list")); let h = el("group_listed__hargreaves"); scrollTo(h); h.tap()
        waitFor(el("multi_MSFT")).tap(); waitFor(text("id 11", contains: true)).tap(); waitFor(el("holding_detail")); scrollTo(el("act_edit")); shot("44_manual_lot_actions")
        el("act_edit").tap(); waitFor(el("manual_form")); sleep(1); shot("45_edit_lot_form")
        more("Sync", "50_sync")
        more("Performance & income", "60_performance_growth")
        launch(); openFromMore("Performance & income"); waitFor(el("performance_tab_benchmarks")).tap(); sleep(2); shot("61_performance_benchmarks")
        el("performance_tab_dividends").tap(); sleep(2); shot("62_performance_dividends")
        more("Corporate actions", "70_corporate")
        more("Connections & keys", "71_connections")
        more("AI assistant", "72_ai")
        more("Change password", "73_password")
        more("Add holding", "74_add_holding")
        launch(); openFromMore("Add holding"); waitFor(el("add_kind_real_estate")).tap(); sleep(1); shot("75_add_property")
    }
}
