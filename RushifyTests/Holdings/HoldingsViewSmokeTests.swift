import SwiftUI
import XCTest
@testable import Rushify

/// Renders the views inside a real window to catch layout/runtime crashes; data is stubbed.
@MainActor
final class HoldingsViewSmokeTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    private func text(_ name: String) -> String { String(data: fixture(name), encoding: .utf8)! }

    private func host<V: View>(_ v: V) -> UIWindow {
        let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        w.rootViewController = UIHostingController(rootView: v.environment(\.hideBalances, false))
        w.makeKeyAndVisible()
        return w
    }
    private func pump(_ s: Double = 1.0) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    func testHoldingsScreenRendersWithStubbedData() async {
        let env = TestEnv()
        MockURLProtocol.reset { req in
            switch req.url?.path ?? "" {
            case "/api/portfolio/dashboard": return .init(body: json(self.text("holdings_dashboard")))
            case "/api/portfolio/holdings-rollups": return .init(body: json(self.text("rollups")))
            default: return .init(status: 404)
            }
        }
        var actionsSeen = 0
        let w = host(NavigationStack { HoldingsScreen(repo: env.repo, session: env.session, holdingActions: { _ in actionsSeen += 1; return AnyView(Text("actions")) }) })
        await pump(1.5)
        XCTAssertNotNil(w.rootViewController?.view)
        env.repo.notifyChanged()   // reload path
        await pump(0.5)
        let seen = MockURLProtocol.seen().compactMap { $0.url?.path }
        XCTAssertTrue(seen.contains("/api/portfolio/dashboard")); XCTAssertTrue(seen.contains("/api/portfolio/holdings-rollups"))
        XCTAssertGreaterThanOrEqual(seen.filter { $0 == "/api/portfolio/dashboard" }.count, 2, "events.version change reloads the screen")
    }

    func testHomeContentViewsRender() async {
        let env = TestEnv()
        let rows = decodeFixture("holdings_dashboard", as: Dashboard.self).rows
        MockURLProtocol.reset { _ in .init(body: json(self.text("wealth"))) }
        let w = host(ScrollView { VStack {
            HoldingsHomeSectorsContent(rows: rows, ccy: "GBP"); HoldingsHomePositionSizeContent(rows: rows, ccy: "GBP")
            HoldingsHomeCustodianContent(rows: rows, ccy: "GBP"); HoldingsHomeWealthContent(repo: env.repo)
        } })
        await pump(1.5)
        XCTAssertNotNil(w.rootViewController?.view)
    }

    func testDetailViewRendersActions() async {
        let rows = decodeFixture("holdings_dashboard", as: Dashboard.self).rows
        let manual = rows.first { $0.manualHoldingId == 11 }!
        let w = host(HoldingsDetailView(row: manual, ccy: "GBP", rollup: nil, primary: true) { Text("actions-here") })
        await pump(0.5)
        XCTAssertNotNil(w.rootViewController?.view)
    }
}
