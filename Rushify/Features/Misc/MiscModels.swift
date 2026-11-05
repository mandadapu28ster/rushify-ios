import Foundation

// MARK: Corporate actions

/// A value inside the free-form `details` object of a corporate action.
enum CorporateJSON: Equatable, Decodable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([CorporateJSON])
    case object([String: CorporateJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .number(String(v)) }
        else if let v = try? c.decode(Decimal.self) { self = .number("\(v)") }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([CorporateJSON].self) { self = .array(v) }
        else if let v = try? c.decode([String: CorporateJSON].self) { self = .object(v) }
        else { self = .null }
    }

    /// Plain content of a primitive (like kotlinx `JsonPrimitive.content`); nil for arrays and objects.
    var primitiveContent: String? {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .string(let s): return s
        case .array, .object: return nil
        }
    }

    private var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return NSDecimalNumber(string: n)
        case .string(let s): return s
        case .array(let a): return a.map { $0.anyValue }
        case .object(let o): return o.mapValues { $0.anyValue }
        }
    }

    /// JSON text (keys sorted so output is stable).
    var jsonText: String {
        switch self {
        case .array, .object:
            let data = try? JSONSerialization.data(withJSONObject: anyValue, options: [.sortedKeys, .withoutEscapingSlashes])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        case .string(let s): return "\"\(s)\""
        default: return primitiveContent ?? ""
        }
    }
}

struct CorporateAction: Equatable, Identifiable {
    var id = 0
    var status = "pending"
    var actionType = ""
    var ticker = ""
    var details: [String: CorporateJSON] = [:]
    var createdAt: String?
}
extension CorporateAction: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        id = f.int("id") ?? 0
        status = f.str("status") ?? "pending"
        actionType = f.str("action_type") ?? ""
        ticker = f.str("ticker") ?? ""
        details = f.obj("details") ?? [:]
        createdAt = f.str("created_at")
    }
}

struct CorporateTickerAttention: Equatable, Identifiable {
    var sourceKey = ""
    var brokerTicker: String?
    var yahooSymbol: String?
    var hasUserMap = false
    var id: String { sourceKey }
}
extension CorporateTickerAttention: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        sourceKey = f.str("source_key") ?? ""
        brokerTicker = f.str("broker_ticker")
        yahooSymbol = f.str("yahoo_symbol")
        hasUserMap = f.bool("has_user_map") ?? false
    }
}

struct CorporateTickerMaps: Equatable {
    var attentionItems: [CorporateTickerAttention] = []
}
extension CorporateTickerMaps: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        attentionItems = f.list("attention_items")
    }
}

// MARK: AI

struct AiWireMessage: Equatable {
    var role: String
    var content: String
    var json: [String: String] { ["role": role, "content": content] }
}

struct AiInsightResponse: Equatable {
    var text = ""
    var disclaimer: String?
    var augmentationWarning: String?
    var suggestOnlineAugmentation = false
}
extension AiInsightResponse: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        text = f.str("text") ?? ""
        disclaimer = f.str("disclaimer")
        augmentationWarning = f.str("augmentation_warning")
        suggestOnlineAugmentation = f.bool("suggest_online_augmentation") ?? false
    }
}

/// Only the three non-secret fields of GET /portfolio/credentials; masked key values are dropped at parse time.
struct AiCredentialsStatus: Equatable {
    var geminiConfigured = false
    var openaiConfigured = false
    var aiProvider: String?

    var provider: String { aiProvider?.lowercased() == "openai" ? "openai" : "gemini" }
    var providerLabel: String { provider == "openai" ? "OpenAI" : "Gemini" }
    /// Same rule as the web: the configured flag of the selected provider.
    var ready: Bool { provider == "openai" ? openaiConfigured : geminiConfigured }
}
extension AiCredentialsStatus: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        geminiConfigured = f.bool("gemini_configured") ?? false
        openaiConfigured = f.bool("openai_configured") ?? false
        aiProvider = f.str("ai_provider")
    }
}

// MARK: Repository calls

extension Repository {
    func miscCorporateCached() async -> Cached<[CorporateAction]>? { await cached("corporate") }
    func miscCorporate() async throws -> Cached<[CorporateAction]> { try await refresh("corporate", path: "api/corporate-actions") }

    /// status is "confirmed" or "dismissed".
    func miscResolveCorporateAction(id: Int, status: String) async throws {
        try await api.sendJSON("PATCH", "api/corporate-actions/\(id)", json: ["status": status])
    }

    func miscTickerMapsCached() async -> Cached<CorporateTickerMaps>? { await cached("ticker-maps") }
    func miscTickerMaps() async throws -> Cached<CorporateTickerMaps> { try await refresh("ticker-maps", path: "api/portfolio/ticker-maps") }

    func miscPutTickerMap(sourceKey: String, yahooSymbol: String) async throws {
        try await api.sendJSON("PUT", "api/portfolio/ticker-maps", json: ["source_key": sourceKey, "yahoo_symbol": yahooSymbol])
    }
    func miscDeleteTickerMap(sourceKey: String) async throws {
        try await api.send("DELETE", "api/portfolio/ticker-maps", query: [URLQueryItem(name: "source_key", value: sourceKey)])
    }

    /// Home ticker-attention "Dismiss".
    func miscDismissTickerBanner() async throws {
        try await api.send("POST", "api/portfolio/ticker-attention-banner/dismiss")
    }

    /// Not cached: it only decides whether the AI composer is enabled. Failure means "unknown", not "not set up".
    func miscAiCredentials() async -> AiCredentialsStatus? {
        guard let data = try? await api.send("GET", "api/portfolio/credentials") else { return nil }
        return try? JSONDecoder().decode(AiCredentialsStatus.self, from: data)
    }

    func miscAiInsight(prompt: String, online: Bool, history: [AiWireMessage]) async throws -> AiInsightResponse {
        let body: [String: Any] = ["prompt": prompt, "use_online_augmentation": online, "conversation_history": history.map { $0.json }]
        return try ApiClient.decode(try await api.sendJSON("POST", "api/ai/insight", json: body))
    }

    /// Public endpoint: no token is sent, and a 401 means a wrong current password, never an expired session.
    func miscReplacePassword(username: String, current: String, new: String, confirm: String) async throws {
        let body = ["username": username, "current_password": current, "new_password": new, "new_password_confirm": confirm]
        try await api.sendJSON("POST", "api/auth/replace-password", json: body, auth: false)
    }
}
