import XCTest
@testable import Rushify

private func d(_ s: String) -> Decimal { Decimal(string: s)! }
private func route(_ table: [String: (Int, String)]) {
    MockURLProtocol.reset { req in
        let key = "\(req.httpMethod ?? "GET") \(req.url?.path ?? "")"
        guard let r = table[key] else { return .init(status: 404, body: json(#"{"detail":"no stub"}"#)) }
        return .init(status: r.0, body: json(r.1))
    }
}

final class HoldingsDtoTests: XCTestCase {
    func testRollupsFixtureDecodes() {
        let r = decodeFixture("rollups", as: HoldingsRollups.self)
        XCTAssertFalse(r.lines.isEmpty); XCTAssertFalse(r.accounts.isEmpty)
        let isa = r.accounts.first { $0.accountRef == "t212:isa" }!
        XCTAssertEqual(isa.realisedGainBaseSum, d("-644.93")); XCTAssertEqual(isa.xirrAnnual, d("0.1628")); XCTAssertEqual(isa.source, "t212")
    }
    func testLenientDecodingNeverFails() throws {
        let line = try JSONDecoder().decode(HoldingsRollupLine.self, from: json(#"{"source":5,"fill_row_count":"7","dividends_by_currency":[{"currency":"USD","amount":12.5},{"amount":"x"}],"open_quantity":1.25}"#))
        XCTAssertEqual(line.source, ""); XCTAssertEqual(line.fillRowCount, 7); XCTAssertEqual(line.dividendsByCurrency.count, 2)
        XCTAssertEqual(line.dividendsByCurrency[0].amount, d("12.5")); XCTAssertNil(line.dividendsByCurrency[1].amount); XCTAssertEqual(line.openQuantity, d("1.25"))
        let empty = try JSONDecoder().decode(HoldingsRollups.self, from: json("{}")); XCTAssertTrue(empty.lines.isEmpty && empty.accounts.isEmpty)
        let w = try JSONDecoder().decode(HoldingsWealthSeries.self, from: json("{}"))
        XCTAssertEqual(w.baseCurrency, "GBP"); XCTAssertEqual(w.minSnapshotsForChart, 5); XCTAssertEqual(w.minHoldDaysForChart, 365); XCTAssertTrue(w.assets.isEmpty)
        let a = try JSONDecoder().decode(HoldingsWealthAsset.self, from: json("{}")); XCTAssertTrue(a.showOnWealthChart); XCTAssertFalse(a.chartEligible)
    }
    func testWealthMoneyStaysDecimal() throws {
        let s = try JSONDecoder().decode(HoldingsWealthSnapshot.self, from: json(#"{"as_of":"2025-01-01","value_gbp":"100000.10","source":"manual"}"#))
        XCTAssertEqual(s.valueGbp, d("100000.10"))
    }
}

final class HoldingsRepositoryTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    private func text(_ name: String) -> String { String(data: fixture(name), encoding: .utf8)! }

    func testRollupsCallTheRightEndpointAndAreCached() async throws {
        let env = TestEnv()
        var before = await env.repo.holdingsRollupsCached(); XCTAssertNil(before)
        route(["GET /api/portfolio/holdings-rollups": (200, text("rollups"))])
        let fresh = try await env.repo.holdingsRollups()
        XCTAssertEqual(fresh.fetchedAt, env.now); XCTAssertFalse(fresh.value.lines.isEmpty)
        let r = MockURLProtocol.seen()[0]
        XCTAssertEqual(r.url?.absoluteString, "http://server.test:8040/api/portfolio/holdings-rollups"); XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-token")
        before = await env.repo.holdingsRollupsCached(); XCTAssertEqual(before?.value.accounts.count, fresh.value.accounts.count)
        MockURLProtocol.reset { _ in .init(error: .notConnectedToInternet) }
        do { _ = try await env.repo.holdingsRollups(); XCTFail() } catch { XCTAssertEqual(error as? ApiError, .network("No internet connection")) }
        let still = await env.repo.holdingsRollupsCached(); XCTAssertNotNil(still, "a failed refresh keeps the saved copy")
    }
    func testAnEmptyRollupsReplyNeverOverwritesGoodData() async throws {
        let env = TestEnv()
        route(["GET /api/portfolio/holdings-rollups": (200, text("rollups"))]); let first = try await env.repo.holdingsRollups()
        route(["GET /api/portfolio/holdings-rollups": (200, "{}")])
        let again = try await env.repo.holdingsRollups()
        XCTAssertEqual(again.value.lines.count, first.value.lines.count, "kept the previous rollups instead of the empty reply")
        let saved = await env.repo.holdingsRollupsCached(); XCTAssertFalse(saved!.value.lines.isEmpty)
    }
    func testRollupsCacheIsPerUser() async throws {
        let env = TestEnv()
        route(["GET /api/portfolio/holdings-rollups": (200, text("rollups"))]); _ = try await env.repo.holdingsRollups()
        env.session.saveLogin(token: "t2", me: Me(id: 99, username: "Other"))
        let other = await env.repo.holdingsRollupsCached(); XCTAssertNil(other)
    }
    func testWealthCallsTheRightEndpointAndIsCached() async throws {
        let env = TestEnv()
        route(["GET /api/portfolio/manual-wealth-series": (200, text("wealth"))])
        let w = try await env.repo.holdingsWealth()
        XCTAssertEqual(MockURLProtocol.seen()[0].url?.path, "/api/portfolio/manual-wealth-series"); XCTAssertEqual(w.value.assets.count, 3)
        let c = await env.repo.holdingsWealthCached(); XCTAssertEqual(c?.value.assets.count, 3)
    }
    func testSessionExpiryOnRollupsSignsOut() async {
        let env = TestEnv(); route(["GET /api/portfolio/holdings-rollups": (401, #"{"detail":"Not authenticated"}"#)])
        do { _ = try await env.repo.holdingsRollups(); XCTFail() } catch { XCTAssertEqual(error as? ApiError, .sessionExpired) }
        XCTAssertTrue(env.session.current.expired)
    }
}

@MainActor
final class HoldingsLoaderTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    private func text(_ name: String) -> String { String(data: fixture(name), encoding: .utf8)! }
    private func waitFor(_ cond: @MainActor () -> Bool, _ what: String) async {
        for _ in 0..<200 { if cond() { return }; try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("timed out: \(what)")
    }

    func testWealthLoaderIsHiddenUntilALineQualifies() async {
        let env = TestEnv()
        route(["GET /api/portfolio/manual-wealth-series": (200, #"{"base_currency":"GBP","assets":[{"manual_holding_id":3,"label":"Chip","asset_kind":"cash","chart_eligible":false,"snapshots":[]}]}"#)])
        let loader = HoldingsHomeWealthLoader(repo: env.repo)
        XCTAssertFalse(loader.isVisible); XCTAssertNil(loader.summary(hide: false))
        loader.load()
        await waitFor({ loader.state.data != nil }, "data")
        XCTAssertFalse(loader.isVisible); XCTAssertNil(loader.summary(hide: false))
    }
    func testWealthLoaderShowsSummaryOnceEligible() async {
        let env = TestEnv()
        route(["GET /api/portfolio/manual-wealth-series": (200, text("wealth"))])
        let loader = HoldingsHomeWealthLoader(repo: env.repo)
        loader.load()
        await waitFor({ loader.isVisible }, "visible")
        XCTAssertEqual(loader.summary(hide: false), "2 lines · £116,000 total."); XCTAssertEqual(loader.summary(hide: true), "2 lines · •••• total.")
    }
    func testWealthLoaderServesSavedCopyWhenOffline() async {
        let env = TestEnv()
        route(["GET /api/portfolio/manual-wealth-series": (200, text("wealth"))]); _ = try? await env.repo.holdingsWealth()
        MockURLProtocol.reset { _ in .init(error: .notConnectedToInternet) }
        let loader = HoldingsHomeWealthLoader(repo: env.repo)
        loader.load()
        await waitFor({ loader.state.error != nil }, "error")
        XCTAssertTrue(loader.isVisible, "saved data stays on screen"); XCTAssertEqual(loader.state.error, "No internet connection")
    }
    func testRollupsLoaderReadsCacheThenRefreshes() async {
        let env = TestEnv(); let repo = env.repo
        route(["GET /api/portfolio/holdings-rollups": (200, text("rollups"))]); _ = try? await repo.holdingsRollups()
        let loader = CachedLoader<HoldingsRollups>(read: { await repo.holdingsRollupsCached() }, fetch: { try await repo.holdingsRollups() })
        loader.load()
        await waitFor({ loader.state.data != nil && !loader.state.loading }, "loaded")
        XCTAssertFalse(loader.state.data!.value.lines.isEmpty); XCTAssertNil(loader.state.error)
    }
}
