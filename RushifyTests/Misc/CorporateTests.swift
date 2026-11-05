import XCTest
@testable import Rushify

@MainActor
final class CorporateTests: XCTestCase {
    private var routes = MiscRoutes()
    override func setUp() { MockURLProtocol.reset() }

    private func routeMaps(_ body: String? = nil) {
        routes.add("GET /api/portfolio/ticker-maps", body: body ?? miscFixtureString("ticker_maps"))
        routes.add("PUT /api/portfolio/ticker-maps", body: #"{"source_key":"ZZZ","yahoo_symbol":"ZZZ.L"}"#)
        routes.add("DELETE /api/portfolio/ticker-maps", status: 204, body: "")
        routes.install()
    }

    // MARK: corporate actions

    func testListSplitsPendingFromResolved() async {
        routes.add("GET /api/corporate-actions", body: miscFixtureString("corporate")); routes.install()
        let vm = CorporateViewModel(repo: TestEnv().repo); await vm.load()
        let list = vm.state.data!.value
        XCTAssertEqual(CorporateText.pending(list).map(\.id), [3])
        XCTAssertEqual(list.count, 2)
    }

    func testEmptyListIsFine() async {
        routes.add("GET /api/corporate-actions", body: "[]"); routes.install()
        let vm = CorporateViewModel(repo: TestEnv().repo); await vm.load()
        XCTAssertTrue(vm.state.data!.value.isEmpty)
    }

    func testConfirmSendsPatchWithStatusAndReloads() async {
        var served = 0
        let body = miscFixtureString("corporate")
        MockURLProtocol.reset { req in
            switch (req.httpMethod ?? "", req.url?.path ?? "") {
            case ("GET", "/api/corporate-actions"): served += 1; return .init(body: json(served == 1 ? body : "[]"))
            case ("PATCH", "/api/corporate-actions/3"): return .init(body: json(#"{"id":3,"status":"confirmed","action_type":"stock_split","ticker":"AAA","details":{},"created_at":"2026-10-17T09:00:00Z"}"#))
            default: return .init(status: 404)
            }
        }
        let env = TestEnv(); let vm = CorporateViewModel(repo: env.repo); await vm.load()
        let v0 = env.repo.events.version
        await vm.resolve(id: 3, status: "confirmed")
        XCTAssertEqual(vm.resolveUi.message, "Action confirmed."); XCTAssertFalse(vm.resolveUi.failed); XCTAssertNil(vm.resolveUi.busyId)
        XCTAssertTrue(vm.state.data!.value.isEmpty)
        let patch = MockURLProtocol.seen().first { $0.httpMethod == "PATCH" }!
        XCTAssertEqual(miscBodyJSON(patch), ["status": "confirmed"])
        XCTAssertEqual(patch.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-token")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertGreaterThan(env.repo.events.version, v0, "a write bumps the data events")
    }

    func testDismissAndFailureAreReported() async {
        routes.add("GET /api/corporate-actions", body: miscFixtureString("corporate"))
        routes.add("PATCH /api/corporate-actions/3", status: 404, body: #"{"detail":"Not found"}"#); routes.install()
        let vm = CorporateViewModel(repo: TestEnv().repo); await vm.load()
        await vm.resolve(id: 3, status: "dismissed")
        XCTAssertTrue(vm.resolveUi.failed); XCTAssertTrue(vm.resolveUi.message!.contains("Not found")); XCTAssertNil(vm.resolveUi.busyId)
        XCTAssertEqual(vm.resolveUi.message, "Could not update: Not found")
    }

    func testDismissedMessage() async {
        routes.add("GET /api/corporate-actions", body: miscFixtureString("corporate"))
        routes.add("PATCH /api/corporate-actions/3"); routes.install()
        let vm = CorporateViewModel(repo: TestEnv().repo); await vm.load()
        await vm.resolve(id: 3, status: "dismissed")
        XCTAssertEqual(vm.resolveUi.message, "Action dismissed.")
        XCTAssertEqual(miscBodyJSON(MockURLProtocol.seen().first { $0.httpMethod == "PATCH" }!), ["status": "dismissed"])
    }

    func testDetailLinesAreReadable() {
        let a: [CorporateAction] = decodeFixture("corporate")
        let lines = Dictionary(uniqueKeysWithValues: CorporateText.detailLines(a[0].details).map { ($0.key, $0.value) })
        XCTAssertEqual(lines["Ratio"], "10:1"); XCTAssertEqual(lines["Effective date"], "2026-10-20"); XCTAssertEqual(lines["New quantity"], "25"); XCTAssertEqual(lines["Flags"], "adr, manual_check")
        XCTAssertEqual(CorporateText.actionTypeLabel("stock_split"), "Stock split")
        XCTAssertTrue(CorporateText.detailLines(a[1].details).isEmpty)
    }

    func testDetailLinesNullAndNested() throws {
        let a = try JSONDecoder().decode(CorporateAction.self, from: json(#"{"id":1,"details":{"gone":null,"ok":true,"price":1.5,"nested":{"b":2,"a":"x"},"mixed":["a",1,null]}}"#))
        let l = Dictionary(uniqueKeysWithValues: CorporateText.detailLines(a.details).map { ($0.key, $0.value) })
        XCTAssertEqual(l["Gone"], "—"); XCTAssertEqual(l["Ok"], "true"); XCTAssertEqual(l["Price"], "1.5")
        XCTAssertEqual(l["Nested"], #"{"a":"x","b":2}"#); XCTAssertEqual(l["Mixed"], "a, 1, null")
    }

    func testModelIsLenient() throws {
        let a = try JSONDecoder().decode(CorporateAction.self, from: json("{}"))
        XCTAssertEqual(a.status, "pending"); XCTAssertEqual(a.id, 0); XCTAssertTrue(a.details.isEmpty); XCTAssertNil(a.createdAt)
        XCTAssertEqual(CorporateText.pending([CorporateAction(status: "PENDING")]).count, 1)
    }

    func testOfflineKeepsCachedList() async {
        routes.add("GET /api/corporate-actions", body: miscFixtureString("corporate")); routes.install()
        let env = TestEnv(); let first = CorporateViewModel(repo: env.repo); await first.load()
        MockURLProtocol.reset { _ in .init(error: .notConnectedToInternet) }
        let vm = CorporateViewModel(repo: env.repo); await vm.load()
        XCTAssertEqual(vm.state.data?.value.count, 2); XCTAssertEqual(vm.state.error, "No internet connection")
    }

    // MARK: ticker maps

    func testTickerMapsAttentionLoads() async {
        routeMaps()
        let vm = CorporateTickerMapsViewModel(repo: TestEnv().repo); await vm.load()
        let items = vm.state.data!.value.attentionItems
        XCTAssertEqual(items.count, 2); XCTAssertNil(items[1].yahooSymbol); XCTAssertTrue(items[0].hasUserMap)
        XCTAssertEqual(items[0].brokerTicker, "AAAl_EQ")
    }

    func testSavingTrimsTheSymbolSendsPutAndRefreshesEverything() async {
        routeMaps(); var changed = 0
        let env = TestEnv(); let vm = CorporateTickerMapsViewModel(repo: env.repo); await vm.load()
        await vm.save(sourceKey: "ZZZ", symbol: "  zzz.l  ") { changed += 1 }
        XCTAssertEqual(vm.edit.message, CorporateText.mapSavedInfo); XCTAssertEqual(changed, 1)
        let put = MockURLProtocol.seen().first { $0.httpMethod == "PUT" }!
        XCTAssertEqual(miscBodyJSON(put), ["source_key": "ZZZ", "yahoo_symbol": "zzz.l"])
        XCTAssertGreaterThanOrEqual(miscCount("GET", "/api/portfolio/ticker-maps"), 2)
        XCTAssertNil(vm.edit.savingKey)
    }

    func testWebWordingConstants() {
        XCTAssertEqual(CorporateText.mapSavedInfo, "Latest portfolio tracking will include this shortly. Until then, treat your portfolio update as in progress. Open Home after a moment for refreshed numbers.")
        XCTAssertEqual(CorporateText.mapEmptyError, "Add the listing symbol you want us to use for quotes and history, then save.")
    }

    func testBlankSymbolIsRejectedWithTheWebMessageAndNothingIsSent() async {
        routeMaps()
        let vm = CorporateTickerMapsViewModel(repo: TestEnv().repo)
        await vm.save(sourceKey: "ZZZ", symbol: "   ")
        XCTAssertEqual(vm.edit.error, CorporateText.mapEmptyError)
        XCTAssertEqual(MockURLProtocol.seen().count, 0)
    }

    func testRemoveSendsDeleteWithTheEncodedSourceKey() async {
        routeMaps(); var changed = false
        let vm = CorporateTickerMapsViewModel(repo: TestEnv().repo)
        await vm.remove(sourceKey: "A B/C&d") { changed = true }
        XCTAssertNotNil(vm.edit.message); XCTAssertTrue(changed)
        let del = MockURLProtocol.seen().first { $0.httpMethod == "DELETE" }!
        let items = URLComponents(url: del.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.map(\.name), ["source_key"]); XCTAssertEqual(items[0].value, "A B/C&d")
        XCTAssertFalse(del.url!.absoluteString.contains("&d"), "the ampersand must be encoded")
    }

    func testFailedSaveShowsTheServerErrorAndDoesNotRefresh() async {
        routeMaps(); routes.add("PUT /api/portfolio/ticker-maps", status: 422, body: #"{"detail":"Symbol not recognised"}"#); routes.install()
        var changed = false
        let vm = CorporateTickerMapsViewModel(repo: TestEnv().repo)
        await vm.save(sourceKey: "ZZZ", symbol: "NOPE") { changed = true }
        XCTAssertEqual(vm.edit.error, "Symbol not recognised"); XCTAssertFalse(changed); XCTAssertNil(vm.edit.savingKey)
        XCTAssertEqual(miscCount("GET", "/api/portfolio/ticker-maps"), 0)
    }

    func testOnlyOneSaveAtATime() async {
        routeMaps(); routes.add("PUT /api/portfolio/ticker-maps", body: "{}", delay: 0.3); routes.install()
        let vm = CorporateTickerMapsViewModel(repo: TestEnv().repo)
        async let a: Void = vm.save(sourceKey: "A", symbol: "AAA")
        async let b: Void = vm.save(sourceKey: "B", symbol: "BBB")
        _ = await (a, b)
        XCTAssertEqual(miscCount("PUT", "/api/portfolio/ticker-maps"), 1)
        XCTAssertNotNil(vm.edit.message)
    }

    func testMessageCanBeCleared() async {
        routeMaps(); let vm = CorporateTickerMapsViewModel(repo: TestEnv().repo)
        await vm.save(sourceKey: "ZZZ", symbol: "ZZZ.L"); XCTAssertNotNil(vm.edit.message)
        vm.clearMessage(); XCTAssertNil(vm.edit.message)
    }

    func testHomeBannerDismissPostsOnceAndFailureIsThrown() async throws {
        routes.add("POST /api/portfolio/ticker-attention-banner/dismiss", status: 204, body: ""); routes.install()
        let env = TestEnv()
        try await env.repo.miscDismissTickerBanner()
        XCTAssertEqual(miscCount("POST", "/api/portfolio/ticker-attention-banner/dismiss"), 1)
        routes.add("POST /api/portfolio/ticker-attention-banner/dismiss", status: 500, body: #"{"detail":"nope"}"#); routes.install()
        do { try await env.repo.miscDismissTickerBanner(); XCTFail("expected error") } catch { XCTAssertEqual((error as? ApiError)?.message, "nope") }
    }
}
