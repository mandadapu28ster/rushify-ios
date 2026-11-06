import XCTest
@testable import Rushify

final class IconLoaderTests: XCTestCase {
    private var session: SessionManager!
    private var loader: IconLoader!
    private let webp = Data([0x52, 0x49, 0x46, 0x46, 1, 2, 3])

    override func setUp() {
        MockURLProtocol.reset()
        session = SessionManager(store: MemoryKeyValueStore(), secrets: MemoryKeyValueStore())
        session.setServer("http://server.test:8040")
        session.saveLogin(token: "jwt-token", me: Me(id: 7, email: "u@example.com", username: "TestUser"))
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        loader = IconLoader(session: session, urlSession: URLSession(configuration: cfg))
    }

    func testKeyNormalisesAndRejectsOddInput() {
        XCTAssertEqual(IconLoader.key(" vod.l "), "VOD.L"); XCTAssertEqual(IconLoader.key("brk-b"), "BRK-B")
        XCTAssertNil(IconLoader.key(nil)); XCTAssertNil(IconLoader.key("  "))
        XCTAssertNil(IconLoader.key("../etc/passwd")); XCTAssertNil(IconLoader.key(String(repeating: "A", count: 41)))
    }

    func testURLUsesTheStoredServerAndOnePathSegment() {
        XCTAssertEqual(IconLoader.url(server: "http://server.test:8040", key: "VOD.L")?.absoluteString, "http://server.test:8040/api/icons/VOD.L.webp")
        XCTAssertEqual(IconLoader.url(server: "https://h", key: "BRK-B")?.path, "/api/icons/BRK-B.webp")
    }

    func testDownloadsFromThePublicEndpointWithoutAuth() async {
        MockURLProtocol.reset { _ in .init(body: self.webp, headers: ["Content-Type": "image/webp"]) }
        let data = await loader.data(for: "vod.l")
        XCTAssertEqual(data, webp)
        let req = MockURLProtocol.seen()[0]
        XCTAssertEqual(req.url?.path, "/api/icons/VOD.L.webp")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testRemembersNoLogoSoListsDoNotReAsk() async {
        MockURLProtocol.reset { _ in .init(status: 404) }
        let first = await loader.data(for: "ZZZZ"), second = await loader.data(for: "ZZZZ")
        XCTAssertNil(first); XCTAssertNil(second)
        XCTAssertTrue(loader.isKnownMissing("zzzz"))
        XCTAssertEqual(MockURLProtocol.seen().count, 1)
    }

    func testServerErrorsAreNotRememberedAsMissing() async {
        MockURLProtocol.reset { _ in .init(status: 500) }
        let d = await loader.data(for: "AAPL")
        XCTAssertNil(d); XCTAssertFalse(loader.isKnownMissing("AAPL"))
    }

    func testBlankSymbolNeverHitsTheNetwork() async {
        MockURLProtocol.reset { _ in .init(body: self.webp) }
        let d = await loader.data(for: " ")
        XCTAssertNil(d); XCTAssertTrue(MockURLProtocol.seen().isEmpty)
    }

    func testBadgeTextAndHueAreStable() {
        XCTAssertEqual(IconBadge.text("VOD.L"), "VO"); XCTAssertEqual(IconBadge.text("BRK-B"), "BR")
        XCTAssertEqual(IconBadge.text(nil), "?"); XCTAssertEqual(IconBadge.text("a"), "A")
        XCTAssertEqual(IconBadge.hue("SAP.DE"), IconBadge.hue("sap.de"))
        XCTAssertTrue((0..<360).contains(IconBadge.hue("AAPL")))
    }
}
