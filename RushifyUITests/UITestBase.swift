import XCTest

/// End-to-end tests run the real app in UI-test mode: it starts against canned responses (Rushify/UITestFixtures), never a server.
class RushifyUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// scenario: "1" signed in, "signedout" fresh install, "expired" every authenticated call answers 401.
    func launch(_ scenario: String = "1") {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["RUSHIFY_UITEST"] = scenario
        app.launch()
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func text(_ s: String, contains: Bool = false) -> XCUIElement {
        let p = contains ? NSPredicate(format: "label CONTAINS %@", s) : NSPredicate(format: "label == %@", s)
        return app.staticTexts.matching(p).firstMatch
    }
    @discardableResult func waitFor(_ e: XCUIElement, _ seconds: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(e.waitForExistence(timeout: seconds), "Not found: \(e)", file: file, line: line); return e
    }
    func assertText(_ s: String, contains: Bool = false, file: StaticString = #filePath, line: UInt = #line) { waitFor(text(s, contains: contains), file: file, line: line) }
    func assertGone(_ e: XCUIElement, _ seconds: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: seconds), .completed, "Still visible: \(e)", file: file, line: line)
    }
    func tapTab(_ name: String) { waitFor(app.tabBars.buttons[name]).tap() }
    /// Opens a row in the More tab list.
    func openFromMore(_ title: String) {
        tapTab("More")
        let row = app.staticTexts[title].firstMatch
        if !row.waitForExistence(timeout: 5) { app.swipeUp() }
        waitFor(row).tap()
    }
    func scrollTo(_ e: XCUIElement, maxSwipes: Int = 8) {
        var n = 0
        while !(e.exists && e.isHittable) && n < maxSwipes { app.swipeUp(); n += 1 }
    }
}
