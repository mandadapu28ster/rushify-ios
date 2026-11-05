import XCTest
@testable import Rushify

/// Routes stubbed requests by "METHOD /path"; unknown routes answer 404.
struct MiscRoutes {
    var table: [String: (URLRequest) -> MockURLProtocol.Stub] = [:]
    mutating func add(_ key: String, status: Int = 200, body: String = "{}", delay: TimeInterval = 0) {
        table[key] = { _ in if delay > 0 { Thread.sleep(forTimeInterval: delay) }; return .init(status: status, body: json(body)) }
    }
    mutating func add(_ key: String, status: Int = 200, data: Data) { table[key] = { _ in .init(status: status, body: data) } }
    func install() {
        let t = table
        MockURLProtocol.reset { req in
            let key = "\(req.httpMethod ?? "GET") \(req.url?.path ?? "")"
            return t[key]?(req) ?? .init(status: 404, body: json(#"{"detail":"no route"}"#))
        }
    }
}

func miscBody(_ r: URLRequest) -> Data? {
    if let b = r.httpBody { return b }
    guard let s = r.httpBodyStream else { return nil }
    s.open(); defer { s.close() }
    var d = Data(); var buf = [UInt8](repeating: 0, count: 512)
    while s.hasBytesAvailable { let n = s.read(&buf, maxLength: 512); if n <= 0 { break }; d.append(buf, count: n) }
    return d
}
func miscBodyJSON(_ r: URLRequest) -> NSDictionary? { miscBody(r).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? NSDictionary } }
func miscCount(_ method: String, _ path: String) -> Int { MockURLProtocol.seen().filter { $0.httpMethod == method && $0.url?.path == path }.count }
func miscFixtureString(_ name: String) -> String { String(data: fixture(name), encoding: .utf8)! }
