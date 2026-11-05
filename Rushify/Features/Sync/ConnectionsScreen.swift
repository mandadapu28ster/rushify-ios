import SwiftUI

/// Read-only view of what is connected. Keys are entered and changed only in the web app and are never shown here.
struct ConnectionsScreen: View {
    let repo: Repository
    @ObservedObject var session: SessionManager
    @StateObject private var vm: ConnectionsViewModel

    init(repo: Repository, session: SessionManager) {
        self.repo = repo; self.session = session
        _vm = StateObject(wrappedValue: ConnectionsViewModel(repo: repo))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Muted("What is connected to your account. Keys are entered and changed only in the web app (Settings → Keys) and are never shown here.")
                if let d = vm.ui.data { content(d) }
                else if let e = vm.ui.error { ErrorState(message: e) { Task { await vm.refresh() } } }
                else { Muted("Loading…") }
            }
            .padding(16)
        }
        .refreshable { await vm.refresh() }
        .background(RColors.bg)
        .navigationTitle("Connections & keys").navigationBarTitleDisplayMode(.inline)
        .task { vm.load() }
    }

    private func card<C: View>(_ id: String, @ViewBuilder _ c: @escaping () -> C) -> some View {
        RCard(content: c).accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }

    @ViewBuilder private func content(_ d: ConnectionsData) -> some View {
        let f = d.flags
        card("conn_t212") {
            SectionTitle("Trading 212")
            row("Invest", ConnectionsText.yesNo(f.t212Invest), f.t212Invest)
            row("Stocks & Shares ISA", ConnectionsText.yesNo(f.t212Isa), f.t212Isa)
            row("SIPP", ConnectionsText.yesNo(f.t212Sipp), f.t212Sipp)
            ForEach(ConnectionsText.t212Alerts(d.sync), id: \.label) { a in
                Banner(text: "\(a.label): API keys rejected or expired. Replace the key and secret in the web app. \(a.error)", color: RColors.loss)
                    .padding(.top, 6).accessibilityIdentifier("t212_alert_\(a.label)")
            }
        }
        card("conn_snaptrade") {
            SectionTitle("SnapTrade")
            row("Status", f.snaptrade ? "Ready" : "Not set", f.snaptrade)
            if let s = ConnectionsText.snaptradeState(d.snaptrade) { Muted(s).padding(.top, 4) }
            if !d.connections.isEmpty {
                Muted("Linked brokerages").padding(.top, 6)
                ForEach(Array(d.connections.enumerated()), id: \.offset) { _, c in
                    row(c.brokerName ?? "Broker", c.disabled ? "Reconnect" : "Active", !c.disabled)
                }
                Muted("Add or reconnect brokers from More → Sync (opens SnapTrade's portal) or in the web app.").padding(.top, 4)
            }
        }
        card("conn_monzo") {
            SectionTitle("Monzo")
            row("Status", monzoLabel(d.monzo), d.monzo?.status == "connected")
            if let m = d.monzo, m.status == "connected" {
                Muted("\(Fmt.plural(m.balanceRows, "balance")) · last synced \(m.lastSyncedAt.map { Fmt.stamp(iso: $0) } ?? "never")")
            }
        }
        card("conn_ai") {
            SectionTitle("AI assistant")
            row("Provider", ConnectionsText.aiProviderLabel(f), true)
            row("Gemini key", ConnectionsText.yesNo(f.gemini), f.gemini)
            row("OpenAI key", ConnectionsText.yesNo(f.openai), f.openai)
            if f.aiProvider?.lowercased() == "openai", let l = ConnectionsText.aiAgentLabel(f.openaiAgentMode) { row("OpenAI agent mode", l, true) }
        }
    }

    private func row(_ label: String, _ value: String, _ good: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 14)).foregroundStyle(RColors.text)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(good ? RColors.gain : RColors.warn).multilineTextAlignment(.trailing)
        }.padding(.vertical, 3)
    }
}
