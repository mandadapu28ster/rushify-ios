import Foundation
import UIKit

/// Stock logos from `GET /api/icons/{symbol}.webp` (96x96 WebP, ~1 KB, cacheable for 30 days).
///
/// `URLCache` on disk honours the server's Cache-Control (a logo is downloaded about once a month), `memory` keeps decoded
/// images for scrolling lists, and `missing` remembers symbols the server has no logo for (404) for this process.
/// Callers draw a letter badge when `image(for:)` returns nil.
final class IconLoader: @unchecked Sendable {
    private let session: SessionManager
    private let urlSession: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var missing = Set<String>()
    private static let maxBytes = 256_000

    init(session: SessionManager, urlSession: URLSession? = nil) {
        self.session = session
        memory.countLimit = 300
        if let urlSession { self.urlSession = urlSession } else {
            let cfg = URLSessionConfiguration.default
            cfg.requestCachePolicy = .useProtocolCachePolicy
            cfg.timeoutIntervalForRequest = 15
            cfg.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 20 * 1024 * 1024, directory: Self.cacheDirectory())
            self.urlSession = URLSession(configuration: cfg, delegate: NoDowngradeDelegate(), delegateQueue: nil)
        }
    }

    private static func cacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("icons", isDirectory: true)
    }

    /// Upper-case, trimmed symbol, or nil when blank or implausible (so we never build odd URLs).
    static func key(_ symbol: String?) -> String? {
        let s = (symbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !s.isEmpty, s.count <= 40, s.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return s
    }

    static func url(server: String, key: String) -> URL? {
        guard var comps = URLComponents(string: server) else { return nil }
        comps.path = "/api/icons/\(key).webp"
        comps.query = nil
        return comps.url
    }

    func cachedImage(_ symbol: String?) -> UIImage? { Self.key(symbol).flatMap { memory.object(forKey: $0 as NSString) } }

    func isKnownMissing(_ symbol: String?) -> Bool {
        guard let k = Self.key(symbol) else { return false }
        lock.lock(); defer { lock.unlock() }
        return missing.contains(k)
    }

    func image(for symbol: String?) async -> UIImage? {
        guard let k = Self.key(symbol) else { return nil }
        if let hit = memory.object(forKey: k as NSString) { return hit }
        guard let data = await data(for: k), let img = UIImage(data: data) else { return nil }
        memory.setObject(img, forKey: k as NSString)
        return img
    }

    /// Raw WebP bytes, or nil when there is no logo (404, remembered) or the request failed (not remembered, retried later).
    func data(for symbol: String?) async -> Data? {
        guard let k = Self.key(symbol), !isKnownMissing(k),
              let server = session.current.serverUrl, let url = Self.url(server: server, key: k) else { return nil }
        var req = URLRequest(url: url)   // public endpoint: deliberately no Authorization header
        req.setValue("image/webp", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await urlSession.data(for: req), let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { lock.lock(); missing.insert(k); lock.unlock(); return nil }
        guard (200..<300).contains(http.statusCode), data.count <= Self.maxBytes else { return nil }
        return data
    }
}

/// Letter badge shown when a symbol has no logo: first two letters of the base symbol on a colour from the symbol.
enum IconBadge {
    static func text(_ symbol: String?) -> String {
        var base = (symbol ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        if let dot = base.lastIndex(of: "."), base.distance(from: dot, to: base.endIndex) <= 5 { base = String(base[..<dot]) }
        let letters = base.filter { $0.isLetter || $0.isNumber }
        return letters.isEmpty ? "?" : String(letters.prefix(2))
    }

    /// Hue 0..<360, stable per symbol.
    static func hue(_ symbol: String?) -> Double {
        var h = 0
        for u in (symbol ?? "").uppercased().unicodeScalars { h = (h * 31 + Int(u.value)) % 360 }
        return Double(h)
    }
}
