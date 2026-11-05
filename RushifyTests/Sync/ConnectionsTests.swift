import XCTest
@testable import Rushify

final class ConnectionsTextTests: XCTestCase {
    func testYesNoAndAiLabels() {
        XCTAssertEqual(ConnectionsText.yesNo(true), "Configured"); XCTAssertEqual(ConnectionsText.yesNo(false), "Not set")
        XCTAssertEqual(ConnectionsText.aiProviderLabel(ConnectionsCredentialFlags(aiProvider: "OpenAI")), "OpenAI")
        XCTAssertEqual(ConnectionsText.aiProviderLabel(ConnectionsCredentialFlags()), "Gemini")
        XCTAssertEqual(ConnectionsText.aiAgentLabel("assistants"), "Assistants API"); XCTAssertEqual(ConnectionsText.aiAgentLabel("chat_tools"), "Chat agent (tools)")
        XCTAssertNil(ConnectionsText.aiAgentLabel(nil)); XCTAssertNil(ConnectionsText.aiAgentLabel("")); XCTAssertEqual(ConnectionsText.aiAgentLabel("other"), "other")
    }
    func testT212Alerts() {
        let s = SyncStatus(accounts: ["invest": SyncT212Account(configured: true), "isa": SyncT212Account(configured: true, needsReconnect: true, lastError: "401 unauthorised"),
                                      "sipp": SyncT212Account(configured: false, needsReconnect: true)])
        let a = ConnectionsText.t212Alerts(s)
        XCTAssertEqual(a.map(\.label), ["Stocks & Shares ISA", "SIPP"]); XCTAssertEqual(a.map(\.error), ["401 unauthorised", "Trading 212 rejected or expired these API keys."])
        XCTAssertTrue(ConnectionsText.t212Alerts(nil).isEmpty)
    }
    func testSnaptradeState() {
        XCTAssertNil(ConnectionsText.snaptradeState(nil)); XCTAssertNil(ConnectionsText.snaptradeState(SyncSnaptradeStatus(configured: false)))
        XCTAssertTrue(ConnectionsText.snaptradeState(SyncSnaptradeStatus(configured: true, authFailed: true))!.contains("401"))
        XCTAssertTrue(ConnectionsText.snaptradeState(SyncSnaptradeStatus(configured: true, needsReconnect: true))!.contains("reconnecting"))
        XCTAssertEqual(ConnectionsText.snaptradeState(SyncSnaptradeStatus(configured: true, needsBrokerLink: true)), "No broker linked yet.")
        XCTAssertEqual(ConnectionsText.snaptradeState(SyncSnaptradeStatus(configured: true, activeConnections: 2)), "2 active connections.")
        XCTAssertEqual(ConnectionsText.snaptradeState(SyncSnaptradeStatus(configured: true, activeConnections: 1)), "1 active connection.")
    }
}

@MainActor
final class ConnectionsViewModelTests: XCTestCase {
    var env: TestEnv!; var stubs: SyncStubs!
    override func setUp() async throws { env = TestEnv(); stubs = SyncStubs() }

    private func routeAll() {
        stubs.fixtureRoute("GET", "/api/portfolio/credentials", "credentials")
        stubs.ok("GET", "/api/sync/status", #"{"t212_configured":true,"accounts":{"isa":{"configured":true,"needs_reconnect":true,"last_error":"401"}}}"#)
        stubs.ok("GET", "/api/snaptrade/status", #"{"snaptrade_configured":true,"snaptrade_active_connections_count":2}"#)
        stubs.fixtureRoute("GET", "/api/monzo/status", "monzo")
        stubs.ok("GET", "/api/snaptrade/connections", #"[{"id":"c1","disabled":false,"broker_name":"AJ Bell","type":"read"},{"id":"c2","disabled":true,"broker_name":"Robinhood","type":"read"}]"#)
    }

    func testLoadsEverything() async {
        routeAll(); let vm = ConnectionsViewModel(repo: env.repo); vm.load()
        await syncWait("data") { vm.ui.data != nil }
        let d = vm.ui.data!
        XCTAssertTrue(d.flags.snaptrade); XCTAssertEqual(d.connections.count, 2); XCTAssertEqual(d.monzo?.status, "connected"); XCTAssertEqual(ConnectionsText.t212Alerts(d.sync).count, 1)
        XCTAssertEqual(d.snaptrade?.activeConnections, 2); XCTAssertFalse(vm.ui.loading); XCTAssertNil(vm.ui.error)
    }
    func testOptionalCallsMayFailWithoutHidingTheRest() async {
        routeAll(); stubs.ok("GET", "/api/snaptrade/connections", "down", status: 500); stubs.ok("GET", "/api/monzo/status", "down", status: 500)
        let vm = ConnectionsViewModel(repo: env.repo); vm.load()
        await syncWait("data") { vm.ui.data != nil }
        let d = vm.ui.data!
        XCTAssertTrue(d.connections.isEmpty); XCTAssertNil(d.monzo); XCTAssertTrue(d.flags.gemini)
    }
    func testCredentialFailureShowsAnError() async {
        routeAll(); stubs.ok("GET", "/api/portfolio/credentials", "down", status: 500)
        let vm = ConnectionsViewModel(repo: env.repo); vm.load()
        await syncWait("error") { vm.ui.error != nil }
        XCTAssertNil(vm.ui.data); XCTAssertFalse(vm.ui.loading)
    }
    func testRefreshReplacesDataAndDoesNotWriteTheMonzoCache() async {
        routeAll(); let vm = ConnectionsViewModel(repo: env.repo)
        await vm.refresh()
        XCTAssertNotNil(vm.ui.data)
        let cached = await env.repo.monzoCached(); XCTAssertNil(cached, "Connections reads Monzo status without caching it")
    }
}
