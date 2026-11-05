import XCTest
@testable import Rushify

final class SyncModelsTests: XCTestCase {
    private func dec<T: Decodable>(_ s: String, as t: T.Type = T.self) -> T { try! JSONDecoder().decode(T.self, from: Data(s.utf8)) }

    func testQuotaFixture() {
        let q: SyncQuota = decodeFixture("quota")
        XCTAssertEqual(q.maxPer24h, 3); XCTAssertEqual(q.t212.remaining, 2); XCTAssertEqual(q.t212.used, 1); XCTAssertTrue(q.t212.rateLimitAllows)
        XCTAssertEqual(q.snaptrade.remaining, 0); XCTAssertFalse(q.snaptrade.rateLimitAllows)
    }
    func testHistoryFixtureAndLenientLogs() {
        let h: [SyncLog] = decodeFixture("sync_history")
        XCTAssertEqual(h.map(\.id), [12, 11, 10]); XCTAssertEqual(h[2].errorMessage, "T212 rate limited"); XCTAssertFalse(h[2].success); XCTAssertNotNil(h[0].finishedAt)
        let l: SyncLog = dec(#"{"id":"7","kind":5}"#)
        XCTAssertEqual(l.id, 7); XCTAssertEqual(l.kind, ""); XCTAssertNil(l.finishedAt)
        let all: [SyncLog] = dec("[{}]"); XCTAssertEqual(all.count, 1)
    }
    func testStatusAndAccounts() {
        let s: SyncStatus = dec(#"{"t212_configured":true,"t212_needs_reconnect":false,"accounts":{"isa":{"configured":true,"needs_reconnect":true,"last_error":"401"},"sipp":{"configured":false}}}"#)
        XCTAssertTrue(s.t212Configured); XCTAssertEqual(s.accounts["isa"], SyncT212Account(configured: true, needsReconnect: true, lastError: "401")); XCTAssertEqual(s.accounts["sipp"]?.needsReconnect, false)
        let empty: SyncStatus = dec("{}"); XCTAssertFalse(empty.t212Configured); XCTAssertTrue(empty.accounts.isEmpty)
    }
    func testSnaptradeStatusAndPortalAndRunning() {
        let s: SyncSnaptradeStatus = dec(#"{"snaptrade_configured":true,"snaptrade_needs_reconnect":true,"snaptrade_disabled":[{"id":"a1","broker_name":"AJ Bell"}],"snaptrade_active_connections_count":2,"snaptrade_connections_count":3}"#)
        XCTAssertTrue(s.configured); XCTAssertTrue(s.needsReconnect); XCTAssertEqual(s.disabled, [SyncSnaptradeDisabled(id: "a1", brokerName: "AJ Bell")]); XCTAssertEqual(s.activeConnections, 2); XCTAssertEqual(s.connections, 3)
        XCTAssertEqual(dec(#"{"redirect_uri":"https://x.example"}"#, as: SyncPortalResponse.self).redirectUri, "https://x.example")
        let t: SyncT212Running = dec(#"{"t212_manual_in_progress":true,"active_sync_log_id":77}"#); XCTAssertTrue(t.inProgress); XCTAssertEqual(t.activeSyncLogId, 77)
        let sn: SyncSnaptradeRunning = dec(#"{"snaptrade_manual_in_progress":true,"active_sync_log_id":null}"#); XCTAssertTrue(sn.inProgress); XCTAssertNil(sn.activeSyncLogId)
        XCTAssertEqual(dec(#"{"sync_log_id":99}"#, as: SyncAccepted.self).syncLogId, 99); XCTAssertNil(dec("{}", as: SyncAccepted.self).syncLogId)
    }
    func testCredentialFlagsNeverModelSecrets() {
        let f: ConnectionsCredentialFlags = decodeFixture("credentials")
        XCTAssertTrue(f.t212Invest); XCTAssertTrue(f.t212Isa); XCTAssertFalse(f.t212Sipp); XCTAssertTrue(f.gemini); XCTAssertFalse(f.openai); XCTAssertTrue(f.snaptrade)
        XCTAssertEqual(f.aiProvider, "gemini"); XCTAssertEqual(f.openaiAgentMode, "chat_tools")
        let described = String(describing: f)
        for secret in ["abcd", "AIza", "t212_api_key", "consumer"] { XCTAssertFalse(described.contains(secret)) }
    }
    func testMonzoModels() {
        let m: MonzoStatus = decodeFixture("monzo")
        XCTAssertTrue(m.configured); XCTAssertEqual(m.status, "connected"); XCTAssertEqual(m.balanceRows, 4); XCTAssertEqual(m.skippedCount, 1); XCTAssertNil(m.lastError); XCTAssertNotNil(m.lastSyncedAt)
        let r: MonzoSyncResult = dec(#"{"monzo_configured":true,"status":"connected","sync":{"accounts":2,"pots":3}}"#)
        XCTAssertEqual(r.sync, MonzoSyncCounts(accounts: 2, pots: 3))
        XCTAssertNil(dec(#"{"status":"pending_approval","sync":null}"#, as: MonzoSyncResult.self).sync)
    }
}
