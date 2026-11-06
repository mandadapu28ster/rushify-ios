import SwiftUI

// MARK: Endpoints

extension Repository {
    func manualFetchHoldings() async throws -> [ManualHoldingOut] { try await api.get("api/portfolio/manual") }
    func manualCreate(_ body: [String: Any]) async throws { try await api.sendJSON("POST", "api/portfolio/manual", json: body) }
    func manualPatch(_ id: Int, _ body: [String: Any]) async throws { try await api.sendJSON("PATCH", "api/portfolio/manual/\(id)", json: body) }
    func manualDelete(_ id: Int) async throws { try await api.send("DELETE", "api/portfolio/manual/\(id)") }
    func manualSell(_ id: Int, _ body: [String: Any]) async throws { try await api.sendJSON("POST", "api/portfolio/manual/\(id)/sell", json: body) }
    func manualPutSector(_ body: [String: Any]) async throws { try await api.sendJSON("PUT", "api/portfolio/sector-override", json: body) }
    func manualSymbolSearch(_ q: String) async throws -> [SymbolHit] { try await api.get("api/portfolio/symbol-search", query: [URLQueryItem(name: "q", value: q)]) }
    func manualSymbolQuote(_ symbol: String) async throws -> SymbolQuote { try await api.get("api/portfolio/symbol-quote", query: [URLQueryItem(name: "symbol", value: symbol)]) }
}

struct ManualWriteUi: Equatable { var busy = false; var message: String?; var error: String? }

/// Online-only writes for manual holdings and sector overrides. Nothing is queued: a failed write shows the server's message and
/// leaves everything as it was. After a success the caller refreshes Home, Holdings and the charts (repo.notifyChanged()).
@MainActor
final class ManualViewModel: ObservableObject {
    @Published private(set) var ui = ManualWriteUi()
    @Published private(set) var details: [Int: ManualHoldingOut] = [:]
    @Published private(set) var hits: [SymbolHit] = []
    @Published private(set) var quote: SymbolQuote?
    var today: () -> ManualDay = { ManualDay.today() }
    /// Web: wait 350 ms after typing before searching. Injectable so tests do not wait.
    var searchDelay: Duration = .milliseconds(350)
    private(set) var searchTask: Task<Void, Never>?
    private let repo: Repository

    init(repo: Repository) { self.repo = repo }

    func clear() { ui = ManualWriteUi() }

    @discardableResult
    func loadDetails() -> Task<Void, Never> {
        Task { if let l = try? await repo.manualFetchHoldings() { details = Dictionary(l.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b }) } }
    }

    /// Same as the web: wait 350 ms after typing, and only search from 2 characters.
    func search(_ q: String) {
        searchTask?.cancel()
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count < 2 { hits = []; return }
        let delay = searchDelay
        searchTask = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            let found = (try? await repo.manualSymbolSearch(t)) ?? []
            if !Task.isCancelled { hits = found }
        }
    }

    /// Picking a hit fills the symbol, then asks for a quote; a failed quote is ignored (the web does the same).
    @discardableResult
    func pick(_ hit: SymbolHit, onSymbol: @escaping (String) -> Void) -> Task<Void, Never> {
        hits = []; quote = nil
        onSymbol(hit.symbol)
        return Task {
            let q = try? await repo.manualSymbolQuote(hit.symbol)
            quote = q
            if let n = q?.normalizedSymbol, !n.trimmingCharacters(in: .whitespaces).isEmpty { onSymbol(n) }
        }
    }

    func resetSearch() { searchTask?.cancel(); hits = []; quote = nil }

    @discardableResult
    private func run(_ built: ManualBuilt, ok: String, onDone: @escaping () -> Void, call: @escaping ([String: Any]) async throws -> Void) -> Task<Void, Never>? {
        if ui.busy { return nil }
        switch built {
        case .err(let m): ui = ManualWriteUi(error: m); return nil
        case .ok(let body):
            ui = ManualWriteUi(busy: true)
            return Task { await perform(ok: ok, onDone: onDone) { try await call(body) } }
        }
    }

    private func perform(ok: String, onDone: () -> Void, _ call: () async throws -> Void) async {
        do { try await call(); ui = ManualWriteUi(message: ok); onDone() }
        catch is CancellationError { ui = ManualWriteUi() }
        catch { ui = ManualWriteUi(error: (error as? ApiError)?.message ?? error.localizedDescription) }
    }

    @discardableResult func create(_ b: ManualBuilt, onDone: @escaping () -> Void) -> Task<Void, Never>? {
        run(b, ok: "Saved. Home and Holdings will refresh shortly.", onDone: onDone) { [repo] in try await repo.manualCreate($0) }
    }
    @discardableResult func editListed(_ id: Int, _ b: ManualBuilt, onDone: @escaping () -> Void) -> Task<Void, Never>? {
        run(b, ok: "Lot updated.", onDone: onDone) { [repo] in try await repo.manualPatch(id, $0) }
    }
    @discardableResult func editValues(_ id: Int, _ b: ManualBuilt, onDone: @escaping () -> Void) -> Task<Void, Never>? {
        run(b, ok: "Values saved.", onDone: { [weak self] in self?.loadDetails(); onDone() }) { [repo] in try await repo.manualPatch(id, $0) }
    }
    @discardableResult func sell(_ id: Int, _ b: ManualBuilt, onDone: @escaping () -> Void) -> Task<Void, Never>? {
        run(b, ok: "Sale recorded.", onDone: onDone) { [repo] in try await repo.manualSell(id, $0) }
    }
    @discardableResult func saveSector(_ b: ManualBuilt, onDone: @escaping () -> Void) -> Task<Void, Never>? {
        run(b, ok: "Sector saved.", onDone: onDone) { [repo] in try await repo.manualPutSector($0) }
    }
    @discardableResult func remove(_ id: Int, onDone: @escaping () -> Void) -> Task<Void, Never>? {
        if ui.busy { return nil }
        ui = ManualWriteUi(busy: true)
        return Task { await perform(ok: "Position removed.", onDone: onDone) { try await repo.manualDelete(id) } }
    }
}

// MARK: Shared form pieces

private struct ManualField: View {
    let label: String
    @Binding var text: String
    let id: String
    var number = false
    var hint: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.r(12, .medium)).foregroundStyle(RColors.muted)
            TextField("", text: $text, prompt: Text(hint ?? (number ? "0.00" : "")).foregroundStyle(RColors.muted.opacity(0.6)))
                .focused($focused)
                .textFieldStyle(.plain)
                .keyboardType(number ? .numbersAndPunctuation : .default)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.r(16)).foregroundStyle(RColors.text)
                .padding(.horizontal, 12).frame(minHeight: 48)
                .background(RColors.variant, in: RoundedRectangle(cornerRadius: RRadius.control))
                .overlay(RoundedRectangle(cornerRadius: RRadius.control).strokeBorder(focused ? RColors.accent : Color.clear, lineWidth: 1.5))
                .animation(.easeOut(duration: 0.15), value: focused)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
    }
}

private struct ManualChipRow: View {
    let options: [(value: String, label: String)]
    let selected: String
    let tagPrefix: String
    let onPick: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.value) { o in
                    Chip(text: o.label, selected: selected == o.value) { onPick(o.value) }.accessibilityIdentifier("\(tagPrefix)\(o.value)")
                }
            }
        }
    }
}

private struct ManualButton: View {
    let title: String
    var danger = false
    var filled = true
    var enabled = true
    let id: String
    let action: () -> Void
    var body: some View {
        Group {
            if filled && !danger { Button(action: action) { Text(title) }.buttonStyle(RPrimaryButtonStyle()) }
            else { Button(action: action) { Text(title) }.buttonStyle(RSecondaryButtonStyle(destructive: danger)) }
        }
        .disabled(!enabled).accessibilityIdentifier(id)
    }
}

private struct ManualFormFrame<Content: View>: View {
    let title: String
    @ObservedObject var vm: ManualViewModel
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.r(20)).foregroundStyle(RColors.text)
                if let e = vm.ui.error { Banner(text: e, color: RColors.loss).accessibilityIdentifier("form_error") }
                content()
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RColors.bg.ignoresSafeArea())
        .accessibilityIdentifier("manual_form")
    }
}

private struct ManualSaveRow: View {
    @ObservedObject var vm: ManualViewModel
    let label: String
    var enabled = true
    let onSave: () -> Void
    let onCancel: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            ManualButton(title: vm.ui.busy ? "Saving…" : label, enabled: enabled && !vm.ui.busy, id: "form_save", action: onSave)
            ManualButton(title: "Cancel", filled: false, enabled: !vm.ui.busy, id: "form_cancel", action: onCancel)
        }
    }
}

// MARK: Kind-dependent fields (property, cash, other)

private struct ManualKindFields: View {
    @Binding var f: ManualRules.NonListed
    let p: String
    var body: some View {
        switch f.kind {
        case .property:
            ManualField(label: "Name", text: $f.label, id: "\(p)label")
            ManualField(label: "Home value", text: $f.homeValue, id: "\(p)home", number: true)
            ManualField(label: "Mortgage balance", text: $f.mortgage, id: "\(p)mortgage", number: true)
        case .cash:
            ManualField(label: "Bank or building society", text: $f.broker, id: "\(p)bank")
            Muted("Account type")
            ManualChipRow(options: ManualRules.cashTypes.map { ($0, $0) }, selected: f.cashType, tagPrefix: "\(p)type_") { f.cashType = $0 }
            if f.cashType == ManualRules.cashOther { ManualField(label: "Describe the account", text: $f.cashTypeOther, id: "\(p)type_other") }
            ManualField(label: "Balance", text: $f.cashBalance, id: "\(p)balance", number: true)
        default:
            ManualField(label: "Name", text: $f.label, id: "\(p)label")
            ManualField(label: "Value", text: $f.otherValue, id: "\(p)other", number: true)
        }
    }
}

// MARK: Forms opened from a holding

private enum ManualFormKind: String, Identifiable { case editLot, sell, editValues, sector, remove; var id: String { rawValue } }

/// Buttons shown under a holding's details; only the ones that apply to this row. Presents the forms itself.
struct ManualActionsView: View {
    let repo: Repository
    let context: HoldingContext
    @StateObject private var vm: ManualViewModel
    @State private var form: ManualFormKind?

    init(repo: Repository, context: HoldingContext) {
        self.repo = repo; self.context = context
        _vm = StateObject(wrappedValue: ManualViewModel(repo: repo))
    }

    var body: some View {
        let a = ManualRules.actions(for: context.row, isPrimaryLot: context.isPrimaryLot)
        if a.any {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Edit")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if a.sector { ManualButton(title: "Change sector", filled: false, id: "act_sector") { open(.sector) } }
                        if a.editLot { ManualButton(title: "Edit lot", filled: false, id: "act_edit") { open(.editLot) } }
                        if a.sell { ManualButton(title: "Record sale", filled: false, id: "act_sell") { open(.sell) } }
                        if a.values { ManualButton(title: "Edit values", filled: false, id: "act_values") { open(.editValues) } }
                        if a.remove { ManualButton(title: "Remove", danger: true, filled: false, id: "act_remove") { open(.remove) } }
                    }
                }
            }
            .padding(.top, 8)
            .sheet(item: $form, onDismiss: { vm.clear() }) { k in
                ManualFormHost(kind: k, vm: vm, repo: repo, context: context,
                               onDone: { repo.notifyChanged(); vm.clear(); form = nil },
                               onCancel: { vm.clear(); form = nil })
                    .presentationDetents([.large])
            }
        }
    }

    private func open(_ k: ManualFormKind) { vm.clear(); form = k }
}

private struct ManualFormHost: View {
    let kind: ManualFormKind
    @ObservedObject var vm: ManualViewModel
    let repo: Repository
    let context: HoldingContext
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        if let id = context.row.manualHoldingId, kind != .sector {
            switch kind {
            case .editLot: ManualEditLotForm(row: context.row, ticker: context.displayTicker, vm: vm, id: id, done: onDone, cancel: onCancel)
            case .sell: ManualSellForm(row: context.row, ticker: context.displayTicker, vm: vm, id: id, done: onDone, cancel: onCancel)
            case .editValues: ManualEditValuesForm(vm: vm, id: id, done: onDone, cancel: onCancel)
            default: ManualRemoveForm(vm: vm, id: id, done: onDone, cancel: onCancel)
            }
        } else if kind == .sector {
            ManualSectorForm(row: context.row, ticker: ManualRules.sectorTicker(displayTicker: context.displayTicker), vm: vm, done: onDone, cancel: onCancel)
        }
    }
}

private struct ManualRemoveForm: View {
    @ObservedObject var vm: ManualViewModel
    let id: Int, done: () -> Void, cancel: () -> Void
    var body: some View {
        ManualFormFrame(title: "Remove this position?", vm: vm) {
            Text("Remove this manual position from the portfolio?\n\nIf you sold the shares, consider using “Record sale” first (sell date and price) so the listed equity chart can track quantity over time. Deleting here removes the line without recording that sale.")
                .font(.r(14)).foregroundStyle(RColors.text).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ManualButton(title: vm.ui.busy ? "Removing…" : "Remove", danger: true, enabled: !vm.ui.busy, id: "remove_ok") { vm.remove(id, onDone: done) }
                ManualButton(title: "Cancel", filled: false, enabled: !vm.ui.busy, id: "form_cancel", action: cancel)
            }
        }
    }
}

private struct ManualEditLotForm: View {
    let row: HoldingRow, ticker: String
    @ObservedObject var vm: ManualViewModel
    let id: Int, done: () -> Void, cancel: () -> Void
    @State private var label: String
    @State private var qty: String
    @State private var broker: String
    @State private var kind: String
    @State private var date: String
    @State private var cost: String

    init(row: HoldingRow, ticker: String, vm: ManualViewModel, id: Int, done: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.row = row; self.ticker = ticker; self.vm = vm; self.id = id; self.done = done; self.cancel = cancel
        _label = State(initialValue: row.instrumentName ?? "")
        _qty = State(initialValue: ManualRules.plain(row.quantity))
        _broker = State(initialValue: row.manualBrokerName ?? row.brokerLabel ?? "")
        _kind = State(initialValue: row.accountKind.flatMap { k in ManualRules.listedEditKinds.contains { $0.value == k } ? k : nil } ?? "unspecified")
        _date = State(initialValue: row.purchaseDate ?? "")
        _cost = State(initialValue: ManualRules.plain(row.costBaseGbp))
    }

    var body: some View {
        ManualFormFrame(title: "Edit lot · \(ticker)", vm: vm) {
            ManualField(label: "Label (optional)", text: $label, id: "f_label")
            ManualField(label: "Quantity", text: $qty, id: "f_qty", number: true)
            ManualField(label: "Broker", text: $broker, id: "f_broker")
            Muted("Account type")
            ManualChipRow(options: ManualRules.listedEditKinds, selected: kind, tagPrefix: "kind_") { kind = $0 }
            ManualField(label: "Purchase date", text: $date, id: "f_date", hint: "YYYY-MM-DD")
            ManualField(label: "Total cost (GBP)", text: $cost, id: "f_cost", number: true)
            ManualSaveRow(vm: vm, label: "Save lot", onSave: {
                vm.editListed(id, ManualRules.listedEdit(label: label, qty: qty, broker: broker, kind: kind, purchaseDate: date, cost: cost, today: vm.today()), onDone: done)
            }, onCancel: cancel)
        }
    }
}

private struct ManualSellForm: View {
    let row: HoldingRow, ticker: String
    @ObservedObject var vm: ManualViewModel
    let id: Int, done: () -> Void, cancel: () -> Void
    @State private var qty = ""
    @State private var date: String
    @State private var price = ""

    init(row: HoldingRow, ticker: String, vm: ManualViewModel, id: Int, done: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.row = row; self.ticker = ticker; self.vm = vm; self.id = id; self.done = done; self.cancel = cancel
        _date = State(initialValue: vm.today().iso)
    }

    var body: some View {
        ManualFormFrame(title: "Record sale · \(ticker)", vm: vm) {
            Muted("Held: \(Fmt.quantity(row.quantity)). All fields are required; use the GBP price per share from your contract note.")
            ManualField(label: "Quantity sold", text: $qty, id: "f_qty", number: true)
            Button("Sell entire position") { qty = ManualRules.plain(row.quantity) }
                .font(.r(14, .medium)).foregroundStyle(RColors.accent).accessibilityIdentifier("sell_all")
            ManualField(label: "Sell date", text: $date, id: "f_date", hint: "YYYY-MM-DD")
            ManualField(label: "Price per share (GBP)", text: $price, id: "f_price", number: true)
            ManualSaveRow(vm: vm, label: "Record sale", onSave: {
                vm.sell(id, ManualRules.sell(held: row.quantity, purchaseDate: row.purchaseDate, qty: qty, executedAt: date, price: price, today: vm.today()), onDone: done)
            }, onCancel: cancel)
        }
    }
}

private struct ManualSectorForm: View {
    let row: HoldingRow, ticker: String
    @ObservedObject var vm: ManualViewModel
    let done: () -> Void, cancel: () -> Void
    @State private var pick: String
    private let current: String?
    private let options: [String]

    init(row: HoldingRow, ticker: String, vm: ManualViewModel, done: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.row = row; self.ticker = ticker; self.vm = vm; self.done = done; self.cancel = cancel
        let cur = row.sector.flatMap { s -> String? in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.isEmpty || s.caseInsensitiveCompare("unknown") == .orderedSame) ? nil : s
        }
        current = cur
        let known = cur.map { c in ManualRules.sectors.contains { $0.caseInsensitiveCompare(c) == .orderedSame } } ?? true
        options = (cur != nil && !known) ? [cur!] + ManualRules.sectors : ManualRules.sectors
        _pick = State(initialValue: cur ?? "")
    }

    var body: some View {
        ManualFormFrame(title: "Change sector · \(ticker)", vm: vm) {
            Muted("Your choice is stored on this account only and applies to every lot of \(ticker).")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options, id: \.self) { s in
                    Button { pick = s } label: {
                        HStack(spacing: 10) {
                            Image(systemName: pick == s ? "largecircle.fill.circle" : "circle").foregroundStyle(pick == s ? RColors.accent : RColors.muted)
                            Text(s == current && !ManualRules.sectors.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) ? "\(s) (from data)" : s)
                                .foregroundStyle(RColors.text)
                            Spacer()
                        }.padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sector_\(s)")
                    .accessibilityAddTraits(pick == s ? .isSelected : [])
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("sector_options")
            ManualSaveRow(vm: vm, label: "Save sector", enabled: !pick.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
                vm.saveSector(ManualRules.sectorBody(ticker: ticker, sector: pick), onDone: done)
            }, onCancel: cancel)
        }
    }
}

private struct ManualEditValuesForm: View {
    @ObservedObject var vm: ManualViewModel
    let id: Int, done: () -> Void, cancel: () -> Void
    var body: some View {
        Group {
            if let m = vm.details[id] {
                ManualEditValuesBody(m: m, vm: vm, id: id, done: done, cancel: cancel)
            } else {
                ManualFormFrame(title: "Edit values", vm: vm) {
                    Muted("Loading…")
                    ManualButton(title: "Cancel", filled: false, id: "form_cancel", action: cancel)
                }
            }
        }
        .task { vm.loadDetails() }
    }
}

private struct ManualEditValuesBody: View {
    let m: ManualHoldingOut
    @ObservedObject var vm: ManualViewModel
    let id: Int, done: () -> Void, cancel: () -> Void
    @State private var f: ManualRules.NonListed
    @State private var mode = "update"
    @State private var updateDate = ""
    @State private var chart: Bool

    init(m: ManualHoldingOut, vm: ManualViewModel, id: Int, done: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.m = m; self.vm = vm; self.id = id; self.done = done; self.cancel = cancel
        _f = State(initialValue: ManualRules.formFrom(m))
        _chart = State(initialValue: m.showOnWealthChart ?? true)
    }

    var body: some View {
        let exited = m.exitDate != nil
        ManualFormFrame(title: exited ? "Wealth chart settings" : "Edit values", vm: vm) {
            if exited { Banner(text: "This line is closed (\(m.exitDate ?? "")). Only notes, currency and the wealth chart setting can change.", color: RColors.warn) }
            if !exited {
                ManualKindFields(f: $f, p: "f_")
                ManualField(label: "Opened date", text: $f.openedDate, id: "f_opened", hint: "YYYY-MM-DD")
                ManualField(label: "Opening amount (GBP)", text: $f.openingValue, id: "f_opening", number: true)
                Muted("Save as")
                ManualChipRow(options: [("update", "New value"), ("exit", "Close line")], selected: mode, tagPrefix: "mode_") { mode = $0 }
                if mode == "update" {
                    ManualField(label: "Value as of (optional)", text: $updateDate, id: "f_update_date", hint: "YYYY-MM-DD, defaults to today")
                } else {
                    Muted("Closing records the exit and the wealth chart steps to zero after it.")
                    ManualField(label: "Exit date", text: $f.exitDate, id: "f_exit_date", hint: "YYYY-MM-DD")
                    ManualField(label: "Exit amount (GBP)", text: $f.exitValue, id: "f_exit_value", number: true)
                }
            }
            ManualField(label: "Currency", text: $f.currency, id: "f_currency")
            ManualField(label: "Notes (optional)", text: $f.notes, id: "f_notes")
            Toggle(isOn: $chart) { Muted("Show on Home “Wealth over time”") }.accessibilityIdentifier("f_chart").tint(RColors.accent)
            if m.chartEligible == false { Muted("This line does not qualify for the chart yet (needs an opening date over a year ago and at least 5 saved values).") }
            ManualSaveRow(vm: vm, label: "Save", onSave: {
                vm.editValues(id, ManualRules.nonListedEdit(ManualRules.NonListedEdit(form: f, exited: exited, showOnChart: chart, mode: mode, updateDate: updateDate), today: vm.today()), onDone: done)
            }, onCancel: cancel)
        }
    }
}

func manualHoldingActions(repo: Repository) -> HoldingActionsBuilder { { ctx in AnyView(ManualActionsView(repo: repo, context: ctx)) } }

// MARK: Add holding (More → Add holding)

/// Add a stock/ETF lot, property, cash savings or another asset. Pushed in the More NavigationStack.
struct AddHoldingScreen: View {
    let repo: Repository
    @StateObject private var vm: ManualViewModel
    @State private var kind = ManualKind.listed
    @State private var formKey = 0

    init(repo: Repository) {
        self.repo = repo
        _vm = StateObject(wrappedValue: ManualViewModel(repo: repo))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Muted("Saved to your account on the server. Cost and gain are only as accurate as what you enter.")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ManualKind.allCases, id: \.api) { k in
                            Chip(text: k.label, selected: kind == k) { kind = k; vm.clear(); vm.resetSearch() }.accessibilityIdentifier("add_kind_\(k.api)")
                        }
                    }
                }
                if let m = vm.ui.message { Banner(text: m, color: RColors.accent).accessibilityIdentifier("add_message") }
                if let e = vm.ui.error { Banner(text: e, color: RColors.loss).accessibilityIdentifier("form_error") }
                Group {
                    if kind == .listed { ManualAddListed(vm: vm, onSaved: saved) } else { ManualAddNonListed(kind: kind, vm: vm, onSaved: saved) }
                }.id("\(kind.api)-\(formKey)")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RColors.bg.ignoresSafeArea())
        .navigationTitle("Add holding").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("add_manual")
        .onAppear { vm.clear(); vm.resetSearch() }
        .onDisappear { vm.clear(); vm.resetSearch() }
    }

    private func saved() { formKey += 1; repo.notifyChanged() }
}

private struct ManualAddListed: View {
    @ObservedObject var vm: ManualViewModel
    let onSaved: () -> Void
    @State private var search = ""
    @State private var symbol = ""
    @State private var label = ""
    @State private var qty = ""
    @State private var broker = ""
    @State private var kind = "sipp"
    @State private var date = ""
    @State private var cost = ""

    var body: some View {
        ManualField(label: "Search company or ticker", text: Binding(get: { search }, set: { search = $0; vm.search($0) }), id: "f_search")
        ForEach(Array(vm.hits.prefix(8)), id: \.symbol) { h in
            Button {
                vm.pick(h) { symbol = $0 }; label = h.name ?? ""; search = ""
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) { Num(h.symbol, size: 13, bold: true); Muted(h.name ?? "") }
                    Spacer(minLength: 8)
                    Muted([h.exchange, h.currency].compactMap { $0 }.joined(separator: " · "))
                }.padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("hit_\(h.symbol)")
        }
        ManualField(label: "Symbol", text: $symbol, id: "f_symbol")
        if let p = vm.quote?.lastPrice {
            Muted("Last quote: \(Fmt.number(p)) \(vm.quote?.currency ?? "") (for information; not saved)").accessibilityIdentifier("quote_info")
        }
        ManualField(label: "Label (optional)", text: $label, id: "f_label")
        ManualField(label: "Quantity", text: $qty, id: "f_qty", number: true)
        ManualField(label: "Broker", text: $broker, id: "f_broker")
        Muted("Account type")
        ManualChipRow(options: ManualRules.listedCreateKinds, selected: kind, tagPrefix: "kind_") { kind = $0 }
        ManualField(label: "Purchase date", text: $date, id: "f_date", hint: "YYYY-MM-DD")
        ManualField(label: "Total cost (GBP)", text: $cost, id: "f_cost", number: true)
        ManualButton(title: vm.ui.busy ? "Saving…" : "Add holding", enabled: !vm.ui.busy, id: "form_save") {
            vm.create(ManualRules.listedCreate(symbol: symbol, label: label, qty: qty, broker: broker, kind: kind, purchaseDate: date, cost: cost, today: vm.today()), onDone: onSaved)
        }
    }
}

private struct ManualAddNonListed: View {
    let kind: ManualKind
    @ObservedObject var vm: ManualViewModel
    let onSaved: () -> Void
    @State private var f: ManualRules.NonListed

    init(kind: ManualKind, vm: ManualViewModel, onSaved: @escaping () -> Void) {
        self.kind = kind; self.vm = vm; self.onSaved = onSaved
        _f = State(initialValue: ManualRules.NonListed(kind: kind))
    }

    var body: some View {
        ManualKindFields(f: $f, p: "f_")
        ManualField(label: "Currency", text: $f.currency, id: "f_currency")
        ManualField(label: "Opened date", text: $f.openedDate, id: "f_opened", hint: "YYYY-MM-DD")
        ManualField(label: "Opening amount (GBP)", text: $f.openingValue, id: "f_opening", number: true)
        Muted("Already closed? Add both an exit date and amount, or leave both blank.")
        ManualField(label: "Exit date (optional)", text: $f.exitDate, id: "f_exit_date", hint: "YYYY-MM-DD")
        ManualField(label: "Exit amount (optional)", text: $f.exitValue, id: "f_exit_value", number: true)
        ManualField(label: "Notes (optional)", text: $f.notes, id: "f_notes")
        ManualButton(title: vm.ui.busy ? "Saving…" : "Add \(kind.label.lowercased())", enabled: !vm.ui.busy, id: "form_save") {
            vm.create(ManualRules.nonListedCreate(f, today: vm.today()), onDone: onSaved)
        }
    }
}
