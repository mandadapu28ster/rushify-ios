import XCTest
@testable import Rushify

final class ServerURLTests: XCTestCase {
    private func ok(_ s: String) -> ServerURL.Parsed { if case .ok(let p) = ServerURL.parse(s) { return p }; XCTFail("expected ok for \(s)"); return ServerURL.Parsed(url: "", scheme: "", host: "", port: nil) }
    private func bad(_ s: String) -> String { if case .bad(let r) = ServerURL.parse(s) { return r }; XCTFail("expected bad for \(s)"); return "" }

    func testHttpsDomainIsNotCleartext() { let r = ok("https://rushify.example.com/"); XCTAssertFalse(r.isCleartext); XCTAssertEqual(r.url, "https://rushify.example.com") }
    func testPublicIpWithPortIsCleartext() { let r = ok("  http://90.255.245.88:8040/ "); XCTAssertTrue(r.isCleartext); XCTAssertEqual(r.port, 8040); XCTAssertEqual(r.url, "http://90.255.245.88:8040") }
    func testPrivateIpAccepted() { XCTAssertTrue(ok("http://192.168.1.20:8040").isCleartext) }
    func testMissingSchemeRejected() { XCTAssertTrue(bad("90.255.245.88:8040").contains("http")) }
    func testOtherSchemeRejected() { XCTAssertTrue(bad("ftp://host").contains("http")) }
    func testEmptyRejected() { XCTAssertFalse(bad("   ").isEmpty) }
    func testPathRejected() { XCTAssertTrue(bad("http://host:8040/api").contains("path")) }
    func testCredentialsRejected() { XCTAssertTrue(bad("http://user:pw@host").contains("credentials")) }
    func testPortZeroRejected() { XCTAssertTrue(bad("http://host:0").contains("Port")) }
    func testPortTooLargeRejected() { XCTAssertTrue(bad("http://host:65536").contains("Port")) }
    func testNonNumericPortRejected() { XCTAssertTrue(bad("http://host:abc").contains("Port")) }
    func testMaxPortAccepted() { XCTAssertEqual(ok("http://host:65535").port, 65535) }
    func testQueryRejected() { XCTAssertTrue(bad("http://host:8040?x=1").contains("path")) }
}

final class FmtTests: XCTestCase {
    private func d(_ s: String) -> Decimal { Decimal(string: s)! }
    func testMoney() {
        XCTAssertEqual(Fmt.money(d("1234.5"), "GBP"), "£1,234.50"); XCTAssertEqual(Fmt.money(d("-2.005"), "GBP"), "-£2.01")
        XCTAssertEqual(Fmt.money(d("10"), "USD"), "$10.00"); XCTAssertEqual(Fmt.money(d("10"), "EUR"), "€10.00"); XCTAssertEqual(Fmt.money(d("10"), "JPY"), "10.00 JPY")
        XCTAssertEqual(Fmt.money(nil, "GBP"), "—"); XCTAssertEqual(Fmt.money(d("5"), "GBP", hide: true), "••••"); XCTAssertEqual(Fmt.money(d("123456.7"), "GBP", scale: 0), "£123,457")
    }
    func testSignedMoney() { XCTAssertEqual(Fmt.signedMoney(d("19.5"), "GBP"), "+£19.50"); XCTAssertEqual(Fmt.signedMoney(d("-1608.62"), "GBP"), "-£1,608.62"); XCTAssertEqual(Fmt.signedMoney(0, "GBP"), "£0.00"); XCTAssertEqual(Fmt.signedMoney(d("1"), "GBP", hide: true), "••••") }
    func testQuantityTrimsToFourDecimals() { XCTAssertEqual(Fmt.quantity(d("0.43181800")), "0.4318"); XCTAssertEqual(Fmt.quantity(d("114.519041")), "114.519"); XCTAssertEqual(Fmt.quantity(d("3")), "3"); XCTAssertEqual(Fmt.quantity(d("1234")), "1,234") }
    func testPercent() { XCTAssertEqual(Fmt.percent(d("44.41")), "44.41%"); XCTAssertEqual(Fmt.percent(d("5"), signed: true), "+5.00%"); XCTAssertEqual(Fmt.percentFromFraction(d("0.1079")), "10.79%"); XCTAssertEqual(Fmt.percentFromFraction(d("0.0952"), signed: true), "+9.52%") }
    func testPlural() { XCTAssertEqual(Fmt.plural(1, "position"), "1 position"); XCTAssertEqual(Fmt.plural(36, "listed position"), "36 listed positions"); XCTAssertEqual(Fmt.plural(2, "asset class", "asset classes"), "2 asset classes") }
    func testStampParsesServerTimestamps() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Fmt.stamp(iso: "2026-10-31T21:26:03Z", zone: utc), "31 Oct, 21:26")
        XCTAssertEqual(Fmt.stamp(iso: "2026-10-31T21:26:03.123456", zone: utc), "31 Oct, 21:26")   // no zone means UTC
        XCTAssertEqual(Fmt.stamp(iso: "2026-10-31T21:26:03+00:00", zone: utc), "31 Oct, 21:26"); XCTAssertEqual(Fmt.stamp(iso: nil), "—"); XCTAssertEqual(Fmt.stamp(iso: "garbage"), "—")
    }
}

final class ModelsTests: XCTestCase {
    func testMeFixture() { let me: Me = decodeFixture("me"); XCTAssertEqual(me.id, 7); XCTAssertEqual(me.username, "TestUser"); XCTAssertEqual(me.baseCurrency, "GBP") }
    func testDashboardFixtureDecodesDecimalsExactly() {
        let d: Dashboard = decodeFixture("dashboard")
        XCTAssertEqual(d.totalMarketValueBase, Decimal(string: "1000.50")); XCTAssertEqual(d.totalRealisedPnlBase, Decimal(string: "-10.10"))
        XCTAssertEqual(d.portfolioXirrAnnual, Decimal(string: "0.1079")); XCTAssertEqual(d.sectorAllocation.map(\.sector), ["Technology", "Health"])
        XCTAssertNil(d.manualListedMarketValueBase, "null stays nil"); XCTAssertFalse(d.rows.isEmpty)
    }
    func testUnknownKeysAndMissingKeysAreTolerated() {
        let d = try! JSONDecoder().decode(Dashboard.self, from: json(#"{"brand_new_field":{"a":1},"rows":[{"ticker":"A"}]}"#))
        XCTAssertEqual(d.baseCurrency, "GBP"); XCTAssertEqual(d.rows.first?.ticker, "A"); XCTAssertEqual(d.tickerMapAttentionCount, 0); XCTAssertNil(d.netWorthTotalBase)
    }
    func testDecimalsAcceptStringsAndNumbers() {
        let d = try! JSONDecoder().decode(Dashboard.self, from: json(#"{"total_cost_base":"800.25","total_pnl_base":200.25,"net_worth_total_base":123456789.12}"#))
        XCTAssertEqual(d.totalCostBase, Decimal(string: "800.25")); XCTAssertEqual(d.totalPnlBase, Decimal(string: "200.25")); XCTAssertEqual(d.netWorthTotalBase, Decimal(string: "123456789.12"))
    }
    func testHoldingRowsFromTheRealisticFixture() {
        let d: Dashboard = decodeFixture("holdings_dashboard")
        XCTAssertTrue(d.rows.contains { $0.source == "monzo" }); let m = d.rows.first { $0.manualHoldingId == 11 }
        XCTAssertEqual(m?.ticker, "MSFT"); XCTAssertEqual(m?.purchaseDate, "2025-01-02"); XCTAssertEqual(m?.costBaseGbp, Decimal(string: "50"))
    }
    func testMistypedFieldBecomesNilNotAFailure() {
        let d = try! JSONDecoder().decode(Dashboard.self, from: json(#"{"rows":"oops","total_cost_base":{"x":1}}"#))
        XCTAssertTrue(d.rows.isEmpty); XCTAssertNil(d.totalCostBase)
    }
}

final class HomeLogicTests: XCTestCase {
    private func d(_ s: String) -> Decimal { Decimal(string: s)! }
    func testListedPositionCountSkipsMonzoCashPropertyOtherAndSold() {
        let rows = [HoldingRow(ticker: "A", source: "t212"), HoldingRow(ticker: "B", source: "monzo"), HoldingRow(ticker: "C", source: "manual", assetKind: "cash"),
                    HoldingRow(ticker: "D", source: "manual", assetKind: "real_estate"), HoldingRow(ticker: "E", source: "manual", assetKind: "other"),
                    HoldingRow(ticker: "F", source: "manual", soldOutAt: "2025-01-01"), HoldingRow(ticker: "G", source: "manual", assetKind: "listed")]
        XCTAssertEqual(HomeLogic.listedPositionCount(rows), 2)
    }
    func testUnrealisedPct() {
        XCTAssertEqual(HomeLogic.unrealisedPct(pnl: d("19911.79"), cost: d("103059.83")), d("19.32")); XCTAssertEqual(HomeLogic.unrealisedPct(pnl: d("-5"), cost: d("40")), d("-12.5"))
        XCTAssertNil(HomeLogic.unrealisedPct(pnl: d("1"), cost: 0)); XCTAssertNil(HomeLogic.unrealisedPct(pnl: nil, cost: d("1")))
    }
    func testNonEquityGainNeedsLinesAndMaterialAmount() {
        var dash = Dashboard(nonEquityManualGainTotalBase: d("63757.56"), nonEquityManualBasisLines: 6, nonEquityManualAnnualizedPct: d("0.11836804"))
        XCTAssertEqual(HomeLogic.nonEquityGain(dash)?.gain, d("63757.56")); XCTAssertEqual(HomeLogic.nonEquityGain(dash)?.pct, d("11.836804"))
        dash.nonEquityManualBasisLines = 0; XCTAssertNil(HomeLogic.nonEquityGain(dash))
        dash.nonEquityManualBasisLines = 2; dash.nonEquityManualGainTotalBase = d("0.0000000001"); XCTAssertNil(HomeLogic.nonEquityGain(dash))
    }
    func testBucketLabels() { XCTAssertEqual(HomeLogic.bucketLabel("equity"), "Equities & funds"); XCTAssertEqual(HomeLogic.bucketLabel("real_estate"), "Property (net)"); XCTAssertEqual(HomeLogic.bucketLabel("cash"), "Cash savings"); XCTAssertEqual(HomeLogic.bucketLabel("some_new_bucket"), "Some new bucket") }
    func testInvestmentsSummaryInWebOrder() {
        let dash = Dashboard(totalMarketValueBase: d("10"), totalCostBase: nil, totalPnlBase: d("2"), totalRealisedPnlBase: d("-1"), portfolioXirrAnnual: d("0.1"), dividendIncomeBrokerCashBase: d("3"))
        XCTAssertEqual(HomeLogic.investmentsSummary(dash, hide: false), "Listed value: £10.00 · Realised P/L: -£1.00 · Unrealised P/L: +£2.00 · Dividend income: £3.00 · XIRR: +10.00%")
        XCTAssertEqual(HomeLogic.investmentsSummary(Dashboard(), hide: false), "—")
        XCTAssertEqual(HomeLogic.investmentsSummary(Dashboard(dividendIncomeTotalBase: d("4")), hide: false), "Dividend income: £4.00")
        let hidden = HomeLogic.investmentsSummary(Dashboard(totalMarketValueBase: d("12345.67")), hide: true); XCTAssertFalse(hidden.contains("12,345"))
    }
    func testAlertsSummary() {
        XCTAssertEqual(HomeLogic.alertsSummary(Dashboard(tickerMapAttentionCount: 2, manualBasisIncompleteCount: 3)), "3 incomplete lots · 2 tickers to confirm")
        XCTAssertEqual(HomeLogic.alertsSummary(Dashboard(manualBasisIncompleteCount: 1)), "1 incomplete lot"); XCTAssertEqual(HomeLogic.alertsSummary(Dashboard()), "")
    }
}
