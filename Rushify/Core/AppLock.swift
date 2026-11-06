import Foundation
import LocalAuthentication

/// Asks the device to confirm the owner (Face ID / Touch ID / Optic ID, falling back to the passcode).
protocol DeviceAuthenticator {
    /// "Face ID", "Touch ID", "Optic ID" or "Passcode"; nil when the device has no passcode set at all.
    var methodName: String? { get }
    func authenticate(reason: String) async -> Bool
}

struct SystemAuthenticator: DeviceAuthenticator {
    var methodName: String? {
        var err: NSError?
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return nil }
        let bio = LAContext()
        if bio.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            switch bio.biometryType {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            default: break
            }
        }
        return "Passcode"
    }
    func authenticate(reason: String) async -> Bool {
        do { return try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) } catch { return false }
    }
}

/// Optional app lock and privacy shield. Locks on launch and after the app has been in the background longer than
/// the chosen time; the shield hides the screen in the app switcher. Nothing here ever stores a credential.
final class AppLock: ObservableObject {
    enum Timeout: Int, CaseIterable, Identifiable {
        case immediately = 0, oneMinute = 60, fiveMinutes = 300, fifteenMinutes = 900
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .immediately: return "Immediately"
            case .oneMinute: return "After 1 minute"
            case .fiveMinutes: return "After 5 minutes"
            case .fifteenMinutes: return "After 15 minutes"
            }
        }
    }

    @Published private(set) var isLocked: Bool
    @Published private(set) var enabled: Bool
    @Published private(set) var timeout: Timeout
    @Published private(set) var privacyShield: Bool
    /// True while the app is not active: views draw an opaque cover so the app switcher shows nothing sensitive.
    @Published private(set) var shieldVisible = false
    @Published private(set) var lastAttemptFailed = false

    private let store: KeyValueStore
    private let authenticator: DeviceAuthenticator
    private let clock: () -> Date
    private var backgroundedAt: Date?
    private enum K { static let enabled = "lock_enabled", timeout = "lock_timeout", shield = "lock_shield" }

    init(store: KeyValueStore, authenticator: DeviceAuthenticator = SystemAuthenticator(), clock: @escaping () -> Date = Date.init) {
        self.store = store; self.authenticator = authenticator; self.clock = clock
        let on = store.get(K.enabled) == "1"
        enabled = on
        timeout = store.get(K.timeout).flatMap(Int.init).flatMap(Timeout.init(rawValue:)) ?? .oneMinute
        privacyShield = store.get(K.shield) != "0"
        isLocked = on   // every launch starts locked when the lock is on
    }

    /// "Face ID", "Touch ID", "Optic ID" or "Passcode"; nil when the phone has no passcode (the lock can't be turned on).
    var methodName: String? { authenticator.methodName }

    /// Turning the lock on first proves the owner can pass it, so nobody gets locked out. Returns whether the setting changed.
    @MainActor @discardableResult
    func setEnabled(_ on: Bool) async -> Bool {
        if on {
            guard authenticator.methodName != nil else { return false }
            guard await authenticator.authenticate(reason: "Turn on the Rushify lock") else { return false }
        }
        enabled = on; store.put(K.enabled, on ? "1" : "0")
        if !on { isLocked = false }
        return true
    }
    func setTimeout(_ t: Timeout) { timeout = t; store.put(K.timeout, String(t.rawValue)) }
    func setPrivacyShield(_ on: Bool) { privacyShield = on; store.put(K.shield, on ? "1" : "0") }

    // MARK: Lifecycle (called from the app's scene phase)

    func appBecameInactive() { if privacyShield { shieldVisible = true } }
    func appEnteredBackground() {
        if privacyShield { shieldVisible = true }
        if backgroundedAt == nil { backgroundedAt = clock() }
    }
    func appBecameActive() {
        shieldVisible = false
        defer { backgroundedAt = nil }
        guard enabled, !isLocked, let since = backgroundedAt else { return }
        if clock().timeIntervalSince(since) >= TimeInterval(timeout.rawValue) { isLocked = true }
    }

    func lockNow() { if enabled { isLocked = true } }

    private var attempt: Task<Bool, Never>?

    /// One prompt at a time: if the lock screen asks again while an attempt is already showing (the view can be rebuilt,
    /// and the tap and the automatic attempt can overlap), the caller waits for that attempt instead of prompting twice.
    @MainActor @discardableResult
    func unlock() async -> Bool {
        guard isLocked else { return true }
        if let attempt { return await attempt.value }
        let authenticator = authenticator
        let task = Task { await authenticator.authenticate(reason: "Unlock Rushify") }
        attempt = task
        let ok = await task.value
        attempt = nil
        if ok { isLocked = false; lastAttemptFailed = false } else { lastAttemptFailed = true }
        return ok
    }
}
