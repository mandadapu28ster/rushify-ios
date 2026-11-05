import XCTest
@testable import Rushify

@MainActor
final class AiTests: XCTestCase {
    private var routes = MiscRoutes()
    override func setUp() { MockURLProtocol.reset() }

    private func creds(_ provider: String?, gemini: Bool, openai: Bool) -> String {
        #"{"gemini_configured":\#(gemini),"openai_configured":\#(openai),\#(provider.map { "\"ai_provider\":\"\($0)\"," } ?? "")"gemini_api_key":"AIza****","openai_api_key":"sk-****","t212_api_secret":"****"}"#
    }
    private func make(_ c: String? = nil) async -> AiViewModel {
        routes.add("GET /api/portfolio/credentials", body: c ?? creds("gemini", gemini: true, openai: false))
        routes.add("POST /api/ai/insight", body: miscFixtureString("ai")); routes.install()
        let vm = AiViewModel(repo: TestEnv().repo); await vm.checkCredentials(); return vm
    }
    private func lastInsight() -> NSDictionary? { MockURLProtocol.seen().last { $0.url?.path == "/api/ai/insight" }.flatMap(miscBodyJSON) }

    func testReplyIsAppendedAndFlagsAreRead() async {
        let vm = await make()
        await vm.send("  Which sectors?  ")
        let s = vm.ui
        XCTAssertEqual(s.messages.map(\.role), ["user", "assistant"]); XCTAssertEqual(s.messages[0].text, "Which sectors?")
        XCTAssertTrue(s.suggestOnline); XCTAssertTrue(s.disclaimer.contains("not financial advice")); XCTAssertFalse(s.sending)
        XCTAssertEqual(lastInsight()?["prompt"] as? String, "Which sectors?")
    }

    func testHistoryContainsCompletedTurnsAndOnlineFlag() async {
        let vm = await make()
        await vm.send("one"); vm.setOnline(true); await vm.send("two")
        let body = lastInsight()!
        XCTAssertEqual(body["use_online_augmentation"] as? Bool, true)
        let h = body["conversation_history"] as! [[String: String]]
        XCTAssertEqual(h.count, 2); XCTAssertEqual(h[0], ["role": "user", "content": "one"]); XCTAssertEqual(h[1]["role"], "assistant")
        XCTAssertFalse(h.contains { $0["content"] == "two" }, "current prompt must not be duplicated in history")
        XCTAssertEqual(vm.ui.messages.count, 4)
    }

    func testNotConfiguredShowsSetupGuidanceAndBlocksFurtherSends() async {
        let vm = await make(); routes.add("POST /api/ai/insight", status: 400, body: #"{"detail":"Gemini API key not configured"}"#); routes.install()
        await vm.send("hello")
        XCTAssertTrue(vm.ui.notConfigured); XCTAssertTrue(vm.ui.messages.isEmpty); XCTAssertEqual(vm.ui.restore, "hello"); XCTAssertEqual(vm.ui.keyReady, false)
        await vm.send("again")
        XCTAssertEqual(miscCount("POST", "/api/ai/insight"), 1)
    }

    func testOtherServerErrorRestoresPromptAndShowsError() async {
        let vm = await make(); routes.add("POST /api/ai/insight", status: 502, body: #"{"detail":"Upstream timeout"}"#); routes.install()
        await vm.send("hello")
        XCTAssertEqual(vm.ui.error, "Upstream timeout"); XCTAssertEqual(vm.ui.restore, "hello"); XCTAssertFalse(vm.ui.notConfigured); XCTAssertTrue(vm.ui.messages.isEmpty)
        vm.consumeRestore(); XCTAssertNil(vm.ui.restore)
    }

    func testBlankAndOverlongPromptsAreRejectedLocally() async {
        let vm = await make()
        await vm.send("   "); XCTAssertTrue(vm.ui.messages.isEmpty)
        await vm.send(String(repeating: "x", count: AiViewModel.maxPrompt + 1))
        XCTAssertTrue(vm.ui.error!.contains("too long")); XCTAssertEqual(vm.ui.error, "Message is too long (max 4000 characters).")
        XCTAssertEqual(miscCount("POST", "/api/ai/insight"), 0)
    }

    func testHistoryIsCappedAtFortyAndEachMessageAtSixteenThousand() {
        let many = (1...50).map { AiChatMsg(role: $0 % 2 == 1 ? "user" : "assistant", text: "m\($0)") }
        let h = AiViewModel.historyFor(many)
        XCTAssertEqual(h.count, 40); XCTAssertEqual(h.first?.content, "m11"); XCTAssertEqual(h.last?.content, "m50")
        XCTAssertEqual(AiViewModel.historyFor([AiChatMsg(role: "user", text: String(repeating: "y", count: 20000))])[0].content.count, 16000)
    }

    func testClearKeepsOnlineChoice() async {
        let vm = await make(); vm.setOnline(true); vm.clear()
        XCTAssertTrue(vm.ui.online); XCTAssertTrue(vm.ui.messages.isEmpty)
    }

    func testAugmentationWarningIsExposedThenClearable() async {
        let vm = await make(); routes.add("POST /api/ai/insight", body: #"{"text":"ok","augmentation_warning":"Online grounding unavailable, used local data."}"#); routes.install()
        await vm.send("q")
        XCTAssertTrue(vm.ui.warning!.contains("local data")); vm.clearWarning(); XCTAssertNil(vm.ui.warning)
    }

    func testClearChatEmptiesTheThreadButKeepsTheProviderInfo() async {
        let vm = await make(); await vm.send("q"); XCTAssertEqual(vm.ui.messages.count, 2)
        vm.clear(); XCTAssertTrue(vm.ui.messages.isEmpty); XCTAssertEqual(vm.ui.providerLabel, "Gemini"); XCTAssertEqual(vm.ui.keyReady, true)
    }

    // MARK: AiErrors

    func testErrorMapping() {
        XCTAssertTrue(AiErrors.forThrown("HTTP 503 Service Unavailable", online: false, providerLabel: "Gemini").contains("temporarily busy"))
        XCTAssertTrue(AiErrors.forThrown("model is overloaded: high demand", online: false, providerLabel: nil).contains("temporarily busy"))
        XCTAssertTrue(AiErrors.forThrown("google_search_retrieval is not supported", online: true, providerLabel: "Gemini").contains("Online augmentation (beta) isn't available"))
        XCTAssertFalse(AiErrors.forThrown("google_search_retrieval is not supported", online: false, providerLabel: "Gemini").contains("Online augmentation"))
        XCTAssertEqual(AiErrors.forThrown("API key missing", online: false, providerLabel: "OpenAI"), "Add your OpenAI API key in the web app under Settings → Keys (and select the matching provider).")
        XCTAssertEqual(AiErrors.forThrown("API key missing", online: false, providerLabel: nil), "Add your Gemini or OpenAI API key in the web app under Settings → Keys (and select the matching provider).")
        XCTAssertEqual(AiErrors.forThrown(nil, online: false, providerLabel: nil), "Couldn't reach the AI service. Check your connection and try again.")
        XCTAssertEqual(AiErrors.forThrown("  ", online: false, providerLabel: nil), "Couldn't reach the AI service. Check your connection and try again.")
        XCTAssertEqual(AiErrors.forThrown("Something specific", online: false, providerLabel: nil), "Something specific")
    }

    func testOpenAiFailureTextDetection() {
        for t in ["OpenAI assistant error: boom", "OpenAI request failed: 429", "You exceeded your current quota", "Error code: rate_limit_exceeded", "invalid_api_key supplied"] { XCTAssertTrue(AiErrors.isOpenAiFailureText(t), t) }
        XCTAssertFalse(AiErrors.isOpenAiFailureText("Your portfolio is 44% technology.")); XCTAssertFalse(AiErrors.isOpenAiFailureText("  "))
        XCTAssertTrue(AiErrors.openAiBanner("Error: quota exceeded, check your plan and billing").contains("Chat agent (tools)"))
        XCTAssertEqual(AiErrors.openAiBanner(String(repeating: "z", count: 2000)).count, 901)
        XCTAssertEqual(AiErrors.openAiBanner("  short failure  "), "short failure")
    }

    func testAnOpenAiErrorInsideANormalReplyBecomesAnErrorBannerNotAnAnswer() async {
        let vm = await make(creds("openai", gemini: false, openai: true))
        routes.add("POST /api/ai/insight", body: #"{"text":"OpenAI request failed: You exceeded your current quota, please check your plan and billing."}"#); routes.install()
        XCTAssertEqual(vm.ui.keyReady, true)
        await vm.send("hello")
        let u = vm.ui
        XCTAssertTrue(u.error!.contains("OpenAI blocked this request")); XCTAssertEqual(u.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(u.messages[1].text, AiErrors.openAiFailedBubble); XCTAssertFalse(u.suggestOnline); XCTAssertFalse(u.sending)
    }

    // MARK: credentials / key readiness

    func testReadinessFollowsTheSelectedProviderLikeTheWeb() throws {
        func status(_ p: String?, _ g: Bool, _ o: Bool) throws -> AiCredentialsStatus { try JSONDecoder().decode(AiCredentialsStatus.self, from: json(creds(p, gemini: g, openai: o))) }
        XCTAssertTrue(try status("gemini", true, false).ready); XCTAssertFalse(try status("gemini", false, true).ready)
        XCTAssertTrue(try status("openai", false, true).ready); XCTAssertFalse(try status("openai", true, false).ready)
        XCTAssertTrue(try status(nil, true, false).ready)
        XCTAssertEqual(try status("OpenAI", false, true).providerLabel, "OpenAI"); XCTAssertEqual(try status(nil, true, false).providerLabel, "Gemini")
    }

    func testFixtureCredentialsDecodeWithoutSecrets() {
        let c: AiCredentialsStatus = decodeFixture("credentials")
        XCTAssertTrue(c.ready); XCTAssertEqual(c.providerLabel, "Gemini"); XCTAssertFalse("\(c)".contains("AIza"))
    }

    func testMissingKeyBlocksSendingBeforeAnyRequest() async {
        let vm = await make(creds("openai", gemini: true, openai: false))
        XCTAssertEqual(vm.ui.keyReady, false); XCTAssertEqual(vm.ui.providerLabel, "OpenAI"); XCTAssertTrue(vm.ui.blocked)
        await vm.send("hello")
        XCTAssertEqual(miscCount("POST", "/api/ai/insight"), 0); XCTAssertTrue(vm.ui.messages.isEmpty)
    }

    func testReadyKeyAllowsSend() async {
        let vm = await make(creds("gemini", gemini: true, openai: false)); routes.add("POST /api/ai/insight", body: #"{"text":"hi"}"#); routes.install()
        await vm.send("hello"); XCTAssertEqual(vm.ui.messages[1].text, "hi")
    }

    func testFailedCredentialsCheckMeansUnknownNotBlocked() async {
        routes.add("GET /api/portfolio/credentials", status: 503, body: "down"); routes.add("POST /api/ai/insight", body: #"{"text":"hi"}"#); routes.install()
        let vm = AiViewModel(repo: TestEnv().repo); await vm.checkCredentials()
        XCTAssertNil(vm.ui.keyReady); XCTAssertFalse(vm.ui.blocked)
        await vm.send("hello"); XCTAssertEqual(vm.ui.messages.count, 2)
    }

    func testServerSaysNotConfiguredAlsoMarksKeyMissingAndKeepsProviderLabel() async {
        let vm = await make(); routes.add("POST /api/ai/insight", status: 400, body: #"{"detail":"Gemini API key not configured"}"#); routes.install()
        await vm.send("hello")
        XCTAssertTrue(vm.ui.notConfigured); XCTAssertEqual(vm.ui.keyReady, false); XCTAssertEqual(vm.ui.providerLabel, "Gemini")
        vm.clear(); XCTAssertEqual(vm.ui.providerLabel, "Gemini"); XCTAssertEqual(vm.ui.keyReady, false)
    }

    // MARK: markdown

    func testMarkdownBoldBulletsAndHeadings() {
        let ai: AiInsightResponse = decodeFixture("ai")
        let a = AiSimpleMarkdown.attributed(ai.text)
        XCTAssertEqual(String(a.characters), "You are heavily exposed to Technology.\n• Tech is 44%\n• Health is 20%\nSummary\nDiversify.")
        let bold = a.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
        XCTAssertEqual(bold.count, 1); XCTAssertEqual(String(a[bold[0].range].characters), "heavily")
        XCTAssertTrue(a.runs.contains { $0.font != nil }, "heading is styled")
    }

    func testMarkdownUnmatchedMarkersStayLiteral() {
        XCTAssertEqual(String(AiSimpleMarkdown.attributed("a **b").characters), "a **b")
        XCTAssertEqual(String(AiSimpleMarkdown.attributed("plain").characters), "plain")
        XCTAssertEqual(String(AiSimpleMarkdown.attributed("x **y** z").characters), "x y z")
    }
}
