import Foundation

// Models for Sync, Connections and Monzo. Lenient decoding (missing/mistyped keys fall back to defaults).
// Only non-secret flags are ever modelled; masked key values in /portfolio/credentials are deliberately ignored.

struct SyncT212Account: Equatable { var configured = false; var needsReconnect = false; var lastError: String? }
extension SyncT212Account: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        configured = f.bool("configured") ?? false; needsReconnect = f.bool("needs_reconnect") ?? false; lastError = f.str("last_error")
    }
}

struct SyncStatus: Equatable {
    var t212Configured = false
    var t212NeedsReconnect = false
    var accounts: [String: SyncT212Account] = [:]
}
extension SyncStatus: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        t212Configured = f.bool("t212_configured") ?? false; t212NeedsReconnect = f.bool("t212_needs_reconnect") ?? false
        accounts = f.obj("accounts") ?? [:]
    }
}

struct SyncSnaptradeDisabled: Equatable { var id = ""; var brokerName: String? }
extension SyncSnaptradeDisabled: Decodable {
    init(from decoder: Decoder) throws { let f = try Fields(decoder); id = f.str("id") ?? ""; brokerName = f.str("broker_name") }
}

struct SyncSnaptradeStatus: Equatable {
    var configured = false
    var needsReconnect = false
    var needsBrokerLink = false
    var authFailed = false
    var disabled: [SyncSnaptradeDisabled] = []
    var connections = 0
    var activeConnections = 0
}
extension SyncSnaptradeStatus: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        configured = f.bool("snaptrade_configured") ?? false; needsReconnect = f.bool("snaptrade_needs_reconnect") ?? false
        needsBrokerLink = f.bool("snaptrade_needs_broker_link") ?? false; authFailed = f.bool("snaptrade_auth_failed") ?? false
        disabled = f.list("snaptrade_disabled"); connections = f.int("snaptrade_connections_count") ?? 0
        activeConnections = f.int("snaptrade_active_connections_count") ?? 0
    }
}

struct SyncSnaptradeConnection: Equatable { var id = ""; var disabled = false; var brokerName: String?; var type: String? }
extension SyncSnaptradeConnection: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        id = f.str("id") ?? ""; disabled = f.bool("disabled") ?? false; brokerName = f.str("broker_name"); type = f.str("type")
    }
}

struct SyncQuotaPart: Equatable { var used = 0; var remaining = 0; var rateLimitAllows = true }
extension SyncQuotaPart: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        used = f.int("used_in_window") ?? 0; remaining = f.int("remaining") ?? 0; rateLimitAllows = f.bool("rate_limit_allows") ?? true
    }
}

struct SyncQuota: Equatable { var maxPer24h = 3; var t212 = SyncQuotaPart(); var snaptrade = SyncQuotaPart() }
extension SyncQuota: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        maxPer24h = f.int("max_per_24h") ?? 3; t212 = f.obj("t212") ?? SyncQuotaPart(); snaptrade = f.obj("snaptrade") ?? SyncQuotaPart()
    }
}

struct SyncLog: Equatable { var id = 0; var kind = ""; var startedAt: String?; var finishedAt: String?; var success = false; var errorMessage: String? }
extension SyncLog: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        id = f.int("id") ?? 0; kind = f.str("kind") ?? ""; startedAt = f.str("started_at"); finishedAt = f.str("finished_at")
        success = f.bool("success") ?? false; errorMessage = f.str("error_message")
    }
}

struct SyncAccepted: Equatable { var syncLogId: Int?; var detail: String? }
extension SyncAccepted: Decodable {
    init(from decoder: Decoder) throws { let f = try Fields(decoder); syncLogId = f.int("sync_log_id"); detail = f.str("detail") }
}

struct SyncT212Running: Equatable { var inProgress = false; var activeSyncLogId: Int? }
extension SyncT212Running: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder); inProgress = f.bool("t212_manual_in_progress") ?? false; activeSyncLogId = f.int("active_sync_log_id")
    }
}

struct SyncSnaptradeRunning: Equatable { var inProgress = false; var activeSyncLogId: Int? }
extension SyncSnaptradeRunning: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder); inProgress = f.bool("snaptrade_manual_in_progress") ?? false; activeSyncLogId = f.int("active_sync_log_id")
    }
}

struct SyncPortalResponse: Equatable { var redirectUri: String? }
extension SyncPortalResponse: Decodable {
    init(from decoder: Decoder) throws { let f = try Fields(decoder); redirectUri = f.str("redirect_uri") }
}

/// Only the non-secret fields of GET /portfolio/credentials.
struct ConnectionsCredentialFlags: Equatable {
    var t212Invest = false, t212Isa = false, t212Sipp = false
    var gemini = false, openai = false, snaptrade = false
    var aiProvider: String?
    var openaiAgentMode: String?
}
extension ConnectionsCredentialFlags: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        t212Invest = f.bool("t212_invest_configured") ?? false; t212Isa = f.bool("t212_isa_configured") ?? false
        t212Sipp = f.bool("t212_sipp_configured") ?? false; gemini = f.bool("gemini_configured") ?? false
        openai = f.bool("openai_configured") ?? false; snaptrade = f.bool("snaptrade_configured") ?? false
        aiProvider = f.str("ai_provider"); openaiAgentMode = f.str("openai_agent_mode")
    }
}

struct MonzoStatus: Equatable {
    var configured = false
    var status: String?
    var lastError: String?
    var lastSyncedAt: String?
    var skippedCount = 0
    var balanceRows = 0
}
extension MonzoStatus: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        configured = f.bool("monzo_configured") ?? false; status = f.str("status"); lastError = f.str("last_error")
        lastSyncedAt = f.str("last_synced_at"); skippedCount = f.int("skipped_count") ?? 0; balanceRows = f.int("balance_rows") ?? 0
    }
}

struct MonzoSyncCounts: Equatable { var accounts = 0; var pots = 0 }
extension MonzoSyncCounts: Decodable {
    init(from decoder: Decoder) throws { let f = try Fields(decoder); accounts = f.int("accounts") ?? 0; pots = f.int("pots") ?? 0 }
}

/// POST /monzo/sync: `sync` is nil while the user still has to approve access in the Monzo app.
struct MonzoSyncResult: Equatable {
    var configured = false
    var status: String?
    var lastError: String?
    var lastSyncedAt: String?
    var skippedCount = 0
    var balanceRows = 0
    var sync: MonzoSyncCounts?
}
extension MonzoSyncResult: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        configured = f.bool("monzo_configured") ?? false; status = f.str("status"); lastError = f.str("last_error")
        lastSyncedAt = f.str("last_synced_at"); skippedCount = f.int("skipped_count") ?? 0; balanceRows = f.int("balance_rows") ?? 0
        sync = f.obj("sync")
    }
}

/// `result` is nil when the server answered 2xx with an empty body (e.g. 204).
struct MonzoSyncOutcome: Equatable { var result: MonzoSyncResult? }

private struct MonzoRefreshResult: Decodable {
    var refreshed = false
    init(from decoder: Decoder) throws { refreshed = try Fields(decoder).bool("refreshed") ?? false }
}

// MARK: Endpoints

extension Repository {
    func syncStatus() async throws -> SyncStatus { try await api.get("api/sync/status") }
    func syncSnaptradeStatus() async throws -> SyncSnaptradeStatus { try await api.get("api/snaptrade/status") }
    func syncQuota() async throws -> SyncQuota { try await api.get("api/sync/manual-quota") }
    func syncLog(_ id: Int) async throws -> SyncLog { try await api.get("api/sync/log/\(id)") }
    func syncT212Running() async throws -> SyncT212Running { try await api.get("api/sync/manual/t212-running") }
    func syncSnaptradeRunning() async throws -> SyncSnaptradeRunning { try await api.get("api/sync/manual/snaptrade-running") }

    /// Cached only so the history can be refreshed; it is never shown, just read to detect that a sync finished.
    func syncHistoryCached() async -> Cached<[SyncLog]>? { await cached("sync-history") }
    func syncHistory() async throws -> Cached<[SyncLog]> { try await refresh("sync-history", path: "api/sync/history") }

    /// Starts a manual sync. Sends `order_history_full_refresh: false`, exactly like Android.
    func syncStart(_ broker: SyncBroker) async throws -> SyncAccepted {
        let path = broker == .t212 ? "api/sync/manual" : "api/snaptrade/sync/manual"
        let data = try await api.sendJSON("POST", path, json: ["order_history_full_refresh": false])
        return try ApiClient.decode(data)
    }

    func syncPortalUrl(reconnectId: String?) async throws -> SyncPortalResponse {
        let body: [String: Any] = reconnectId.map { ["reconnect_authorization_id": $0] } ?? [:]
        return try ApiClient.decode(try await api.sendJSON("POST", "api/snaptrade/portal-url", json: body))
    }

    func connectionsFlags() async throws -> ConnectionsCredentialFlags { try await api.get("api/portfolio/credentials") }
    func connectionsSnaptradeConnections() async throws -> [SyncSnaptradeConnection] { try await api.get("api/snaptrade/connections") }

    func monzoCached() async -> Cached<MonzoStatus>? { await cached("monzo") }
    func monzo() async throws -> Cached<MonzoStatus> { try await refresh("monzo", path: "api/monzo/status") }

    /// An empty 2xx body (204) is a success with no result.
    func monzoSyncNow() async throws -> MonzoSyncOutcome {
        let data = try await api.send("POST", "api/monzo/sync")
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return MonzoSyncOutcome(result: nil) }
        return MonzoSyncOutcome(result: try ApiClient.decode(data))
    }
}

/// Like the web: refresh Monzo when the app opens, only if the server says it is stale. Failure is ignored.
func syncMonzoRefreshIfStale(repo: Repository) async -> Bool {
    do {
        let data = try await repo.api.send("POST", "api/monzo/refresh-if-stale")
        let r: MonzoRefreshResult = try ApiClient.decode(data)
        if r.refreshed { repo.notifyChanged() }
        return r.refreshed
    } catch { return false }
}

/// Only absolute http/https URLs with a host may be opened (same rule as Android's SafeUrl).
enum SyncSafeUrl {
    static func httpOrNull(_ raw: String?) -> URL? {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return nil }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
