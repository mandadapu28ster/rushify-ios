import XCTest

/// Every screen reached the way a user reaches it, against the canned responses in Rushify/UITestFixtures.
final class HomeUITests: RushifyUITestCase {
    func testHomeShowsTheHeadlineNumbersAndInvestments() {
        launch()
        assertText("£337,002.06")
        assertText("8 listed positions", contains: true)
        assertText("£122,995.09"); assertText("+£19,917.96", contains: true); assertText("-£1,608.62")
        assertText("+9.53%")
    }

    func testOnlyOneSecondarySectionIsOpenAtATime() {
        launch()
        waitFor(el("net_worth"))
        scrollTo(el("section_toggle_alerts"))
        el("section_toggle_alerts").tap()
        waitFor(el("section_body_alerts"))
        scrollTo(el("section_toggle_freshness"))
        el("section_toggle_freshness").tap()
        waitFor(el("section_body_freshness"))
        assertGone(el("section_body_alerts"))
    }

    func testInvestmentsOpensAndClosesOnItsOwn() {
        launch()
        waitFor(el("section_body_investments"))
        el("section_toggle_investments").tap()
        assertGone(el("section_body_investments"))
        waitFor(el("section_summary_investments"))
    }

    func testAlertsListTheCountsAndReviewSymbolsOpensCorporateActions() {
        launch()
        waitFor(el("net_worth"))
        scrollTo(el("section_toggle_alerts"))
        XCTAssertTrue(el("section_summary_alerts").exists)
        el("section_toggle_alerts").tap()
        assertText("3 manual listed lots are missing", contains: true)
        scrollTo(el("review_symbols")); el("review_symbols").tap()
        waitFor(el("confirm_3"))
    }

    func testHideBalancesMasksTheAmounts() {
        launch()
        assertText("£337,002.06")
        tapTab("More"); waitFor(el("toggle_hide")).tap()
        tapTab("Home")
        assertText("••••")
        XCTAssertFalse(text("£337,002.06").exists)
    }

    func testPerformanceLinkOpensTheCharts() {
        launch()
        waitFor(el("net_worth")); scrollTo(el("open_performance")); el("open_performance").tap()
        waitFor(el("performance_tab_growth"))
    }
}

final class PulseUITests: RushifyUITestCase {
    func testRadarShowsHealthScopesAndDisclaimer() {
        launch()
        tapTab("Pulse")
        waitFor(el("pulse_title"))
        assertText("Test headline", contains: true)
        waitFor(el("scope_overall"))
        scrollTo(el("radar_disclaimer")); waitFor(el("radar_disclaimer"))
    }

    func testNewsGroupsByCompanyAndShowsHeadlines() {
        launch()
        tapTab("Pulse"); waitFor(el("pulse_tab_news")).tap()
        assertText("Markets rally on rate hopes")
        assertText("Alpha beats estimates", contains: true)
    }

    func testWatchlistsShowTheLists() {
        launch()
        tapTab("Pulse"); waitFor(el("pulse_tab_watchlists")).tap()
        assertText("India"); assertText("List-1")
        waitFor(el("watch_new_name"))
    }
}

final class MoreScreensUITests: RushifyUITestCase {
    func testPerformanceTabsSwitch() {
        launch(); openFromMore("Performance & income")
        waitFor(el("performance_tab_growth"))
        el("performance_tab_benchmarks").tap(); waitFor(el("benchmark_chart"))
        el("performance_tab_dividends").tap(); waitFor(el("dividend_chart"))
        el("performance_tab_growth").tap(); waitFor(el("growth_chart"))
    }

    func testCorporateActionsConfirmAsksFirstAndShowsTheResult() {
        launch(); openFromMore("Corporate actions")
        waitFor(el("confirm_3")).tap()
        waitFor(app.alerts.firstMatch).buttons["Cancel"].tap()
        assertGone(app.alerts.firstMatch)
        el("confirm_3").tap(); waitFor(app.alerts.firstMatch).buttons.matching(identifier: "confirm_dialog_ok").firstMatch.tap()
        waitFor(el("resolve_message"))
    }

    func testCorporateSymbolsToConfirmListsTheTickers() {
        launch(); openFromMore("Corporate actions")
        scrollTo(el("map_input_ZZZ")); waitFor(el("map_input_ZZZ"))
        XCTAssertTrue(el("map_save_ZZZ").exists)
    }

    func testConnectionsShowStatusWithoutSecrets() {
        launch(); openFromMore("Connections & keys")
        waitFor(el("conn_t212")); XCTAssertTrue(el("conn_snaptrade").exists); XCTAssertTrue(el("conn_monzo").exists); XCTAssertTrue(el("conn_ai").exists)
        XCTAssertFalse(text("AIza****XYZ", contains: true).exists, "keys are never shown")
        XCTAssertFalse(text("****abcd", contains: true).exists)
    }

    func testAiAssistantAnswersAndClears() {
        launch(); openFromMore("AI assistant")
        waitFor(el("ai_disclaimer"))
        let input = waitFor(el("ai_input")); input.tap(); input.typeText("How diversified am I?")
        el("ai_send").tap()
        assertText("Diversify.", contains: true)
        el("ai_clear").tap()
    }

    func testChangePasswordChecksTheNewPasswordBeforeSending() {
        launch(); openFromMore("Change password")
        let cur = waitFor(el("pw_current")); cur.tap(); app.typeText("oldpassword1")
        el("pw_new").tap(); app.typeText("short")
        el("pw_confirm").tap(); app.typeText("different")
        el("pw_submit").tap()
        waitFor(el("pw_error"))
        XCTAssertFalse(el("pw_done").exists)
    }

    func testWrongCurrentPasswordIsExplainedAndTheUserStaysSignedIn() {
        launch(); openFromMore("Change password")
        let cur = waitFor(el("pw_current")); cur.tap(); app.typeText("wrong")
        el("pw_new").tap(); app.typeText("Newpassword123!")
        el("pw_confirm").tap(); app.typeText("Newpassword123!")
        el("pw_submit").tap()
        assertText("Current password is incorrect.")
        app.navigationBars.buttons.firstMatch.tap()      // back to the More list (the keyboard may still be up)
        tapTab("Home"); waitFor(el("net_worth"))
    }

    func testAddHoldingKindsAndValidationMessage() {
        launch(); openFromMore("Add holding")
        waitFor(el("add_manual"))
        el("form_save").tap()
        assertText("Fill in ticker, qty, broker, account type, purchase date, and total cost in GBP.")
        el("add_kind_real_estate").tap(); waitFor(el("f_home"))
        el("add_kind_cash").tap(); waitFor(el("f_bank"))
        el("add_kind_other").tap(); waitFor(el("f_other"))
    }

    func testAddHoldingSearchFillsTheSymbol() {
        launch(); openFromMore("Add holding")
        let search = waitFor(el("f_search")); search.tap(); search.typeText("vod")
        waitFor(el("hit_VOD")).tap()
        waitFor(el("quote_info"))
    }
}
