import XCTest
@testable import Rushify

@MainActor
final class PasswordTests: XCTestCase {
    private var routes = MiscRoutes()
    override func setUp() { MockURLProtocol.reset() }

    func testValidationMatchesTheWeb() {
        XCTAssertEqual(PasswordRules.validate("old", "newpass12", "different"), "New password and confirmation do not match.")
        XCTAssertEqual(PasswordRules.validate("old", "short", "short"), "New password must be at least 8 characters.")
        XCTAssertEqual(PasswordRules.validate("samepass1", "samepass1", "samepass1"), "New password must be different from your current password.")
        XCTAssertEqual(PasswordRules.validate("", "newpass12", "newpass12"), "Enter your current password.")
        XCTAssertNil(PasswordRules.validate("old", "newpass12", "newpass12"))
    }

    func testInvalidInputSendsNothing() async {
        let vm = PasswordViewModel(repo: TestEnv().repo)
        await vm.submit(current: "old", new: "short", confirm: "short")
        XCTAssertTrue(vm.ui.error!.contains("at least 8")); XCTAssertEqual(MockURLProtocol.seen().count, 0)
    }

    func testSuccessSendsTheWebFieldsWithoutAnAuthToken() async {
        routes.add("POST /api/auth/replace-password", body: #"{"ok":true}"#); routes.install()
        let vm = PasswordViewModel(repo: TestEnv().repo)
        await vm.submit(current: "oldpass1", new: "newpass12", confirm: "newpass12")
        XCTAssertTrue(vm.ui.done); XCTAssertNil(vm.ui.error); XCTAssertFalse(vm.ui.busy)
        let req = MockURLProtocol.seen().first { $0.httpMethod == "POST" }!
        XCTAssertEqual(miscBodyJSON(req), ["username": "TestUser", "current_password": "oldpass1", "new_password": "newpass12", "new_password_confirm": "newpass12"])
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testAWrongCurrentPasswordDoesNotSignTheUserOut() async {
        routes.add("POST /api/auth/replace-password", status: 401, body: #"{"detail":"Login failure try again."}"#); routes.install()
        let env = TestEnv(); let vm = PasswordViewModel(repo: env.repo)
        await vm.submit(current: "wrongpass", new: "newpass12", confirm: "newpass12")
        XCTAssertEqual(vm.ui.error, "Current password is incorrect.")
        XCTAssertTrue(env.session.current.loggedIn); XCTAssertFalse(env.session.current.expired)
    }

    func testALockedAccountMessageIsShown() async {
        routes.add("POST /api/auth/replace-password", status: 403, body: #"{"detail":"You are locked, wait for one day and try again"}"#); routes.install()
        let vm = PasswordViewModel(repo: TestEnv().repo)
        await vm.submit(current: "x1234567", new: "newpass12", confirm: "newpass12")
        XCTAssertTrue(vm.ui.error!.contains("locked")); XCTAssertFalse(vm.ui.done)
    }

    func testNotSignedInIsReported() async {
        let vm = PasswordViewModel(repo: TestEnv(signedIn: false).repo)
        await vm.submit(current: "oldpass1", new: "newpass12", confirm: "newpass12")
        XCTAssertEqual(vm.ui.error, "You are not signed in."); XCTAssertEqual(MockURLProtocol.seen().count, 0)
    }

    func testFinishEndsTheSessionAndWipesTheCache() async {
        routes.add("GET /api/corporate-actions", body: miscFixtureString("corporate")); routes.install()
        let env = TestEnv(); _ = try? await env.repo.miscCorporate()
        let before = await env.repo.miscCorporateCached(); XCTAssertNotNil(before)
        let vm = PasswordViewModel(repo: env.repo); await vm.finish()
        XCTAssertFalse(env.session.current.loggedIn); XCTAssertTrue(env.session.current.expired)
        let after = await env.repo.miscCorporateCached(); XCTAssertNil(after)
    }
}
