import XCTest
@testable import Rushify

final class PerformanceLogicTests: XCTestCase {
    private func d(_ s: String) -> Decimal { Decimal(string: s)! }
    private let growth: PerformanceGrowth = decodeFixture("growth")
    private let dividends: PerformanceDividends = decodeFixture("dividends")

    // MARK: period options
    func testPeriodOptionsAndDefaultsMatchTheWeb() {
        typealias O = PerformancePeriodOptions
        XCTAssertEqual(O.growth("monthly"), [6, 12, 18, 24]); XCTAssertEqual(O.growth("yearly"), [3, 5, 8, 10])
        XCTAssertEqual(O.dividends("monthly"), [6, 12, 18, 24, 36]); XCTAssertEqual(O.dividends("yearly"), [3, 4, 5, 8, 10, 15])
        XCTAssertEqual(O.default("monthly"), 12); XCTAssertEqual(O.default("yearly"), 5)
        XCTAssertEqual(O.label("monthly", 12), "12 mo"); XCTAssertEqual(O.label("yearly", 5), "5 yr")
    }

    // MARK: wire format of the DTOs
    func testGrowthParsesDecimalsExactly() {
        XCTAssertEqual(growth.periods.count, 3)
        XCTAssertEqual(growth.periods[1].capitalGainBase, d("-300.50"))
        XCTAssertEqual(growth.periods[1].purchaseEvents.first?.label, "Alpha Corp")
        XCTAssertEqual(growth.periods.last?.totalGrowthBase, d("830.19"))
        XCTAssertEqual(growth.periods[1].brokers.first?.brokerLabel, "Broker X")
    }
    func testGrowthComponentsAddUpToTotal() {
        for p in growth.periods { XCTAssertEqual(p.totalGrowthBase, p.capitalGainBase! + p.incomeBase! + p.currencyGainBase!, p.label) }
    }
    func testBenchmarksAndDividendsParse() {
        let b: PerformanceBenchmarks = decodeFixture("benchmarks")
        XCTAssertEqual(b.portfolioReturnPct, d("7.33")); XCTAssertNil(b.series.last?.sp100Index); XCTAssertEqual(b.series.last?.portfolioIndex, 107.33)
        XCTAssertEqual(dividends.series.last?.kind, "forecast_forward"); XCTAssertEqual(dividends.symbols, ["AAA", "BBB"])
    }
    func testDailyFixtureParses() {
        let g: PerformanceGrowth = decodeFixture("growth_daily")
        XCTAssertTrue(g.compact); XCTAssertEqual(g.equityDaily?.count, 3); XCTAssertEqual(g.equityDaily?.last?.brokers.last?.brokerLabel, "Hargreaves")
        XCTAssertNil(growth.equityDaily)
    }
    func testLenientDecodingNeverThrows() throws {
        let g = try JSONDecoder().decode(PerformanceGrowth.self, from: json(#"{"periods":[{"label":5,"total_growth_base":12.5}],"equity_daily":"nope"}"#))
        XCTAssertEqual(g.periods.count, 1); XCTAssertEqual(g.periods[0].totalGrowthBase, d("12.5")); XCTAssertNil(g.equityDaily); XCTAssertEqual(g.baseCurrency, "GBP")
    }

    // MARK: growth maths
    func testGrowthSummaryAddsUpAndComponentsReconcile() {
        let s = PerformanceGrowthMath.summary(growth.periods)
        XCTAssertEqual(s.total, d("654.94")); XCTAssertEqual(s.price, d("299.50")); XCTAssertEqual(s.interaction, d("376.48"))
        XCTAssertEqual(s.income, d("17.00")); XCTAssertEqual(s.currency, d("-38.04"))
        XCTAssertEqual(s.total, s.price + s.interaction + s.income + s.currency)
    }
    func testSharesOfTotalUseOneDecimal() {
        let s = PerformanceGrowthMath.summary(growth.periods)
        XCTAssertEqual(s.share(s.price), "45.7% of total"); XCTAssertEqual(s.share(s.interaction), "57.5% of total"); XCTAssertEqual(s.share(s.currency), "-5.8% of total")
    }
    func testShareIsADashWhenTheTotalIsAboutZero() {
        XCTAssertEqual(PerformanceGrowthMath.summary([PerformanceGrowthPeriod(priceGainBase: d("5"), totalGrowthBase: 0)]).share(d("5")), "—")
    }
    func testStackSumNoteOnlyAppearsBeyondRounding() {
        var ok = PerformanceGrowthPeriod(priceGainBase: d("10"), interactionGainBase: d("1"), incomeBase: d("1"), currencyGainBase: d("-2"), totalGrowthBase: d("10.01"))
        XCTAssertEqual(PerformanceGrowthMath.stackSum(ok), d("10")); XCTAssertFalse(PerformanceGrowthMath.stackDiffers(ok))
        ok.totalGrowthBase = d("10.5"); XCTAssertTrue(PerformanceGrowthMath.stackDiffers(ok))
    }
    func testInteractionNoteExplainsTheRemainder() {
        XCTAssertTrue(PerformanceGrowthMath.interactionNote.contains("remainder") && PerformanceGrowthMath.interactionNote.contains("Interaction"))
    }

    // MARK: benchmarks
    func testPercentagePointGapAndWording() {
        typealias B = PerformanceBenchmarkMath
        XCTAssertEqual(B.points(d("7.33"), d("2.95")), d("4.38")); XCTAssertEqual(B.pointsText(d("4.38")), "+4.38 pp"); XCTAssertEqual(B.pointsText(d("-1.2")), "-1.20 pp")
        XCTAssertNil(B.points(nil, d("1"))); XCTAssertEqual(B.pointsText(nil), "—")
        XCTAssertEqual(B.verdict(d("1"), "FTSE 100"), "Portfolio total return exceeded FTSE 100 over the same dates.")
        XCTAssertEqual(B.verdict(d("-1"), "S&P 100 (^OEX)"), "Portfolio total return trailed S&P 100 (^OEX) over the same dates."); XCTAssertNil(B.verdict(nil, "x"))
        XCTAssertEqual(B.pointsText(0), "+0.00 pp"); XCTAssertEqual(B.pointsText(d("-0.001")), "0.00 pp")
        XCTAssertEqual(B.indexText(101.5), "101.50"); XCTAssertEqual(B.indexText(nil), "—")
    }

    // MARK: listed equity per broker
    private func pt(_ label: String, _ mv: String?, _ inv: String?, _ b: [(String, String, String)] = []) -> PerformanceEquityPoint {
        PerformanceEquityPoint(label: label, mv: mv.map(d), invested: inv.map(d), brokers: b.map { PerformanceGrowthBroker(brokerLabel: $0.0, listedEquityMvEndBase: d($0.1), investedCapitalEndBase: d($0.2)) })
    }
    private let labels = ["A", "B"]
    private var points: [PerformanceEquityPoint] { [
        pt("Jan", "300", "250", [("A", "100", "80"), ("B", "200", "170")]),
        pt("Feb", "330", "260", [("A", "130", "90"), ("B", "200", "170")]),
    ] }
    func testAllBrokersSelectedUsesTheAggregateFields() {
        let s = PerformanceEquityTrend.series(points, selected: ["A", "B"], allLabels: labels, totals: true)
        XCTAssertEqual(s.lines.map { $0.name }, ["MV", "Book", "A · mv", "A · book", "B · mv", "B · book"])
        XCTAssertEqual(s.lines[0].values, [d("300"), d("330")]); XCTAssertEqual(s.deltaMv, d("30"))
    }
    func testPartialSelectionSumsTheSelectedBrokersAndSaysSo() {
        let s = PerformanceEquityTrend.series(points, selected: ["A"], allLabels: labels, totals: true)
        XCTAssertEqual(s.lines.map { $0.name }, ["MV (selected)", "Book (selected)", "A · mv", "A · book"])
        XCTAssertEqual(s.lines[0].values, [d("100"), d("130")]); XCTAssertEqual(s.lines[1].values, [d("80"), d("90")]); XCTAssertEqual(s.deltaMv, d("30"))
    }
    func testBookLinesAreDashedAndTotalsCanBeHidden() {
        let s = PerformanceEquityTrend.series(points, selected: ["A", "B"], allLabels: labels, totals: false)
        XCTAssertTrue(s.lines.allSatisfy { !$0.isTotal })
        XCTAssertTrue(s.lines.filter { $0.name.hasSuffix("book") }.allSatisfy { $0.dashed }); XCTAssertTrue(s.lines.filter { $0.name.hasSuffix("mv") }.allSatisfy { !$0.dashed })
        XCTAssertEqual(s.deltaMv, d("30"))
    }
    func testEmptySelectionFallsBackToEveryBroker() { XCTAssertEqual(PerformanceEquityTrend.series(points, selected: [], allLabels: labels, totals: true).lines.count, 6) }
    func testMissingBrokerSliceGivesAGapNotAZero() {
        let s = PerformanceEquityTrend.series([pt("Jan", "10", "9", [("A", "10", "9")]), pt("Feb", "20", "18", [("A", "20", "18"), ("B", "5", "4")])], selected: ["A", "B"], allLabels: labels, totals: false)
        let b = s.lines.first { $0.name == "B · mv" }!
        XCTAssertNil(b.values[0]); XCTAssertEqual(b.values[1], d("5"))
    }
    func testPartialDetection() {
        XCTAssertTrue(PerformanceEquityTrend.isPartial(["A"], labels)); XCTAssertFalse(PerformanceEquityTrend.isPartial(["A", "B"], labels)); XCTAssertFalse(PerformanceEquityTrend.isPartial([], labels))
    }
    func testNoPointsNoDelta() { XCTAssertNil(PerformanceEquityTrend.series([], selected: ["A"], allLabels: labels, totals: true).deltaMv) }

    func testBrokerPickerLabelsIncludeOpenAndSoldManualBrokers() {
        let rows = (decodeFixture("holdings_dashboard") as Dashboard).rows
        let l = PerformanceBrokerLabels.listedEquity(rows)
        for want in ["AJ Bell · LISA", "Hargreaves", "Trading 212 · ISA", "Trading 212 · Invest"] { XCTAssertTrue(l.contains(want), want) }
        XCTAssertFalse(l.contains("Monzo"))
        XCTAssertEqual(l, l.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending })
    }

    // MARK: dividends
    func testStacksKeepActualAndEstimateApartPerTicker() {
        let s = PerformanceDividendStacks.build(dividends.series)
        XCTAssertEqual(s.tickers, ["AAA", "BBB"])
        let oct = s.bars[2]
        XCTAssertEqual(oct.actual, [d("20.00"), d("7.67")]); XCTAssertEqual(oct.forecast, [d("5.16"), 0])
        XCTAssertTrue(s.bars.last!.forecastZone); XCTAssertFalse(oct.forecastZone)
    }
    func testAverageIsTheMeanOfBarsOutsideTheForecastZone() { XCTAssertEqual(PerformanceDividendStacks.build(dividends.series).average, d("60.94")) }
    func testNoHistoryMeansNoAverage() {
        XCTAssertNil(PerformanceDividendStacks.build([PerformanceDividendPoint(label: "Next", kind: "forecast_forward", totalBase: d("5"), forecastZone: true)]).average)
    }
    func testSmallerPayersCollapseIntoOther() {
        let layers = (1...8).map { PerformanceDividendLayer(ticker: "T\($0)", layer: "actual", amountBase: Decimal($0)) }
        let s = PerformanceDividendStacks.build([PerformanceDividendPoint(label: "Jan", kind: "historical", totalBase: d("36"), layers: layers)])
        XCTAssertEqual(s.tickers, ["T8", "T7", "T6", "T5", "T4", "Other"])
        XCTAssertEqual(s.bars[0].actual.last, d("6"))
        XCTAssertEqual(s.bars[0].actual.reduce(0, +), d("36"))
    }
    func testNullAmountsCountAsZero() {
        let p = PerformanceDividendPoint(label: "Jan", layers: [PerformanceDividendLayer(ticker: "A", layer: "actual", amountBase: nil)])
        XCTAssertEqual(PerformanceDividendStacks.build([p]).bars[0].total, 0)
    }
    func testDividendMathSummaryAndContributors() {
        let s = PerformanceDividendMath.summary(dividends)
        XCTAssertEqual(s.received, d("182.83")); XCTAssertEqual(s.forecast, d("436.10"))
        let top = PerformanceDividendMath.topContributors(dividends.series[2], 5)
        XCTAssertEqual(top.map { $0.ticker }, ["AAA", "BBB"])
        XCTAssertEqual(top[0].amount, d("25.16"))          // actual 20.00 + forecast 5.16
        XCTAssertEqual(PerformanceDividendMath.axisLabel(dividends.series[3]), "Next 6m"); XCTAssertEqual(PerformanceDividendMath.axisLabel(dividends.series[0]), "Aug 2026")
    }
}
