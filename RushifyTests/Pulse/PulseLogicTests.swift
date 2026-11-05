import XCTest
@testable import Rushify

private func d(_ s: String) -> Decimal { Decimal(string: s)! }
private typealias F = PulseWatchlistFormat

final class PulseWatchlistFormatTests: XCTestCase {
    private let lists: PulseWatchlists = decodeFixture("watchlists")
    private var first: PulseWatchItem { lists.watchlists[0].items[0] }
    private var etf: PulseWatchItem { lists.watchlists[0].items[1] }

    func testValuationRatio() {
        XCTAssertEqual(F.valuationRatio(nil), "—"); XCTAssertEqual(F.valuationRatio(d("0")), "NM"); XCTAssertEqual(F.valuationRatio(d("-3")), "NM")
        XCTAssertEqual(F.valuationRatio(d("12.345")), "12.35"); XCTAssertEqual(F.valuationRatio(d("100")), "100"); XCTAssertEqual(F.valuationRatio(d("1234.6")), "1235")
    }
    func testRoeIsPercentNumberAndNegativeIsNm() {
        XCTAssertEqual(F.roe(d("23.52")), "23.52%"); XCTAssertEqual(F.roe(d("-4.2")), "NM"); XCTAssertEqual(F.roe(nil), "—"); XCTAssertEqual(F.roe(0), "0.00%")
    }
    func testCompactMoney() {
        XCTAssertEqual(F.compactMoney(d("1533278552064")), "1.53T"); XCTAssertEqual(F.compactMoney(d("38015200768")), "38.02B")
        XCTAssertEqual(F.compactMoney(d("12300000")), "12.30M"); XCTAssertEqual(F.compactMoney(d("12345")), "12.3K")
        XCTAssertEqual(F.compactMoney(d("950")), "950"); XCTAssertEqual(F.compactMoney(d("-2500000")), "-2.50M"); XCTAssertEqual(F.compactMoney(nil), "—")
    }
    func testNetCashLines() {
        XCTAssertEqual(F.netCashLine(d("38015200768")), "Net cash 38.02B"); XCTAssertEqual(F.netCashLine(d("-2500000")), "Net debt 2.50M")
        XCTAssertEqual(F.netCashLine(0), "Net cash neutral"); XCTAssertNil(F.netCashLine(nil))
    }
    func testIndustryHintNeedsTwoPeersAndAPositiveMedian() {
        XCTAssertEqual(F.industryHint(d("61.3867"), 2), "ind 61.4x (2)"); XCTAssertEqual(F.industryHint(d("150.2"), 3), "ind 150x (3)")
        XCTAssertNil(F.industryHint(d("61"), 1)); XCTAssertNil(F.industryHint(0, 5)); XCTAssertNil(F.industryHint(nil, 5))
    }
    func testPeTextShowsForwardOnlyWhenItDiffers() {
        XCTAssertEqual(F.peText(first), "62.74 / 49.68 fwd")
        var same = first; same.forwardPeRatio = d("62.74"); XCTAssertEqual(F.peText(same), "62.74")
        var none = first; none.forwardPeRatio = nil; XCTAssertEqual(F.peText(none), "62.74")
        XCTAssertEqual(F.peText(etf), "NM")
    }
    func testDividendYieldFractionsAreScaledLikeTheWeb() {
        XCTAssertEqual(F.dividendPct(d("0.0067")), "0.67%"); XCTAssertEqual(F.dividendPct(d("1")), "100.00%")
        XCTAssertEqual(F.dividendPct(d("1.2")), "1.20%"); XCTAssertEqual(F.dividendPct(nil), "—")
    }
    func testIndexLikeTag() {
        XCTAssertTrue(F.isIndexLike("ETF")); XCTAssertTrue(F.isIndexLike("mutualfund")); XCTAssertFalse(F.isIndexLike("EQUITY")); XCTAssertFalse(F.isIndexLike(nil))
    }
    func testRangeAndPriceAndReturn() {
        XCTAssertEqual(F.range52(first.week52Low, first.week52High), "1,259–1,575"); XCTAssertEqual(F.range52(nil, nil), "—")
        XCTAssertEqual(F.price(first.lastPrice, "INR"), "1,506.50 INR"); XCTAssertEqual(F.price(nil, "INR"), "—")
        XCTAssertEqual(F.returnText(first.changePct), "+2.29%"); XCTAssertEqual(F.returnText(etf.changePct), "-1.50%"); XCTAssertEqual(F.returnText(nil), "—")
        XCTAssertEqual(F.percentPlain(d("-0.001")), "0.00%", "no negative zero")
    }
    func testFixtureParsesTheFullMetricSet() {
        XCTAssertEqual(first.revenueGrowthPct, d("14.10")); XCTAssertEqual(first.industryPeerCount, 2); XCTAssertNil(first.pegRatio)
        XCTAssertTrue(first.fetchNews); XCTAssertFalse(etf.fetchNews)
        XCTAssertEqual(F.industryHint(first.industryPbMedian, first.industryPeerCount), "ind 13.2x (2)")
        XCTAssertEqual(F.compactMoney(first.netCash), "38.02B"); XCTAssertEqual(F.compactMoney(first.marketCap), "1.53T")
        XCTAssertEqual(F.roe(first.roe), "23.52%"); XCTAssertEqual(F.percentPlain(first.profitMargin), "16.77%"); XCTAssertEqual(F.dividendPct(first.dividendYield), "0.67%")
        XCTAssertEqual(F.valuationRatio(etf.debtToEquity), "150"); XCTAssertEqual(F.netCashLine(etf.netCash), "Net debt 2.50M")
        XCTAssertEqual(lists.maxWatchlists, 5); XCTAssertEqual(lists.maxItemsPerWatchlist, 30); XCTAssertEqual(lists.cache.cacheHours, 2)
    }
    func testModelsAreLenientAndDecimalsExact() throws {
        let w = try JSONDecoder().decode(PulseWatchlists.self, from: json("{}"))
        XCTAssertEqual(w, PulseWatchlists())
        let it = try JSONDecoder().decode(PulseWatchItem.self, from: json(#"{"yahoo_symbol":"X","last_price":12.5,"market_cap":"1533278552064","fetch_news":"junk"}"#))
        XCTAssertEqual(it.lastPrice, d("12.5")); XCTAssertEqual(it.marketCap, d("1533278552064")); XCTAssertFalse(it.fetchNews)
        XCTAssertEqual(try JSONDecoder().decode(PulseNews.self, from: json("{}")), PulseNews())
        XCTAssertEqual(try JSONDecoder().decode(PulseRadar.self, from: json("{}")).scoredMvPct, 100)
    }
}

final class PulseWatchlistRulesTests: XCTestCase {
    private let lists: PulseWatchlists = decodeFixture("watchlists")

    func testCreateRules() {
        let w = lists
        XCTAssertTrue(PulseWatchlistRules.canCreate(w, "  Tech  ")); XCTAssertFalse(PulseWatchlistRules.canCreate(w, "   "))
        XCTAssertFalse(PulseWatchlistRules.canCreate(w, String(repeating: "x", count: 65))); XCTAssertTrue(PulseWatchlistRules.canCreate(w, String(repeating: "x", count: 64)))
        var full = w; full.maxWatchlists = 2
        XCTAssertFalse(PulseWatchlistRules.canCreate(full, "a")); XCTAssertTrue(PulseWatchlistRules.atListCap(full))
        full.limitsUnlimited = true; XCTAssertTrue(PulseWatchlistRules.canCreate(full, "a")); XCTAssertFalse(PulseWatchlistRules.atListCap(full))
        XCTAssertTrue(PulseWatchlistRules.canCreate(nil, "a")); XCTAssertFalse(PulseWatchlistRules.atListCap(nil))
    }
    func testItemCapNewsCountAndSearchable() {
        let l = lists.watchlists[0]
        var w = lists
        XCTAssertFalse(PulseWatchlistRules.atItemCap(w, l))
        w.maxItemsPerWatchlist = 2; XCTAssertTrue(PulseWatchlistRules.atItemCap(w, l))
        w.limitsUnlimited = true; XCTAssertFalse(PulseWatchlistRules.atItemCap(w, l))
        XCTAssertEqual(PulseWatchlistRules.newsCount(l), 1)
        XCTAssertTrue(PulseWatchlistRules.hasAnyItems(lists)); XCTAssertFalse(PulseWatchlistRules.hasAnyItems(PulseWatchlists()))
        XCTAssertTrue(PulseWatchlistRules.searchable("vo")); XCTAssertFalse(PulseWatchlistRules.searchable(" v ")); XCTAssertFalse(PulseWatchlistRules.searchable(""))
    }
    func testRefreshMessagesMatchTheWebWording() {
        func msg(_ r: PulseWatchlistRefresh) -> String { PulseRefreshMessage.of(r) }
        XCTAssertEqual(msg(.init(refreshed: 0, allFresh: true)), "Up to date (within 2h).")
        XCTAssertEqual(msg(.init(refreshed: 1)), "Refreshed 1 symbol. Open Pulse → News and tap Refresh there for headlines.")
        XCTAssertEqual(msg(.init(refreshed: 3)), "Refreshed 3 symbols. Open Pulse → News and tap Refresh there for headlines.")
        XCTAssertEqual(msg(.init(refreshed: 0, allFresh: false)), "No symbols to refresh.")
        XCTAssertTrue(msg(.init(refreshed: 2, errors: ["x"])).hasSuffix("1 could not be refreshed."))
    }
}

final class PulseNewsTextTests: XCTestCase {
    func testDecodesEntitiesAndTags() {
        XCTAssertEqual(PulseNewsText.plain("A &amp; B &lt;C&gt; it&#39;s"), "A & B <C> it's")
        XCTAssertEqual(PulseNewsText.plain("<b>x</b>&nbsp;&nbsp;y"), "x y")
        XCTAssertEqual(PulseNewsText.plain("&#233;"), "é")
        XCTAssertEqual(PulseNewsText.plain("&#xE9;&#x1F600;"), "é😀")
        XCTAssertEqual(PulseNewsText.plain("&#99999999; stays"), "&#99999999; stays")
        XCTAssertEqual(PulseNewsText.plain("a\u{00A0}\u{00A0}b\n c"), "a b c")
    }
    func testHidesSummaryThatRepeatsTitle() {
        let t = "100 years of stock market history shows why picking winners is very difficult - AJ Bell"
        XCTAssertNil(PulseNewsText.summary(t, "100 years of stock market history shows why picking winners is very difficult&nbsp;&nbsp;AJ Bell", "AJ Bell"))
        XCTAssertNil(PulseNewsText.summary("Same headline", "Same headline&nbsp;&nbsp;", nil))
        XCTAssertNil(PulseNewsText.summary("Same headline", "Same headline - Reuters", "Reuters"))
    }
    func testKeepsRealSummary() {
        XCTAssertEqual(PulseNewsText.summary("Headline", "More detail here.", "Reuters"), "More detail here.")
        XCTAssertEqual(PulseNewsText.summary("Headline", "Headline and more context", "Reuters"), "Headline and more context")
        XCTAssertNil(PulseNewsText.summary("Headline", "   ", nil)); XCTAssertNil(PulseNewsText.summary("Headline", nil, nil))
    }
    func testSourceLabels() {
        XCTAssertEqual(pulseSourceLabel("yahoo"), "Yahoo"); XCTAssertEqual(pulseSourceLabel("google"), "Google News")
        XCTAssertEqual(pulseSourceLabel("Reuters"), "Reuters"); XCTAssertNil(pulseSourceLabel(nil)); XCTAssertNil(pulseSourceLabel(""))
    }
    func testOnlyHttpLinksAreOpened() {
        XCTAssertEqual(PulseSafeUrl.httpOrNull("https://example.com/a?b=1")?.absoluteString, "https://example.com/a?b=1")
        XCTAssertEqual(PulseSafeUrl.httpOrNull("  http://news.example.org  ")?.absoluteString, "http://news.example.org/")
        XCTAssertEqual(PulseSafeUrl.httpOrNull("HTTPS://EXAMPLE.com")?.absoluteString, "https://example.com/")
        XCTAssertNotNil(PulseSafeUrl.httpOrNull("https://news.google.com/rss/articles/CBMi?oc=5"))
        for bad in ["javascript:alert(1)", "intent://x", "file:///etc/passwd", "data:text/html,x", "content://a/b", "example.com/a", "", "https://", "http://a.com/\u{0007}x", nil] {
            XCTAssertNil(PulseSafeUrl.httpOrNull(bad), bad ?? "nil")
        }
    }
    func testEmptyNewsMessagesAndGroupOpening() {
        XCTAssertTrue(PulseNewsView.emptyText(symbols: []).hasPrefix("No symbols to fetch yet"))
        XCTAssertTrue(PulseNewsView.emptyText(symbols: ["AAA", "BBB"]).hasPrefix("No headlines in the current window for AAA, BBB."))
        XCTAssertTrue(PulseNewsView.emptyText(symbols: (1...8).map { "S\($0)" }).contains("S1, S2, S3, S4, S5, S6 (+2 more)."))
        XCTAssertTrue(PulseNewsView.isOpen(key: "A", index: 0, open: [], filter: nil), "first card opens by default")
        XCTAssertFalse(PulseNewsView.isOpen(key: "B", index: 1, open: [], filter: nil))
        XCTAssertFalse(PulseNewsView.isOpen(key: "A", index: 0, open: ["B"], filter: nil))
        XCTAssertTrue(PulseNewsView.isOpen(key: "B", index: 1, open: ["B"], filter: nil))
        XCTAssertTrue(PulseNewsView.isOpen(key: "B", index: 0, open: [], filter: "B"), "a filtered company is always open")
    }
}

final class PulseRadarTests: XCTestCase {
    private let radar: PulseRadar = decodeFixture("radar")

    func testParsesBucketsCoverageAndAccounts() {
        let r = radar
        XCTAssertEqual(r.dimensions.count, 5); XCTAssertEqual(r.healthScore, d("2.99")); XCTAssertEqual(r.healthMax, 5)
        XCTAssertEqual(r.ratingBuckets.count, 5); XCTAssertEqual(r.ratingBuckets[0].tickers, ["AAA", "BBB"])
        XCTAssertEqual(r.scoredMvPct, 94); XCTAssertEqual(r.notCoveredMvPct, 5); XCTAssertEqual(r.indexFundMvPct, 1); XCTAssertEqual(r.coveredPositionCount, 2)
        XCTAssertEqual(r.accounts.count, 2); XCTAssertEqual(r.accounts[1].positionCount, 2); XCTAssertEqual(r.accounts[0].listedMvBase, d("1000.50"))
        XCTAssertEqual(r.rewards.map(\.text), ["Up 22%"]); XCTAssertEqual(r.risks.map(\.text), ["Debt"]); XCTAssertNil(r.message)
    }
    func testScoreBandsMatchTheWeb() {
        XCTAssertEqual(PulseRadarColors.scoreHex(72), 0x22C55E); XCTAssertEqual(PulseRadarColors.scoreHex(58), 0x84CC16)
        XCTAssertEqual(PulseRadarColors.scoreHex(45), 0xEAB308); XCTAssertEqual(PulseRadarColors.scoreHex(32), 0xF97316); XCTAssertEqual(PulseRadarColors.scoreHex(31), 0xEF4444)
        XCTAssertEqual(PulseRadarColors.bucketHex("index_fund"), 0x6366F1); XCTAssertEqual(PulseRadarColors.bucketHex("unknown"), 0x64748B)
        XCTAssertEqual(PulseRadarColors.bucketHex("strong_buy"), 0x15803D)
    }
    func testGaugeFractionAndRadarGeometry() {
        XCTAssertEqual(PulseChartMath.gaugeFraction(score: 3, max: 5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PulseChartMath.gaugeFraction(score: 0, max: 5), 0); XCTAssertEqual(PulseChartMath.gaugeFraction(score: 9, max: 5), 1)
        XCTAssertEqual(PulseChartMath.gaugeFraction(score: 3, max: 1), 0)
        let top = PulseChartMath.radarPoint(center: CGPoint(x: 100, y: 100), radius: 50, i: 0, n: 5, f: 1)
        XCTAssertEqual(top.x, 100, accuracy: 1e-9); XCTAssertEqual(top.y, 50, accuracy: 1e-9)
        let half = PulseChartMath.radarPoint(center: CGPoint(x: 100, y: 100), radius: 50, i: 0, n: 5, f: 0.5)
        XCTAssertEqual(half.y, 75, accuracy: 1e-9)
    }
}
