import Foundation

/// Typed failures so screens can map them to the right message (same table as the Android app).
enum ApiError: Error, Equatable {
    case badCredentials(String)
    case locked(String)
    case inactive(String)
    case sessionExpired
    case quotaReached(String)
    case syncRunning(String)
    case server(Int, String)
    case network(String)
    case invalid(String)
    case notConfigured(String)

    var message: String {
        switch self {
        case .badCredentials(let m), .locked(let m), .inactive(let m), .quotaReached(let m), .syncRunning(let m),
             .network(let m), .invalid(let m), .notConfigured(let m): return m
        case .sessionExpired: return "Session expired. Please sign in again."
        case .server(_, let m): return m
        }
    }
}

extension ApiError: LocalizedError { var errorDescription: String? { message } }

enum ApiErrors {
    /// FastAPI errors: {"detail": "text"} or {"detail": [{"msg": "..."}]}.
    static func detail(from data: Data) -> String? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let d = obj["detail"] else { return nil }
        return text(d)
    }
    private static func text(_ any: Any) -> String? {
        if let s = any as? String { return s }
        if let a = any as? [Any] { return a.compactMap { text($0) }.joined(separator: "; ") }
        if let o = any as? [String: Any] { return (o["msg"] as? String) ?? String(describing: o) }
        return nil
    }

    static func map(status: Int, body: Data, hadAuth: Bool) -> ApiError {
        let detail = detail(from: body)
        switch status {
        case 401: return hadAuth ? .sessionExpired : .badCredentials(detail ?? "Login failure try again.")
        case 403:
            if let d = detail, d.localizedCaseInsensitiveContains("inactive") { return .inactive(d) }
            return .locked(detail ?? "You are locked, wait for one day and try again")
        case 400:
            if let d = detail, d.localizedCaseInsensitiveContains("not configured") { return .notConfigured(d) }
            return .server(400, detail ?? "Bad request")
        case 409: return .syncRunning(detail ?? "A sync is already running")
        case 429: return .quotaReached(detail ?? "Daily manual sync limit reached")
        default: return .server(status, detail ?? "Server error (\(status))")
        }
    }
}
