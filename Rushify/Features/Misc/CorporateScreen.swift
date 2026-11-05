import SwiftUI

struct CorporateScreen: View {
    let repo: Repository
    @ObservedObject var session: SessionManager
    @StateObject private var vm: CorporateViewModel
    @StateObject private var maps: CorporateTickerMapsViewModel
    @State private var drafts: [String: String] = [:]
    @State private var removeKey: String?
    @State private var confirm: (action: CorporateAction, status: String)?

    init(repo: Repository, session: SessionManager) {
        self.repo = repo; self.session = session
        _vm = StateObject(wrappedValue: CorporateViewModel(repo: repo))
        _maps = StateObject(wrappedValue: CorporateTickerMapsViewModel(repo: repo))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let list = vm.state.data?.value
                AsOfBar(asOf: vm.state.data?.fetchedAt, error: vm.state.error, hasData: list != nil, loading: vm.state.loading)
                if let m = vm.resolveUi.message {
                    Banner(text: m, color: vm.resolveUi.failed ? RColors.loss : RColors.accent).accessibilityIdentifier("resolve_message")
                }
                if let list { content(list) }
                else if let e = vm.state.error { ErrorState(message: e) { Task { await vm.refresh() } } }
                else { Muted("Loading…") }
            }
            .padding(16)
        }
        .refreshable { await vm.refresh(); await maps.refresh() }
        .background(RColors.bg)
        .navigationTitle("Corporate actions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .task { await maps.load() }
        .task(id: maps.edit.message) {
            guard maps.edit.message != nil else { return }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !Task.isCancelled { maps.clearMessage() }
        }
        .alert("Remove your map?", isPresented: Binding(get: { removeKey != nil }, set: { if !$0 { removeKey = nil } })) {
            Button("Remove", role: .destructive) {
                if let k = removeKey { Task { await maps.remove(sourceKey: k, onChanged: {}) } }
                removeKey = nil
            }.accessibilityIdentifier("map_remove_ok")
            Button("Cancel", role: .cancel) { removeKey = nil }
        } message: { Text("The listing you chose for this broker ticker is removed. Global mappings (if any) still apply.") }
        .alert(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button(confirm?.status == "confirmed" ? "Confirm" : "Dismiss") {
                if let c = confirm { Task { await vm.resolve(id: c.action.id, status: c.status) } }
                confirm = nil
            }.accessibilityIdentifier("confirm_dialog_ok")
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { Text(confirmMessage) }
    }

    private var confirmTitle: String {
        guard let c = confirm else { return "" }
        let t = CorporateText.actionTypeLabel(c.action.actionType)
        return c.status == "confirmed" ? "Confirm \(t)?" : "Dismiss \(t)?"
    }
    private var confirmMessage: String {
        guard let c = confirm else { return "" }
        return "\(c.action.ticker): " + (c.status == "confirmed" ? "this updates your portfolio data on the server." : "this will be ignored and removed from the to-confirm list.")
    }

    @ViewBuilder private func content(_ list: [CorporateAction]) -> some View {
        let open = CorporateText.pending(list)
        let done = list.filter { a in !open.contains(a) }
        SectionTitle("To confirm")
        if open.isEmpty {
            RCard {
                Text("Nothing to review").foregroundStyle(RColors.text)
                Muted("Splits, mergers and similar events will appear here when detected.").accessibilityIdentifier("corporate_empty")
            }
        }
        ForEach(open) { a in pendingCard(a) }
        if !done.isEmpty {
            SectionTitle("Resolved")
            ForEach(done) { a in
                RCard {
                    HStack(alignment: .firstTextBaseline) {
                        Num(a.ticker); Spacer()
                        Muted("\(CorporateText.actionTypeLabel(a.actionType)) · \(a.status)")
                    }
                }
            }
        }
        symbols()
    }

    private func pendingCard(_ a: CorporateAction) -> some View {
        RCard {
            HStack(alignment: .firstTextBaseline) { Num(a.ticker, bold: true); Spacer(); Muted(CorporateText.actionTypeLabel(a.actionType)) }
            ForEach(Array(CorporateText.detailLines(a.details).enumerated()), id: \.offset) { _, l in
                HStack(alignment: .firstTextBaseline) { Muted(l.key); Spacer(); Num(l.value, size: 12).multilineTextAlignment(.trailing) }
            }
            Muted("Detected \(Fmt.stamp(iso: a.createdAt))")
            HStack(spacing: 10) {
                actionButton("Confirm", prominent: true, id: "confirm_\(a.id)") { confirm = (a, "confirmed") }
                actionButton("Dismiss", prominent: false, id: "dismiss_\(a.id)") { confirm = (a, "dismissed") }
            }.padding(.top, 4)
        }
    }

    private func actionButton(_ title: String, prominent: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(prominent ? RColors.bg : RColors.text)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(prominent ? RColors.accent : RColors.variant, in: Capsule())
        }
        .buttonStyle(.plain).disabled(vm.resolveUi.busyId != nil).opacity(vm.resolveUi.busyId != nil ? 0.5 : 1)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private func symbols() -> some View {
        let items = maps.state.data?.value.attentionItems ?? []
        SectionTitle("Symbols to confirm")
        Muted("Enter the listing your broker uses (for example VOD.L). The choice is stored on this account only.")
        if let m = maps.edit.message { Banner(text: m, color: RColors.accent).accessibilityIdentifier("map_message") }
        if let e = maps.edit.error { Banner(text: e, color: RColors.loss).accessibilityIdentifier("map_error") }
        if items.isEmpty { Muted("Nothing needs your review right now.").accessibilityIdentifier("symbols_empty") }
        ForEach(items) { it in symbolCard(it) }
    }

    private func symbolCard(_ it: CorporateTickerAttention) -> some View {
        let busy = maps.edit.savingKey == it.sourceKey
        let draft = Binding(get: { drafts[it.sourceKey] ?? it.yahooSymbol ?? "" }, set: { drafts[it.sourceKey] = $0 })
        return RCard {
            HStack(alignment: .firstTextBaseline) {
                Num(it.brokerTicker ?? it.sourceKey, size: 13, bold: true); Spacer()
                if it.hasUserMap { Muted("YOUR MAP") }
            }
            Muted("Match in use: \(it.yahooSymbol ?? Fmt.dash)")
            TextField("Listing symbol", text: draft)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(10).foregroundStyle(RColors.text)
                .background(RColors.variant, in: RoundedRectangle(cornerRadius: 8))
                .disabled(busy)
                .accessibilityIdentifier("map_input_\(it.sourceKey)")
            HStack(spacing: 10) {
                Button { Task { await maps.save(sourceKey: it.sourceKey, symbol: draft.wrappedValue, onChanged: {}) } } label: {
                    Text(busy ? "Saving…" : "Save").font(.system(size: 14, weight: .semibold)).foregroundStyle(RColors.bg)
                        .padding(.horizontal, 18).padding(.vertical, 9).background(RColors.accent, in: Capsule())
                }
                .buttonStyle(.plain).disabled(maps.edit.savingKey != nil).opacity(maps.edit.savingKey != nil ? 0.5 : 1)
                .accessibilityIdentifier("map_save_\(it.sourceKey)")
                if it.hasUserMap {
                    Button("Remove my map") { removeKey = it.sourceKey }
                        .font(.system(size: 14)).foregroundStyle(RColors.accent)
                        .disabled(maps.edit.savingKey != nil)
                        .accessibilityIdentifier("map_remove_\(it.sourceKey)")
                }
            }
        }
    }
}
