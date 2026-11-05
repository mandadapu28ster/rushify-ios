import Foundation

struct ConnectionsData {
    var flags: ConnectionsCredentialFlags
    var sync: SyncStatus?
    var snaptrade: SyncSnaptradeStatus?
    var monzo: MonzoStatus?
    var connections: [SyncSnaptradeConnection]
}
struct ConnectionsUi { var loading = false; var error: String?; var data: ConnectionsData? }

/// Read-only view of what is connected. Keys themselves are entered only in the web app and never shown here.
@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var ui = ConnectionsUi()
    private let repo: Repository
    init(repo: Repository) { self.repo = repo }

    func load() { if ui.data == nil && !ui.loading { Task { await refresh() } } }

    func refresh() async {
        ui.loading = true; ui.error = nil
        // Everything except the flags is optional: one failing call must not hide the rest.
        async let sync = try? repo.syncStatus()
        async let snap = try? repo.syncSnaptradeStatus()
        async let monzo: MonzoStatus? = try? repo.api.get("api/monzo/status")
        async let conns = try? repo.connectionsSnaptradeConnections()
        async let flagsResult: Result<ConnectionsCredentialFlags, Error> = { do { return .success(try await repo.connectionsFlags()) } catch { return .failure(error) } }()
        let (s, sn, m, c, fr) = await (sync, snap, monzo, conns, flagsResult)
        switch fr {
        case .success(let f): ui = ConnectionsUi(data: ConnectionsData(flags: f, sync: s, snaptrade: sn, monzo: m, connections: c ?? []))
        case .failure(let e):
            if e is CancellationError { ui.loading = false } else { ui.loading = false; ui.error = (e as? ApiError)?.message ?? e.localizedDescription }
        }
    }
}

enum ConnectionsText {
    static func yesNo(_ b: Bool) -> String { b ? "Configured" : "Not set" }
    static func aiProviderLabel(_ f: ConnectionsCredentialFlags) -> String { f.aiProvider?.lowercased() == "openai" ? "OpenAI" : "Gemini" }
    static func aiAgentLabel(_ mode: String?) -> String? {
        switch mode {
        case "assistants": return "Assistants API"
        case "chat_tools": return "Chat agent (tools)"
        case nil, "": return nil
        default: return mode
        }
    }
    /// One line per T212 account that needs new keys.
    static func t212Alerts(_ sync: SyncStatus?) -> [(label: String, error: String)] {
        [("invest", "Invest"), ("isa", "Stocks & Shares ISA"), ("sipp", "SIPP")].compactMap { k, label in
            guard let a = sync?.accounts[k], a.needsReconnect else { return nil }
            return (label, a.lastError ?? "Trading 212 rejected or expired these API keys.")
        }
    }
    static func snaptradeState(_ s: SyncSnaptradeStatus?) -> String? {
        guard let s, s.configured else { return nil }
        if s.authFailed { return "Authentication failed (401). Your SnapTrade user secret may be invalid." }
        if s.needsReconnect { return "A broker link was disabled or expired and needs reconnecting." }
        if s.needsBrokerLink { return "No broker linked yet." }
        return "\(s.activeConnections) active connection\(s.activeConnections == 1 ? "" : "s")."
    }
}
