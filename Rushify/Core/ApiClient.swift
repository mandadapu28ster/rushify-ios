import Foundation

/// Refuses an HTTPS -> HTTP redirect so a secure connection can never be downgraded silently.
final class NoDowngradeDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if task.originalRequest?.url?.scheme == "https", request.url?.scheme == "http" { completionHandler(nil) } else { completionHandler(request) }
    }
}

/// HTTP client for the Rushify server: base URL and bearer token come from the session; a 401 on a signed-in call ends the session.
final class ApiClient {
    let session: SessionManager
    private let urlSession: URLSession

    init(session: SessionManager, urlSession: URLSession? = nil) {
        self.session = session
        if let urlSession { self.urlSession = urlSession } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 30
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            cfg.urlCache = nil
            self.urlSession = URLSession(configuration: cfg, delegate: NoDowngradeDelegate(), delegateQueue: nil)
        }
    }

    /// `auth: false` sends no token and never ends the session on 401 (login, public endpoints).
    /// `bearer` sends an explicit token (used right after login, before it is stored). `baseURL` overrides the stored server.
    @discardableResult
    func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
              auth: Bool = true, bearer: String? = nil, baseURL: String? = nil) async throws -> Data {
        let state = session.current
        guard let base = baseURL ?? state.serverUrl, var comps = URLComponents(string: base) else { throw ApiError.network("No server configured") }
        comps.path = path.hasPrefix("/") ? path : "/" + path
        comps.queryItems = query.isEmpty ? nil : query
        guard let url = comps.url else { throw ApiError.invalid("Bad request address") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let token = bearer ?? (auth ? state.token : nil)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let data: Data, response: URLResponse
        do { (data, response) = try await urlSession.data(for: req) }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw ApiError.network(Self.describe(error)) }

        guard let http = response as? HTTPURLResponse else { throw ApiError.network("Invalid response from server") }
        if (200..<300).contains(http.statusCode) { return data }
        let signedIn = auth && bearer == nil && state.token != nil
        if http.statusCode == 401 && signedIn { session.expire() }
        throw ApiErrors.map(status: http.statusCode, body: data, hadAuth: auth && bearer == nil && (state.token != nil || state.expired))
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        try Self.decode(try await send("GET", path, query: query))
    }

    static func decode<T: Decodable>(_ data: Data, as type: T.Type = T.self) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ApiError.server(200, "Unexpected response from server") }
    }

    static func describe(_ error: Error) -> String {
        guard let e = error as? URLError else { return error.localizedDescription }
        switch e.code {
        case .notConnectedToInternet, .dataNotAllowed: return "No internet connection"
        case .timedOut: return "The server took too long to respond"
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost: return "Could not connect to the server"
        case .appTransportSecurityRequiresSecureConnection: return "This address needs HTTPS"
        default: return e.localizedDescription
        }
    }
}
