import XCTest

final class HoldingsUITests: RushifyUITestCase {
    private func openHoldings() { launch(); openFromMore("Holdings"); waitFor(el("holdings_list")) }
    private func open(_ group: String) { let g = el("group_\(group)"); scrollTo(g); waitFor(g).tap() }

    func testAccountGroupsShowRealisedPayoutsAndXirr() {
        openHoldings()
        assertText("Trading 212 · ISA")
        XCTAssertEqual(waitFor(el("xirr_t212:isa")).label, "XIRR: 16.28%")
        XCTAssertEqual(el("xirr_t212:invest").label, "XIRR: -13.89%")
    }

    func testAccountsSummaryExpandsToPerAccountFiguresAndATotal() {
        openHoldings()
        waitFor(el("accounts_summary")).tap()
        assertText("Total (all accounts)"); assertText("Total deposits (principal)")
    }

    func testMissingPurchaseDatesAreFlagged() {
        openHoldings()
        assertText("3 manual listed lots are missing", contains: true)
    }

    func testOnlyOneAccountGroupIsOpenAtATime() {
        openHoldings()
        open("t212:isa"); assertText("Infosys")
        open("listed__hargreaves"); assertText("MSFT")
        assertGone(text("Infosys"))
        open("listed__hargreaves"); assertGone(text("MSFT"))     // tapping the open group closes it
    }

    func testSearchOpensMatchesAndHidesTheRest() {
        openHoldings()
        let search = waitFor(el("holdings_search")); search.tap(); search.typeText("Infosys")
        assertText("Infosys"); assertGone(text("Microsoft", contains: true))
    }

    func testSoldLotsAppearOnlyWhenAsked() {
        openHoldings()
        open("listed__hargreaves")
        assertGone(text("OLDM"))
        let toggle = el("show_sold")
        var n = 0; while !(toggle.exists && toggle.isHittable) && n < 8 { app.swipeDown(); n += 1 }   // the switch sits at the top of the list
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()      // the switch is at the row's right edge
        XCTAssertEqual(toggle.value as? String, "1", "the switch turned on")
        let sold = text("OLDM"); scrollTo(sold, maxSwipes: 20)
        waitFor(sold)
    }

    func testManualLotDetailOffersTheEditActions() {
        openHoldings(); open("listed__hargreaves")
        waitFor(el("multi_MSFT")).tap()
        waitFor(text("id 11", contains: true)).tap()
        waitFor(el("holding_detail"))
        for id in ["act_sector", "act_edit", "act_sell", "act_remove"] { scrollTo(el(id)); XCTAssertTrue(el(id).exists, id) }
        XCTAssertFalse(el("act_values").exists, "value edits are for property, cash and other assets")
    }

    func testEditLotOpensItsFormAndCancelsWithoutWriting() {
        openHoldings(); open("listed__hargreaves")
        waitFor(el("multi_MSFT")).tap(); waitFor(text("id 11", contains: true)).tap()
        scrollTo(el("act_edit")); el("act_edit").tap()
        waitFor(el("manual_form")); waitFor(el("f_qty"))
        el("form_cancel").tap()
        assertGone(el("manual_form"))
    }

    func testRecordSaleRefusesMoreThanIsHeld() {
        openHoldings(); open("listed__hargreaves")
        waitFor(el("multi_MSFT")).tap(); waitFor(text("id 11", contains: true)).tap()
        scrollTo(el("act_sell")); el("act_sell").tap()
        let qty = waitFor(el("f_qty")); qty.tap(); qty.typeText("9")
        let price = el("f_price"); price.tap(); price.typeText("10")
        el("form_save").tap()
        assertText("Sold quantity cannot exceed current holding (1).")
    }

    func testBrokerPositionOffersOnlyTheSectorChange() {
        openHoldings(); open("t212:isa")
        waitFor(text("Infosys")).tap()
        waitFor(el("holding_detail"))
        scrollTo(el("act_sector")); XCTAssertTrue(el("act_sector").exists)
        XCTAssertFalse(el("act_edit").exists); XCTAssertFalse(el("act_remove").exists); XCTAssertFalse(el("act_sell").exists)
    }
}

final class HomeInsightsUITests: RushifyUITestCase {
    func testSectionSummariesAreShownWhileCollapsed() {
        launch(); waitFor(el("net_worth"))
        for id in ["pies", "positions", "custodian"] { scrollTo(el("section_summary_\(id)")); XCTAssertTrue(el("section_summary_\(id)").exists, id) }
    }

    func testPositionSizeOpensWithBarsAndTheLegend() {
        launch(); waitFor(el("net_worth"))
        scrollTo(el("section_toggle_positions")); el("section_toggle_positions").tap()
        waitFor(el("section_body_positions"))
    }

    func testNetWorthByBrokerExpandsAnInstitution() {
        launch(); waitFor(el("net_worth"))
        scrollTo(el("section_toggle_custodian")); el("section_toggle_custodian").tap()
        waitFor(el("section_body_custodian")); assertText("Grand total")
        let inst = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'custodian_' AND NOT identifier == 'custodian_section'")).firstMatch
        scrollTo(inst); waitFor(inst).tap()
        assertText("Listed", contains: true)
    }

    func testPortfolioDrillsIntoASectorAndBack() {
        launch(); waitFor(el("net_worth"))
        scrollTo(el("section_toggle_pies")); el("section_toggle_pies").tap()
        waitFor(el("section_body_pies")); assertText("Net worth by asset class")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sector_' AND NOT identifier == 'sector_section' AND NOT identifier == 'sector_back'")).firstMatch
        scrollTo(row); waitFor(row).tap()
        waitFor(el("sector_back")).tap()
        waitFor(row)
    }

    func testWealthOverTimeShowsAndFiltersByKind() {
        launch(); waitFor(el("net_worth"))
        scrollTo(el("section_toggle_wealth")); el("section_toggle_wealth").tap()
        waitFor(el("section_body_wealth")); scrollTo(el("wealth_filter_Property")); waitFor(el("wealth_filter_Property")).tap()
        assertText("Living Home")
    }
}

final class SyncUITests: RushifyUITestCase {
    func testAllThreeProvidersAreOnTheSyncScreenAndThereIsNoHistory() {
        launch(); openFromMore("Sync")
        waitFor(el("broker_T212")); XCTAssertTrue(el("broker_SNAPTRADE").exists); XCTAssertTrue(el("broker_MONZO").exists)
        assertText("Manual syncs are limited to 3 per rolling 24 hours for Trading 212 and for SnapTrade. Monzo has no daily limit.")
        XCTAssertFalse(text("History").exists); XCTAssertFalse(text("No syncs yet.").exists)
    }

    func testQuotaIsShownAndAnExhaustedProviderIsBlockedWithAReason() {
        launch(); openFromMore("Sync")
        assertText("2 of 3 manual syncs left today (rolling 24 h)")
        assertText("0 of 3 manual syncs left today (rolling 24 h)")
        XCTAssertFalse(waitFor(el("sync_SNAPTRADE")).isEnabled)
        XCTAssertTrue(waitFor(el("sync_T212")).isEnabled)
        waitFor(el("sync_reason_SNAPTRADE"))
    }

    func testStartingASyncAsksFirstAndThenShowsProgress() {
        launch(); openFromMore("Sync")
        waitFor(el("sync_T212")).tap()
        let alert = waitFor(app.alerts.firstMatch)
        alert.buttons["Cancel"].tap(); assertGone(app.alerts.firstMatch)
        XCTAssertFalse(el("sync_running_T212").exists, "cancelling does not start a sync")
        el("sync_T212").tap()
        waitFor(app.alerts.firstMatch).buttons.matching(identifier: "confirm_sync").firstMatch.tap()
        waitFor(el("sync_running_T212"))
    }

    func testMonzoSyncReportsWhatItPulled() {
        launch(); openFromMore("Sync")
        waitFor(el("monzo_status")); waitFor(el("monzo_sync")).tap()
        waitFor(el("monzo_message")); assertText("Synced 2 accounts and 3 pots.")
    }
}

final class MoreMenuUITests: RushifyUITestCase {
    func testTheMenuListsEveryScreenAndNoMonzoEntry() {
        launch(); tapTab("More")
        for t in ["Holdings", "Sync", "AI assistant", "Performance & income", "Corporate actions", "Connections & keys", "Add holding", "Change password"] {
            let row = app.staticTexts[t].firstMatch
            if !row.exists { app.swipeUp() }
            XCTAssertTrue(row.exists, t)
        }
        XCTAssertFalse(app.staticTexts["Balances and sync"].exists)
    }
}
