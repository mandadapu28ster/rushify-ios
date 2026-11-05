import Foundation

struct MonzoSyncUi: Equatable { var syncing = false; var message: String?; var failed = false }

/// Exactly the web wording for the three outcomes of a Monzo sync.
enum MonzoMessages {
    static let waiting = "Still waiting for approval. Open the Monzo app and approve access."
    static let updated = "Monzo balances updated."
    static func synced(_ c: MonzoSyncCounts) -> String {
        "Synced \(c.accounts) account\(c.accounts == 1 ? "" : "s") and \(c.pots) pot\(c.pots == 1 ? "" : "s")."
    }
    static func of(_ o: MonzoSyncOutcome) -> String {
        guard let r = o.result else { return updated }
        if let s = r.sync { return synced(s) }
        return waiting
    }
}

/// Web labels: Connected, Waiting for approval in the Monzo app, Needs reconnect, Keys saved - not connected, Not set.
func monzoStatusLabel(_ status: String?) -> String {
    switch status {
    case nil, "": return "Keys saved — not connected"
    case "connected": return "Connected"
    case "pending_approval": return "Waiting for approval in the Monzo app"
    case "needs_reconnect": return "Needs reconnect"
    case "not_connected": return "Keys saved — not connected"
    default:
        let s = status!.replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
func monzoLabel(_ m: MonzoStatus?) -> String { guard let m, m.configured else { return "Not set" }; return monzoStatusLabel(m.status) }
func monzoCanSync(_ m: MonzoStatus?) -> Bool { guard let m else { return false }; return m.configured && (m.status == "connected" || m.status == "pending_approval") }

@MainActor
final class MonzoViewModel: ObservableObject {
    @Published private(set) var state = LoadState<MonzoStatus>()
    @Published private(set) var sync = MonzoSyncUi()
    private let repo: Repository
    private var loadTask: Task<Void, Never>?

    init(repo: Repository) { self.repo = repo }

    func load() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            if let c = await self.repo.monzoCached() { self.state.data = c }
            await self.refresh()
        }
    }

    func refresh() async {
        state.loading = true
        do { state = LoadState(data: try await repo.monzo()) }
        catch is CancellationError { state.loading = false }
        catch { state.loading = false; state.error = (error as? ApiError)?.message ?? error.localizedDescription }
    }

    /// Pulls fresh balances from Monzo through the server; `onDone` lets the caller refresh the dashboard.
    @discardableResult
    func syncNow(onDone: @escaping () -> Void = {}) -> Task<Void, Never>? {
        if sync.syncing { return nil }
        sync = MonzoSyncUi(syncing: true)
        return Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.repo.monzoSyncNow()
                self.sync = MonzoSyncUi(message: MonzoMessages.of(outcome))
                if outcome.result?.sync != nil || outcome.result == nil { onDone() }
                await self.refresh()
            } catch is CancellationError {
                self.sync = MonzoSyncUi()
            } catch {
                self.sync = MonzoSyncUi(message: "Monzo sync failed: \((error as? ApiError)?.message ?? error.localizedDescription)", failed: true)
                await self.refresh()
            }
        }
    }
}
