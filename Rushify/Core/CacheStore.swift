import CryptoKit
import Foundation

/// One raw JSON response per name, keyed by "server|userId|name". Not normalised on purpose.
struct CacheEntry: Codable, Equatable {
    var key: String
    var body: Data
    var fetchedAt: Date
}

protocol CacheStore: Sendable {
    func get(_ key: String) async -> CacheEntry?
    func put(_ entry: CacheEntry) async
    func clear() async
}

actor MemoryCacheStore: CacheStore {
    private var map: [String: CacheEntry] = [:]
    func get(_ key: String) -> CacheEntry? { map[key] }
    func put(_ entry: CacheEntry) { map[entry.key] = entry }
    func clear() { map.removeAll() }
}

/// Files in Application Support, one per key. Excluded from iCloud backup and protected until first unlock.
actor FileCacheStore: CacheStore {
    private let dir: URL
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RushifyCache", isDirectory: true)
        dir = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var url = base; try? url.setResourceValues(values)
    }
    private func file(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(hash + ".json")
    }
    func get(_ key: String) -> CacheEntry? {
        guard let data = try? Data(contentsOf: file(key)), let e = try? JSONDecoder().decode(CacheEntry.self, from: data), e.key == key else { return nil }
        return e
    }
    func put(_ entry: CacheEntry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: file(entry.key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func clear() {
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? FileManager.default.removeItem(at: f) }
    }
}
