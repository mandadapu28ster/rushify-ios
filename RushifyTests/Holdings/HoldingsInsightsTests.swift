import XCTest
@testable import Rushify

private func d(_ s: String) -> Decimal { Decimal(string: s)! }

final class HoldingsInsightsTests: XCTestCase {
    private func row(_ ticker: String = "T", source: String = "t212", label: String? = nil, kind: String? = nil, acct: String? = nil, sector: String? = nil, mv: String? = nil,
                     cost: String? = nil, pnl: String? = nil, name: String? = nil, manualBroker: String? = nil, qty: String? = nil) -> HoldingRow {
        HoldingRow(ticker: ticker, instrumentName: name, source: source, brokerLabel: label, accountKind: acct, sector: sector, assetKind: kind,
                   quantity: qty.map(d), marketValueBase: mv.map(d), costBase: cost.map(d), pnlStockBase: pnl.map(d), manualBrokerName: manualBroker)
    }
    let holdings = decodeFixture("holdings_dashboard", as: Dashboard.self).rows

    // ======================= institution keys =======================
    func testInstitutionKeysStripAccountWrappers() {
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(label: "Trading 212 · ISA")), "Trading 212")
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "csv", label: "Trading 212 · Cash ISA (CSV)")), "Trading 212")
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "snaptrade", label: "AJ Bell · LISA")), "AJ Bell")
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "snaptrade", label: "AJ Bell · My nickname")), "AJ Bell")      // snaptrade always aggregates on institution
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "csv", label: "Lightyear · Invest (CSV)")), "Lightyear")
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "manual", manualBroker: "Zopa Bank")), "Zopa Bank")
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "manual", manualBroker: "Trading 212 Cash ISA")), "Trading 212")
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "manual", manualBroker: "Hargreaves Lansdown · ISA")), "Hargreaves Lansdown")
    }
    func testSpecialInstitutionNames() {
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(kind: "real_estate")), "Property"); XCTAssertEqual(HoldingsCustodian.institutionKey(row(kind: "other")), "Other assets")
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "manual", label: "Manual entry")), "No institution name")
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "t212", label: nil)), "Trading 212"); XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "snaptrade", label: " ")), "SnapTrade")
        XCTAssertEqual(HoldingsCustodian.institutionKey(row(source: "", label: nil)), "Other")
    }
    func testListedWrapperLabels() {
        let cases: [(String, String)] = [("isa", "ISA"), ("sipp", "SIPP"), ("invest", "Invest"), ("lisa", "LISA"), ("lifetime_isa", "LISA"), ("cash_isa", "ISA"),
                                         ("junior_isa", "JISA"), ("junior_sipp", "JSIPP"), ("jsipp", "JSIPP"), ("zzz", "Other"), ("", "Other")]
        for (k, want) in cases { XCTAssertEqual(HoldingsCustodian.listedAccountLabel(row(acct: k)), want, k) }
        XCTAssertEqual(HoldingsCustodian.listedAccountLabel(row(kind: "cash")), "")
    }
    func testCashBucketLabels() {
        XCTAssertEqual(HoldingsCustodian.cashBucketLabel(row(source: "monzo", kind: "cash", acct: "joint")), "Joint account")
        XCTAssertEqual(HoldingsCustodian.cashBucketLabel(row(source: "csv", kind: "cash", acct: "cash_isa")), "Cash ISA")
        XCTAssertEqual(HoldingsCustodian.cashBucketLabel(row(source: "t212", kind: "cash", acct: "some_thing")), "some thing")
        XCTAssertEqual(HoldingsCustodian.cashBucketLabel(row(source: "manual", kind: "cash", name: "Zopa Bank · Cash ISA")), "Cash ISA")
        XCTAssertEqual(HoldingsCustodian.cashBucketLabel(row(source: "manual", kind: "cash", name: "A · B · Savings account")), "Savings account")
        XCTAssertEqual(HoldingsCustodian.cashBucketLabel(row(source: "manual", kind: "cash", name: "Plain")), "Plain"); XCTAssertEqual(HoldingsCustodian.cashBucketLabel(row(source: "manual", kind: "cash")), "Other")
        XCTAssertEqual(HoldingsCustodian.cashBucketLabel(row(kind: nil)), "")
    }

    // ======================= market value fallbacks =======================
    func testQuotedValueWins() { XCTAssertEqual(HoldingsCustodian.marketValue(row(mv: "5", cost: "9")), d("5")) }
    func testNonPositiveValueOfBrokerRowIsZero() { XCTAssertEqual(HoldingsCustodian.marketValue(row(mv: "0", cost: "9")), 0) }
    func testOpenManualLotFallsBackToCostThenAveragePrice() {
        var manual = HoldingRow(ticker: "X", source: "manual", manualHoldingId: 1, quantity: d("2"))
        manual.costBase = d("30"); XCTAssertEqual(HoldingsCustodian.marketValue(manual), d("30"))
        manual.costBase = nil; manual.costBaseGbp = d("25"); XCTAssertEqual(HoldingsCustodian.marketValue(manual), d("25"))
        manual.costBaseGbp = nil; manual.avgPrice = d("10"); manual.fxToBase = d("0.8"); XCTAssertEqual(HoldingsCustodian.marketValue(manual), d("16"))
        manual.fxToBase = nil; XCTAssertEqual(HoldingsCustodian.marketValue(manual), d("20"))
        manual.soldOutAt = "2026-01-01"; manual.costBase = d("30"); XCTAssertEqual(HoldingsCustodian.marketValue(manual), 0)
    }

    // ======================= net worth by broker =======================
    func testBrokerRowsAreSortedAndTotalledLikeTheWeb() {
        let r = HoldingsCustodian.build(holdings)
        XCTAssertEqual(r.map { $0.name }, ["Property", "Zopa Bank", "Trading 212", "Other assets", "Monzo", "AJ Bell", "Hargreaves"])
        let t212 = r.first { $0.name == "Trading 212" }!
        XCTAssertEqual(t212.equity, d("340")); XCTAssertEqual(t212.cash, d("5050")); XCTAssertEqual(t212.total, d("5390"))
    }
    func testListedAndCashAreSplitByAccountType() {
        let t212 = HoldingsCustodian.build(holdings).first { $0.name == "Trading 212" }!
        XCTAssertEqual(t212.listedByAccount, [HoldingsNamedAmount(account: "ISA", value: d("300")), HoldingsNamedAmount(account: "Invest", value: d("40"))])
        XCTAssertEqual(t212.cashByAccount, [HoldingsNamedAmount(account: "Other", value: d("5000")), HoldingsNamedAmount(account: "ISA", value: d("50"))])
        XCTAssertEqual(t212.wrappers["ISA"], d("300")); XCTAssertEqual(t212.wrappers["Invest"], d("40")); XCTAssertEqual(t212.wrappers["SIPP"], 0)
    }
    func testASingleOtherSplitIsHiddenButStillStacked() {
        let aj = HoldingsCustodian.build(holdings).first { $0.name == "AJ Bell" }!
        XCTAssertTrue(aj.listedByAccount.isEmpty); XCTAssertTrue(aj.cashByAccount.isEmpty); XCTAssertEqual(aj.wrappers["Other"], d("530")); XCTAssertEqual(aj.total, d("550"))
    }
    func testMonzoCashIsBucketedByAccountType() {
        let m = HoldingsCustodian.build(holdings).first { $0.name == "Monzo" }!
        XCTAssertEqual(Set(m.cashByAccount.map { $0.account }), ["Current account", "Young account", "Savings", "Pot"]); XCTAssertEqual(m.cash, d("1385.04"))
    }
    func testZeroValueRowsAreSkippedSoSoldLotsAddNothing() { XCTAssertEqual(HoldingsCustodian.build(holdings).first { $0.name == "Hargreaves" }!.total, d("180")) }
    func testGrandTotalMatchesTheDashboardRowsWithValue() {
        XCTAssertEqual(holdings.reduce(Decimal(0)) { $0 + HoldingsCustodian.marketValue($1) }, HoldingsCustodian.build(holdings).reduce(Decimal(0)) { $0 + $1.total })
    }
    func testBrokerPickerLabelsIncludeOpenAndSoldManualBrokers() {
        let labels = HoldingsCustodian.listedEquityBrokerLabels(holdings)
        for l in ["AJ Bell · LISA", "Hargreaves", "Trading 212 · ISA", "Trading 212 · Invest"] { XCTAssertTrue(labels.contains(l), l) }
        XCTAssertFalse(labels.contains("Monzo")); XCTAssertEqual(labels, labels.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending })
    }

    // ======================= sectors =======================
    func testSectorsAggregateListedRowsOnly() {
        let s = HoldingsSectors.build(decodeFixture("dashboard", as: Dashboard.self).rows)
        XCTAssertEqual(s.map { $0.sector }, ["Technology", "Health", "Unknown"])
        XCTAssertEqual(s[0].value, d("600.30")); XCTAssertEqual(s[0].cost, d("500.00")); XCTAssertEqual(s[0].gain, d("100.30")); XCTAssertEqual(s[0].gainPct, d("20.06"))
        XCTAssertEqual(s[0].allocPct, d("59.94")); XCTAssertEqual(holdingsRound(s.reduce(Decimal(0)) { $0 + $1.allocPct }, 0), d("100"))
    }
    func testSectorHoldingsMergeLotsAndShowShareOfSector() {
        let rows = [row("aaa", sector: "Tech", mv: "30", cost: "20", pnl: "10"), row("AAA", source: "snaptrade", sector: "Tech", mv: "10", cost: "10", pnl: "0"), row("BBB", sector: "Tech", mv: "60", cost: "50", pnl: "10")]
        let tech = HoldingsSectors.build(rows)[0]
        XCTAssertEqual(HoldingsSectors.build(rows).count, 1)
        XCTAssertEqual(tech.holdings.map { $0.ticker }, ["BBB", "AAA"]); XCTAssertEqual(tech.holdings[1].value, d("40")); XCTAssertEqual(tech.holdings[1].shareOfSectorPct, d("40.00"))
        XCTAssertEqual(tech.value, d("100")); XCTAssertEqual(tech.gain, d("20"))
    }
    func testSectorsIgnoreCashMonzoAndNonListed() {
        let rows = [row("CASH.1", kind: "cash", mv: "5"), row("M", source: "monzo", mv: "5"), row("P", kind: "real_estate", mv: "5"), row("Z", mv: "0"), row("OK", sector: "S", mv: "2")]
        XCTAssertEqual(HoldingsSectors.build(rows).map { $0.sector }, ["S"])
    }
    func testSectorGainPctIsNilWithoutCost() { XCTAssertNil(HoldingsSectors.build([row("A", sector: "S", mv: "5")])[0].gainPct) }

    // ======================= position bars =======================
    func testPositionBarsMergeBrokersSortByValueAndKeepCostAndGain() {
        let bars = HoldingsPositionBars.build([row("GOOGL", source: "snaptrade", mv: "300", cost: "200"), row("googl", mv: "100", cost: "150"), row("AAPL", mv: "500", cost: "400"), row("CASH.x", kind: "cash", mv: "9")])
        XCTAssertEqual(bars.map { $0.ticker }, ["AAPL", "GOOGL"])
        XCTAssertEqual(bars[1].value, d("400")); XCTAssertEqual(bars[1].cost, d("350")); XCTAssertEqual(bars[1].pnl, d("50")); XCTAssertEqual(bars[0].pnl, d("100"))
    }
    func testPositionBarFallsBackToRowPnlWhenCostIsMissing() { XCTAssertEqual(HoldingsPositionBars.build([row("A", mv: "50", pnl: "7")])[0].pnl, d("7")) }
    func testPositionBarTieBreaksByTicker() { XCTAssertEqual(HoldingsPositionBars.build([row("B", mv: "5"), row("A", mv: "5")]).map { $0.ticker }, ["A", "B"]) }
    func testPositionBarsStripVenueSuffixes() { XCTAssertEqual(HoldingsPositionBars.build([row("INFY_US_EQ", mv: "5")]).map { $0.ticker }, ["INFY"]) }

    // ======================= wealth over time =======================
    private func asset(_ id: Int, _ kind: String, eligible: Bool = true, show: Bool = true, _ snaps: [(String, String)] = []) -> HoldingsWealthAsset {
        HoldingsWealthAsset(manualHoldingId: id, label: "Line \(id)", assetKind: kind, showOnWealthChart: show, snapshotCount: snaps.count, chartEligible: eligible, exited: false,
                            snapshots: snaps.map { HoldingsWealthSnapshot(asOf: $0.0, valueGbp: d($0.1), source: "manual") })
    }
    private var wealth: HoldingsWealthSeries {
        HoldingsWealthSeries(assets: [
            asset(1, "real_estate", [("2025-01-01", "100"), ("2026-01-01", "120")]),
            asset(2, "cash", [("2025-06-01", "10")]),
            asset(3, "cash", eligible: false, [("2025-02-01", "99")]),
            asset(4, "other", eligible: true, show: false, [("2025-03-01", "7")]),
        ])
    }
    func testSectionOnlyAppearsWhenSomeLineQualifies() {
        XCTAssertTrue(HoldingsWealthMath.visible(wealth)); XCTAssertFalse(HoldingsWealthMath.visible(nil))
        XCTAssertFalse(HoldingsWealthMath.visible(HoldingsWealthSeries(assets: [asset(3, "cash", eligible: false)])))
        XCTAssertEqual(HoldingsWealthMath.eligible(wealth).map { $0.manualHoldingId }, [1, 2]); XCTAssertEqual(HoldingsWealthMath.ineligibleCount(wealth), 1)
    }
    func testValuesCarryForwardFromTheLastSnapshotOnOrBeforeEachDate() {
        let c = HoldingsWealthMath.chart(wealth, .all)
        XCTAssertEqual(c.dates, ["2025-01-01", "2025-06-01", "2026-01-01"])
        XCTAssertEqual(c.lines[0].values, [d("100"), d("100"), d("120")]); XCTAssertEqual(c.lines[1].values, [0, d("10"), d("10")])
    }
    func testFiltersByKind() {
        XCTAssertEqual(HoldingsWealthMath.chart(wealth, .property).lines.map { $0.name }, ["Line 1"]); XCTAssertEqual(HoldingsWealthMath.chart(wealth, .cash).lines.map { $0.name }, ["Line 2"])
        XCTAssertTrue(HoldingsWealthMath.chart(wealth, .other).lines.isEmpty)
    }
    func testWealthFixtureDecodesAndHasOneQualifyingLineGroup() {
        let w = decodeFixture("wealth", as: HoldingsWealthSeries.self)
        XCTAssertEqual(w.baseCurrency, "GBP"); XCTAssertEqual(w.minSnapshotsForChart, 5); XCTAssertEqual(w.minHoldDaysForChart, 365)
        XCTAssertEqual(HoldingsWealthMath.eligible(w).count, 2); XCTAssertEqual(HoldingsWealthMath.ineligibleCount(w), 1)
        XCTAssertEqual(HoldingsWealthMath.totalNow(w), d("116000"))
    }

    // ======================= home summaries =======================
    func testSummariesMatchAndroidWording() {
        let rows = decodeFixture("dashboard", as: Dashboard.self).rows
        let sec = HoldingsSectors.build(rows)
        XCTAssertEqual(HoldingsHomeSummaries.sectors(rows: rows, ccy: "GBP", hide: false), "3 sectors · listed total \(Fmt.money(sec.reduce(Decimal(0)) { $0 + $1.value }, "GBP", scale: 0)).")
        XCTAssertEqual(HoldingsHomeSummaries.positions(rows: rows), "3 positions — bars ordered by market value.")
        XCTAssertNil(HoldingsHomeSummaries.sectors(rows: [], ccy: "GBP", hide: false)); XCTAssertNil(HoldingsHomeSummaries.positions(rows: [])); XCTAssertNil(HoldingsHomeSummaries.custodian(rows: [], ccy: "GBP", hide: false))
    }
    func testCustodianSummaryAndHiding() {
        let s = HoldingsHomeSummaries.custodian(rows: holdings, ccy: "GBP", hide: false)!
        let grand = HoldingsCustodian.build(holdings).reduce(Decimal(0)) { $0 + $1.total }
        XCTAssertEqual(s, "7 institutions · total \(Fmt.money(grand, "GBP")).")
        let hidden = HoldingsHomeSummaries.custodian(rows: holdings, ccy: "GBP", hide: true)!
        XCTAssertEqual(hidden, "7 institutions · total ••••."); XCTAssertEqual(HoldingsHomeSummaries.sectors(rows: holdings, ccy: "GBP", hide: true)!.contains("••••"), true)
        XCTAssertEqual(HoldingsHomeSummaries.custodian(rows: [row("A", source: "t212", label: "Trading 212 · ISA", mv: "5")], ccy: "GBP", hide: false), "1 institution · total £5.00.")
    }
    func testWealthShouldLoadOnlyForManualNonListedLines() {
        XCTAssertTrue(HoldingsHomeSummaries.wealthShouldLoad(rows: holdings))
        XCTAssertFalse(HoldingsHomeSummaries.wealthShouldLoad(rows: [HoldingRow(ticker: "X", source: "manual", assetKind: "listed", manualHoldingId: 1), HoldingRow(ticker: "C", source: "t212", assetKind: "cash"),
                                                                       HoldingRow(ticker: "P", source: "manual", assetKind: "real_estate")]))
        XCTAssertTrue(HoldingsHomeSummaries.wealthShouldLoad(rows: [HoldingRow(ticker: "P", source: "manual", assetKind: "real_estate", manualHoldingId: 3)]))
    }
    func testWealthSummary() {
        XCTAssertEqual(HoldingsHomeSummaries.wealth(wealth, hide: false), "2 lines · £130 total.")
        XCTAssertEqual(HoldingsHomeSummaries.wealth(wealth, hide: true), "2 lines · •••• total.")
        XCTAssertNil(HoldingsHomeSummaries.wealth(nil, hide: false)); XCTAssertNil(HoldingsHomeSummaries.wealth(HoldingsWealthSeries(assets: [asset(3, "cash", eligible: false)]), hide: false))
    }
    func testRoundingHalfUp() { XCTAssertEqual(holdingsRound(d("2.675"), 2), d("2.68")); XCTAssertEqual(holdingsRound(d("-2.5"), 0), d("-3")) }
}
