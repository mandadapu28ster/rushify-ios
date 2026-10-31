import XCTest
@testable import Rushify

final class SessionTests: XCTestCase {
    private func make() -> (SessionManager, MemoryKeyValueStore, MemoryKeyValueStore) {
        let store = MemoryKeyValueStore(), secrets = MemoryKeyValueStore()
        return (SessionManager(store: store, secrets: secrets), store, secrets)
    }
    private let me = Me(id: 7, email: "u@example.com", username: "TestUser", role: "user", baseCurrency: "GBP")

    func testSetServerReportsChangeAndDropsTheSession() {
        let (s, _, _) = make()
        XCTAssertTrue(s.setServer("http://a:1")); s.saveLogin(token: "t", me: me); XCTAssertTrue(s.current.loggedIn)
        XCTAssertFalse(s.setServer("http://a:1")); XCTAssertTrue(s.current.loggedIn, "same server keeps the session")
        XCTAssertTrue(s.setServer("http://b:2")); XCTAssertFalse(s.current.loggedIn); XCTAssertNil(s.current.userId)
    }
    func testTokenGoesToTheSecureStoreOnly() {
        let (s, store, secrets) = make()
        s.setServer("http://a:1"); s.saveLogin(token: "secret-jwt", me: me)
        XCTAssertEqual(secrets.get("token"), "secret-jwt"); XCTAssertNil(store.get("token"))
        XCTAssertFalse((store.get("username") ?? "").contains("secret"))
    }
    func testSessionSurvivesARestart() {
        let (s, store, secrets) = make()
        s.setServer("http://a:1"); s.saveLogin(token: "t", me: me)
        let again = SessionManager(store: store, secrets: secrets)
        XCTAssertTrue(again.current.loggedIn); XCTAssertEqual(again.current.username, "TestUser"); XCTAssertEqual(again.current.userId, 7)
    }
    func testExpireIsSingleFlightAndSignInClearsTheFlag() {
        let (s, _, secrets) = make()
        s.setServer("http://a:1"); s.saveLogin(token: "t", me: me)
        XCTAssertTrue(s.expire()); XCTAssertFalse(s.expire(), "second 401 does nothing")
        XCTAssertTrue(s.current.expired); XCTAssertFalse(s.current.loggedIn); XCTAssertNil(secrets.get("token"))
        s.saveLogin(token: "t2", me: me); XCTAssertFalse(s.current.expired); XCTAssertTrue(s.current.loggedIn)
    }
    func testLogoutKeepsTheServerButForgetsTheUser() {
        let (s, _, _) = make()
        s.setServer("http://a:1"); s.saveLogin(token: "t", me: me); s.logout()
        XCTAssertEqual(s.current.serverUrl, "http://a:1"); XCTAssertNil(s.current.token); XCTAssertNil(s.current.username)
        s.clearServer(); XCTAssertNil(s.current.serverUrl)
    }
    func testCacheScopeSeparatesServersAndUsers() {
        let (s, _, _) = make()
        s.setServer("http://a:1"); s.saveLogin(token: "t", me: me); let one = s.current.cacheScope
        s.saveLogin(token: "t", me: Me(id: 8, username: "Other")); XCTAssertNotEqual(one, s.current.cacheScope)
        s.setServer("http://b:2"); XCTAssertTrue(s.current.cacheScope.hasPrefix("http://b:2"))
    }
    func testCleartextAcknowledgementIsPerServer() {
        let (s, _, _) = make()
        XCTAssertFalse(s.cleartextAcknowledged("http://a:1")); s.acknowledgeCleartext("http://a:1")
        XCTAssertTrue(s.cleartextAcknowledged("http://a:1")); XCTAssertFalse(s.cleartextAcknowledged("http://b:1"))
    }
    func testHideBalancesPersists() { let (s, store, secrets) = make(); s.hideBalances = true; XCTAssertTrue(SessionManager(store: store, secrets: secrets).hideBalances) }
    func testAdminAndCleartextFlags() {
        let (s, _, _) = make()
        s.setServer("http://a:1"); s.saveLogin(token: "t", me: Me(id: 1, username: "root", role: "Admin"))
        XCTAssertTrue(s.current.isAdmin); XCTAssertTrue(s.current.cleartext); s.setServer("https://a"); XCTAssertFalse(s.current.cleartext)
    }
}

final class ApiClientTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    private func header(_ r: URLRequest, _ k: String) -> String? { r.value(forHTTPHeaderField: k) }

    func testSignedInGetSendsTheBearerTokenToTheStoredServer() async throws {
        let env = TestEnv(); MockURLProtocol.reset { _ in .init(body: json("{}")) }
        _ = try await env.api.send("GET", "api/portfolio/dashboard", query: [URLQueryItem(name: "a", value: "b")])
        let r = MockURLProtocol.seen()[0]
        XCTAssertEqual(r.url?.absoluteString, "http://server.test:8040/api/portfolio/dashboard?a=b"); XCTAssertEqual(header(r, "Authorization"), "Bearer jwt-token"); XCTAssertEqual(header(r, "Accept"), "application/json")
    }
    func testNoTokenMeansNoAuthorizationHeader() async throws {
        let env = TestEnv(signedIn: false); MockURLProtocol.reset { _ in .init(body: json("{}")) }
        _ = try await env.api.send("GET", "api/health"); XCTAssertNil(header(MockURLProtocol.seen()[0], "Authorization"))
    }
    func testUnauthenticatedCallsSkipTheTokenAndNeverEndTheSession() async {
        let env = TestEnv(); MockURLProtocol.reset { _ in .init(status: 401, body: json(#"{"detail":"Incorrect password"}"#)) }
        do { _ = try await env.api.send("POST", "api/auth/change-password", body: json("{}"), auth: false); XCTFail() } catch { XCTAssertEqual(error as? ApiError, .badCredentials("Incorrect password")) }
        XCTAssertNil(header(MockURLProtocol.seen()[0], "Authorization")); XCTAssertTrue(env.session.current.loggedIn, "a wrong password must not sign the user out")
    }
    func testA401WhileSignedInExpiresTheSessionOnce() async {
        let env = TestEnv(); MockURLProtocol.reset { _ in .init(status: 401, body: json(#"{"detail":"Not authenticated"}"#)) }
        do { _ = try await env.api.send("GET", "api/x"); XCTFail() } catch { XCTAssertEqual(error as? ApiError, .sessionExpired) }
        XCTAssertTrue(env.session.current.expired); XCTAssertFalse(env.session.current.loggedIn)
    }
    func testErrorTable() async {
        let env = TestEnv(signedIn: false)
        func code(_ status: Int, _ body: String) async -> ApiError? {
            MockURLProtocol.reset { _ in .init(status: status, body: json(body)) }
            do { _ = try await env.api.send("GET", "api/x"); return nil } catch { return error as? ApiError }
        }
        let c1 = await code(403, #"{"detail":"Account is inactive"}"#); XCTAssertEqual(c1, .inactive("Account is inactive"))
        let c2 = await code(403, "{}"); XCTAssertEqual(c2, .locked("You are locked, wait for one day and try again"))
        let c3 = await code(400, #"{"detail":"Gemini key not configured"}"#); XCTAssertEqual(c3, .notConfigured("Gemini key not configured"))
        let c4 = await code(400, #"{"detail":"No fields to update"}"#); XCTAssertEqual(c4, .server(400, "No fields to update"))
        let c5 = await code(429, #"{"detail":"Daily manual sync limit reached"}"#); XCTAssertEqual(c5, .quotaReached("Daily manual sync limit reached"))
        let c6 = await code(409, "{}"); XCTAssertEqual(c6, .syncRunning("A sync is already running"))
        let c7 = await code(422, #"{"detail":[{"msg":"quantity must be greater than zero"},{"msg":"broker_name is required"}]}"#); XCTAssertEqual(c7, .server(422, "quantity must be greater than zero; broker_name is required"))
        let c8 = await code(500, "<html>boom</html>"); XCTAssertEqual(c8, .server(500, "Server error (500)"))
        let c9 = await code(401, "{}"); XCTAssertEqual(c9, .badCredentials("Login failure try again."))
    }
    func testTransportFailuresGetFriendlyMessages() async {
        let env = TestEnv(); func fail(_ c: URLError.Code) async -> ApiError? {
            MockURLProtocol.reset { _ in .init(error: c) }
            do { _ = try await env.api.send("GET", "api/x"); return nil } catch { return error as? ApiError }
        }
        let a = await fail(.notConnectedToInternet); XCTAssertEqual(a, .network("No internet connection"))
        let b = await fail(.timedOut); XCTAssertEqual(b, .network("The server took too long to respond"))
        let c = await fail(.cannotConnectToHost); XCTAssertEqual(c, .network("Could not connect to the server"))
        XCTAssertTrue(env.session.current.loggedIn, "a network failure never signs the user out")
    }
    func testNoServerConfigured() async {
        let env = TestEnv(); env.session.clearServer()
        do { _ = try await env.api.send("GET", "api/x"); XCTFail() } catch { XCTAssertEqual(error as? ApiError, .network("No server configured")) }
    }
    func testUnexpectedBodyOn200IsAReadableError() async {
        let env = TestEnv(); MockURLProtocol.reset { _ in .init(body: json("<html>login page</html>")) }
        do { let _: Me = try await env.api.get("api/auth/me"); XCTFail() } catch { XCTAssertEqual(error as? ApiError, .server(200, "Unexpected response from server")) }
    }
    func testAnHttpsToHttpRedirectIsRefused() {
        let session = URLSession(configuration: .ephemeral), delegate = NoDowngradeDelegate()
        func redirected(from: String, to: String) -> URLRequest? {
            let task = session.dataTask(with: URLRequest(url: URL(string: from)!))
            let resp = HTTPURLResponse(url: URL(string: from)!, statusCode: 302, httpVersion: nil, headerFields: nil)!
            var out: URLRequest? = URLRequest(url: URL(string: "http://sentinel")!)
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: resp, newRequest: URLRequest(url: URL(string: to)!)) { out = $0 }
            return out
        }
        XCTAssertNil(redirected(from: "https://a.test/x", to: "http://a.test/x"), "downgrade refused")
        XCTAssertNotNil(redirected(from: "http://a.test/x", to: "https://a.test/x")); XCTAssertNotNil(redirected(from: "https://a.test/x", to: "https://b.test/x"))
    }
}

final class RepositoryTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    private func route(_ table: [String: (Int, String)]) {
        MockURLProtocol.reset { req in
            let key = "\(req.httpMethod ?? "GET") \(req.url!.path)"
            guard let (status, body) = table[key] else { return .init(status: 404) }
            return .init(status: status, body: json(body))
        }
    }
    private let meJson = #"{"id":9,"email":"a@b.c","username":"Nine","role":"user","base_currency":"GBP"}"#

    func testLoginSignsInWithTheReturnedTokenAndNeverStoresThePassword() async throws {
        let env = TestEnv(signedIn: false)
        route(["POST /api/auth/login": (200, #"{"access_token":"new-token","token_type":"bearer"}"#), "GET /api/auth/me": (200, meJson)])
        try await env.repo.login(username: "Nine", password: "hunter2-secret")
        XCTAssertEqual(env.session.current.token, "new-token"); XCTAssertEqual(env.session.current.userId, 9)
        let reqs = MockURLProtocol.seen()
        XCTAssertEqual(reqs.count, 2); XCTAssertNil(reqs[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(reqs[1].value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
        let sent = reqs[0].httpBody ?? reqs[0].httpBodyStream.map { s in s.open(); defer { s.close() }; var d = Data(); var buf = [UInt8](repeating: 0, count: 512); while s.hasBytesAvailable { let n = s.read(&buf, maxLength: 512); if n <= 0 { break }; d.append(buf, count: n) }; return d }
        let body = try JSONSerialization.jsonObject(with: sent ?? Data()) as? [String: String]
        XCTAssertEqual(body?["username"], "Nine"); XCTAssertEqual(body?["password"], "hunter2-secret")
        let stored = [env.session.current.token, env.session.current.username, env.session.current.serverUrl].compactMap { $0 }
        XCTAssertFalse(stored.contains { $0.contains("hunter2") })
    }
    func testWrongPasswordShowsTheServerMessageAndLeavesNoSession() async {
        let env = TestEnv(signedIn: false); env.session.clearExpiredFlag()
        route(["POST /api/auth/login": (401, #"{"detail":"Login failure try again."}"#)])
        do { try await env.repo.login(username: "x", password: "y"); XCTFail() } catch { XCTAssertEqual(error as? ApiError, .badCredentials("Login failure try again.")) }
        XCTAssertFalse(env.session.current.loggedIn); XCTAssertFalse(env.session.current.expired)
    }
    func testLockedAccountMessage() async {
        let env = TestEnv(signedIn: false); route(["POST /api/auth/login": (403, #"{"detail":"Too many attempts, locked for 24h"}"#)])
        do { try await env.repo.login(username: "x", password: "y"); XCTFail() } catch { XCTAssertEqual(error as? ApiError, .locked("Too many attempts, locked for 24h")) }
    }
    func testHealthUsesTheTypedAddressWithoutAToken() async throws {
        let env = TestEnv(); MockURLProtocol.reset { _ in .init(body: json(#"{"status":"ok","app":"rushify","version":"0.2.2"}"#)) }
        let h = try await env.repo.health(baseURL: "https://typed.example.com")
        XCTAssertEqual(h.version, "0.2.2"); let r = MockURLProtocol.seen()[0]
        XCTAssertEqual(r.url?.absoluteString, "https://typed.example.com/api/health"); XCTAssertNil(r.value(forHTTPHeaderField: "Authorization"))
    }
    func testTokenSignInForDebugBuilds() async throws {
        let env = TestEnv(signedIn: false); route(["GET /api/auth/me": (200, meJson)])
        try await env.repo.signIn(withToken: "tok"); XCTAssertEqual(env.session.current.token, "tok"); XCTAssertEqual(env.session.current.username, "Nine")
    }
    func testDashboardIsCachedAndServedWhenTheNetworkFails() async throws {
        let env = TestEnv(); let dash = String(data: fixture("dashboard"), encoding: .utf8)!
        var cachedBefore = await env.repo.dashboardCached(); XCTAssertNil(cachedBefore)
        route(["GET /api/portfolio/dashboard": (200, dash)])
        let fresh = try await env.repo.dashboard(); XCTAssertEqual(fresh.fetchedAt, env.now)
        cachedBefore = await env.repo.dashboardCached(); XCTAssertEqual(cachedBefore?.value.totalMarketValueBase, Decimal(string: "1000.50"))
        MockURLProtocol.reset { _ in .init(error: .notConnectedToInternet) }
        do { _ = try await env.repo.dashboard(); XCTFail() } catch { XCTAssertEqual(error as? ApiError, .network("No internet connection")) }
        let still = await env.repo.dashboardCached(); XCTAssertNotNil(still, "a failed refresh keeps the saved copy")
    }
    func testAnEmptyResponseNeverOverwritesGoodData() async throws {
        let env = TestEnv(); let dash = String(data: fixture("dashboard"), encoding: .utf8)!
        route(["GET /api/portfolio/dashboard": (200, dash)]); _ = try await env.repo.dashboard()
        route(["GET /api/portfolio/dashboard": (200, "{}")])
        let result = try await env.repo.dashboard()
        XCTAssertEqual(result.value.totalMarketValueBase, Decimal(string: "1000.50"), "kept the previous data instead of the empty reply")
        let saved = await env.repo.dashboardCached(); XCTAssertFalse(saved!.value.rows.isEmpty)
    }
    func testCacheIsPrivatePerUserAndWipedOnDemand() async throws {
        let env = TestEnv(); let dash = String(data: fixture("dashboard"), encoding: .utf8)!
        route(["GET /api/portfolio/dashboard": (200, dash)]); _ = try await env.repo.dashboard()
        env.session.saveLogin(token: "t2", me: Me(id: 99, username: "Someone else"))
        let other = await env.repo.dashboardCached(); XCTAssertNil(other, "another account never sees the previous user's data")
        env.session.saveLogin(token: "t", me: Me(id: 7, username: "TestUser")); let back = await env.repo.dashboardCached(); XCTAssertNotNil(back)
        await env.repo.wipeCache(); let wiped = await env.repo.dashboardCached(); XCTAssertNil(wiped)
    }
    func testSessionExpiryDuringARefreshSignsOut() async {
        let env = TestEnv(); route(["GET /api/portfolio/dashboard": (401, #"{"detail":"Not authenticated"}"#)])
        do { _ = try await env.repo.dashboard(); XCTFail() } catch { XCTAssertEqual(error as? ApiError, .sessionExpired) }
        XCTAssertTrue(env.session.current.expired)
    }
}

final class FileCacheStoreTests: XCTestCase {
    func testRoundTripReplaceAndClear() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rushify-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileCacheStore(directory: dir)
        var miss = await store.get("k"); XCTAssertNil(miss)
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        await store.put(CacheEntry(key: "k", body: Data("one".utf8), fetchedAt: t))
        var hit = await store.get("k"); XCTAssertEqual(hit?.body, Data("one".utf8)); XCTAssertEqual(hit?.fetchedAt, t)
        await store.put(CacheEntry(key: "k", body: Data("two".utf8), fetchedAt: t)); hit = await store.get("k"); XCTAssertEqual(hit?.body, Data("two".utf8))
        await store.put(CacheEntry(key: "http://a|1|dashboard", body: Data("x".utf8), fetchedAt: t))
        let again = FileCacheStore(directory: dir), survived = await again.get("http://a|1|dashboard"); XCTAssertNotNil(survived, "survives a restart")
        await store.clear(); miss = await store.get("k"); XCTAssertNil(miss)
    }
}
