import XCTest
@testable import Rushify

private func d(_ s: String) -> Decimal { Decimal(string: s)! }

final class HoldingsLogicTests: XCTestCase {
    let rows = decodeFixture("holdings_dashboard", as: Dashboard.self).rows
    let rollups = decodeFixture("rollups", as: HoldingsRollups.self)
    var lines: [HoldingsRollupLine] { rollups.lines }
    func row(_ ticker: String, _ acc: String? = nil) -> HoldingRow { rows.first { $0.ticker == ticker && (acc == nil || $0.snaptradeAccountId == acc) }! }
    func groups(_ ex: HoldingsExposureFilter = .all, q: String = "", showSold: Bool = false, sort: HoldingsSort = .value) -> [HoldingsGroup] {
        HoldingsGroups.build(rows: rows, query: q, sort: sort, rollups: rollups, exposure: ex, showSold: showSold)
    }

    // ---- tickers ----
    func testStripsVenueSuffixes() {
        XCTAssertEqual(HoldingsLogic.stripT212VenueSuffix("INFY_US_EQ"), "INFY"); XCTAssertEqual(HoldingsLogic.stripT212VenueSuffix("VUAG_EQ"), "VUAG")
        XCTAssertEqual(HoldingsLogic.stripT212VenueSuffix("VOD_L_EQ"), "VOD"); XCTAssertEqual(HoldingsLogic.stripT212VenueSuffix("ABC_WBAG_EQ"), "ABC")
        XCTAssertEqual(HoldingsLogic.stripT212VenueSuffix("GOOGL"), "GOOGL"); XCTAssertEqual(HoldingsLogic.stripT212VenueSuffix(nil), "")
        XCTAssertEqual(HoldingsLogic.stripT212VenueSuffix("ABC_WB_EQ"), "ABC"); XCTAssertEqual(HoldingsLogic.stripT212VenueSuffix("  infy_us_eq "), "infy")
    }
    func testDisplayTickerUsesRollupElseStrips() {
        XCTAssertEqual(HoldingsLogic.displayTicker(row("INFY_US_EQ"), nil), "INFY")
        XCTAssertEqual(HoldingsLogic.displayTicker(row("VUAG_EQ"), lines.first { $0.displayTicker == "VUAG.L" }), "VUAG.L")
        XCTAssertEqual(HoldingsLogic.displayTicker(row("GOOGL", "acc-a"), nil), "GOOGL")
        XCTAssertEqual(HoldingsLogic.displayTicker(row("MSFT"), nil), "MSFT")
    }
    func testClassTickersMatchAcrossDashAndDot() { XCTAssertTrue(HoldingsLogic.rowTickerMatchesRollup("BRK-B", lines.first { $0.brokerTicker == "BRK.B" }!)) }
    func testUnrelatedTickersDoNotMatch() { XCTAssertFalse(HoldingsLogic.rowTickerMatchesRollup("AAPL_US_EQ", lines.first { $0.displayTicker == "INFY" }!)) }

    // ---- matching ----
    func testRowsMatchTheirOwnAccountOnly() {
        XCTAssertEqual(HoldingsLogic.findRollupForRow(row("GOOGL", "acc-a"), lines)!.accountRef, "snaptrade:acc-a")
        XCTAssertEqual(HoldingsLogic.findRollupForRow(row("GOOGL", "acc-b"), lines)!.accountRef, "snaptrade:acc-b")
        XCTAssertEqual(HoldingsLogic.findRollupForRow(row("AAPL_US_EQ"), lines)!.accountRef, "t212:invest")
        XCTAssertEqual(HoldingsLogic.findRollupForRow(row("INFY_US_EQ"), lines)!.accountRef, "t212:isa")
    }
    func testManualLotsMatchById() {
        XCTAssertEqual(HoldingsLogic.findRollupForRow(rows.first { $0.manualHoldingId == 11 }!, lines)!.accountRef, "manual:11")
        XCTAssertNil(HoldingsLogic.findRollupForRow(rows.first { $0.manualHoldingId == 12 }!, lines))
    }
    func testCashAndNonBrokerRowsNeverMatch() {
        XCTAssertNil(HoldingsLogic.findRollupForRow(row("CASH.t212.1"), lines)); XCTAssertNil(HoldingsLogic.findRollupForRow(row("MZ1"), lines))
    }
    func testBestRankedRollupWinsWhenSeveralMatch() {
        let extra = HoldingsRollupLine(source: "t212", accountRef: "t212:isa", brokerTicker: "INFY_X_EQ", displayTicker: "INFY", exposure: "open_full", fillRowCount: 99)
        XCTAssertEqual(HoldingsLogic.findRollupForRow(row("INFY_US_EQ"), lines + [extra])!.brokerTicker, "INFY_US_EQ")   // exact broker ticker beats more fills
    }
    func testExposureOfTheMatchedRollupIsReported() {
        XCTAssertEqual(HoldingsLogic.findRollupForRow(row("VUAG_EQ"), lines)!.exposure, "open_partial")
        XCTAssertNil(HoldingsLogic.findRollupForRow(row("VUAG_EQ"), lines, .openFull))
    }

    // ---- exposure filter ----
    func testAllKeepsEverything() { XCTAssertEqual(HoldingsLogic.applyExposureFilter(rows, lines, .all, false).count, rows.count) }
    func testOpenNoSellsKeepsOnlyFullyOpenBrokerLinesAndHidesCash() {
        let kept = HoldingsLogic.applyExposureFilter(rows, lines, .openFull, false).map { $0.ticker }
        for t in ["INFY_US_EQ", "AAPL_US_EQ", "GOOGL", "BRK-B"] { XCTAssertTrue(kept.contains(t), t) }
        XCTAssertFalse(kept.contains("VUAG_EQ")); XCTAssertFalse(kept.contains { $0.hasPrefix("CASH.") })
        XCTAssertTrue(kept.contains("MZ3") || kept.contains("NWRE.1"))
    }
    func testOpenReducedKeepsOnlyReducedBrokerLines() {
        let broker = HoldingsLogic.applyExposureFilter(rows, lines, .openPartial, false).filter { HoldingsLogic.isBrokerListedEquityRow($0) }.map { $0.ticker }
        XCTAssertEqual(broker, ["VUAG_EQ"])
    }
    func testClosedModeHidesBrokerListedCashAndOpenManualLots() {
        let kept = HoldingsLogic.applyExposureFilter(rows, lines, .closed, false)
        XCTAssertTrue(kept.allSatisfy { !HoldingsLogic.isBrokerListedEquityRow($0) && !HoldingsLogic.isBrokerCash($0) })
        XCTAssertTrue(kept.allSatisfy { ![11, 12, 13].contains($0.manualHoldingId ?? -1) })
        XCTAssertTrue(kept.contains { $0.ticker == "NWRE.1" })
    }
    func testSoldManualLotsOnlyShowWhenAsked() {
        XCTAssertTrue(HoldingsLogic.applyExposureFilter(rows, lines, .closed, false).allSatisfy { $0.manualHoldingId != 13 })
        XCTAssertTrue(HoldingsLogic.applyExposureFilter(rows, lines, .closed, true).contains { $0.manualHoldingId == 13 })
    }
    func testSoldRule() {
        XCTAssertTrue(HoldingsLogic.isManualListedSold(rows.first { $0.manualHoldingId == 13 }!))
        XCTAssertFalse(HoldingsLogic.isManualListedSold(rows.first { $0.manualHoldingId == 11 }!))
        XCTAssertTrue(HoldingsLogic.isManualListedSold(HoldingRow(ticker: "X", source: "manual", quantity: 0)))
        XCTAssertFalse(HoldingsLogic.isManualListedSold(HoldingRow(ticker: "X", source: "t212", soldOutAt: "2026-01-01")))
    }

    // ---- groups: order, titles, metrics ----
    func testGroupOrderMatchesTheWeb() {
        let names = groups().map { $0.name }
        XCTAssertEqual(Array(names.prefix(2)), ["Trading 212 · Invest", "Trading 212 · ISA"])
        let i = names.firstIndex(of: "AJ Bell · LISA · SnapTrade")!; XCTAssertTrue((2...4).contains(i))
        let kinds = groups().map { $0.kind }
        let order: [HoldingsGroupKind] = [.t212, .snaptrade, .csv, .monzo, .manualListed, .manualProperty, .manualCash, .manualOther, .other]
        let ranks = kinds.map { order.firstIndex(of: $0)! }
        XCTAssertEqual(ranks, ranks.sorted())
    }
    func testSameLabelAccountsStaySeparate() { XCTAssertEqual(groups().filter { $0.name == "AJ Bell · LISA · SnapTrade" && !$0.rows.isEmpty }.count, 2) }
    func testAccountMetricsAreAttachedByRef() {
        let isa = groups().first { $0.accountRef == "t212:isa" }!
        XCTAssertEqual(isa.account!.realisedGainBaseSum, d("-644.93")); XCTAssertEqual(isa.account!.xirrAnnual, d("0.1628"))
        XCTAssertEqual(groups().first { $0.accountRef == "snaptrade:acc-b" }!.account!.accountRef, "snaptrade:acc-b")
    }
    func testBrokerGroupCountsExcludeCashButShowIt() {
        let isa = groups().first { $0.accountRef == "t212:isa" }!
        XCTAssertEqual(isa.positionCount, 2); XCTAssertEqual(isa.cashValue, d("50")); XCTAssertEqual(isa.totalValue, d("350")); XCTAssertEqual(isa.totalPnl, d("5"))
        XCTAssertEqual(isa.totalQty, d("5"))
    }
    func testAGroupWithNoListedRowsShowsZeroUnrealisedNotADash() {
        XCTAssertEqual(groups().first { $0.accountRef == "snaptrade:acc-zzzzzzzzzzzzzz1234" }!.totalPnl, 0)
    }
    func testManualGroupsHaveWebTitlesAndBadges() {
        let g = groups().filter { [.manualListed, .manualCash, .manualProperty, .manualOther].contains($0.kind) }
        XCTAssertEqual(g.map { $0.name }, ["Hargreaves", "Property (manual)", "Zopa Bank · Cash ISA", "Other assets (manual)"])
        XCTAssertEqual(g.map { $0.badge }, ["Manual listed", "Property", "Cash savings", "Other assets"])
    }
    func testMonzoIsOneGroupWithABadge() {
        let m = groups().filter { $0.kind == .monzo }; XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].name, "Monzo"); XCTAssertEqual(m[0].badge, "Bank (synced)"); XCTAssertEqual(m[0].rows.count, 4)
    }
    func testSoldLotsAppearOnlyWithTheToggle() {
        XCTAssertTrue(groups().first { $0.kind == .manualListed }!.rows.allSatisfy { $0.manualHoldingId != 13 })
        XCTAssertTrue(groups(showSold: true).first { $0.kind == .manualListed }!.rows.contains { $0.manualHoldingId == 13 })
    }

    // ---- closed instruments ----
    func testClosedLinesAttachToTheirAccountAndAreDeduped() {
        let closed = groups().first { $0.accountRef == "t212:isa" }!.closed
        XCTAssertEqual(closed.count, 1); XCTAssertEqual(closed[0].fillRowCount, 5)     // two OLDCO lines collapse, the one with more fills wins
    }
    func testAccountWithOnlyClosedHistoryStillGetsABlock() {
        let g = groups().first { $0.accountRef == "snaptrade:acc-zzzzzzzzzzzzzz1234" }!
        XCTAssertTrue(g.rows.isEmpty); XCTAssertEqual(g.closed.count, 1); XCTAssertEqual(g.name, "SnapTrade · acc-zzzz…1234")
    }
    func testClosedCardsHiddenInOpenFilters() {
        XCTAssertTrue(groups(.openFull).allSatisfy { $0.closed.isEmpty }); XCTAssertTrue(groups(.openPartial).allSatisfy { $0.closed.isEmpty })
        XCTAssertTrue(groups(.all).contains { !$0.closed.isEmpty })
    }
    func testClosedModeShowsClosedInstrumentsAndNoOpenBrokerRows() {
        let g = groups(.closed)
        XCTAssertTrue(g.filter { $0.brokerLike }.allSatisfy { $0.rows.isEmpty }); XCTAssertEqual(g.filter { !$0.closed.isEmpty }.count, 2)
    }
    func testSearchAlsoFiltersClosedInstruments() {
        XCTAssertEqual(groups(q: "oldco").flatMap { $0.closed }.count, 1); XCTAssertTrue(groups(q: "zzzz-nothing").isEmpty)
    }

    // ---- items / primary metrics ----
    func testSameTickerLinesCollapseUnderOneSummary() {
        var extra = row("INFY_US_EQ"); extra.quantity = d("1"); extra.marketValueBase = d("10")
        let g = HoldingsGroups.build(rows: rows + [extra], rollups: rollups).first { $0.accountRef == "t212:isa" }!
        let items = HoldingsGroups.items(g, rollups, .all)
        var multis: [(String, Int)] = [], singles: [HoldingRow] = []
        for i in items { switch i { case .multi(let t, let rs): multis.append((t, rs.count)); case .single(let r): singles.append(r) } }
        XCTAssertEqual(multis.count, 1); XCTAssertEqual(multis[0].0, "INFY"); XCTAssertEqual(multis[0].1, 2)
        XCTAssertTrue(singles.contains { $0.assetKind == "cash" })   // cash stays a single line
    }
    func testManualLotsOfOneTickerGroupToo() {
        let g = groups().first { $0.kind == .manualListed }!
        let items = HoldingsGroups.items(g, rollups, .all); XCTAssertEqual(items.count, 1)
        guard case .multi(_, let rs) = items[0] else { return XCTFail("expected a multi item") }
        XCTAssertEqual(rs.count, 2)
    }
    func testNonListedGroupsAreNeverNested() {
        for g in groups() where g.kind == .monzo || g.kind == .manualCash {
            for i in HoldingsGroups.items(g, rollups, .all) { if case .multi = i { XCTFail("nested") } }
        }
    }
    func testFirstLineOfASplitPositionCarriesTheFees() {
        var extra = row("INFY_US_EQ"); extra.quantity = d("1"); extra.marketValueBase = d("10"); extra.currency = "EUR"
        let ordered = [row("INFY_US_EQ"), extra]
        let primary = HoldingsGroups.primaryMetricRows(ordered, lines, .all)
        XCTAssertEqual(primary.count, 1); XCTAssertEqual(primary.values.first, HoldingsLogic.rowSlotId(ordered[0]))
        XCTAssertNotEqual(HoldingsLogic.rowSlotId(ordered[0]), HoldingsLogic.rowSlotId(ordered[1]))
    }

    // ---- account summaries ----
    func testSummariesAreOrderedCsvMonzoSnaptradeT212() {
        XCTAssertEqual(HoldingsAccountSummaries.build(rollups, rows).map { $0.source }, ["csv", "monzo", "snaptrade", "snaptrade", "t212", "t212"])
    }
    func testMonzoAppearsOnceEvenThoughServerAndDashboardBothKnowAboutIt() {
        let monzo = HoldingsAccountSummaries.build(rollups, rows).filter { $0.source == "monzo" }
        XCTAssertEqual(monzo.count, 1); XCTAssertEqual(monzo[0].label, "Monzo · 4 balances"); XCTAssertEqual(monzo[0].monzoTotal, d("1385.04"))
    }
    func testMonzoLineIsBuiltFromDashboardRowsWhenServerSendsNone() {
        let noMonzo = HoldingsRollups(lines: rollups.lines, accounts: rollups.accounts.filter { $0.source != "monzo" })
        let m = HoldingsAccountSummaries.build(noMonzo, rows).first { $0.source == "monzo" }!
        XCTAssertEqual(m.label, "Monzo · 4 balances"); XCTAssertEqual(m.monzoTotal, d("1385.04"))
    }
    func testMonzoLineSingularLabel() {
        let one = rows.filter { $0.source == "monzo" }.prefix(1)
        XCTAssertEqual(HoldingsAccountSummaries.build(HoldingsRollups(), Array(one)).first!.label, "Monzo · 1 balance")
    }
    func testMonzoNeverCountsInTheTotals() {
        var noisy = rollups
        noisy.accounts = rollups.accounts.map { var a = $0; if a.source == "monzo" { a.realisedGainBaseSum = d("999"); a.listedInvestmentsMvBaseSum = d("999999") }; return a }
        let t = HoldingsAccountSummaries.totals(HoldingsAccountSummaries.build(noisy, rows))!
        XCTAssertEqual(t.realised, d("-1608.42")); XCTAssertEqual(t.investments, d("69138.65"))
    }
    func testSummaryLabelsMatchTheWebFormats() {
        let labels = HoldingsAccountSummaries.build(rollups, rows).map { $0.label }
        for l in ["Trading 212 · Cash ISA (CSV)", "Trading 212 · ISA", "AJ Bell · LISA · SnapTrade", "Monzo · 4 balances"] { XCTAssertTrue(labels.contains(l), l) }
    }
    func testTotalsExcludeMonzoAndSumEveryColumn() {
        let t = HoldingsAccountSummaries.totals(HoldingsAccountSummaries.build(rollups, rows))!
        XCTAssertEqual(t.realised, d("-1608.42")); XCTAssertEqual(t.unrealised, d("18829.33")); XCTAssertEqual(t.investments, d("69138.65")); XCTAssertEqual(t.payout, d("1924.90"))
    }
    func testNoAccountsMeansNoTotalsRow() {
        XCTAssertNil(HoldingsAccountSummaries.totals(HoldingsAccountSummaries.build(HoldingsRollups(), rows.filter { $0.source == "monzo" })))
    }
    func testAccountLabelsFromRefs() {
        XCTAssertEqual(HoldingsLogic.formatRollupAccountLabel("t212:invest"), "Trading 212 · INVEST")
        XCTAssertEqual(HoldingsLogic.formatRollupAccountLabel("csv:lightyear:invest"), "Lightyear · Invest (CSV)")
        XCTAssertEqual(HoldingsLogic.formatRollupAccountLabel("csv:freetrade-plus:sipp"), "Freetrade Plus · SIPP (CSV)")
        XCTAssertEqual(HoldingsLogic.formatRollupAccountLabel("snaptrade:1234"), "SnapTrade · 1234")
        XCTAssertEqual(HoldingsLogic.formatRollupAccountLabel("snaptrade:abc", ["abc": "AJ Bell · LISA"]), "AJ Bell · LISA · SnapTrade")
        XCTAssertEqual(HoldingsLogic.formatRollupAccountLabel("csv:trading212"), "Trading 212 · Invest (CSV)")
        XCTAssertEqual(HoldingsLogic.formatRollupAccountLabel("whatever"), "whatever")
    }

    // ---- Monzo ----
    func testMonzoSectionsAreOrderedAndSortedByValue() {
        let s = HoldingsLogic.monzoSections(rows.filter { $0.source == "monzo" })
        XCTAssertEqual(s.map { $0.title }, ["Accounts", "Savings & ISAs", "Pots"])
        XCTAssertEqual(s[0].rows.map { $0.instrumentName }, ["Monzo · Current account", "Monzo · Young account"])   // 181.04 before 104.00
        XCTAssertEqual(HoldingsLogic.monzoKindBadge("savings"), "Savings"); XCTAssertEqual(HoldingsLogic.monzoKindBadge("pot"), "Pot"); XCTAssertNil(HoldingsLogic.monzoKindBadge("current"))
        XCTAssertEqual(HoldingsLogic.monzoRowName(rows.first { $0.ticker == "MZ4" }!), "Bills (Current account)")
    }

    // ---- misc ----
    func testAbbreviationsLikeTheWeb() {
        XCTAssertEqual(Fmt.abbreviate(d("1234000000000")), "1.23T"); XCTAssertEqual(Fmt.abbreviate(d("4500000000")), "4.50B"); XCTAssertEqual(Fmt.abbreviate(d("12300000")), "12.30M")
        XCTAssertEqual(Fmt.abbreviate(d("950")), "950"); XCTAssertEqual(Fmt.abbreviate(nil), "—")
    }
    func testRollupExposureLabels() {
        XCTAssertEqual(HoldingsLogic.rollupExposureLabel("open_full"), "Open (synced)"); XCTAssertEqual(HoldingsLogic.rollupExposureLabel("open_partial"), "Open (reduced)")
        XCTAssertEqual(HoldingsLogic.rollupExposureLabel("closed_history"), "Closed (history)"); XCTAssertEqual(HoldingsLogic.rollupExposureLabel("zzz"), "zzz")
    }
    func testExposureHintsMatchTheWeb() {
        XCTAssertTrue(HoldingsExposureFilter.allCases.allSatisfy { !$0.hint.isEmpty })
        XCTAssertEqual(HoldingsExposureFilter.allCases.map { $0.label }, ["All", "Open (no sells)", "Open (reduced)", "Closed (history)"])
        XCTAssertEqual(HoldingsSort.allCases.map { $0.label }, ["Value", "P/L", "Name"])
    }
    func testManualGroupKeys() {
        let listed = HoldingRow(ticker: "X", source: "manual", brokerLabel: "  Hargreaves ", manualBrokerName: "Other")
        XCTAssertEqual(HoldingsLogic.manualGroupKey(listed), "listed__hargreaves")
        var cash = HoldingRow(ticker: "C", source: "manual", assetKind: "cash"); cash.manualBrokerName = "Zopa Bank"; cash.instrumentName = "Zopa Bank · Cash ISA"
        XCTAssertEqual(HoldingsLogic.manualGroupKey(cash), "cash__zopa bank__cash isa")
        cash.manualBrokerName = nil; cash.brokerLabel = "Nationwide · x"; cash.instrumentName = "Flex"
        XCTAssertEqual(HoldingsLogic.manualGroupKey(cash), "cash__nationwide__flex")
        XCTAssertEqual(HoldingsLogic.manualGroupKey(HoldingRow(ticker: "P", source: "manual", assetKind: "real_estate")), "property__manual entry")
        XCTAssertEqual(HoldingsLogic.manualGroupKey(HoldingRow(ticker: "O", source: "manual", assetKind: "other", manualBrokerName: "Gold")), "other__gold")
        XCTAssertEqual(HoldingsLogic.manualGroupTitle("property__gold", HoldingRow(ticker: "P", manualBrokerName: "Gold")), "Gold · Property")
        XCTAssertEqual(HoldingsLogic.manualGroupTitle("other__x", HoldingRow(ticker: "O")), "Other assets (manual)")
    }
    func testCsvAccountRefFromRow() {
        var r = HoldingRow(ticker: "X", source: "csv", brokerLabel: "Freetrade Plus · SIPP (CSV)", accountKind: "sipp")
        XCTAssertEqual(HoldingsLogic.csvAccountRefFromRow(r), "csv:freetrade-plus:sipp")
        r.brokerAccountRef = " CSV:Trading-212:ISA "; XCTAssertEqual(HoldingsLogic.csvAccountRefFromRow(r), "csv:trading212:isa")
    }
    func testSearchMatchesTickerNameAndSortByName() {
        let g = HoldingsGroups.build(rows: rows, query: "hargreaves")
        XCTAssertFalse(g.isEmpty); XCTAssertTrue(g.allSatisfy { $0.kind == .manualListed })
        let sorted = HoldingsGroups.sortRows(rows.filter { $0.source == "monzo" }, .name).map { ($0.instrumentName ?? $0.ticker).lowercased() }
        XCTAssertEqual(sorted, sorted.sorted())
    }
}
