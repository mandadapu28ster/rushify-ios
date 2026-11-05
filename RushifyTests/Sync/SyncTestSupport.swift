import XCTest
@testable import Rushify

/// Routes stubbed requests by "METHOD /path". Unrouted requests answer 404. Never touches a real server.
final class SyncStubs {
    typealias Handler = (URLRequest) -> MockURLProtocol.Stub
    private var routes: [String: Handler] = [:]
    private let lock = NSLock()

    init() {
        MockURLProtocol.reset { [unowned self] req in
            self.lock.lock(); let h = self.routes["\(req.httpMethod ?? "GET") \(req.url?.path ?? "")"]; self.lock.unlock()
            return h?(req) ?? .init(status: 404, body: Data(#"{"detail":"no stub"}"#.utf8))
        }
    }
    deinit { MockURLProtocol.reset() }

    func route(_ method: String, _ path: String, _ h: @escaping Handler) { lock.lock(); routes["\(method) \(path)"] = h; lock.unlock() }
    func ok(_ method: String, _ path: String, _ body: String, status: Int = 200) { route(method, path) { _ in .init(status: status, body: Data(body.utf8)) } }
    func fixtureRoute(_ method: String, _ path: String, _ name: String) { route(method, path) { _ in .init(body: fixture(name)) } }

    func count(_ method: String, _ path: String) -> Int { MockURLProtocol.seen().filter { $0.httpMethod == method && $0.url?.path == path }.count }
    func requests(_ method: String, _ path: String) -> [URLRequest] { MockURLProtocol.seen().filter { $0.httpMethod == method && $0.url?.path == path } }
    func bodyJSON(_ method: String, _ path: String) -> [String: Any]? {
        guard let r = requests(method, path).first, let d = syncBodyData(r) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// The standard Sync screen stubs (T212 + SnapTrade configured, 2 syncs left, nothing running).
    func routeSync() {
        ok("GET", "/api/sync/status", #"{"t212_configured":true,"accounts":{}}"#)
        ok("GET", "/api/snaptrade/status", #"{"snaptrade_configured":true,"snaptrade_active_connections_count":1}"#)
        route("GET", "/api/sync/manual-quota") { _ in .init(body: Data(String(decoding: fixture("quota"), as: UTF8.self)
            .replacingOccurrences(of: "\"remaining\":0", with: "\"remaining\":2")
            .replacingOccurrences(of: "\"rate_limit_allows\":false", with: "\"rate_limit_allows\":true").utf8)) }
        fixtureRoute("GET", "/api/sync/history", "sync_history")
        ok("GET", "/api/sync/manual/t212-running", #"{"t212_manual_in_progress":false,"active_sync_log_id":null}"#)
        ok("GET", "/api/sync/manual/snaptrade-running", #"{"snaptrade_manual_in_progress":false,"active_sync_log_id":null}"#)
    }
}

func syncBodyData(_ r: URLRequest) -> Data? {
    r.httpBody ?? r.httpBodyStream.map { s in
        s.open(); defer { s.close() }
        var d = Data(); var buf = [UInt8](repeating: 0, count: 512)
        while s.hasBytesAvailable { let n = s.read(&buf, maxLength: 512); if n <= 0 { break }; d.append(buf, count: n) }
        return d
    }
}

/// Polls until the condition holds (real time, short steps) and fails the test on timeout.
@MainActor
func syncWait(_ what: String = "condition", timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line, _ cond: () -> Bool) async {
    let end = Date().addingTimeInterval(timeout)
    while !cond() {
        if Date() > end { XCTFail("Timed out waiting for \(what)", file: file, line: line); return }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}
