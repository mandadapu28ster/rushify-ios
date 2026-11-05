import Foundation

struct Cached<T> {
    var value: T
    var fetchedAt: Date
}

/// Cache-first data access. A response that looks empty never overwrites good saved data.
final class Repository {
    let api: ApiClient
    let session: SessionManager
    let events = DataEvents()
    private let cache: CacheStore
    private let clock: () -> Date

    init(api: ApiClient, session: SessionManager, cache: CacheStore, clock: @escaping () -> Date = Date.init) {
        self.api = api; self.session = session; self.cache = cache; self.clock = clock
    }

    private func key(_ name: String) -> String { "\(session.current.cacheScope)|\(name)" }

    func cached<T: Decodable>(_ name: String, as type: T.Type = T.self) async -> Cached<T>? {
        guard let e = await cache.get(key(name)), let v = try? JSONDecoder().decode(T.self, from: e.body) else { return nil }
        return Cached(value: v, fetchedAt: e.fetchedAt)
    }

    func refresh<T: Decodable>(_ name: String, path: String, query: [URLQueryItem] = [], as type: T.Type = T.self,
                               isEmpty: (T) -> Bool = { _ in false }) async throws -> Cached<T> {
        let data = try await api.send("GET", path, query: query)
        let fresh: T = try ApiClient.decode(data)
        if isEmpty(fresh), let old: Cached<T> = await cached(name) { return old }
        let now = clock()
        await cache.put(CacheEntry(key: key(name), body: data, fetchedAt: now))
        return Cached(value: fresh, fetchedAt: now)
    }

    func wipeCache() async { await cache.clear() }

    // MARK: Auth

    func health(baseURL: String) async throws -> Health {
        try ApiClient.decode(try await api.send("GET", "api/health", auth: false, baseURL: baseURL))
    }

    /// Password is sent once and never stored; only the returned token is kept (Keychain).
    func login(username: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let token: TokenResponse = try ApiClient.decode(try await api.send("POST", "api/auth/login", body: body, auth: false))
        let me: Me = try ApiClient.decode(try await api.send("GET", "api/auth/me", auth: false, bearer: token.accessToken))
        session.saveLogin(token: token.accessToken, me: me)
    }

    /// Debug builds only: sign in with an existing token (used to test against a real account without typing a password).
    func signIn(withToken token: String) async throws {
        let me: Me = try ApiClient.decode(try await api.send("GET", "api/auth/me", auth: false, bearer: token))
        session.saveLogin(token: token, me: me)
    }

    // MARK: Data

    func dashboardCached() async -> Cached<Dashboard>? { await cached("dashboard") }
    func dashboard() async throws -> Cached<Dashboard> {
        try await refresh("dashboard", path: "api/portfolio/dashboard") { (d: Dashboard) in d.rows.isEmpty && d.netWorthTotalBase == nil }
    }
}
