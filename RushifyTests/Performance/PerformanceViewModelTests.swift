import XCTest
@testable import Rushify

@MainActor
final class PerformanceViewModelTests: XCTestCase {
    private var env: TestEnv!
    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    override func setUp() { env = TestEnv() }
    override func tearDown() { MockURLProtocol.reset() }

    private func route(_ routes: [String: () -> Data], delay: [String: TimeInterval] = [:]) {
        MockURLProtocol.reset { req in
            let url = req.url!.absoluteString
            for (k, v) in delay where url.contains(k) { Thread.sleep(forTimeInterval: v) }
            for (k, body) in routes where url.contains(k) { return .init(body: body()) }
            return .init(status: 404)
        }
    }
    private func until(_ what: String = "", timeout: TimeInterval = 6, _ cond: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond() && Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(cond(), "timed out: \(what)")
    }
    private func settle() async { try? await Task.sleep(nanoseconds: 300_000_000) }
    private func paths() -> [String] { MockURLProtocol.seen().map { $0.url!.absoluteString } }

    // MARK: growth
    func testGrowthLoadsAndCachesPerGranularity() async {
        route(["portfolio/growth": { fixture("growth") }])
        let vm = PerformanceGrowthModel(repo: env.repo); vm.load()
        await until { vm.state.data != nil }
        XCTAssertEqual(vm.state.data?.value.periods.count, 3)
        XCTAssertEqual(vm.state.data?.value.periods.last?.totalGrowthBase, d("830.19"))
        let m = await env.repo.performanceGrowthCached("monthly", 12), y = await env.repo.performanceGrowthCached("yearly", 5)
        XCTAssertNotNil(m); XCTAssertNil(y)
    }

    func testGrowthSendsGranularityAndCount() async {
        route(["portfolio/growth": { fixture("growth") }])
        let vm = PerformanceGrowthModel(repo: env.repo); vm.load(); await until { vm.state.data != nil }
        vm.select("yearly"); await until { vm.state.data != nil && vm.granularity == "yearly" }
        let p = paths().filter { $0.contains("growth") }
        XCTAssertTrue(p.contains { $0.contains("granularity=monthly") && $0.contains("count=12") && $0.contains("compact=false") }, "\(p)")
        XCTAssertTrue(p.contains { $0.contains("granularity=yearly") && $0.contains("count=5") }, "\(p)")
    }

    func testSlowReplyForOldParameterNeverOverwritesNewSelection() async {
        // Monthly answers slowly and yearly quickly; the late monthly body must be ignored.
        route(["granularity=monthly": { fixture("growth") },
               "granularity=yearly": { String(decoding: fixture("growth"), as: UTF8.self).replacingOccurrences(of: "\"granularity\":\"monthly\"", with: "\"granularity\":\"yearly\"").data(using: .utf8)! }],
              delay: ["granularity=monthly": 0.6])
        let vm = PerformanceGrowthModel(repo: env.repo); vm.load(); vm.select("yearly")
        await until { vm.state.data?.value.granularity == "yearly" }
        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertEqual(vm.state.data?.value.granularity, "yearly")
    }

    func testYearlyAsksForFiveYearsAndPeriodsSelectionResetsWhenGranularityChanges() async {
        route(["portfolio/growth": { fixture("growth") }])
        let vm = PerformanceGrowthModel(repo: env.repo); vm.load(); await until { vm.state.data != nil }
        vm.select(n: 24); await until { vm.state.data != nil && vm.count == 24 }
        XCTAssertEqual(vm.granularity, "monthly")
        vm.select("yearly"); XCTAssertEqual(vm.count, 5)
        vm.select("monthly"); XCTAssertEqual(vm.count, 12)
        await until { vm.state.data != nil }
        XCTAssertTrue(paths().contains { $0.contains("granularity=monthly") && $0.contains("count=24") })
        XCTAssertTrue(paths().contains { $0.contains("granularity=yearly") && $0.contains("count=5") })
    }

    func testSelectingTheSameParametersDoesNotReload() async {
        route(["portfolio/growth": { fixture("growth") }])
        let vm = PerformanceGrowthModel(repo: env.repo); vm.load(); await until { vm.state.data != nil }
        let before = paths().count
        vm.select("monthly"); vm.select(n: 12); await settle()
        XCTAssertEqual(paths().count, before); XCTAssertNotNil(vm.state.data)
    }

    // MARK: benchmarks
    func testBenchmarksRangeSwitchReloads() async {
        route(["portfolio/benchmarks": { fixture("benchmarks") }])
        let vm = PerformanceBenchmarksModel(repo: env.repo); vm.load(); await until { vm.state.data != nil }
        vm.select("week"); await until { vm.state.data != nil && vm.mode == "week" }
        let c = await env.repo.performanceBenchmarksCached("week", 12)
        XCTAssertNotNil(c); XCTAssertEqual(vm.mode, "week")
    }

    func testBenchmarkNullIndexValuesAreTolerated() async {
        route(["portfolio/benchmarks": { fixture("benchmarks") }])
        let vm = PerformanceBenchmarksModel(repo: env.repo); vm.load(); await until { vm.state.data != nil }
        XCTAssertNil(vm.state.data?.value.series.last?.sp100Index)
    }

    func testBenchmarksUseGranularityAndCountLikeTheWebAndRangeOnlyForDayWeek() async {
        route(["portfolio/benchmarks": { fixture("benchmarks") }])
        let vm = PerformanceBenchmarksModel(repo: env.repo); vm.load(); await until { vm.state.data != nil }
        vm.select("yearly"); await until { vm.state.data != nil && vm.mode == "yearly" }
        vm.select("day"); await until { vm.state.data != nil && vm.mode == "day" }
        let p = paths().filter { $0.contains("benchmarks") }
        XCTAssertTrue(p.contains { $0.contains("granularity=monthly") && $0.contains("count=12") && !$0.contains("range=") }, "\(p)")
        XCTAssertTrue(p.contains { $0.contains("granularity=yearly") && $0.contains("count=5") && !$0.contains("range=") }, "\(p)")
        XCTAssertTrue(p.contains { $0.contains("range=day") && !$0.contains("granularity=") && !$0.contains("count=") }, "\(p)")
    }

    // MARK: dividends
    func testDividendsDefaultToYearlyFiveYearsLikeTheWeb() async {
        route(["dividend-dashboard": { fixture("dividends") }])
        let vm = PerformanceDividendsModel(repo: env.repo); vm.load(); await until { vm.state.data != nil }
        XCTAssertEqual(vm.granularity, "yearly"); XCTAssertEqual(vm.count, 5)
        let q = paths().first { $0.contains("dividend-dashboard") }!
        XCTAssertTrue(q.contains("granularity=yearly") && q.contains("history_count=5") && !q.contains("symbol="), q)
    }

    func testDividendsSymbolFilterIsSentAndCachedSeparately() async {
        route(["dividend-dashboard": { fixture("dividends") }])
        let vm = PerformanceDividendsModel(repo: env.repo); vm.load(); await until { vm.state.data != nil }
        vm.select(symbol: .some("AAA")); await until { vm.state.data != nil && vm.symbol == "AAA" }
        let a = await env.repo.performanceDividendsCached("yearly", 5, symbol: "AAA"), all = await env.repo.performanceDividendsCached("yearly", 5, symbol: nil)
        XCTAssertNotNil(a); XCTAssertNotNil(all)
        XCTAssertTrue(paths().contains { $0.contains("symbol=AAA") })
        vm.select(symbol: .some(nil)); XCTAssertNil(vm.symbol)
        vm.select(n: 8); XCTAssertNil(vm.symbol, "a nil symbol argument keeps the filter state")
    }

    func testDividendSwitchToMonthlyResetsToTwelveMonthsAndKeepsFilter() async {
        route(["dividend-dashboard": { fixture("dividends") }])
        let vm = PerformanceDividendsModel(repo: env.repo); vm.load(); await until { vm.state.data != nil }
        vm.select(symbol: .some("BBB")); vm.select("monthly")
        XCTAssertEqual(vm.count, 12); XCTAssertEqual(vm.symbol, "BBB"); XCTAssertEqual(vm.granularity, "monthly")
    }

    // MARK: daily equity
    func testDailyRequestFormat() async {
        route(["portfolio/growth": { fixture("growth_daily") }])
        let vm = PerformanceEquityModel(repo: env.repo)
        vm.sync("monthly", 12, selected: ["AJ Bell · LISA", "Hargreaves"])
        await until { vm.state.data != nil }
        let url = URLComponents(string: paths().first { $0.contains("growth") }!)!
        let q = url.queryItems!.map { "\($0.name)=\($0.value ?? "")" }
        XCTAssertTrue(q.contains("equity_series_step=daily") && q.contains("compact=true") && q.contains("granularity=monthly") && q.contains("count=12"), "\(q)")
        XCTAssertEqual(url.queryItems!.filter { $0.name == "equity_brokers" }.map { $0.value }, ["AJ Bell · LISA", "Hargreaves"])
        XCTAssertEqual(vm.state.data?.value.equityDaily?.count, 3)
        let c = await env.repo.performanceGrowthDailyCached("monthly", 12, brokers: ["Hargreaves", "AJ Bell · LISA"])   // cache key sorts the brokers
        XCTAssertNotNil(c)
    }

    func testDailySyncOnlyReloadsWhenSomethingChanged() async {
        route(["portfolio/growth": { fixture("growth_daily") }])
        let vm = PerformanceEquityModel(repo: env.repo)
        vm.sync("monthly", 12, selected: ["A"]); await until { vm.state.data != nil }
        let n = paths().count
        vm.sync("monthly", 12, selected: ["A"]); await settle()
        XCTAssertEqual(paths().count, n, "same window and brokers with data loaded: no refetch")
        vm.sync("monthly", 12, selected: ["A", "B"]); await until { paths().count > n }
        vm.sync("yearly", 5, selected: ["A", "B"]); await until { paths().count > n + 1 }
    }

    func testEquityPrefsUpdate() {
        let vm = PerformanceEquityModel(repo: env.repo)
        XCTAssertEqual(vm.prefs, PerformanceEquityPrefs(daily: false, totals: true, selected: nil))
        vm.update { $0.daily = true; $0.selected = ["A"] }; vm.update { $0.totals.toggle() }
        XCTAssertEqual(vm.prefs, PerformanceEquityPrefs(daily: true, totals: false, selected: ["A"]))
    }

    // MARK: error mapping and offline
    func testServerErrorWithoutCacheShowsErrorAndNoData() async {
        MockURLProtocol.reset { _ in .init(status: 503, body: json("down")) }
        let vm = PerformanceGrowthModel(repo: env.repo); vm.load()
        await until { vm.state.error != nil }
        XCTAssertNil(vm.state.data); XCTAssertFalse(vm.state.loading)
    }

    func testOfflineKeepsSavedDataAndReportsTheError() async {
        route(["portfolio/growth": { fixture("growth") }])
        let first = PerformanceGrowthModel(repo: env.repo); first.load(); await until { first.state.data != nil }
        MockURLProtocol.reset { _ in .init(error: .notConnectedToInternet) }
        let vm = PerformanceGrowthModel(repo: env.repo); vm.load()
        await until { vm.state.error != nil }
        XCTAssertEqual(vm.state.data?.value.periods.count, 3, "saved copy stays on screen")
        XCTAssertEqual(vm.state.error, "No internet connection")
    }

    func testEmptyReplyNeverOverwritesGoodSavedData() async {
        route(["portfolio/growth": { fixture("growth") }])
        let first = PerformanceGrowthModel(repo: env.repo); first.load(); await until { first.state.data != nil }
        route(["portfolio/growth": { json(#"{"periods":[]}"#) }])
        let again = PerformanceGrowthModel(repo: env.repo); again.load()
        await until { again.state.data != nil && !again.state.loading }
        XCTAssertEqual(again.state.data?.value.periods.count, 3)
    }

    func testHttpErrorMessageIsMapped() async {
        MockURLProtocol.reset { _ in .init(status: 500, body: json(#"{"detail":"boom"}"#)) }
        do { _ = try await env.repo.performanceDividends("yearly", 5, symbol: nil); XCTFail("should throw") }
        catch { XCTAssertTrue(error is ApiError, "\(error)") }
    }

    // MARK: query builders
    func testQueryBuilders() {
        func s(_ q: [URLQueryItem]) -> [String] { q.map { "\($0.name)=\($0.value ?? "")" } }
        XCTAssertEqual(s(PerformanceQuery.growth("monthly", 12)), ["granularity=monthly", "count=12", "compact=false"])
        XCTAssertEqual(s(PerformanceQuery.benchmarks("week", 12)), ["range=week"])
        XCTAssertEqual(s(PerformanceQuery.benchmarks("yearly", 5)), ["granularity=yearly", "count=5"])
        XCTAssertEqual(s(PerformanceQuery.dividends("monthly", 36, symbol: "AAA")), ["granularity=monthly", "history_count=36", "symbol=AAA"])
        XCTAssertEqual(s(PerformanceQuery.growthDaily("yearly", 5, brokers: [])), ["granularity=yearly", "count=5", "compact=true", "equity_series_step=daily"])
    }
}
