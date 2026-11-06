import SwiftUI

private extension View {
    func syncId(_ id: String) -> some View { accessibilityIdentifier(id) }
}

/// Trading 212, SnapTrade and Monzo manual sync. Pushed inside the More NavigationStack.
struct SyncScreen: View {
    let repo: Repository
    @ObservedObject var session: SessionManager
    let showTitle: Bool
    @StateObject private var vm: SyncViewModel
    @StateObject private var monzo: MonzoViewModel
    @State private var confirm: SyncBroker?
    @State private var now: Int64 = 0
    @Environment(\.openURL) private var openURL

    init(repo: Repository, session: SessionManager, showTitle: Bool = true) {
        self.repo = repo; self.session = session; self.showTitle = showTitle
        _vm = StateObject(wrappedValue: SyncViewModel(repo: repo))
        _monzo = StateObject(wrappedValue: MonzoViewModel(repo: repo))
    }

    private var ui: SyncUi { vm.ui }
    private var hasCooldowns: Bool { !ui.cooldowns.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if showTitle { Text("Sync").font(.r(24, .semibold)).foregroundStyle(RColors.text).syncId("sync_title") }
                AsOfBar(asOf: ui.historyAsOf, error: ui.error, hasData: !ui.history.isEmpty || ui.quota != nil, loading: ui.loading,
                        label: ui.historyAsOf.map { "Updated \(Fmt.stamp($0))" })
                if ui.quota == nil, let e = ui.error { ErrorState(message: e) { vm.refresh() } }
                if let m = ui.message {
                    Banner(text: m, color: (m.localizedCaseInsensitiveContains("fail") || m.localizedCaseInsensitiveContains("limit")) ? RColors.loss : RColors.accent)
                        .syncId("sync_message")
                }
                ForEach(SyncBroker.allCases, id: \.self) { brokerCard($0) }
                MonzoSyncCard(vm: monzo) { repo.notifyChanged() }
                Muted("Manual syncs are limited to 3 per rolling 24 hours for Trading 212 and for SnapTrade. Monzo has no daily limit.")
            }
            .padding(16)
        }
        .refreshable { await vm.refreshNow(); await monzo.refresh() }
        .background(RColors.bg)
        .task { vm.load(); monzo.load() }
        .task(id: hasCooldowns) {
            now = vm.clock()
            while hasCooldowns && !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000_000); now = vm.clock() }
        }
        .onChange(of: ui.portalUrl) { _, url in
            if let url { vm.portalOpened(); openURL(url) }
        }
        .onDisappear { vm.stop() }
        .alert("Sync \(confirm?.label ?? "")?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { b in
            Button("Sync") { confirm = nil; vm.sync(b) }.accessibilityIdentifier("confirm_sync")
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { b in
            Text("This uses one of your daily manual syncs for \(b.label).")
        }
    }

    @ViewBuilder private func brokerCard(_ b: SyncBroker) -> some View {
        let running = ui.running[b] == true
        let q = b == .t212 ? ui.quota?.t212 : ui.quota?.snaptrade
        let reason = SyncRules.disabledReason(b, ui, now: hasCooldowns ? max(now, vm.clock()) : vm.clock())
        RCard {
            Text(b.label).font(.r(16, .semibold)).foregroundStyle(RColors.text)
            brokerStatus(b)
            if let q { Muted("\(q.remaining) of \(ui.quota?.maxPer24h ?? 3) manual syncs left today (rolling 24 h)") }
            Spacer().frame(height: 8)
            if running {
                ProgressView().progressViewStyle(.linear).tint(RColors.accent).syncId("sync_running_\(b.rawValue)")  // indeterminate: the API reports no percentage
                Muted("\(b.label) sync in progress…").padding(.top, 4)
            } else {
                Button { confirm = b } label: { Text("Sync now") }
                    .buttonStyle(RPrimaryButtonStyle()).disabled(reason != nil).syncId("sync_\(b.rawValue)")
                if let reason { Muted(reason).padding(.top, 4).syncId("sync_reason_\(b.rawValue)") }
            }
        }
        .accessibilityElement(children: .contain).syncId("broker_\(b.rawValue)")
    }

    /// Connection state of one broker, with the same cases as the web (expired link, reconnect, connect a brokerage).
    @ViewBuilder private func brokerStatus(_ b: SyncBroker) -> some View {
        if b == .t212 {
            let st = ui.status
            let alerts = ConnectionsText.t212Alerts(st)
            if let st {
                if st.t212NeedsReconnect || !alerts.isEmpty {
                    Banner(text: "Broker link expired. Trading 212 rejected the credentials. Replace the API keys in the web app (Settings → Keys).", color: RColors.warn).syncId("t212_expired")
                    ForEach(Array(alerts.enumerated()), id: \.offset) { _, a in Muted("\(a.label): \(a.error)") }
                } else if !st.t212Configured {
                    Muted("Not connected. Add Trading 212 keys in the web app (Settings → Keys).")
                } else { Muted("Connected") }
            } else { Muted("Checking connection…") }
        } else {
            snaptradeStatus()
        }
    }

    @ViewBuilder private func snaptradeStatus() -> some View {
        if let st = ui.snaptrade {
            if !st.configured {
                Muted("Not connected. Add your SnapTrade keys in the web app (Settings → Keys).")
            } else if st.authFailed {
                Banner(text: "SnapTrade session expired. The connection failed (401) and your SnapTrade user secret may be invalid. Reset the SnapTrade keys in the web app.", color: RColors.loss).syncId("snaptrade_auth_failed")
            } else if st.needsReconnect {
                let first = st.disabled.first
                VStack(alignment: .leading, spacing: 6) {
                    Banner(text: "Broker link disabled or expired\(first?.brokerName.map { " (\($0))" } ?? ""). Reconnect it in SnapTrade, then sync.", color: RColors.warn)
                    portalButton(ui.portalBusy ? "Opening…" : "Reconnect in SnapTrade", id: "snaptrade_reconnect_btn") { vm.openPortal(reconnectId: first?.id) }
                }.accessibilityElement(children: .contain).syncId("snaptrade_reconnect")
            } else if st.needsBrokerLink {
                VStack(alignment: .leading, spacing: 6) {
                    Banner(text: "Connect a brokerage. Link at least one read-only brokerage account in SnapTrade's portal, then sync.", color: RColors.accent)
                    portalButton(ui.portalBusy ? "Opening portal…" : "Open connection portal", id: "snaptrade_link_btn") { vm.openPortal(reconnectId: nil) }
                }.accessibilityElement(children: .contain).syncId("snaptrade_link")
            } else {
                Muted("\(st.activeConnections) active broker connection\(st.activeConnections == 1 ? "" : "s") · daily sync")
            }
        } else { Muted("Checking connection…") }
        if let e = ui.portalError { Banner(text: e, color: RColors.loss).syncId("portal_error") }
    }

    private func portalButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title) }
            .buttonStyle(RPrimaryButtonStyle()).disabled(ui.portalBusy).syncId(id)
    }
}

/// Monzo's manual sync, shown on Sync next to Trading 212 and SnapTrade (it does not use the broker sync quota).
struct MonzoSyncCard: View {
    @ObservedObject var vm: MonzoViewModel
    var onSynced: () -> Void

    var body: some View {
        let m = vm.state.data?.value
        RCard {
            Text("Monzo").font(.r(16, .semibold)).foregroundStyle(RColors.text)
            if let m {
                let ok = m.configured && m.status == "connected"
                Text(monzoLabel(m)).font(.r(13)).foregroundStyle(ok ? RColors.gain : RColors.warn).accessibilityIdentifier("monzo_status")
                if m.status == "connected" {
                    Muted("\(Fmt.plural(m.balanceRows, "balance")) · last synced \(m.lastSyncedAt.map { Fmt.stamp(iso: $0) } ?? "never"). Refreshed daily at 21:00 (London).")
                }
                if let e = m.lastError { Banner(text: e, color: RColors.loss).padding(.top, 6) }
                if !m.configured { Muted("Connect Monzo in the web app (Settings → Keys). OAuth sign-in stays on the web by design.") }
                else if m.status == "pending_approval" { Muted("Open the Monzo app and approve the access request, then sync.") }
                else if m.status != "connected" { Muted("Finish connecting Monzo in the web app (Settings → Keys), then sync here.") }
                if monzoCanSync(m) {
                    let syncing = vm.sync.syncing
                    Button { vm.syncNow(onDone: onSynced) } label: {
                        Text(syncing ? "Syncing…" : (m.status == "pending_approval" ? "Check approval / sync" : "Sync now"))
                    }
                    .buttonStyle(RPrimaryButtonStyle()).disabled(syncing).padding(.top, 8).accessibilityIdentifier("monzo_sync")
                }
                if let msg = vm.sync.message {
                    Banner(text: msg, color: vm.sync.failed ? RColors.loss : RColors.accent).padding(.top, 8).accessibilityIdentifier("monzo_message")
                }
            } else {
                Muted(vm.state.error != nil ? "Could not load Monzo status." : "Loading Monzo…")
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("broker_MONZO")
    }
}
