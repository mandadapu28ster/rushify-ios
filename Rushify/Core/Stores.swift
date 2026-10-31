import Foundation
import Security

protocol KeyValueStore: AnyObject {
    func get(_ key: String) -> String?
    func put(_ key: String, _ value: String?)
    func clear()
}

final class MemoryKeyValueStore: KeyValueStore {
    private var map: [String: String] = [:]
    private let lock = NSLock()
    func get(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return map[key] }
    func put(_ key: String, _ value: String?) { lock.lock(); defer { lock.unlock() }; if let value { map[key] = value } else { map.removeValue(forKey: key) } }
    func clear() { lock.lock(); defer { lock.unlock() }; map.removeAll() }
}

/// Non-secret preferences (server address, display name, toggles).
final class UserDefaultsStore: KeyValueStore {
    private let defaults: UserDefaults
    private let prefix: String
    init(suite: String = "rushify.prefs", prefix: String = "rushify.") {
        defaults = UserDefaults(suiteName: suite) ?? .standard
        self.prefix = prefix
    }
    func get(_ key: String) -> String? { defaults.string(forKey: prefix + key) }
    func put(_ key: String, _ value: String?) { if let value { defaults.set(value, forKey: prefix + key) } else { defaults.removeObject(forKey: prefix + key) } }
    func clear() { for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(prefix) { defaults.removeObject(forKey: k) } }
}

/// Keychain storage. Only the JWT is ever stored as a credential; the password never is.
final class KeychainStore: KeyValueStore {
    private let service: String
    init(service: String = "com.rushify.mobile.session") { self.service = service }

    private func query(_ key: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let key { q[kSecAttrAccount as String] = key }
        return q
    }
    func get(_ key: String) -> String? {
        var q = query(key); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    func put(_ key: String, _ value: String?) {
        SecItemDelete(query(key) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    func clear() { SecItemDelete(query(nil) as CFDictionary) }
}
