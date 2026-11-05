import Foundation

enum SyncBroker: String, CaseIterable, Hashable {
    case t212 = "T212", snaptrade = "SNAPTRADE"
    var label: String { self == .t212 ? "Trading 212" : "SnapTrade" }
}

/// After a failed or timed-out sync the button is held back: 10 s normally, 10 min when the provider is rate limiting.
struct SyncCooldown: Equatable { var untilMs: Int64; var provider: Bool }

enum SyncRules {
    static let shortCooldownMs: Int64 = 10_000
    static let providerCooldownMs: Int64 = 10 * 60_000
    private static let rateLimitPattern = "429|rate limit|too many requests|throttl|temporarily unavailable|too many"

    static func looksRateLimited(_ msg: String?) -> Bool {
        guard let msg, !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return msg.range(of: rateLimitPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func cooldownFor(_ msg: String?, now: Int64) -> SyncCooldown {
        let provider = looksRateLimited(msg)
        return SyncCooldown(untilMs: now + (provider ? providerCooldownMs : shortCooldownMs), provider: provider)
    }

    /// Server-closed stale logs get friendly text; an empty error becomes a generic one.
    static func errorText(_ err: String?) -> String {
        let s = (err ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "Sync finished with an error." }
        return s.range(of: "sync did not complete \\(stale", options: [.regularExpression, .caseInsensitive]) != nil
            ? "Sync did not complete (stale; task or server ended without finishing). Try again." : s
    }

    static let t212Provider = "Trading 212 is temporarily limiting requests. Try again in about 10 minutes."
    static let snaptradeProvider = "SnapTrade may be rate limiting. Try again in about 10 minutes."
    static let short = "Please wait a few seconds before syncing again."

    /// Why the Sync button is off, in the web's priority order; nil when it is allowed.
    static func disabledReason(_ b: SyncBroker, _ s: SyncUi, now: Int64) -> String? {
        let cd = s.cooldowns[b].flatMap { now < $0.untilMs ? $0 : nil }
        let q = b == .t212 ? s.quota?.t212 : s.quota?.snaptrade
        if let cd { return cd.provider ? (b == .t212 ? t212Provider : snaptradeProvider) : short }
        if b == .t212 {
            if s.status?.t212NeedsReconnect == true { return "Trading 212 link expired. Update the keys in the web app (Settings → Keys) to enable sync." }
            if s.status?.t212Configured == false { return "Add Trading 212 keys in the web app (Settings → Keys) to enable sync." }
        } else if let st = s.snaptrade {
            if !st.configured { return "SnapTrade is not fully configured. Save your Client ID and Consumer Key in the web app, complete the portal link, then sync." }
            if st.authFailed { return "SnapTrade link expired. Reset the keys in the web app to enable sync." }
            if st.needsBrokerLink { return "Open the connection portal first and link at least one brokerage account (read-only). Then sync." }
            if st.needsReconnect { return "A SnapTrade broker link needs reconnecting. Reconnect it, then sync." }
        }
        if let q, q.remaining <= 0 { return "Manual sync limit reached (3 successful pulls per rolling 24 hours). Try again after older pulls drop out of the window." }
        if let q, !q.rateLimitAllows { return "Please wait a moment before syncing again." }
        return nil
    }
}

enum SyncKindLabel {
    /// Server kinds: manual, scheduled (Trading 212) and snaptrade_manual, snaptrade_scheduled.
    static func of(_ kind: String) -> String {
        let broker = kind.lowercased().hasPrefix("snaptrade") ? "SnapTrade" : "Trading 212"
        let k = kind.lowercased()
        let how = k.hasSuffix("manual") ? " (manual)" : (k.hasSuffix("scheduled") ? " (scheduled)" : "")
        return broker + how
    }
}

struct SyncUi {
    var loading = false
    var error: String?
    var status: SyncStatus?
    var snaptrade: SyncSnaptradeStatus?
    var quota: SyncQuota?
    var history: [SyncLog] = []          // fetched only to detect completion; never shown
    var historyAsOf: Date?
    var running: [SyncBroker: Bool] = [:]
    var message: String?
    var cooldowns: [SyncBroker: SyncCooldown] = [:]
    var portalBusy = false
    var portalUrl: URL?                  // set once, then opened by the screen and cleared
    var portalError: String?
}

@MainActor
final class SyncViewModel: ObservableObject {
    @Published private(set) var ui = SyncUi()
    private let repo: Repository
    private let pollDelayMs: Int64
    let clock: () -> Int64
    private let sleep: (Int64) async throws -> Void
    private var pollers: [SyncBroker: Task<Void, Never>] = [:]
    private var loadTask: Task<Void, Never>?

    init(repo: Repository, pollDelayMs: Int64 = 3000,
         clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
         sleep: @escaping (Int64) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) }) {
        self.repo = repo; self.pollDelayMs = pollDelayMs; self.clock = clock; self.sleep = sleep
    }

    private func update(_ f: (inout SyncUi) -> Void) { f(&ui) }

    /// Opening the screen: saved history first, then fresh data, then pick up syncs that are already running.
    func load() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            if let c = await self.repo.syncHistoryCached() {
                self.update { $0.history = c.value.sorted { $0.id > $1.id }; $0.historyAsOf = c.fetchedAt }
            }
            await self.refreshNow()
            await self.resumeRunning()
        }
    }

    func stop() { pollers.values.forEach { $0.cancel() }; pollers = [:]; loadTask?.cancel(); loadTask = nil }

    /// A sync started earlier (even before the app was closed) keeps running on the server: pick it up again.
    private func resumeRunning() async {
        if let r = try? await repo.syncT212Running(), r.inProgress { resume(.t212, id: r.activeSyncLogId) }
        if let r = try? await repo.syncSnaptradeRunning(), r.inProgress { resume(.snaptrade, id: r.activeSyncLogId) }
    }

    private func resume(_ b: SyncBroker, id: Int?) {
        guard ui.running[b] != true else { return }
        update { $0.running[b] = true }
        if let id { poll(b, id: id) } else { pollRunning(b) }
    }

    func refresh() { Task { await refreshNow() } }

    func refreshNow() async {
        update { $0.loading = true }
        do {
            let status = try await repo.syncStatus()
            let snap = try await repo.syncSnaptradeStatus()
            let quota = try await repo.syncQuota()
            let hist = try await repo.syncHistory()
            update {
                $0.loading = false; $0.error = nil; $0.status = status; $0.snaptrade = snap; $0.quota = quota
                $0.history = hist.value.sorted { $0.id > $1.id }; $0.historyAsOf = hist.fetchedAt
            }
        } catch is CancellationError {
            update { $0.loading = false }
        } catch {
            update { $0.loading = false; $0.error = (error as? ApiError)?.message ?? error.localizedDescription }
        }
    }

    /// Call only after the user confirmed. Does nothing while running or while the button is disabled.
    @discardableResult
    func sync(_ broker: SyncBroker) -> Task<Void, Never>? {
        if ui.running[broker] == true { return nil }
        if SyncRules.disabledReason(broker, ui, now: clock()) != nil { return nil }
        update { $0.message = nil; $0.running[broker] = true }
        return Task { [weak self] in
            guard let self else { return }
            do {
                let accepted = try await self.repo.syncStart(broker)
                if let id = accepted.syncLogId { self.poll(broker, id: id) }
                else { self.update { $0.running[broker] = false }; await self.refreshNow() }
            } catch let e as ApiError {
                switch e {
                case .quotaReached(let m):
                    self.update { $0.running[broker] = false; $0.message = "Daily manual sync limit reached. \(m)" }
                    await self.refreshNow()
                case .syncRunning:
                    // 409: another sync is already running; show the running state, no new request.
                    self.update { $0.message = "A sync is already running for \(broker.label)." }
                    await self.refreshNow()
                    self.pollRunning(broker)
                default:
                    let now = self.clock()
                    self.update { $0.running[broker] = false; $0.message = SyncRules.errorText(e.message); $0.cooldowns[broker] = SyncRules.cooldownFor(e.message, now: now) }
                }
            } catch {
                self.update { $0.running[broker] = false }
            }
        }
    }

    private func pollRunning(_ broker: SyncBroker) {
        pollers[broker]?.cancel()
        pollers[broker] = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<60 {
                do { try await self.sleep(self.pollDelayMs) } catch { return }
                let latest = try? await self.repo.syncHistory().value.max { $0.id < $1.id }
                if let latest, latest.finishedAt != nil { await self.finish(broker, latest); return }
            }
            self.update { $0.running[broker] = false }
        }
    }

    private func poll(_ broker: SyncBroker, id: Int) {
        pollers[broker]?.cancel()
        pollers[broker] = Task { [weak self] in
            guard let self else { return }
            var wait = self.pollDelayMs
            for _ in 0..<80 {
                do { try await self.sleep(wait) } catch { return }
                do {
                    let log = try await self.repo.syncLog(id)
                    if log.finishedAt != nil { await self.finish(broker, log); return }
                } catch ApiError.sessionExpired { return }
                catch is CancellationError { return }
                catch { /* keep polling with backoff */ }
                wait = min(wait * 3 / 2, 15_000)
            }
            let now = self.clock()
            self.update {
                $0.running[broker] = false
                $0.message = "Sync is taking longer than expected. Check again in a minute."
                $0.cooldowns[broker] = SyncRules.cooldownFor(nil, now: now)
            }
        }
    }

    private func finish(_ broker: SyncBroker, _ log: SyncLog) async {
        let now = clock()
        update {
            $0.running[broker] = false
            $0.message = log.success ? "\(broker.label) sync finished." : "\(broker.label) sync failed: \(SyncRules.errorText(log.errorMessage))"
            if !log.success { $0.cooldowns[broker] = SyncRules.cooldownFor(log.errorMessage, now: now) }
        }
        if log.success { repo.notifyChanged() }
        await refreshNow()
    }

    /// Opens SnapTrade's connection portal (new brokerage, or reconnect a disabled link). Only an http(s) address is handed back.
    @discardableResult
    func openPortal(reconnectId: String?) -> Task<Void, Never>? {
        if ui.portalBusy { return nil }
        update { $0.portalBusy = true; $0.portalError = nil }
        return Task { [weak self] in
            guard let self else { return }
            do {
                let r = try await self.repo.syncPortalUrl(reconnectId: reconnectId)
                let url = SyncSafeUrl.httpOrNull(r.redirectUri)
                self.update { $0.portalBusy = false; $0.portalUrl = url; $0.portalError = url == nil ? "Could not open SnapTrade portal" : nil }
            } catch {
                let m = (error as? ApiError)?.message
                self.update { $0.portalBusy = false; $0.portalError = (m?.isEmpty == false ? m : nil) ?? "Could not open SnapTrade portal" }
            }
        }
    }

    func portalOpened() { update { $0.portalUrl = nil } }
}
