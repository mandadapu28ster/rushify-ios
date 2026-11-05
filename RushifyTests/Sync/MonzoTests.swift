import XCTest
@testable import Rushify

final class MonzoTextTests: XCTestCase {
    func testStatusWordingMatchesTheWeb() {
        XCTAssertEqual(monzoStatusLabel("connected"), "Connected")
        XCTAssertEqual(monzoStatusLabel("pending_approval"), "Waiting for approval in the Monzo app")
        XCTAssertEqual(monzoStatusLabel("needs_reconnect"), "Needs reconnect")
        XCTAssertEqual(monzoStatusLabel("not_connected"), "Keys saved — not connected")
        XCTAssertEqual(monzoStatusLabel(nil), "Keys saved — not connected"); XCTAssertEqual(monzoStatusLabel(""), "Keys saved — not connected")
        XCTAssertEqual(monzoStatusLabel("some_new_state"), "Some new state")
        let m = MonzoStatus(configured: true, status: "connected")
        XCTAssertEqual(monzoLabel(nil), "Not set"); XCTAssertEqual(monzoLabel(MonzoStatus(configured: false, status: "connected")), "Not set"); XCTAssertEqual(monzoLabel(m), "Connected")
        XCTAssertTrue(monzoCanSync(m)); XCTAssertTrue(monzoCanSync(MonzoStatus(configured: true, status: "pending_approval")))
        XCTAssertFalse(monzoCanSync(MonzoStatus(configured: true, status: "needs_reconnect"))); XCTAssertFalse(monzoCanSync(MonzoStatus(configured: false, status: "connected"))); XCTAssertFalse(monzoCanSync(nil))
    }
    func testSyncMessages() {
        XCTAssertEqual(MonzoMessages.synced(MonzoSyncCounts(accounts: 3, pots: 2)), "Synced 3 accounts and 2 pots.")
        XCTAssertEqual(MonzoMessages.synced(MonzoSyncCounts(accounts: 1, pots: 1)), "Synced 1 account and 1 pot.")
        XCTAssertEqual(MonzoMessages.of(MonzoSyncOutcome(result: nil)), MonzoMessages.updated); XCTAssertEqual(MonzoMessages.updated, "Monzo balances updated.")
        XCTAssertEqual(MonzoMessages.of(MonzoSyncOutcome(result: MonzoSyncResult(status: "pending_approval"))), MonzoMessages.waiting)
        XCTAssertEqual(MonzoMessages.waiting, "Still waiting for approval. Open the Monzo app and approve access.")
    }
}

@MainActor
final class MonzoViewModelTests: XCTestCase {
    var env: TestEnv!; var stubs: SyncStubs!
    override func setUp() async throws { env = TestEnv(); stubs = SyncStubs() }

    private func loaded() async -> MonzoViewModel {
        stubs.fixtureRoute("GET", "/api/monzo/status", "monzo")
        let vm = MonzoViewModel(repo: env.repo); vm.load()
        await syncWait("monzo status") { vm.state.data != nil }
        return vm
    }

    func testStatusLoads() async {
        let vm = await loaded(); let m = vm.state.data!.value
        XCTAssertTrue(m.configured); XCTAssertEqual(monzoStatusLabel(m.status), "Connected"); XCTAssertEqual(m.balanceRows, 4)
    }
    func testOfflineKeepsSavedStatusWithAnError() async {
        _ = await loaded()
        stubs.ok("GET", "/api/monzo/status", "down", status: 500)
        let vm2 = MonzoViewModel(repo: env.repo); vm2.load()
        await syncWait("error") { vm2.state.error != nil }
        XCTAssertEqual(vm2.state.data?.value.status, "connected", "saved copy stays on screen")
    }
    func testSyncWith204EmptyBodyIsASuccessAndRefreshesTheDashboard() async {
        let vm = await loaded()
        stubs.route("POST", "/api/monzo/sync") { _ in .init(status: 204) }
        var refreshed = false
        await vm.syncNow { refreshed = true }?.value
        XCTAssertFalse(vm.sync.failed); XCTAssertEqual(vm.sync.message, "Monzo balances updated."); XCTAssertTrue(refreshed)
        XCTAssertEqual(stubs.count("POST", "/api/monzo/sync"), 1)
        XCTAssertFalse(vm.sync.syncing)
    }
    func testSyncWithJsonBodyAlsoSucceeds() async {
        let vm = await loaded()
        stubs.ok("POST", "/api/monzo/sync", #"{"ok":true,"synced":4}"#)
        await vm.syncNow()?.value
        XCTAssertFalse(vm.sync.failed); XCTAssertNotNil(vm.sync.message)
    }
    func testSyncWithCountsRefreshesTheDashboard() async {
        let vm = await loaded()
        stubs.ok("POST", "/api/monzo/sync", #"{"monzo_configured":true,"status":"connected","sync":{"accounts":2,"pots":3}}"#)
        var refreshed = false
        await vm.syncNow { refreshed = true }?.value
        XCTAssertEqual(vm.sync.message, "Synced 2 accounts and 3 pots."); XCTAssertTrue(refreshed)
    }
    func testStillWaitingForApprovalDoesNotRefreshAnything() async {
        let vm = await loaded()
        stubs.ok("POST", "/api/monzo/sync", #"{"monzo_configured":true,"status":"pending_approval","sync":null}"#)
        var refreshed = false
        await vm.syncNow { refreshed = true }?.value
        XCTAssertEqual(vm.sync.message, MonzoMessages.waiting); XCTAssertFalse(refreshed); XCTAssertFalse(vm.sync.failed)
    }
    func testSyncFailureShowsTheServerError() async {
        let vm = await loaded()
        stubs.ok("POST", "/api/monzo/sync", #"{"detail":"Monzo needs reauthorisation"}"#, status: 502)
        await vm.syncNow()?.value
        XCTAssertTrue(vm.sync.failed); XCTAssertEqual(vm.sync.message, "Monzo sync failed: Monzo needs reauthorisation")
    }
    func testASecondTapWhileSyncingIsIgnored() async {
        let vm = await loaded()
        stubs.ok("POST", "/api/monzo/sync", "{}")
        let first = vm.syncNow(); XCTAssertNil(vm.syncNow()); await first?.value
        XCTAssertEqual(stubs.count("POST", "/api/monzo/sync"), 1)
    }
    func testSyncSendsBearerToken() async {
        let vm = await loaded(); stubs.ok("POST", "/api/monzo/sync", "{}"); await vm.syncNow()?.value
        XCTAssertEqual(stubs.requests("POST", "/api/monzo/sync").first?.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-token")
    }

    func testRefreshOnOpenOnlyActsWhenTheServerRefreshed() async {
        stubs.ok("POST", "/api/monzo/refresh-if-stale", #"{"refreshed":true}"#)
        let v0 = env.repo.events.version
        let a = await syncMonzoRefreshIfStale(repo: env.repo); XCTAssertTrue(a)
        stubs.ok("POST", "/api/monzo/refresh-if-stale", #"{"refreshed":false}"#)
        let b = await syncMonzoRefreshIfStale(repo: env.repo); XCTAssertFalse(b)
        stubs.ok("POST", "/api/monzo/refresh-if-stale", "down", status: 500)
        let c = await syncMonzoRefreshIfStale(repo: env.repo); XCTAssertFalse(c)
        XCTAssertEqual(stubs.count("POST", "/api/monzo/refresh-if-stale"), 3)
        XCTAssertEqual(env.repo.events.version, v0 + 1, "only the refreshing call announces a data change")
    }
}
