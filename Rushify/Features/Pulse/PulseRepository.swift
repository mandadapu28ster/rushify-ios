import Foundation

/// Pulse endpoints. Reads are cache-first (an empty reply never overwrites good saved data); writes return nothing,
/// callers re-read the lists afterwards so the screen shows the server's truth.
extension Repository {
    func pulseRadarCached(_ scope: String) async -> Cached<PulseRadar>? { await cached("radar:\(scope)") }
    func pulseRadar(_ scope: String) async throws -> Cached<PulseRadar> {
        try await refresh("radar:\(scope)", path: "api/pulse/radar", query: [URLQueryItem(name: "scope", value: scope)]) { (r: PulseRadar) in r.dimensions.isEmpty }
    }

    func pulseNewsCached() async -> Cached<PulseNews>? { await cached("news") }
    func pulseNews(force: Bool = false) async throws -> Cached<PulseNews> {
        try await refresh("news", path: "api/pulse/news", query: force ? [URLQueryItem(name: "refresh", value: "true")] : []) { (n: PulseNews) in n.groups.isEmpty }
    }

    func pulseWatchlistsCached() async -> Cached<PulseWatchlists>? { await cached("watchlists") }
    func pulseWatchlists() async throws -> Cached<PulseWatchlists> {
        try await refresh("watchlists", path: "api/pulse/watchlists") { (w: PulseWatchlists) in w.watchlists.isEmpty }
    }

    /// Forced server refresh (force=true), then re-read the lists so the new quotes actually appear.
    func pulseRefreshWatchlistsNow() async throws -> (PulseWatchlistRefresh, Cached<PulseWatchlists>) {
        let data = try await api.send("POST", "api/pulse/watchlists/refresh", query: [URLQueryItem(name: "force", value: "true")])
        let summary: PulseWatchlistRefresh = try ApiClient.decode(data)
        return (summary, try await pulseWatchlists())
    }

    func pulseCreateWatchlist(name: String) async throws {
        try await api.sendJSON("POST", "api/pulse/watchlists", json: ["name": name])
    }
    func pulseDeleteWatchlist(id: Int) async throws {
        try await api.send("DELETE", "api/pulse/watchlists/\(id)")
    }
    func pulseAddWatchItem(listId: Int, hit: SymbolHit, fetchNews: Bool) async throws {
        let body: [String: Any] = ["yahoo_symbol": hit.symbol, "company_name": hit.name ?? NSNull(), "exchange": hit.exchange ?? NSNull(), "fetch_news": fetchNews]
        try await api.sendJSON("POST", "api/pulse/watchlists/\(listId)/items", json: body)
    }
    func pulsePatchWatchItem(listId: Int, itemId: Int, fetchNews: Bool) async throws {
        try await api.sendJSON("PATCH", "api/pulse/watchlists/\(listId)/items/\(itemId)", json: ["fetch_news": fetchNews])
    }
    func pulseDeleteWatchItem(listId: Int, itemId: Int) async throws {
        try await api.send("DELETE", "api/pulse/watchlists/\(listId)/items/\(itemId)")
    }
    func pulseSymbolSearch(_ q: String) async throws -> [SymbolHit] {
        try await api.get("api/portfolio/symbol-search", query: [URLQueryItem(name: "q", value: q)])
    }
}
