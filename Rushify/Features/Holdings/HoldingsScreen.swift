import SwiftUI

private struct HoldingsDetailTarget: Identifiable {
    let id = UUID()
    let row: HoldingRow
    let rollup: HoldingsRollupLine?
    let primary: Bool
}

/// The Holdings screen (Android HoldingsScreen). Pushed inside the More tab's NavigationStack, so it does not wrap itself in one.
struct HoldingsScreen: View {
    let repo: Repository
    let holdingActions: HoldingActionsBuilder?
    let showTitle: Bool
    @ObservedObject private var events: DataEvents
    @StateObject private var dash: CachedLoader<Dashboard>
    @StateObject private var rollupsVm: CachedLoader<HoldingsRollups>
    @Environment(\.hideBalances) private var hide

    @State private var query = ""
    @State private var sort: HoldingsSort = .value
    @State private var exposure: HoldingsExposureFilter = .all
    @State private var showSold = false
    /// One account group open at a time keeps the page short (searching opens every match).
    @State private var expanded: String?
    @State private var openMulti: Set<String> = []
    @State private var selected: HoldingsDetailTarget?

    init(repo: Repository, session: SessionManager, holdingActions: HoldingActionsBuilder? = nil, showTitle: Bool = true) {
        self.repo = repo; self.holdingActions = holdingActions; self.showTitle = showTitle
        _events = ObservedObject(wrappedValue: repo.events)
        _dash = StateObject(wrappedValue: CachedLoader(read: { await repo.dashboardCached() }, fetch: { try await repo.dashboard() }))
        _rollupsVm = StateObject(wrappedValue: CachedLoader(read: { await repo.holdingsRollupsCached() }, fetch: { try await repo.holdingsRollups() }))
    }

    var body: some View {
        let d = dash.state.data?.value
        let ccy = d?.baseCurrency ?? "GBP"
        let rollups = rollupsVm.state.data?.value ?? HoldingsRollups()
        let soldCount = d?.rows.filter { HoldingsLogic.isManualListedSold($0) }.count ?? 0
        let groups = d.map { HoldingsGroups.build(rows: $0.rows, query: query, sort: sort, rollups: rollups, exposure: exposure, showSold: showSold) } ?? []
        let summaries = d.map { HoldingsAccountSummaries.build(rollups, $0.rows) } ?? []

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                header(d, soldCount)
                if !summaries.isEmpty { HoldingsAccountsSummaryCard(summaries: summaries, ccy: ccy) }
                if d == nil {
                    if let e = dash.state.error { ErrorState(message: e) { Task { await refreshAll() } } } else { Muted("Loading holdings…") }
                } else if groups.isEmpty {
                    Muted(query.holdingsTrimmed.isEmpty ? "No positions yet. Sync a broker from More → Sync, or add one from More → Add holding." : "No matches for \"\(query)\".")
                }
                ForEach(groups, id: \.key) { g in
                    let open = !query.holdingsTrimmed.isEmpty || g.key == expanded
                    RCard { HoldingsGroupHeader(group: g, exposure: exposure, ccy: ccy) }
                        .contentShape(Rectangle())
                        .onTapGesture { expanded = (g.key == expanded) ? nil : g.key }
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("group_\(g.key)")
                    if open {
                        HoldingsGroupBody(group: g, rollups: rollups, exposure: exposure, ccy: ccy, openMulti: openMulti,
                                          toggleMulti: { k in if openMulti.contains(k) { openMulti.remove(k) } else { openMulti.insert(k) } },
                                          onPick: { row, rollup, primary in selected = HoldingsDetailTarget(row: row, rollup: rollup, primary: primary) })
                    }
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier("holdings_list")
        .refreshable { await refreshAll() }
        .background(RColors.bg)
        .task { dash.load(); rollupsVm.load() }
        .onChange(of: events.version) { _, _ in Task { await refreshAll() } }
        .sheet(item: $selected) { t in
            HoldingsDetailSheet(target: t, ccy: ccy, actions: holdingActions)
        }
    }

    private func refreshAll() async {
        async let a: Void = dash.refresh()
        async let b: Void = rollupsVm.refresh()
        _ = await (a, b)
    }

    @ViewBuilder private func header(_ d: Dashboard?, _ soldCount: Int) -> some View {
        if showTitle { Text("Holdings").font(.r(24, .regular)).foregroundStyle(RColors.text).accessibilityIdentifier("holdings_title") }
        AsOfBar(asOf: dash.state.data?.fetchedAt, error: dash.state.error, hasData: d != nil, loading: dash.state.loading,
                label: d.map { "Data as of \(Fmt.stamp(iso: $0.asOf))" })
        if rollupsVm.state.loading && d != nil && rollupsVm.state.data == nil { Muted("Updating broker rollups and account totals…") }
        let incomplete = d?.manualBasisIncompleteCount ?? 0
        if incomplete > 0 {
            Banner(text: "\(incomplete) manual listed lot\(incomplete == 1 ? " is" : "s are") missing a purchase date or total GBP cost. Open each lot in Holdings and choose Edit lot so cost vs gain is correct.")
                .accessibilityIdentifier("incomplete_lots")
        }
        TextField("Search ticker, name or sector", text: $query)
            .textFieldStyle(.plain).font(.r(15)).foregroundStyle(RColors.text)
            .padding(10).background(RColors.variant, in: RoundedRectangle(cornerRadius: 10))
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier("holdings_search")
        HStack(spacing: 8) {
            ForEach(HoldingsSort.allCases, id: \.self) { s in Chip(text: s.label, selected: sort == s) { sort = s }.accessibilityIdentifier("holdings_sort_\(s.label)") }
        }
        Muted("Listed broker positions")
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HoldingsExposureFilter.allCases, id: \.self) { f in Chip(text: f.label, selected: exposure == f) { exposure = f }.accessibilityIdentifier("holdings_exposure_\(f.label)") }
            }
        }
        Muted(exposure.hint).accessibilityIdentifier("exposure_hint")
        if soldCount > 0 {
            Toggle(isOn: $showSold) { Muted("Show sold positions (\(soldCount) closed manual lot\(soldCount == 1 ? "" : "s"))") }
                .tint(RColors.accent).accessibilityIdentifier("show_sold")
        }
    }
}

// MARK: accounts summary (the web's "Broker accounts (local history)" table)

private struct HoldingsKV: View {
    let label: String, value: String
    var color: Color = RColors.text
    var body: some View { HStack { Muted(label); Spacer(minLength: 8); Num(value, color: color, size: 12) }.padding(.vertical, 1) }
}

private struct HoldingsAccountsSummaryCard: View {
    let summaries: [HoldingsAccountSummary]
    let ccy: String
    @Environment(\.hideBalances) private var hide
    @State private var open = false

    var body: some View {
        let totals = HoldingsAccountSummaries.totals(summaries)
        RCard {
            HStack(alignment: .top) {
                Text("Broker accounts (local history)").font(.r(16, .semibold)).foregroundStyle(RColors.text)
                Spacer(minLength: 8)
                Muted(open ? "▲" : "▼")
            }
            .contentShape(Rectangle())
            .onTapGesture { open.toggle() }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("accounts_summary")
            Muted(Fmt.plural(summaries.count, "account") + (totals.map { " · realised \(Fmt.signedMoney($0.realised, ccy, hide: hide)) · unrealised \(Fmt.signedMoney($0.unrealised, ccy, hide: hide))" } ?? ""))
            if open {
                Muted("Realised, unrealised, tax / FX / broker fees come from stored order fills. Dividend payouts are equity dividends only; interest on cash is reported separately; Payout is dividends plus interest.").padding(.top, 6)
                ForEach(Array(summaries.enumerated()), id: \.offset) { _, a in block(a).padding(.top, 10) }
                if let t = totals {
                    Text("Total (all accounts)").font(.r(15, .semibold)).foregroundStyle(RColors.accent).padding(.top, 12).accessibilityIdentifier("accounts_total")
                    HoldingsKV(label: "Investments", value: Fmt.money(t.investments, ccy, hide: hide))
                    HoldingsKV(label: "Realised", value: Fmt.signedMoney(t.realised, ccy, hide: hide), color: RColors.pnl(t.realised))
                    HoldingsKV(label: "Unrealised", value: Fmt.signedMoney(t.unrealised, ccy, hide: hide), color: RColors.pnl(t.unrealised))
                    HoldingsKV(label: "Tax", value: Fmt.money(t.tax, ccy, hide: hide))
                    HoldingsKV(label: "FX fees", value: Fmt.money(t.fxFees, ccy, hide: hide))
                    HoldingsKV(label: "Broker cost", value: Fmt.money(t.brokerCost, ccy, hide: hide))
                    HoldingsKV(label: "Interest on cash", value: Fmt.money(t.interest, ccy, hide: hide))
                    HoldingsKV(label: "Dividend payouts", value: Fmt.money(t.dividends, ccy, hide: hide))
                    HoldingsKV(label: "Payout", value: Fmt.money(t.payout, ccy, hide: hide))
                }
            }
        }
    }

    @ViewBuilder private func block(_ a: HoldingsAccountSummary) -> some View {
        Text(a.label).font(.r(14, .medium)).foregroundStyle(RColors.text)
        Muted(a.source)
        if a.source == "monzo" {
            HoldingsKV(label: "Balance", value: Fmt.money(a.monzoTotal, ccy, hide: hide)); Muted("Bank balance: no trades or payouts")
        } else if let x = a.account {
            let cashIsa = x.accountRef.holdingsTrimmed.lowercased().hasSuffix(":cash_isa")
            HoldingsKV(label: cashIsa ? "Total deposits (principal)" : "Investments", value: Fmt.money(x.listedInvestmentsMvBaseSum, ccy, hide: hide))
            HoldingsKV(label: "Realised", value: Fmt.signedMoney(x.realisedGainBaseSum, ccy, hide: hide), color: RColors.pnl(x.realisedGainBaseSum))
            HoldingsKV(label: "Unrealised", value: Fmt.signedMoney(x.unrealisedPnlBaseSum, ccy, hide: hide), color: RColors.pnl(x.unrealisedPnlBaseSum))
            HoldingsKV(label: "Tax", value: Fmt.money(x.fillTaxBaseSum, ccy, hide: hide)); HoldingsKV(label: "FX fees", value: Fmt.money(x.fillFxFeesBaseSum, ccy, hide: hide))
            HoldingsKV(label: "Broker cost", value: Fmt.money(x.fillBrokerFeesBaseSum, ccy, hide: hide))
            HoldingsKV(label: "Interest on cash", value: Fmt.money(x.interestOnCashBaseSum, ccy, hide: hide))
            HoldingsKV(label: "Dividend payouts", value: Fmt.money(x.dividendPayoutBaseSum, ccy, hide: hide))
            HoldingsKV(label: "Payout", value: Fmt.money(x.combinedBrokerPayoutBaseSum, ccy, hide: hide))
        }
    }
}

// MARK: group header + body

private struct HoldingsHeaderMetric: View {
    let label: String, value: Decimal?, ccy: String
    var signed = false
    @Environment(\.hideBalances) private var hide
    var body: some View {
        HStack(spacing: 0) {
            Muted("\(label): ")
            Num(signed ? Fmt.signedMoney(value, ccy, hide: hide) : Fmt.money(value, ccy, hide: hide), color: signed ? RColors.pnl(value) : RColors.text, size: 12)
        }
    }
}

private struct HoldingsGroupHeader: View {
    let group: HoldingsGroup
    let exposure: HoldingsExposureFilter
    let ccy: String
    @Environment(\.hideBalances) private var hide

    private var line1: String {
        let g = group, nClosed = g.closed.count
        if g.kind == .monzo { return "\(Fmt.plural(g.rows.count, "balance")) · total value \(Fmt.money(g.totalValue, ccy, hide: hide))" }
        if g.brokerLike || g.kind == .manualListed {
            if exposure == .closed {
                let open = g.listedRows.isEmpty ? "No open broker lines" : Fmt.plural(g.listedRows.count, "open line")
                return open + (nClosed > 0 ? " · \(Fmt.plural(nClosed, "closed instrument")) (order history)" : "")
            }
            var s = Fmt.plural(g.positionCount, "position")
            if exposure == .all && g.hasCash { s += " · cash \(Fmt.money(g.cashValue, ccy, hide: hide))" }
            s += " · total qty \(Fmt.quantity(g.totalQty)) · total value \(Fmt.money(g.totalValue, ccy, hide: hide))"
            return s
        }
        return "\(Fmt.plural(g.rows.count, "line")) · total value \(Fmt.money(g.totalValue, ccy, hide: hide))"
    }

    var body: some View {
        let g = group
        HStack {
            Text(g.name).font(.r(16, .semibold)).foregroundStyle(RColors.text)
            Spacer(minLength: 8)
            if let b = g.badge { Muted(b.uppercased()) }
        }
        Muted(line1)
        let acc = g.account
        if g.kind == .t212 || g.kind == .snaptrade {
            let payouts = acc?.combinedBrokerPayoutBaseSum ?? acc?.dividendPayoutBaseSum
            HoldingsHeaderMetric(label: "Realised", value: acc?.realisedGainBaseSum, ccy: ccy, signed: true)
            HoldingsHeaderMetric(label: "Unrealised", value: g.totalPnl, ccy: ccy, signed: true)
            HoldingsHeaderMetric(label: "Cash payouts", value: payouts, ccy: ccy)
            Muted("XIRR: \(Fmt.percentFromFraction(acc?.xirrAnnual))").accessibilityIdentifier("xirr_\(g.key)")
        } else if g.kind == .csv {
            HoldingsHeaderMetric(label: "Realised", value: acc?.realisedGainBaseSum, ccy: ccy, signed: true)
            HoldingsHeaderMetric(label: "Unrealised", value: g.totalPnl, ccy: ccy, signed: true)
        } else if g.kind == .manualListed {
            HoldingsHeaderMetric(label: "Unrealised", value: g.totalPnl, ccy: ccy, signed: true)
        }
    }
}

private func holdingsLotLabel(_ r: HoldingRow, _ kind: HoldingsGroupKind, _ i: Int) -> String {
    if kind == .manualListed { return "Lot · \(r.purchaseDate ?? "no date")\(r.manualHoldingId.map { " · id \($0)" } ?? "")" }
    return "Line \(i + 1) · \(r.currency ?? "")"
}

private struct HoldingsGroupBody: View {
    let group: HoldingsGroup
    let rollups: HoldingsRollups
    let exposure: HoldingsExposureFilter
    let ccy: String
    let openMulti: Set<String>
    let toggleMulti: (String) -> Void
    let onPick: (HoldingRow, HoldingsRollupLine?, Bool) -> Void
    @Environment(\.hideBalances) private var hide

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if group.kind == .monzo { monzo } else { standard }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var monzo: some View {
        ForEach(HoldingsLogic.monzoSections(group.rows), id: \.title) { section in
            HStack {
                Text(section.title).font(.r(13, .semibold)).foregroundStyle(RColors.accent)
                Spacer()
                Num(Fmt.money(section.rows.reduce(Decimal(0)) { $0 + ($1.marketValueBase ?? 0) }, ccy, hide: hide), size: 12)
            }.padding(.top, 8)
            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, r in HoldingsMonzoRow(row: r, ccy: ccy) { onPick(r, nil, true) } }
        }
    }

    @ViewBuilder private var standard: some View {
        let items = HoldingsGroups.items(group, rollups, exposure)
        let primary = HoldingsGroups.primaryMetricRows(HoldingsGroups.displayOrder(items), rollups.lines, exposure)
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            switch item {
            case .single(let r):
                HoldingsRowLine(row: r, rollups: rollups, exposure: exposure, ccy: ccy, primary: primary, lotLabel: nil, onPick: onPick)
            case .multi(let ticker, let rows):
                let key = group.key + "|" + ticker
                let isOpen = openMulti.contains(key)
                HoldingsMultiHeader(ticker: ticker, rows: rows, kind: group.kind, ccy: ccy, open: isOpen) { toggleMulti(key) }
                if isOpen {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        HoldingsRowLine(row: r, rollups: rollups, exposure: exposure, ccy: ccy, primary: primary, lotLabel: holdingsLotLabel(r, group.kind, i), onPick: onPick)
                            .padding(.leading, 12)
                    }
                }
            }
        }
        if group.brokerLike {
            if !group.closed.isEmpty {
                Text("Closed (order history, no open quantity)").font(.r(12)).foregroundStyle(RColors.muted).padding(.top, 10)
                ForEach(Array(group.closed.enumerated()), id: \.offset) { _, l in HoldingsClosedCard(line: l, ccy: ccy) }
            } else if exposure == .closed {
                Muted("No closed instruments in order history for this account.").padding(.top, 8)
            }
        }
    }
}

private struct HoldingsMultiHeader: View {
    let ticker: String, rows: [HoldingRow], kind: HoldingsGroupKind, ccy: String, open: Bool
    let onTap: () -> Void
    @Environment(\.hideBalances) private var hide
    private static func noun(_ kind: HoldingsGroupKind) -> String {
        switch kind {
        case .manualListed: return "lots"
        case .snaptrade: return "SnapTrade lines"
        case .csv: return "CSV import lines"
        case .t212: return "Trading 212 lines"
        default: return "lines"
        }
    }
    var body: some View {
        let noun = Self.noun(kind)
        let value = rows.reduce(Decimal(0)) { $0 + ($1.marketValueBase ?? 0) }
        let pnls = rows.compactMap { $0.pnlStockBase }
        let pnl: Decimal? = pnls.isEmpty ? nil : pnls.reduce(0, +)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack { Num(ticker, bold: true); Spacer(minLength: 8); Num(Fmt.money(value, ccy, hide: hide)) }
                HStack {
                    Muted("\(rows.count) \(noun) · total qty \(Fmt.quantity(rows.reduce(Decimal(0)) { $0 + ($1.quantity ?? 0) })) \(open ? "▲" : "▼")")
                    Spacer(minLength: 8)
                    Num(Fmt.signedMoney(pnl, ccy, hide: hide), color: RColors.pnl(pnl), size: 12)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("multi_\(ticker)")
    }
}

private struct HoldingsRowLine: View {
    let row: HoldingRow, rollups: HoldingsRollups, exposure: HoldingsExposureFilter, ccy: String
    let primary: [String: String]
    let lotLabel: String?
    let onPick: (HoldingRow, HoldingsRollupLine?, Bool) -> Void
    @Environment(\.hideBalances) private var hide
    var body: some View {
        let rollup = HoldingsLogic.findRollupForRow(row, rollups.lines, exposure)
        let isPrimary = rollup == nil || primary[HoldingsLogic.rollupIdentityKey(rollup)] == HoldingsLogic.rowSlotId(row)
        let sold = HoldingsLogic.isManualListedSold(row)
        let tags = [sold ? "Sold" : nil, rollup.map { HoldingsLogic.rollupExposureLabel($0.exposure) }].compactMap { $0 }
        let ticker = HoldingsLogic.displayTicker(row, rollup)
        Button { onPick(row, rollup, isPrimary) } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Num(ticker, bold: true)
                    Muted(lotLabel ?? row.instrumentName ?? row.sector ?? "")
                    if !tags.isEmpty { Text(tags.joined(separator: " · ")).font(.r(10)).foregroundStyle(sold ? RColors.warn : RColors.muted) }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Num(Fmt.money(row.marketValueBase, ccy, hide: hide))
                    Num(Fmt.signedMoney(row.pnlStockBase, ccy, hide: hide), color: RColors.pnl(row.pnlStockBase), size: 12)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("holding_row_\(ticker)")
    }
}

private struct HoldingsMonzoRow: View {
    let row: HoldingRow, ccy: String
    let onTap: () -> Void
    @Environment(\.hideBalances) private var hide
    var body: some View {
        let badge = HoldingsLogic.monzoKindBadge(row.accountKind)
        Button(action: onTap) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(HoldingsLogic.monzoRowName(row)).font(.r(14)).foregroundStyle(RColors.text)
                    if let badge { Muted(badge) }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Num(Fmt.money(row.marketValueBase, ccy, hide: hide))
                    if let c = row.currency, c != ccy, let q = row.quantity { Muted("(\(c) \(Fmt.number(q)))") }
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 5).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("monzo_row_\(row.ticker)")
    }
}

private struct HoldingsClosedCard: View {
    let line: HoldingsRollupLine, ccy: String
    @Environment(\.hideBalances) private var hide
    var body: some View {
        let l = line
        let sym = HoldingsLogic.rollupDisplaySymbol(l)
        VStack(alignment: .leading, spacing: 2) {
            HStack { Num(sym, bold: true); Spacer(); Muted("Closed (history)") }
            if let n = l.instrumentName { Muted(n) }
            if let bt = l.brokerTicker, !bt.holdingsTrimmed.isEmpty, bt.caseInsensitiveCompare(sym) != .orderedSame,
               HoldingsLogic.stripT212VenueSuffix(bt).uppercased() != sym.uppercased() { Muted(bt) }
            HoldingsKV(label: "P/L (FIFO realised)", value: Fmt.signedMoney(l.fifoRealisedBase, ccy, hide: hide), color: RColors.pnl(l.fifoRealisedBase))
            HoldingsKV(label: "Bought (qty)", value: Fmt.quantity(l.buyFillQty)); HoldingsKV(label: "Sold (qty)", value: Fmt.quantity(l.sellFillQty))
            HoldingsKV(label: "Fill rows", value: String(l.fillRowCount))
            HoldingsKV(label: "Tax", value: Fmt.money(l.fillTaxBaseSum ?? 0, ccy, hide: hide))
            HoldingsKV(label: "FX fees", value: Fmt.money(l.fillFxFeesBaseSum ?? 0, ccy, hide: hide))
            HoldingsKV(label: "Broker fees", value: Fmt.money(l.fillBrokerFeesBaseSum ?? 0, ccy, hide: hide))
            HoldingsDividendsBlock(line: l, base: ccy)
            Muted("Realised uses FIFO on stored fills; fees are the sums on those fills.")
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("closed_\(sym)")
    }
}

/// Broker-reported cash dividends (or a market-data estimate for manual lots), like the web's dividends block.
struct HoldingsDividendsBlock: View {
    let line: HoldingsRollupLine
    let base: String
    @Environment(\.hideBalances) private var hide
    var body: some View {
        let n = line.dividendPayoutCount
        if n > 0 {
            let rows = line.dividendsByCurrency
            let baseSum = line.dividendPayoutBaseSum
            let redundant = rows.count == 1 && baseSum != nil
                && rows[0].currency.holdingsTrimmed.caseInsensitiveCompare(base.holdingsTrimmed) == .orderedSame
                && rows[0].amount != nil && rows[0].amount! == baseSum!
            VStack(alignment: .leading, spacing: 2) {
                Muted(line.source == "manual" ? "Estimated dividends (market data)" : "Broker cash dividends")
                Num("\(n) payouts", size: 12)
                if !redundant { Muted(rows.isEmpty ? "—" : rows.map { "\($0.currency) \(Fmt.number($0.amount))" }.joined(separator: " · ")) }
                Muted("Total (\(base)): \(baseSum != nil ? Fmt.money(baseSum, base, hide: hide) : "— (could not convert all payouts: missing FX)")")
            }
            .padding(.top, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dividends_block")
        }
    }
}

// MARK: detail sheet

private struct HoldingsDetailSheet: View {
    let target: HoldingsDetailTarget
    let ccy: String
    let actions: HoldingActionsBuilder?
    var body: some View {
        let ticker = HoldingsLogic.displayTicker(target.row, target.rollup)
        HoldingsDetailView(row: target.row, ccy: ccy, rollup: target.rollup, primary: target.primary) {
            if let actions { actions(HoldingContext(row: target.row, displayTicker: ticker, isPrimaryLot: target.primary)) }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(RColors.surface)
    }
}

/// Everything Android's HoldingDetail shows for one line. `actions` renders at the bottom (the shell's edit/delete buttons).
struct HoldingsDetailView<Actions: View>: View {
    let row: HoldingRow
    let ccy: String
    var rollup: HoldingsRollupLine?
    var primary = true
    @ViewBuilder var actions: () -> Actions
    @Environment(\.hideBalances) private var hide

    private func detail(_ label: String, _ value: String, _ color: Color = RColors.text) -> some View {
        HStack(alignment: .firstTextBaseline) { Muted(label); Spacer(minLength: 12); Num(value, color: color, size: 14).multilineTextAlignment(.trailing) }
    }

    /// A titled group of rows on its own raised surface.
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.r(11, .semibold)).tracking(0.8).foregroundStyle(RColors.muted).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(RColors.variant.opacity(0.55), in: RoundedRectangle(cornerRadius: RRadius.card))
        }
    }

    var body: some View {
        let r = row
        let sold = HoldingsLogic.isManualListedSold(r)
        let tags = [sold ? "Sold" : nil, rollup.map { HoldingsLogic.rollupExposureLabel($0.exposure) }].compactMap { $0 }
        let hasFundamentals = [r.dividendYield, r.roe, r.debtToEquity, r.profitMargin, r.revenue].contains { $0 != nil }
        let hasValuation = [r.peRatio, r.pbRatio, r.pegRatio, r.priceToSales].contains { $0 != nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hero: what it is, what it is worth, and how it is doing
                VStack(alignment: .leading, spacing: 6) {
                    Text(HoldingsLogic.displayTicker(r, rollup)).font(.r(26, .bold)).foregroundStyle(RColors.text)
                    Muted([r.instrumentName, r.brokerLabel].compactMap { $0 }.joined(separator: " · "))
                    if !tags.isEmpty { Text(tags.joined(separator: " · ")).font(.r(12, .medium)).foregroundStyle(sold ? RColors.warn : RColors.accent) }
                    HStack(alignment: .firstTextBaseline) {
                        Num(Fmt.money(r.marketValueBase, ccy, hide: hide), size: 30, bold: true)
                        Spacer(minLength: 8)
                        if r.pnlStockBase != nil {
                            Text(Fmt.signedMoney(r.pnlStockBase, ccy, hide: hide)).font(.r(14, .semibold)).monospacedDigit()
                                .foregroundStyle(RColors.pnl(r.pnlStockBase))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(RColors.pnl(r.pnlStockBase).opacity(0.14), in: Capsule())
                        }
                    }.padding(.top, 4)
                }
                if sold { Banner(text: "Fully exited\(r.soldOutAt.map { " on \($0)" } ?? ""). Kept for your records.") }

                group("Position") {
                    detail("Sector", r.sector ?? Fmt.dash)
                    detail("Quantity", Fmt.quantity(r.quantity))
                    detail("Currency", r.currency ?? Fmt.dash)
                    detail("Average price", Fmt.money(r.avgPrice, r.currency, hide: hide))
                    detail("Current price", Fmt.money(r.currentPrice, r.currency, hide: hide))
                    detail("Market value", Fmt.money(r.marketValueBase, ccy, hide: hide))
                    detail("Cost", Fmt.money(r.costBase, ccy, hide: hide))
                    detail("P/L (price)", Fmt.signedMoney(r.pnlStockBase, ccy, hide: hide), RColors.pnl(r.pnlStockBase))
                    if let p = r.purchaseDate { detail("Purchase date", p) }
                    if r.source == "manual" && HoldingsLogic.isListedAssetKind(r.assetKind) {
                        let isSet = r.purchaseDate != nil && r.costBaseGbp != nil
                        if isSet { detail("Purchase & cost (GBP)", "\(r.purchaseDate!) · \(Fmt.money(r.costBaseGbp, "GBP", hide: hide))") }
                        else { Text("Purchase & cost (GBP): not set. Use Edit lot below.").font(.r(12)).foregroundStyle(RColors.warn).accessibilityIdentifier("basis_not_set") }
                        if isSet { detail("FX effect (approx.)", r.pnlCurrencyEffect != nil ? Fmt.signedMoney(r.pnlCurrencyEffect, ccy, hide: hide) : Fmt.dash, RColors.pnl(r.pnlCurrencyEffect)) }
                    }
                }

                if let ru = rollup {
                    group("Fees & dividends") {
                        if primary {
                            detail("Tax", Fmt.money(ru.fillTaxBaseSum ?? 0, ccy, hide: hide))
                            detail("FX fees", Fmt.money(ru.fillFxFeesBaseSum ?? 0, ccy, hide: hide))
                            detail("Broker fees", Fmt.money(ru.fillBrokerFeesBaseSum ?? 0, ccy, hide: hide))
                            HoldingsDividendsBlock(line: ru, base: ccy)
                        } else { Muted("Fees and dividends for this symbol are shown on its first line.") }
                    }
                }

                if hasValuation {
                    group("Valuation") {
                        detail("P/E", Fmt.number(r.peRatio)); detail("P/B", Fmt.number(r.pbRatio))
                        detail("PEG", Fmt.number(r.pegRatio)); detail("P/S", Fmt.number(r.priceToSales))
                    }
                }
                if hasFundamentals {
                    group("Quality & income") {
                        detail("Dividend yield", Fmt.percentFromFraction(r.dividendYield)); detail("ROE", Fmt.percentFromFraction(r.roe))
                        detail("Debt / equity", Fmt.number(r.debtToEquity)); detail("Profit margin", Fmt.percent(r.profitMargin))
                        detail("Revenue", Fmt.abbreviate(r.revenue))
                    }
                } else if !hasValuation {
                    Muted("No fundamentals data for this holding.")
                }
                Muted("Prices are end-of-day / cached, not live.")
                actions()
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("holding_detail")
    }
}
