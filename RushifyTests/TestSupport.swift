import Foundation
@testable import Rushify

final class FixtureLocator {}
func fixture(_ name: String) -> Data {
    let url = Bundle(for: FixtureLocator.self).url(forResource: name, withExtension: "json")
        ?? Bundle(for: FixtureLocator.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}
func decodeFixture<T: Decodable>(_ name: String, as type: T.Type = T.self) -> T { try! JSONDecoder().decode(T.self, from: fixture(name)) }

/// Stubs every request made through a URLSession that uses this protocol; records what was sent.
final class MockURLProtocol: URLProtocol {
    struct Stub { var status = 200; var body = Data(); var headers: [String: String] = ["Content-Type": "application/json"]; var error: URLError.Code? }
    nonisolated(unsafe) static var handler: ((URLRequest) -> Stub)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(_ h: ((URLRequest) -> Stub)? = nil) { lock.lock(); handler = h; requests = []; lock.unlock() }
    static func seen() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); let h = Self.handler; Self.lock.unlock()
        let stub = h?(request) ?? Stub(status: 404)
        if let code = stub.error { client?.urlProtocol(self, didFailWithError: URLError(code)); return }
        let resp = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func json(_ s: String) -> Data { Data(s.utf8) }

/// A signed-in test environment: memory stores, a stubbed network and an in-memory cache.
struct TestEnv {
    let session: SessionManager
    let api: ApiClient
    let repo: Repository
    let cache: MemoryCacheStore
    var now: Date

    init(signedIn: Bool = true, now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        let s = SessionManager(store: MemoryKeyValueStore(), secrets: MemoryKeyValueStore())
        s.setServer("http://server.test:8040")
        if signedIn { s.saveLogin(token: "jwt-token", me: Me(id: 7, email: "u@example.com", username: "TestUser")) }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        session = s
        api = ApiClient(session: s, urlSession: URLSession(configuration: cfg))
        cache = MemoryCacheStore()
        self.now = now
        let n = now
        repo = Repository(api: api, session: s, cache: cache, clock: { n })
    }
}
