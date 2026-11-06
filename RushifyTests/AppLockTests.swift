import XCTest
@testable import Rushify

private final class FakeAuthenticator: DeviceAuthenticator {
    var methodName: String? = "Face ID"
    var result = true
    private(set) var prompts = 0
    func authenticate(reason: String) async -> Bool { prompts += 1; return result }
}

final class AppLockTests: XCTestCase {
    private var store: MemoryKeyValueStore!
    private var auth: FakeAuthenticator!
    private var now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() { store = MemoryKeyValueStore(); auth = FakeAuthenticator(); now = Date(timeIntervalSince1970: 1_700_000_000) }
    private func make() -> AppLock { AppLock(store: store, authenticator: auth, clock: { [unowned self] in self.now }) }
    private func background(for seconds: TimeInterval, _ lock: AppLock) { lock.appEnteredBackground(); now.addTimeInterval(seconds); lock.appBecameActive() }

    func testTheLockIsOffByDefaultAndNeverLocks() {
        let lock = make()
        XCTAssertFalse(lock.enabled); XCTAssertFalse(lock.isLocked)
        background(for: 3600, lock); XCTAssertFalse(lock.isLocked)
    }

    func testTurningItOnRequiresTheOwnerToPassFirst() async {
        let lock = make(); auth.result = false
        let failed = await lock.setEnabled(true); XCTAssertFalse(failed); XCTAssertFalse(lock.enabled); XCTAssertEqual(auth.prompts, 1)
        auth.result = true
        let ok = await lock.setEnabled(true); XCTAssertTrue(ok); XCTAssertTrue(lock.enabled); XCTAssertFalse(lock.isLocked, "turning it on does not lock you out")
    }

    func testAPhoneWithoutAPasscodeCannotTurnItOn() async {
        auth.methodName = nil; let lock = make()
        let ok = await lock.setEnabled(true); XCTAssertFalse(ok); XCTAssertFalse(lock.enabled); XCTAssertEqual(auth.prompts, 0)
    }

    func testEveryLaunchStartsLockedWhenEnabled() async {
        let first = make(); _ = await first.setEnabled(true)
        let relaunch = make(); XCTAssertTrue(relaunch.enabled); XCTAssertTrue(relaunch.isLocked)
    }

    func testUnlockSucceedsOrStaysLocked() async {
        let lock = make(); _ = await lock.setEnabled(true); lock.lockNow()
        auth.result = false; let no = await lock.unlock(); XCTAssertFalse(no); XCTAssertTrue(lock.isLocked); XCTAssertTrue(lock.lastAttemptFailed)
        auth.result = true; let yes = await lock.unlock(); XCTAssertTrue(yes); XCTAssertFalse(lock.isLocked); XCTAssertFalse(lock.lastAttemptFailed)
    }

    func testItLocksOnlyAfterTheChosenTimeInTheBackground() async {
        let lock = make(); _ = await lock.setEnabled(true); lock.setTimeout(.fiveMinutes)
        background(for: 299, lock); XCTAssertFalse(lock.isLocked, "back within the time")
        background(for: 300, lock); XCTAssertTrue(lock.isLocked, "exactly at the limit locks")
    }

    func testImmediatelyLocksOnEveryReturn() async {
        let lock = make(); _ = await lock.setEnabled(true); lock.setTimeout(.immediately)
        background(for: 0, lock); XCTAssertTrue(lock.isLocked)
    }

    func testAPromptInterruptionDoesNotCountAsLeavingTheApp() async {
        let lock = make(); _ = await lock.setEnabled(true); lock.setTimeout(.oneMinute)
        lock.appBecameInactive(); now.addTimeInterval(500); lock.appBecameActive()    // Face ID sheet: inactive, never backgrounded
        XCTAssertFalse(lock.isLocked)
    }

    func testTheShieldCoversTheScreenWheneverTheAppIsNotActive() {
        let lock = make(); XCTAssertFalse(lock.shieldVisible)
        lock.appBecameInactive(); XCTAssertTrue(lock.shieldVisible)
        lock.appBecameActive(); XCTAssertFalse(lock.shieldVisible)
        lock.appEnteredBackground(); XCTAssertTrue(lock.shieldVisible)
    }

    func testTheShieldCanBeSwitchedOff() {
        let lock = make(); lock.setPrivacyShield(false)
        lock.appBecameInactive(); XCTAssertFalse(lock.shieldVisible); lock.appEnteredBackground(); XCTAssertFalse(lock.shieldVisible)
    }

    func testSettingsSurviveARestart() async {
        let a = make(); _ = await a.setEnabled(true); a.setTimeout(.fifteenMinutes); a.setPrivacyShield(false)
        let b = make(); XCTAssertTrue(b.enabled); XCTAssertEqual(b.timeout, .fifteenMinutes); XCTAssertFalse(b.privacyShield)
    }

    func testTurningItOffUnlocksAndForgets() async {
        let lock = make(); _ = await lock.setEnabled(true); lock.lockNow(); XCTAssertTrue(lock.isLocked)
        _ = await lock.setEnabled(false); XCTAssertFalse(lock.isLocked); XCTAssertFalse(make().enabled)
    }

    func testDefaultTimeoutIsOneMinute() { XCTAssertEqual(make().timeout, .oneMinute) }
}
