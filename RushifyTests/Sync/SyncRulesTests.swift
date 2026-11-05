import XCTest
@testable import Rushify

final class SyncRulesTests: XCTestCase {
    private let okQuota = SyncQuota(maxPer24h: 3, t212: SyncQuotaPart(used: 1, remaining: 2, rateLimitAllows: true), snaptrade: SyncQuotaPart(used: 1, remaining: 2, rateLimitAllows: true))
    private func ui(_ status: SyncStatus? = nil, _ snap: SyncSnaptradeStatus? = nil, _ quota: SyncQuota? = nil, _ cd: [SyncBroker: SyncCooldown] = [:]) -> SyncUi {
        SyncUi(status: status, snaptrade: snap, quota: quota, cooldowns: cd)
    }

    func testRateLimitDetectionAndCooldowns() {
        for s in ["HTTP 429", "Rate limit exceeded", "Too many requests", "throttled", "Temporarily unavailable"] { XCTAssertTrue(SyncRules.looksRateLimited(s), s) }
        XCTAssertFalse(SyncRules.looksRateLimited("bad credentials")); XCTAssertFalse(SyncRules.looksRateLimited(nil)); XCTAssertFalse(SyncRules.looksRateLimited("  "))
        XCTAssertEqual(SyncRules.cooldownFor("boom", now: 1_000).untilMs, 1_000 + 10_000)
        XCTAssertEqual(SyncRules.cooldownFor("429 slow down", now: 1_000).untilMs, 1_000 + 600_000)
        XCTAssertTrue(SyncRules.cooldownFor("429", now: 0).provider)
        XCTAssertFalse(SyncRules.cooldownFor(nil, now: 0).provider)
    }

    func testStaleAndEmptySyncErrorsGetFriendlyText() {
        XCTAssertEqual(SyncRules.errorText(nil), "Sync finished with an error.")
        XCTAssertEqual(SyncRules.errorText("   "), "Sync finished with an error.")
        XCTAssertEqual(SyncRules.errorText("Sync did not complete (stale: see history)"), "Sync did not complete (stale; task or server ended without finishing). Try again.")
        XCTAssertEqual(SyncRules.errorText("T212 down"), "T212 down")
    }

    func testT212DisabledReasonsInPriorityOrder() {
        let now: Int64 = 1_000_000
        XCTAssertNil(SyncRules.disabledReason(.t212, ui(SyncStatus(t212Configured: true), nil, okQuota), now: now))
        // cooldown beats everything
        XCTAssertEqual(SyncRules.disabledReason(.t212, ui(SyncStatus(t212Configured: true, t212NeedsReconnect: true), nil, okQuota, [.t212: SyncCooldown(untilMs: now + 5, provider: true)]), now: now), SyncRules.t212Provider)
        XCTAssertEqual(SyncRules.disabledReason(.t212, ui(SyncStatus(t212Configured: true), nil, okQuota, [.t212: SyncCooldown(untilMs: now + 5, provider: false)]), now: now), SyncRules.short)
        XCTAssertNil(SyncRules.disabledReason(.t212, ui(SyncStatus(t212Configured: true), nil, okQuota, [.t212: SyncCooldown(untilMs: now - 1, provider: true)]), now: now), "expired cooldown")
        XCTAssertTrue(SyncRules.disabledReason(.t212, ui(SyncStatus(t212Configured: true, t212NeedsReconnect: true), nil, okQuota), now: now)!.contains("expired"))
        XCTAssertTrue(SyncRules.disabledReason(.t212, ui(SyncStatus(t212Configured: false), nil, okQuota), now: now)!.contains("Add Trading 212 keys"))
        let none = SyncQuota(maxPer24h: 3, t212: SyncQuotaPart(used: 3, remaining: 0, rateLimitAllows: false), snaptrade: okQuota.snaptrade)
        XCTAssertTrue(SyncRules.disabledReason(.t212, ui(SyncStatus(t212Configured: true), nil, none), now: now)!.contains("limit reached"))
        let soon = SyncQuota(maxPer24h: 3, t212: SyncQuotaPart(used: 1, remaining: 2, rateLimitAllows: false), snaptrade: okQuota.snaptrade)
        XCTAssertEqual(SyncRules.disabledReason(.t212, ui(SyncStatus(t212Configured: true), nil, soon), now: now), "Please wait a moment before syncing again.")
        XCTAssertNil(SyncRules.disabledReason(.t212, ui(nil, nil, nil), now: now), "nothing loaded yet: not blocked by rules")
    }

    func testSnaptradeDisabledReasons() {
        func r(_ s: SyncSnaptradeStatus) -> String? { SyncRules.disabledReason(.snaptrade, ui(nil, s, okQuota), now: 0) }
        XCTAssertNil(r(SyncSnaptradeStatus(configured: true, activeConnections: 1)))
        XCTAssertTrue(r(SyncSnaptradeStatus(configured: false))!.contains("not fully configured"))
        XCTAssertTrue(r(SyncSnaptradeStatus(configured: true, authFailed: true))!.contains("expired"))
        XCTAssertTrue(r(SyncSnaptradeStatus(configured: true, needsBrokerLink: true))!.contains("connection portal"))
        XCTAssertTrue(r(SyncSnaptradeStatus(configured: true, needsReconnect: true))!.contains("reconnecting"))
        XCTAssertEqual(SyncRules.disabledReason(.snaptrade, ui(nil, SyncSnaptradeStatus(configured: true), SyncQuota(maxPer24h: 3, t212: okQuota.t212, snaptrade: SyncQuotaPart(used: 3, remaining: 0, rateLimitAllows: false))), now: 0)?.hasPrefix("Manual sync limit reached"), true)
        XCTAssertEqual(SyncRules.disabledReason(.snaptrade, ui(nil, nil, okQuota, [.snaptrade: SyncCooldown(untilMs: 10, provider: true)]), now: 0), SyncRules.snaptradeProvider)
    }

    func testBrokerLabelsAndKindLabels() {
        XCTAssertEqual(SyncBroker.t212.label, "Trading 212"); XCTAssertEqual(SyncBroker.snaptrade.label, "SnapTrade")
        XCTAssertEqual(SyncBroker.t212.rawValue, "T212"); XCTAssertEqual(SyncBroker.snaptrade.rawValue, "SNAPTRADE")
        XCTAssertEqual(SyncKindLabel.of("manual"), "Trading 212 (manual)")
        XCTAssertEqual(SyncKindLabel.of("scheduled"), "Trading 212 (scheduled)")
        XCTAssertEqual(SyncKindLabel.of("snaptrade_manual"), "SnapTrade (manual)")
        XCTAssertEqual(SyncKindLabel.of("snaptrade_scheduled"), "SnapTrade (scheduled)")
    }

    func testSafeUrlOnlyAllowsHttpAndHttps() {
        XCTAssertEqual(SyncSafeUrl.httpOrNull(" https://app.snaptrade.com/connect?x=1 ")?.absoluteString, "https://app.snaptrade.com/connect?x=1")
        XCTAssertNotNil(SyncSafeUrl.httpOrNull("http://x.example/c"))
        for bad in ["javascript:alert(1)", "intent://x#Intent;end", "file:///etc/passwd", "content://x/y", "data:text/html,hi", "ftp://x.example", "x.example/c", "//x.example", "", "  ", "https://", "https://x.example/\u{0007}"] {
            XCTAssertNil(SyncSafeUrl.httpOrNull(bad), bad)
        }
        XCTAssertNil(SyncSafeUrl.httpOrNull(nil))
    }
}
