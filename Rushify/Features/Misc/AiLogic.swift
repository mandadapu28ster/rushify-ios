import SwiftUI

struct AiChatMsg: Equatable, Identifiable {
    let id = UUID()
    var role: String
    var text: String
    static func == (a: AiChatMsg, b: AiChatMsg) -> Bool { a.role == b.role && a.text == b.text }
}

struct AiUi: Equatable {
    var messages: [AiChatMsg] = []
    var sending = false
    var error: String?
    var notConfigured = false
    var warning: String?
    var suggestOnline = false
    var online = false
    var restore: String?          // prompt handed back to the text box after a failure
    var providerLabel: String?    // "Gemini" or "OpenAI", from the user's saved provider
    var keyReady: Bool?           // nil = not checked yet / check failed (then the server decides)
    var disclaimer = "Educational / testing only; not financial advice."

    /// The composer is off when the key is known to be missing (server said so, or the credentials check did).
    var blocked: Bool { notConfigured || keyReady == false }
}

/// The web's wording for AI failures, keyed off the provider and the server's own error text.
enum AiErrors {
    private static let openAiPrefixes = ["openai assistant error", "openai assistant run", "openai assistant returned", "openai assistant stalled", "openai assistant hit", "openai assistant run timed out", "openai tool loop", "openai request failed"]

    /// True when the backend put an OpenAI error string into a normal (HTTP 200) reply.
    static func isOpenAiFailureText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return false }
        return openAiPrefixes.contains { t.hasPrefix($0) } || t.contains("rate_limit") || t.contains("rate limit exceeded")
            || t.contains("exceeded your current quota") || t.contains("invalid_api_key")
    }

    static func openAiBanner(_ full: String) -> String {
        let low = full.lowercased()
        if low.contains("rate_limit") || low.contains("rate limit") || (low.contains("quota") && low.contains("exceeded")) || low.contains("check your plan and billing") {
            return "OpenAI blocked this request (quota or rate limit). Check usage and billing at platform.openai.com, then retry. Tip: in the web app under Settings → Keys use \"Chat agent (tools)\" instead of Assistants; it usually uses fewer Assistants API calls."
        }
        let t = full.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 900 ? String(t.prefix(900)) + "…" : t
    }

    static let openAiFailedBubble = "Couldn't generate a reply. See the red error notice. It is often quota, billing or rate limits on your OpenAI account."

    /// Thrown errors: known categories get the web's text; anything else keeps the server's own message.
    static func forThrown(_ message: String?, online: Bool, providerLabel: String?) -> String {
        let low = (message ?? "").lowercased()
        if online && (low.contains("google_search_retrieval is not supported") || low.contains("please use google_search tool instead")) {
            return "Online augmentation (beta) isn't available right now. Turn it off and try again, or retry later."
        }
        if low.contains("503") || low.contains("unavailable") || low.contains("high demand") {
            return "Google's AI is temporarily busy (high demand). This is not a Rushify outage. Try again in a few minutes."
        }
        if low.contains("not configured") || low.contains("api key") {
            return "Add your \(providerLabel ?? "Gemini or OpenAI") API key in the web app under Settings → Keys (and select the matching provider)."
        }
        if message == nil || message!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Couldn't reach the AI service. Check your connection and try again."
        }
        return message!
    }
}

/// Chat lives in memory only: it is never cached to disk and is discarded with the session.
@MainActor
final class AiViewModel: ObservableObject {
    static let maxPrompt = 4000
    static let maxHistory = 40
    static let maxContent = 16000

    @Published var ui = AiUi()
    private let repo: Repository

    init(repo: Repository) { self.repo = repo }

    /// Like the web: learn up front whether the selected provider has a key, instead of after a failed send.
    func checkCredentials() async {
        if let c = await repo.miscAiCredentials() { ui.providerLabel = c.providerLabel; ui.keyReady = c.ready }
    }

    func setOnline(_ on: Bool) { ui.online = on; ui.suggestOnline = false }
    func clear() { ui = AiUi(online: ui.online, providerLabel: ui.providerLabel, keyReady: ui.keyReady) }
    func clearWarning() { ui.warning = nil }
    func consumeRestore() { ui.restore = nil }

    func send(_ raw: String) async {
        let prompt = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cur = ui
        if prompt.isEmpty || cur.sending || cur.blocked { return }
        if prompt.utf16.count > Self.maxPrompt { ui.error = "Message is too long (max \(Self.maxPrompt) characters)."; return }
        let history = Self.historyFor(cur.messages)
        ui.messages.append(AiChatMsg(role: "user", text: prompt))
        ui.sending = true; ui.error = nil; ui.warning = nil; ui.suggestOnline = false
        do {
            let r = try await repo.miscAiInsight(prompt: prompt, online: cur.online, history: history)
            if AiErrors.isOpenAiFailureText(r.text) {
                // The server answered 200 but the text is an OpenAI error: show it as an error, keep the question in the chat.
                ui.messages.append(AiChatMsg(role: "assistant", text: AiErrors.openAiFailedBubble))
                ui.sending = false; ui.error = AiErrors.openAiBanner(r.text); ui.warning = nil; ui.suggestOnline = false
                return
            }
            ui.messages.append(AiChatMsg(role: "assistant", text: r.text))
            ui.sending = false
            ui.warning = r.augmentationWarning
            ui.suggestOnline = r.suggestOnlineAugmentation && !ui.online
            ui.disclaimer = r.disclaimer ?? ui.disclaimer
        } catch let e as ApiError {
            ui.messages.removeLast(); ui.sending = false; ui.restore = prompt
            if case .notConfigured = e { ui.notConfigured = true; ui.keyReady = false }
            else { ui.error = AiErrors.forThrown(e.message, online: cur.online, providerLabel: cur.providerLabel) }
        } catch {
            ui.messages.removeLast(); ui.sending = false; ui.restore = prompt
        }
    }

    /// Completed turns only, last 40, each capped to the server's per-message limit.
    static func historyFor(_ messages: [AiChatMsg]) -> [AiWireMessage] {
        messages.suffix(maxHistory).map { AiWireMessage(role: $0.role, content: String($0.text.prefix(maxContent))) }
    }
}

/// Minimal markdown: **bold**, "* " / "- " bullets and "#" headings. Everything else is shown as plain text.
enum AiSimpleMarkdown {
    static func attributed(_ src: String) -> AttributedString {
        var out = AttributedString()
        let lines = src.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        for (i, rawLine) in lines.enumerated() {
            if i > 0 { out += AttributedString("\n") }
            var line = rawLine
            let heading = line.drop(while: { $0.isWhitespace }).hasPrefix("#")
            if heading {
                line = String(line.drop(while: { $0.isWhitespace }).drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let trimmed = String(line.drop(while: { $0.isWhitespace }))
            if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") { line = "• " + trimmed.dropFirst(2) }
            var part = bold(line)
            if heading { part.font = .system(size: 14, weight: .semibold) }
            out += part
        }
        return out
    }

    private static func bold(_ line: String) -> AttributedString {
        var out = AttributedString()
        let parts = line.components(separatedBy: "**")
        for (idx, p) in parts.enumerated() {
            if idx % 2 == 0 { out += AttributedString(p) }
            else if idx < parts.count - 1 {
                var b = AttributedString(p)
                b.inlinePresentationIntent = .stronglyEmphasized
                out += b
            } else { out += AttributedString("**" + p) } // opening marker with no closing one: show literally
        }
        return out
    }
}
