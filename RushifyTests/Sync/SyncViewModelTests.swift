import XCTest
@testable import Rushify

@MainActor
final class SyncViewModelTests: XCTestCase {
    var env: TestEnv!; var stubs: SyncStubs!
    var now: Int64 = 1_000_000
    var sleeps: [Int64] = []

    override func setUp() async throws { env = TestEnv(); stubs = SyncStubs(); now = 1_000_000; sleeps = [] }

    private func makeVM() -> SyncViewModel {
        SyncViewModel(repo: env.repo, pollDelayMs: 5, clock: { [unowned self] in self.now },
                      sleep: { [unowned self] ms in await MainActor.run { self.sleeps.append(ms) }; try await Task.sleep(nanoseconds: 1_000_000) })
    }
    private func readyVM() async -> SyncViewModel {
        stubs.routeSync()
        let vm = makeVM(); vm.refresh()
        await syncWait("quota") { vm.ui.quota != nil }
        return vm
    }
    private func log(_ id: Int, kind: String = "manual", finished: Bool, ok: Bool = true, err: String? = nil) -> String {
        let e = err.map { "\"\($0)\"" } ?? "null"
        return "{\"id\":\(id),\"kind\":\"\(kind)\",\"started_at\":\"2026-10-17T10:00:00Z\",\"finished_at\":\(finished ? "\"2026-10-17T10:00:09Z\"" : "null"),\"success\":\(ok),\"error_message\":\(e)}"
    }

    // MARK: loading

    func testLoadsQuotaStatusAndHistoryNewestFirst() async {
        let vm = await readyVM()
        XCTAssertEqual(vm.ui.quota?.snaptrade.remaining, 2)   // routeSync overrides the fixture's exhausted quota
        XCTAssertEqual(vm.ui.history.first?.id, 12); XCTAssertNotNil(vm.ui.historyAsOf); XCTAssertNil(vm.ui.error); XCTAssertFalse(vm.ui.loading)
    }
    func testFailureKeepsErrorAndNoQuota() async {
        stubs.routeSync(); stubs.ok("GET", "/api/sync/manual-quota", #"{"detail":"down"}"#, status: 500)
        let vm = makeVM(); vm.refresh()
        await syncWait("error") { vm.ui.error != nil }
        XCTAssertNil(vm.ui.quota); XCTAssertFalse(vm.ui.loading)
    }
    func testSavedHistoryShowsFirstThenOfflineKeepsData() async {
        let vm = await readyVM()   // history cached by the first fetch
        stubs.ok("GET", "/api/sync/status", "down", status: 500)
        let vm2 = makeVM(); vm2.load()
        await syncWait("error") { vm2.ui.error != nil }
        XCTAssertEqual(vm2.ui.history.first?.id, 12, "saved history still there")
        XCTAssertNotNil(vm2.ui.historyAsOf); _ = vm
    }

    // MARK: starting a sync

    func testQuotaReached429ShowsMessageAndDoesNotRun() async {
        let vm = await readyVM()
        stubs.ok("POST", "/api/sync/manual", #"{"detail":"Daily manual sync limit reached"}"#, status: 429)
        await vm.sync(.t212)?.value
        XCTAssertTrue(vm.ui.message!.contains("limit")); XCTAssertEqual(vm.ui.message, "Daily manual sync limit reached. Daily manual sync limit reached")
        XCTAssertNotEqual(vm.ui.running[.t212], true)
    }
    func testConflict409SwitchesToRunningStateWithoutASecondPost() async {
        let vm = await readyVM()
        stubs.ok("POST", "/api/sync/manual", #"{"detail":"A sync is already running"}"#, status: 409)
        await vm.sync(.t212)?.value
        XCTAssertEqual(vm.ui.message, "A sync is already running for Trading 212.")
        XCTAssertEqual(vm.ui.running[.t212], true, "running state is shown while polling history")
        XCTAssertEqual(stubs.count("POST", "/api/sync/manual"), 1)
        vm.stop()
    }
    func testConflictThenHistoryFinishedEndsTheRunningState() async {
        let vm = await readyVM()
        stubs.ok("POST", "/api/sync/manual", #"{"detail":"A sync is already running"}"#, status: 409)
        await vm.sync(.t212)?.value
        await syncWait("running ended by history") { vm.ui.running[.t212] != true }   // fixture history: latest log (id 12) is finished
        XCTAssertTrue(vm.ui.message?.contains("sync finished") == true || vm.ui.message?.contains("failed") == true)
    }
    func testAccepted202PollsUntilFinishedThenReportsSuccessAndAnnouncesChange() async {
        let vm = await readyVM(); let v0 = env.repo.events.version
        stubs.ok("POST", "/api/sync/manual", #"{"sync_log_id":99}"#, status: 202)
        var polls = 0
        stubs.route("GET", "/api/sync/log/99") { [self] _ in polls += 1; return .init(body: Data(log(99, finished: polls >= 3).utf8)) }
        await vm.sync(.t212)?.value
        XCTAssertEqual(vm.ui.running[.t212], true); XCTAssertNil(vm.ui.message)
        await syncWait("finished") { vm.ui.message == "Trading 212 sync finished." }
        XCTAssertGreaterThanOrEqual(polls, 3); XCTAssertNotEqual(vm.ui.running[.t212], true); XCTAssertTrue(vm.ui.cooldowns.isEmpty)
        XCTAssertEqual(env.repo.events.version, v0 + 1)
    }
    func testAcceptedWithoutLogIdJustRefreshes() async {
        let vm = await readyVM()
        stubs.ok("POST", "/api/sync/manual", #"{"detail":"ok"}"#, status: 202)
        await vm.sync(.t212)?.value
        XCTAssertNotEqual(vm.ui.running[.t212], true)
    }
    func testFailedSyncSurfacesServerErrorTextAndStartsACooldown() async {
        let vm = await readyVM()
        stubs.ok("POST", "/api/snaptrade/sync/manual", #"{"sync_log_id":5}"#, status: 202)
        stubs.ok("GET", "/api/sync/log/5", log(5, kind: "snaptrade_manual", finished: true, ok: false, err: "Broker auth failed"))
        await vm.sync(.snaptrade)?.value
        await syncWait("failure message") { vm.ui.message?.contains("failed") == true }
        XCTAssertEqual(vm.ui.message, "SnapTrade sync failed: Broker auth failed")
        XCTAssertEqual(vm.ui.cooldowns[.snaptrade]?.provider, false)
    }
    func testStaleLogGetsFriendlyTextAndCooldown() async {
        let vm = await readyVM()
        stubs.ok("POST", "/api/snaptrade/sync/manual", #"{"sync_log_id":9}"#, status: 202)
        stubs.ok("GET", "/api/sync/log/9", log(9, kind: "snaptrade_manual", finished: true, ok: false, err: "Sync did not complete (stale)"))
        await vm.sync(.snaptrade)?.value
        await syncWait("stale message") { vm.ui.message?.contains("failed") == true }
        XCTAssertTrue(vm.ui.message!.contains("Sync did not complete (stale; task or server ended without finishing)")); XCTAssertNotNil(vm.ui.cooldowns[.snaptrade])
    }
    func testWireFormatSendsFullRefreshFalseAndBearer() async {
        let vm = await readyVM()
        stubs.ok("POST", "/api/sync/manual", #"{"sync_log_id":1}"#, status: 202)
        stubs.ok("GET", "/api/sync/log/1", log(1, finished: true))
        await vm.sync(.t212)?.value
        let body = stubs.bodyJSON("POST", "/api/sync/manual")
        XCTAssertEqual(body?["order_history_full_refresh"] as? Bool, false); XCTAssertEqual(body?.count, 1)
        XCTAssertEqual(stubs.requests("POST", "/api/sync/manual").first?.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-token")
        await syncWait("done") { vm.ui.message != nil }
    }
    func testSnaptradeUsesItsOwnEndpoint() async {
        let vm = await readyVM(); stubs.ok("POST", "/api/snaptrade/sync/manual", #"{"sync_log_id":2}"#, status: 202)
        stubs.ok("GET", "/api/sync/log/2", log(2, kind: "snaptrade_manual", finished: true))
        await vm.sync(.snaptrade)?.value
        XCTAssertEqual(stubs.count("POST", "/api/snaptrade/sync/manual"), 1); XCTAssertEqual(stubs.count("POST", "/api/sync/manual"), 0)
        await syncWait("done") { vm.ui.message == "SnapTrade sync finished." }
    }
    func testASyncInProgressIgnoresASecondStart() async {
        let vm = await readyVM(); stubs.ok("POST", "/api/sync/manual", #"{"sync_log_id":3}"#, status: 202)
        stubs.ok("GET", "/api/sync/log/3", log(3, finished: false))
        await vm.sync(.t212)?.value
        XCTAssertNil(vm.sync(.t212)); XCTAssertEqual(stubs.count("POST", "/api/sync/manual"), 1)
        vm.stop()
    }
    func testNothingIsSentWhileTheRulesDisableTheButton() async {
        stubs.routeSync(); stubs.ok("GET", "/api/sync/status", #"{"t212_configured":false}"#)
        let vm = makeVM(); vm.refresh(); await syncWait("status") { vm.ui.status != nil && vm.ui.quota != nil }
        XCTAssertNil(vm.sync(.t212)); XCTAssertEqual(stubs.count("POST", "/api/sync/manual"), 0)
    }

    // MARK: cooldowns

    func testAFailedSyncStartsAShortCooldownThatBlocksAndThenReleases() async {
        let vm = await readyVM()
        stubs.ok("POST", "/api/sync/manual", #"{"detail":"Internal error"}"#, status: 500)
        await vm.sync(.t212)?.value
        XCTAssertNotNil(vm.ui.cooldowns[.t212]); XCTAssertEqual(vm.ui.message, "Internal error")
        XCTAssertNil(vm.sync(.t212), "held back"); XCTAssertEqual(stubs.count("POST", "/api/sync/manual"), 1)
        XCTAssertEqual(SyncRules.disabledReason(.t212, vm.ui, now: now), SyncRules.short)
        now += 11_000
        await vm.sync(.t212)?.value
        XCTAssertEqual(stubs.count("POST", "/api/sync/manual"), 2)
    }
    func testProviderRateLimitStartsALongCooldown() async {
        let vm = await readyVM()
        stubs.ok("POST", "/api/sync/manual", #"{"detail":"Trading 212 rate limit exceeded (429)"}"#, status: 502)
        await vm.sync(.t212)?.value
        XCTAssertEqual(vm.ui.cooldowns[.t212]?.provider, true)
        now += 120_000; XCTAssertEqual(SyncRules.disabledReason(.t212, vm.ui, now: now), SyncRules.t212Provider)
        now += 500_000; XCTAssertNil(SyncRules.disabledReason(.t212, vm.ui, now: now))
    }
    func testNetworkFailureAlsoCoolsDown() async {
        let vm = await readyVM()
        stubs.route("POST", "/api/sync/manual") { _ in .init(error: .notConnectedToInternet) }
        await vm.sync(.t212)?.value
        XCTAssertEqual(vm.ui.message, "No internet connection"); XCTAssertNotNil(vm.ui.cooldowns[.t212])
    }
    func testASuccessfulSyncStartsNoCooldown() async {
        let vm = await readyVM(); stubs.ok("POST", "/api/sync/manual", #"{"sync_log_id":5}"#, status: 202)
        stubs.ok("GET", "/api/sync/log/5", log(5, finished: true))
        await vm.sync(.t212)?.value
        await syncWait("finished") { vm.ui.message?.contains("finished") == true }
        XCTAssertTrue(vm.ui.cooldowns.isEmpty)
    }

    // MARK: polling

    func testPollingBacksOffAndStopsAfterTheLimit() async {
        let vm = await readyVM(); stubs.ok("POST", "/api/sync/manual", #"{"sync_log_id":8}"#, status: 202)
        stubs.ok("GET", "/api/sync/log/8", log(8, finished: false))
        await vm.sync(.t212)?.value
        await syncWait("gave up", timeout: 15) { vm.ui.message == "Sync is taking longer than expected. Check again in a minute." }
        XCTAssertEqual(sleeps.count, 80)
        XCTAssertEqual(Array(sleeps.prefix(4)), [5, 7, 10, 15]); XCTAssertEqual(sleeps.last, 15_000)
        XCTAssertNotEqual(vm.ui.running[.t212], true); XCTAssertEqual(vm.ui.cooldowns[.t212]?.provider, false)
    }
    func testPollingSurvivesTransientErrors() async {
        let vm = await readyVM(); stubs.ok("POST", "/api/sync/manual", #"{"sync_log_id":4}"#, status: 202)
        var n = 0
        stubs.route("GET", "/api/sync/log/4") { [self] _ in n += 1; return n < 3 ? .init(status: 500, body: Data(#"{"detail":"x"}"#.utf8)) : .init(body: Data(log(4, finished: true).utf8)) }
        await vm.sync(.t212)?.value
        await syncWait("finished") { vm.ui.message == "Trading 212 sync finished." }
        XCTAssertGreaterThanOrEqual(n, 3)
    }
    func testSessionExpiryStopsPolling() async {
        let vm = await readyVM(); stubs.ok("POST", "/api/sync/manual", #"{"sync_log_id":6}"#, status: 202)
        stubs.ok("GET", "/api/sync/log/6", #"{"detail":"Not authenticated"}"#, status: 401)
        await vm.sync(.t212)?.value
        await syncWait("poll attempted") { self.stubs.count("GET", "/api/sync/log/6") >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(stubs.count("GET", "/api/sync/log/6"), 1)
        XCTAssertTrue(env.session.current.expired)
    }

    // MARK: resume

    func testASyncStartedEarlierIsPickedUpAgainOnOpen() async {
        stubs.routeSync(); stubs.ok("GET", "/api/sync/manual/t212-running", #"{"t212_manual_in_progress":true,"active_sync_log_id":77}"#)
        var polls = 0
        stubs.route("GET", "/api/sync/log/77") { [self] _ in polls += 1; return .init(body: Data(log(77, finished: polls >= 3).utf8)) }
        let vm = makeVM(); vm.load()
        await syncWait("resumed") { vm.ui.running[.t212] == true }
        await syncWait("finished") { vm.ui.message?.contains("finished") == true }
        XCTAssertNotEqual(vm.ui.running[.t212], true); XCTAssertGreaterThanOrEqual(polls, 3)
        XCTAssertEqual(stubs.count("POST", "/api/sync/manual"), 0)
    }
    func testResumeWithoutALogIdWatchesTheHistory() async {
        stubs.routeSync(); stubs.ok("GET", "/api/sync/manual/snaptrade-running", #"{"snaptrade_manual_in_progress":true,"active_sync_log_id":null}"#)
        let vm = makeVM(); vm.load()
        await syncWait("resumed") { vm.ui.running[.snaptrade] == true }
        await syncWait("history shows finished") { vm.ui.running[.snaptrade] != true }
    }
    func testNothingRunningMeansNothingResumed() async {
        stubs.routeSync(); let vm = makeVM(); vm.load()
        await syncWait("quota") { vm.ui.quota != nil }
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(vm.ui.running.values.allSatisfy { !$0 })
    }

    // MARK: SnapTrade portal

    func testPortalReconnectSendsTheAuthorizationIdAndHandsBackAnHttpsUrl() async {
        let vm = await readyVM(); stubs.ok("POST", "/api/snaptrade/portal-url", #"{"redirect_uri":"https://app.snaptrade.com/connect?x=1"}"#)
        await vm.openPortal(reconnectId: "auth-1")?.value
        XCTAssertEqual(vm.ui.portalUrl?.absoluteString, "https://app.snaptrade.com/connect?x=1"); XCTAssertFalse(vm.ui.portalBusy)
        XCTAssertEqual(stubs.bodyJSON("POST", "/api/snaptrade/portal-url") as? [String: String], ["reconnect_authorization_id": "auth-1"])
        vm.portalOpened(); XCTAssertNil(vm.ui.portalUrl)
    }
    func testPortalForANewBrokerSendsAnEmptyObject() async {
        let vm = await readyVM(); stubs.ok("POST", "/api/snaptrade/portal-url", #"{"redirect_uri":"https://x.example/c"}"#)
        await vm.openPortal(reconnectId: nil)?.value
        XCTAssertNotNil(vm.ui.portalUrl); XCTAssertEqual(stubs.bodyJSON("POST", "/api/snaptrade/portal-url")?.count, 0)
    }
    func testPortalRejectsNonHttpAddresses() async {
        let vm = await readyVM(); stubs.ok("POST", "/api/snaptrade/portal-url", #"{"redirect_uri":"javascript:alert(1)"}"#)
        await vm.openPortal(reconnectId: nil)?.value
        XCTAssertNil(vm.ui.portalUrl); XCTAssertEqual(vm.ui.portalError, "Could not open SnapTrade portal")
    }
    func testPortalErrorsAreShown() async {
        let vm = await readyVM(); stubs.ok("POST", "/api/snaptrade/portal-url", #"{"detail":"SnapTrade is not configured"}"#, status: 400)
        await vm.openPortal(reconnectId: nil)?.value
        XCTAssertFalse(vm.ui.portalError?.isEmpty ?? true); XCTAssertFalse(vm.ui.portalBusy)
    }
}

