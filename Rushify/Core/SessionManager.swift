import Foundation

struct SessionState: Equatable {
    var serverUrl: String?
    var token: String?
    var userId: Int?
    var username: String?
    var role: String?
    var baseCurrency = "GBP"
    var expired = false

    var isAdmin: Bool { role?.lowercased() == "admin" }
    var loggedIn: Bool { !(token ?? "").isEmpty && serverUrl != nil }
    var cleartext: Bool { serverUrl?.hasPrefix("http://") == true }
    /// Cache scope: server + user, so data never leaks across accounts or servers.
    var cacheScope: String { "\(serverUrl ?? "nil")|\(userId.map(String.init) ?? "nil")" }
}

/// Holds the server, the signed-in user and the token. Safe to call from any thread; `state` is what views observe.
final class SessionManager: ObservableObject, @unchecked Sendable {
    @Published private(set) var state: SessionState
    private var _current: SessionState
    private let lock = NSLock()
    private let store: KeyValueStore
    private let secrets: KeyValueStore

    init(store: KeyValueStore, secrets: KeyValueStore) {
        self.store = store; self.secrets = secrets
        let s = SessionState(
            serverUrl: store.get(K.server), token: secrets.get(K.token), userId: store.get(K.userId).flatMap(Int.init),
            username: store.get(K.username), role: store.get(K.role), baseCurrency: store.get(K.ccy) ?? "GBP")
        _current = s; state = s
    }

    var current: SessionState { lock.lock(); defer { lock.unlock() }; return _current }

    private func publish(_ s: SessionState) {
        _current = s
        if Thread.isMainThread { state = s } else { DispatchQueue.main.async { self.state = s } }
    }

    /// Changing the server drops the session. Returns true when the server actually changed.
    @discardableResult func setServer(_ url: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if url == _current.serverUrl { return false }
        secrets.put(K.token, nil)
        [K.userId, K.username, K.role].forEach { store.put($0, nil) }
        store.put(K.server, url)
        publish(SessionState(serverUrl: url))
        return true
    }

    func saveLogin(token: String, me: Me) {
        lock.lock(); defer { lock.unlock() }
        secrets.put(K.token, token)
        store.put(K.userId, String(me.id)); store.put(K.username, me.username); store.put(K.ccy, me.baseCurrency); store.put(K.role, me.role)
        var s = _current
        s.token = token; s.userId = me.id; s.username = me.username; s.role = me.role; s.baseCurrency = me.baseCurrency; s.expired = false
        publish(s)
    }

    /// Single-flight: concurrent 401s clear the session once. Returns true for the caller that cleared it.
    @discardableResult func expire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard _current.token != nil else { return false }
        secrets.put(K.token, nil)
        var s = _current; s.token = nil; s.expired = true
        publish(s)
        return true
    }

    func logout() {
        lock.lock(); defer { lock.unlock() }
        secrets.put(K.token, nil)
        [K.userId, K.username, K.role].forEach { store.put($0, nil) }
        var s = _current; s.token = nil; s.userId = nil; s.username = nil; s.role = nil; s.expired = false
        publish(s)
    }

    func clearServer() {
        lock.lock(); defer { lock.unlock() }
        secrets.put(K.token, nil)
        [K.server, K.userId, K.username, K.role].forEach { store.put($0, nil) }
        publish(SessionState())
    }

    func clearExpiredFlag() {
        lock.lock(); defer { lock.unlock() }
        var s = _current; s.expired = false; publish(s)
    }

    func cleartextAcknowledged(_ server: String) -> Bool { store.get(K.ack + server) == "1" }
    func acknowledgeCleartext(_ server: String) { store.put(K.ack + server, "1") }

    var hideBalances: Bool {
        get { store.get(K.hide) == "1" }
        set { store.put(K.hide, newValue ? "1" : "0") }
    }

    private enum K {
        static let server = "server", token = "token", userId = "user_id", username = "username", ccy = "ccy"
        static let role = "role", ack = "ack:", hide = "hide"
    }
}
