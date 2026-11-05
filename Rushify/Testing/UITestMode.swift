import Foundation

/// UI-test mode (debug builds only). `RUSHIFY_UITEST` selects a scenario; the app then talks to canned responses
/// bundled in UITestFixtures instead of a server, so XCUITests are deterministic and never touch real data.
///   1          signed in (default)
///   signedout  fresh install: Connect screen, then Login against the canned server
///   expired    signed in, but every authenticated call answers 401 (session expiry)
enum UITestMode {
    static var scenario: String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["RUSHIFY_UITEST"]
        #else
        return nil
        #endif
    }
    static var isActive: Bool { scenario != nil }

    /// Session, network and cache for the scenario, or nil outside UI-test mode.
    static func parts() -> (session: SessionManager, urlSession: URLSession, cache: CacheStore)? {
        #if DEBUG
        guard let scenario else { return nil }
        let session = SessionManager(store: MemoryKeyValueStore(), secrets: MemoryKeyValueStore())
        if scenario != "signedout" {
            session.setServer("http://uitest.local:8040")
            session.saveLogin(token: "uitest-token", me: Me(id: 7, email: "user@example.com", username: "TestUser"))
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FixtureURLProtocol.self]
        return (session, URLSession(configuration: cfg), MemoryCacheStore())
        #else
        return nil
        #endif
    }
}

#if DEBUG
/// Serves `UITestFixtures/<METHOD>_<path>.json` (slashes become underscores, numeric ids become `id`).
final class FixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func fixtureName(method: String, path: String, query: String?) -> String {
        let parts = path.split(separator: "/").map { Int($0) != nil ? "id" : String($0) }
        var name = method + "_" + parts.joined(separator: "_")
        if query?.contains("equity_series_step=daily") == true { name += "_daily" }
        return name
    }

    static func respond(method: String, path: String, query: String?, hasAuth: Bool, body: String) -> (status: Int, data: Data) {
        let publicPaths: Set<String> = ["/api/health", "/api/auth/login", "/api/auth/replace-password"]
        if UITestMode.scenario == "expired", hasAuth, !publicPaths.contains(path) { return (401, Data(#"{"detail":"Not authenticated"}"#.utf8)) }
        if path == "/api/auth/login", body.contains("wrong") { return (401, Data(#"{"detail":"Login failure try again."}"#.utf8)) }
        if path == "/api/auth/replace-password", body.contains("wrong") { return (401, Data(#"{"detail":"Incorrect password"}"#.utf8)) }
        let name = fixtureName(method: method, path: path, query: query)
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "UITestFixtures") ?? Bundle.main.url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: url) { return (200, data) }
        switch method {
        case "GET": return (404, Data(#"{"detail":"No fixture for \#(name)"}"#.utf8))
        case "DELETE": return (204, Data())
        default: return (200, Data("{}".utf8))
        }
    }

    override func startLoading() {
        guard let url = request.url else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        var bodyText = ""
        if let b = request.httpBody { bodyText = String(decoding: b, as: UTF8.self) }
        else if let s = request.httpBodyStream {
            s.open(); defer { s.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 1024)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: 1024); if n <= 0 { break }; data.append(buf, count: n) }
            bodyText = String(decoding: data, as: UTF8.self)
        }
        let r = Self.respond(method: request.httpMethod ?? "GET", path: url.path, query: url.query, hasAuth: request.value(forHTTPHeaderField: "Authorization") != nil, body: bodyText)
        let resp = HTTPURLResponse(url: url, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: r.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
