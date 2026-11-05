import XCTest
@testable import Rushify

private typealias Stub = MockURLProtocol.Stub
private func bodyOf(_ r: URLRequest) -> [String: Any] {
    let data = r.httpBody ?? r.httpBodyStream.map { s -> Data in
        s.open(); defer { s.close() }
        var d = Data(); var buf = [UInt8](repeating: 0, count: 512)
        while s.hasBytesAvailable { let n = s.read(&buf, maxLength: 512); if n <= 0 { break }; d.append(buf, count: n) }
        return d
    } ?? Data()
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}
private func seen(_ method: String, _ path: String) -> [URLRequest] { MockURLProtocol.seen().filter { $0.httpMethod == method && $0.url?.path == path } }
private func ok(_ s: String, _ status: Int = 200) -> Stub { Stub(status: status, body: json(s)) }
private let listsPath = "/api/pulse/watchlists"

/// Routes by "METHOD /path"; anything unrouted is a 404.
private func route(_ table: [String: (URLRequest) -> Stub]) {
    MockURLProtocol.reset { req in table["\(req.httpMethod ?? "GET") \(req.url?.path ?? "")"]?(req) ?? Stub(status: 404) }
}
@MainActor private func waitUntil(_ what: String = "", timeout: Double = 5, _ cond: () -> Bool) async {
    let end = Date().addingTimeInterval(timeout)
    while !cond() && Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
    XCTAssertTrue(cond(), "timed out: \(what)")
}

final class PulseRepositoryTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }

    func testRadarIsRequestedWithScopeAndCachedPerScope() async throws {
        let env = TestEnv(); route(["GET /api/pulse/radar": { _ in .init(body: fixture("radar")) }])
        _ = try await env.repo.pulseRadar("overall")
        let q = MockURLProtocol.seen()[0].url?.query
        XCTAssertEqual(q, "scope=overall")
        let cachedOverall = await env.repo.pulseRadarCached("overall"), cachedOther = await env.repo.pulseRadarCached("other")
        XCTAssertNotNil(cachedOverall); XCTAssertNil(cachedOther)
        XCTAssertEqual(MockURLProtocol.seen()[0].value(forHTTPHeaderField: "Authorization"), "Bearer jwt-token")
    }
    func testScopeWithColonIsSentIntact() async throws {
        let env = TestEnv(); route(["GET /api/pulse/radar": { _ in .init(body: fixture("radar")) }])
        _ = try await env.repo.pulseRadar("t212:isa")
        let comps = URLComponents(url: MockURLProtocol.seen()[0].url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(comps?.queryItems?.first?.value, "t212:isa")
    }
    func testNewsForceAddsRefreshTrueAndNormalOmitsIt() async throws {
        let env = TestEnv(); route(["GET /api/pulse/news": { _ in ok(#"{"groups":[{"key":"A","label":"A","items":[{"id":1,"title":"t"}]}]}"#) }])
        _ = try await env.repo.pulseNews()
        _ = try await env.repo.pulseNews(force: true)
        let qs = MockURLProtocol.seen().map { $0.url?.query }
        XCTAssertEqual(qs, [nil, "refresh=true"])
    }
    func testEmptyRepliesNeverOverwriteGoodSavedData() async throws {
        let env = TestEnv(); var body = fixture("radar")
        MockURLProtocol.reset { _ in .init(body: body) }
        let good = try await env.repo.pulseRadar("overall")
        XCTAssertEqual(good.value.dimensions.count, 5)
        body = json(#"{"scope_key":"overall","dimensions":[]}"#)
        let again = try await env.repo.pulseRadar("overall")
        XCTAssertEqual(again.value.dimensions.count, 5, "empty reply keeps the saved radar")
        // news and watchlists follow the same rule
        MockURLProtocol.reset { req in req.url?.path.hasSuffix("news") == true ? ok(#"{"groups":[]}"#) : ok(#"{"watchlists":[]}"#) }
        let n0: Cached<PulseNews>? = nil, w0: Cached<PulseWatchlists>? = nil
        XCTAssertNil(n0); XCTAssertNil(w0)
        MockURLProtocol.reset { req in req.url?.path.hasSuffix("news") == true ? ok(#"{"groups":[{"key":"A","label":"A","items":[{"id":1,"title":"t"}]}]}"#) : ok(listsJson("India", "100.00")) }
        _ = try await env.repo.pulseNews(); _ = try await env.repo.pulseWatchlists()
        MockURLProtocol.reset { req in req.url?.path.hasSuffix("news") == true ? ok(#"{"groups":[]}"#) : ok(#"{"watchlists":[]}"#) }
        let n = try await env.repo.pulseNews(), w = try await env.repo.pulseWatchlists()
        XCTAssertEqual(n.value.groups.count, 1); XCTAssertEqual(w.value.watchlists.count, 1)
    }
    func testSymbolSearchSendsTheQuery() async throws {
        let env = TestEnv(); route(["GET /api/portfolio/symbol-search": { _ in ok(#"[{"symbol":"VOD.L","name":"Vodafone","exchange":"LSE","currency":null,"type":"EQUITY"}]"#) }])
        let hits = try await env.repo.pulseSymbolSearch("vod")
        XCTAssertEqual(hits.first?.symbol, "VOD.L"); XCTAssertEqual(hits.first?.exchange, "LSE"); XCTAssertNil(hits.first?.currency)
        XCTAssertEqual(MockURLProtocol.seen()[0].url?.query, "q=vod")
    }
}

private func listsJson(_ name: String, _ price: String) -> String {
    #"{"watchlists":[{"id":1,"name":"\#(name)","items":[{"id":1,"yahoo_symbol":"AAA","last_price":"\#(price)","currency":"USD"}]}]}"#
}

@MainActor
final class PulseLoadersTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }

    func testRadarModelLoadsAndSwitchingScopeReloadsWithTheNewScope() async {
        let env = TestEnv()
        route(["GET /api/pulse/radar": { req in
            let scope = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
            return Stub(body: json(String(decoding: fixture("radar"), as: UTF8.self).replacingOccurrences(of: "\"scope_key\": \"overall\"", with: "\"scope_key\": \"\(scope)\"")))
        }])
        let vm = PulseRadarModel(repo: env.repo)
        vm.load(); await waitUntil("radar loaded") { vm.state.data != nil && !vm.state.loading }
        XCTAssertEqual(vm.state.data?.value.scopeKey, "overall")
        vm.select("t212:isa")
        await waitUntil("scope loaded") { vm.state.data?.value.scopeKey == "t212:isa" }
        vm.select("t212:isa")   // same scope is a no-op
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(MockURLProtocol.seen().count, 2)
    }
    func testSlowReplyForOldScopeNeverOverwritesTheNewSelection() async {
        let env = TestEnv()
        route(["GET /api/pulse/radar": { req in
            let scope = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
            if scope == "overall" { Thread.sleep(forTimeInterval: 0.6) }
            return Stub(body: json(String(decoding: fixture("radar"), as: UTF8.self).replacingOccurrences(of: "\"scope_key\": \"overall\"", with: "\"scope_key\": \"\(scope)\"")))
        }])
        let vm = PulseRadarModel(repo: env.repo)
        vm.load(); vm.select("other")
        await waitUntil("new scope") { vm.state.data?.value.scopeKey == "other" }
        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertEqual(vm.state.data?.value.scopeKey, "other")
    }
    func testNewsModelForceRefreshAsksForRefreshOnceThenGoesBackToNormal() async {
        let env = TestEnv()
        route(["GET /api/pulse/news": { _ in ok(#"{"groups":[{"key":"A","label":"A","items":[{"id":1,"title":"t"}]}],"symbols":["A"]}"#) }])
        let vm = PulseNewsModel(repo: env.repo)
        vm.load(); await waitUntil("news") { vm.state.data != nil && !vm.state.loading }
        await vm.forceRefresh(); await vm.refresh()
        XCTAssertEqual(MockURLProtocol.seen().map { $0.url?.query }, [nil, "refresh=true", nil])
    }
    func testOfflineKeepsTheSavedNewsAndShowsTheError() async {
        let env = TestEnv()
        route(["GET /api/pulse/news": { _ in ok(#"{"groups":[{"key":"A","label":"A","items":[{"id":1,"title":"t"}]}]}"#) }])
        let first = PulseNewsModel(repo: env.repo); first.load(); await waitUntil("saved") { first.state.data != nil && !first.state.loading }
        MockURLProtocol.reset { _ in Stub(error: .notConnectedToInternet) }
        let vm = PulseNewsModel(repo: env.repo); vm.load()
        await waitUntil("offline") { vm.state.error != nil }
        XCTAssertNotNil(vm.state.data, "saved headlines stay on screen"); XCTAssertEqual(vm.state.error, "No internet connection")
    }
}

@MainActor
final class PulseWatchlistsModelTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    private let fixtureLists = String(decoding: fixture("watchlists"), as: UTF8.self)

    private func loaded(_ extra: [String: (URLRequest) -> Stub] = [:], lists: String? = nil, env: TestEnv = TestEnv(), debounce: UInt64 = 20) async -> (PulseWatchlistsModel, TestEnv) {
        var table: [String: (URLRequest) -> Stub] = ["GET \(listsPath)": { _ in ok(lists ?? self.fixtureLists) }]
        table.merge(extra) { $1 }
        route(table)
        let vm = PulseWatchlistsModel(repo: env.repo, debounceMillis: debounce)
        vm.load(); await waitUntil("lists loaded") { vm.state.data != nil && !vm.state.loading }
        return (vm, env)
    }

    func testCreateSendsTheTrimmedNameAndReReadsTheLists() async {
        let (vm, env) = await loaded(["POST \(listsPath)": { _ in ok(#"{"id":3,"name":"Tech ideas","items":[]}"#) }])
        let v0 = env.repo.events.version
        await vm.createList("  Tech ideas  ")
        XCTAssertEqual(vm.edit.message, "List created."); XCTAssertNil(vm.edit.error)
        let posts = seen("POST", listsPath)
        XCTAssertEqual(posts.count, 1); XCTAssertEqual(bodyOf(posts[0]) as NSDictionary, ["name": "Tech ideas"] as NSDictionary)
        XCTAssertGreaterThanOrEqual(seen("GET", listsPath).count, 2)
        XCTAssertEqual(env.repo.events.version, v0 + 1, "a successful write notifies the app")
    }
    func testCreateIsBlockedAtTheCapWithNoRequest() async {
        let (vm, _) = await loaded(lists: fixtureLists.replacingOccurrences(of: "\"max_watchlists\": 5", with: "\"max_watchlists\": 2"))
        await vm.createList("One more")
        XCTAssertEqual(vm.edit.error, "Maximum lists reached."); XCTAssertEqual(seen("POST", listsPath).count, 0)
    }
    func testBlankNameIsRejectedLocally() async {
        let (vm, _) = await loaded()
        await vm.createList("   ")
        XCTAssertTrue(vm.edit.error!.contains("Enter a name")); XCTAssertEqual(seen("POST", listsPath).count, 0)
    }
    func testDeleteListCallsTheEndpointOnce() async {
        let (vm, _) = await loaded(["DELETE \(listsPath)/2": { _ in Stub(status: 204) }])
        await vm.deleteList(2)
        XCTAssertEqual(vm.edit.message, "List deleted."); XCTAssertEqual(seen("DELETE", "\(listsPath)/2").count, 1)
    }
    func testAddSymbolSendsNameExchangeAndTheNewsChoice() async {
        let (vm, _) = await loaded(["POST \(listsPath)/2/items": { _ in ok(#"{"id":2,"name":"List-1","items":[]}"#) }])
        await vm.addSymbol(vm.state.data!.value.watchlists[1], SymbolHit(symbol: "VOD.L", name: "Vodafone Group", exchange: "LSE"), fetchNews: true)
        XCTAssertEqual(vm.edit.message, "VOD.L added.")
        let b = bodyOf(seen("POST", "\(listsPath)/2/items")[0])
        XCTAssertEqual(b as NSDictionary, ["yahoo_symbol": "VOD.L", "company_name": "Vodafone Group", "exchange": "LSE", "fetch_news": true] as NSDictionary)
    }
    func testAddSymbolWithoutNameSendsExplicitNulls() async {
        let (vm, _) = await loaded(["POST \(listsPath)/2/items": { _ in ok(#"{"id":2,"name":"List-1","items":[]}"#) }])
        await vm.addSymbol(vm.state.data!.value.watchlists[1], SymbolHit(symbol: "X"), fetchNews: false)
        let b = bodyOf(seen("POST", "\(listsPath)/2/items")[0])
        XCTAssertTrue(b["company_name"] is NSNull); XCTAssertTrue(b["exchange"] is NSNull); XCTAssertEqual(b["fetch_news"] as? Bool, false)
    }
    func testAddIsBlockedWhenTheListIsFull() async {
        let (vm, _) = await loaded(lists: fixtureLists.replacingOccurrences(of: "\"max_items_per_watchlist\": 30", with: "\"max_items_per_watchlist\": 2"))
        await vm.addSymbol(vm.state.data!.value.watchlists[0], SymbolHit(symbol: "X"), fetchNews: true)
        XCTAssertEqual(vm.edit.error, "This list is full."); XCTAssertEqual(seen("POST", "\(listsPath)/1/items").count, 0)
    }
    func testToggleNewsFlipsTheCurrentValue() async {
        let (vm, _) = await loaded(["PATCH \(listsPath)/1/items/1": { _ in ok(#"{"id":1,"name":"India","items":[]}"#) }, "PATCH \(listsPath)/1/items/2": { _ in ok(#"{"id":1,"name":"India","items":[]}"#) }])
        let l = vm.state.data!.value.watchlists[0]
        await vm.toggleNews(l, l.items[0])
        XCTAssertEqual(bodyOf(seen("PATCH", "\(listsPath)/1/items/1")[0]) as NSDictionary, ["fetch_news": false] as NSDictionary)
        XCTAssertNil(vm.edit.error); XCTAssertNil(vm.edit.message)
        await vm.toggleNews(l, l.items[1])
        XCTAssertEqual(bodyOf(seen("PATCH", "\(listsPath)/1/items/2")[0]) as NSDictionary, ["fetch_news": true] as NSDictionary)
    }
    func testRemoveSymbol() async {
        let (vm, _) = await loaded(["DELETE \(listsPath)/1/items/2": { _ in Stub(status: 204) }])
        let l = vm.state.data!.value.watchlists[0]
        await vm.removeSymbol(l, l.items[1])
        XCTAssertEqual(vm.edit.message, "VUAG.L removed.")
    }
    func testServerRefusalShowsTheServerMessageAndKeepsTheLists() async {
        let (vm, _) = await loaded(["POST \(listsPath)": { _ in ok(#"{"detail":"You can have at most 5 watchlists"}"#, 422) }])
        await vm.createList("X")
        XCTAssertEqual(vm.edit.error, "You can have at most 5 watchlists"); XCTAssertEqual(vm.state.data?.value.watchlists.count, 2)
    }
    func testASecondChangeWhileBusyIsIgnored() async {
        let (vm, _) = await loaded(["DELETE \(listsPath)/2": { _ in Thread.sleep(forTimeInterval: 0.3); return Stub(status: 204) }])
        let t = Task { await vm.deleteList(2) }
        await vm.deleteList(2); await t.value
        XCTAssertEqual(seen("DELETE", "\(listsPath)/2").count, 1)
    }

    // MARK: forced refresh

    func testPullToRefreshForcesTheServerThenShowsTheNewQuotes() async {
        var posted = false
        let (vm, _) = await loaded(["GET \(listsPath)": { _ in ok(listsJson("India", posted ? "200.00" : "100.00")) },
                                    "POST \(listsPath)/refresh": { _ in posted = true; return ok(#"{"refreshed":3,"skipped":0,"errors":[],"cache_hours":2,"all_fresh":true}"#) }])
        XCTAssertEqual(vm.state.data?.value.watchlists[0].items[0].lastPrice, Decimal(string: "100.00"))
        await vm.forceRefresh()
        XCTAssertEqual(vm.state.data?.value.watchlists[0].items[0].lastPrice, Decimal(string: "200.00"))
        XCTAssertEqual(vm.refreshUi.message, "Refreshed 3 symbols. Open Pulse → News and tap Refresh there for headlines.")
        XCTAssertEqual(seen("POST", "\(listsPath)/refresh")[0].url?.query, "force=true")
    }
    func testSummaryReplyIsNotMistakenForAWatchlistAndNeverBlanksTheScreen() async {
        let (vm, _) = await loaded(["GET \(listsPath)": { _ in ok(listsJson("India", "100.00")) },
                                    "POST \(listsPath)/refresh": { _ in ok(#"{"refreshed":0,"skipped":4,"errors":[],"cache_hours":2,"all_fresh":true}"#) }])
        await vm.forceRefresh()
        XCTAssertEqual(vm.state.data?.value.watchlists.count, 1); XCTAssertEqual(vm.refreshUi.message, "Up to date (within 2h).")
    }
    func testFailedRefreshShowsTheErrorAndKeepsOldData() async {
        let (vm, _) = await loaded(["GET \(listsPath)": { _ in ok(listsJson("India", "100.00")) },
                                    "POST \(listsPath)/refresh": { _ in ok(#"{"detail":"Market data provider down"}"#, 502) }])
        await vm.forceRefresh()
        XCTAssertTrue(vm.refreshUi.failed); XCTAssertTrue(vm.refreshUi.message!.contains("Market data provider down")); XCTAssertNotNil(vm.state.data)
    }
    func testOfflineKeepsSavedListsWithAnError() async {
        let env = TestEnv()
        _ = await loaded(env: env)
        MockURLProtocol.reset { _ in Stub(error: .notConnectedToInternet) }
        let vm = PulseWatchlistsModel(repo: env.repo); vm.load()
        await waitUntil("offline") { vm.state.error != nil }
        XCTAssertEqual(vm.state.data?.value.watchlists.count, 2); XCTAssertEqual(vm.state.error, "No internet connection")
    }

    // MARK: symbol search

    private let search: [String: (URLRequest) -> Stub] = ["GET /api/portfolio/symbol-search": { _ in ok(#"[{"symbol":"VOD.L","name":"Vodafone","exchange":"LSE","currency":null,"type":"EQUITY"}]"#) }]

    func testSearchWaitsForTwoCharactersAndDebounces() async {
        let (vm, _) = await loaded(search)
        vm.onQuery("v"); try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(seen("GET", "/api/portfolio/symbol-search").count, 0)
        vm.onQuery("vo"); vm.onQuery("vod")   // the first keystroke is superseded
        await waitUntil("results") { !vm.search.results.isEmpty }
        XCTAssertEqual(vm.search.results[0].symbol, "VOD.L")
        let calls = seen("GET", "/api/portfolio/symbol-search")
        XCTAssertEqual(calls.count, 1); XCTAssertEqual(calls[0].url?.query, "q=vod"); XCTAssertFalse(vm.search.searching)
    }
    func testSearchFailureJustClearsResults() async {
        let (vm, _) = await loaded(["GET /api/portfolio/symbol-search": { _ in ok("down", 503) }])
        vm.onQuery("vod"); try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(vm.search.results.isEmpty); XCTAssertFalse(vm.search.searching)
    }
    func testClearSearchResetsEverything() async {
        let (vm, _) = await loaded(search)
        vm.onQuery("vod"); vm.clearSearch()
        XCTAssertEqual(vm.search, PulseSearchUi())
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(seen("GET", "/api/portfolio/symbol-search").count, 0, "a cleared search never fires")
    }
}
