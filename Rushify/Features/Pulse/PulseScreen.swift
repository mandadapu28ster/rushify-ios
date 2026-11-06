import SwiftUI

/// The Pulse tab: Radar, News and Watchlists behind three chips.
struct PulseScreen: View {
    private let repo: Repository
    @StateObject private var radar: PulseRadarModel
    @StateObject private var news: PulseNewsModel
    @StateObject private var watch: PulseWatchlistsModel
    @State private var tab = 0

    init(repo: Repository, session: SessionManager) {
        self.repo = repo
        _radar = StateObject(wrappedValue: PulseRadarModel(repo: repo))
        _news = StateObject(wrappedValue: PulseNewsModel(repo: repo))
        _watch = StateObject(wrappedValue: PulseWatchlistsModel(repo: repo))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Muted("Market news, watchlists and radar.")
                RSegmented(titles: ["Radar", "News", "Watchlists"], selection: $tab, idPrefix: "pulse_tab").padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
            Group {
                switch tab {
                case 0: PulseRadarTab(model: radar)
                case 1: PulseNewsTab(model: news)
                default: PulseWatchlistTab(model: watch)
                }
            }
            .transition(.opacity).id(tab)
        }
        .animation(RMotion.fade, value: tab)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RColors.bg)
    }
}

// MARK: - Radar

private struct PulseRadarTab: View {
    @ObservedObject var model: PulseRadarModel
    @Environment(\.hideBalances) private var hide
    @State private var openBucket: String?

    var body: some View {
        let s = model.state
        let r = s.data?.value
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AsOfBar(asOf: s.data?.fetchedAt, error: s.error, hasData: r != nil, loading: s.loading, label: nil)
                if let r { content(r) }
                else if let e = s.error { ErrorState(message: e) { Task { await model.refresh() } } }
                else { Muted("Loading portfolio radar…") }
            }
            .padding(16)
        }
        .refreshable { await model.refresh() }
        .task { model.load() }
    }

    @ViewBuilder private func content(_ r: PulseRadar) -> some View {
        if r.accounts.count > 1 || r.scopeKey != "overall" {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(r.accounts.enumerated()), id: \.offset) { _, a in
                        Chip(text: "\(a.label) · \(Fmt.plural(a.positionCount, "holding"))", selected: a.key == r.scopeKey) { model.select(a.key) }
                            .accessibilityIdentifier("scope_\(a.key)")
                    }
                }
            }
        }
        if let m = r.message { Banner(text: m) }
        if r.positionCount > 0 {
            RCard {
                if let h = r.headline { Text(h).font(.subheadline.weight(.semibold)).foregroundStyle(RColors.text) }
                if let sm = r.summary { Muted(sm).padding(.top, 4) }
                if r.scoredMvPct < 100 || r.indexFundMvPct > 0 || r.notCoveredMvPct > 0 {
                    Muted("MV coverage: \(r.scoredMvPct)% scored equities" + (r.indexFundMvPct > 0 ? " · \(r.indexFundMvPct)% index/funds" : "") + (r.notCoveredMvPct > 0 ? " · \(r.notCoveredMvPct)% not scored" : ""))
                        .padding(.top, 6).accessibilityIdentifier("mv_coverage")
                }
            }
            RCard {
                SectionTitle("Rewards")
                if r.rewards.isEmpty { Muted("No standout positives in this scope.") }
                else { ForEach(Array(r.rewards.enumerated()), id: \.offset) { _, n in Text("★ " + n.text).font(.footnote).foregroundStyle(RColors.gain).padding(.vertical, 3) } }
            }
            RCard {
                SectionTitle("Risk checks")
                if r.risks.isEmpty { Muted("No major risk flags from fundamentals rules.") }
                else { ForEach(Array(r.risks.enumerated()), id: \.offset) { _, n in Text("! " + n.text).font(.footnote).foregroundStyle(RColors.warn).padding(.vertical, 3) } }
            }
            if !r.dimensions.isEmpty { axesCard(r) }
            healthCard(r)
            Muted("Scores are heuristic quality tilts (not analyst buy/sell calls). Value is sector-relative where possible; health uses leverage, liquidity and FCF yield; index funds use a neutral model profile. Refresh Home after a market-data sync for the latest fundamentals.")
                .accessibilityIdentifier("radar_disclaimer")
        }
    }

    private func axesCard(_ r: PulseRadar) -> some View {
        RCard {
            SectionTitle("Five fundamentals axes")
            Muted("Portfolio-weighted. The dashed outline is the benchmark (100 on every axis).")
            HStack { Spacer(); PulseRadarChart(labels: r.dimensions.map(\.label), scores: r.dimensions.map(\.score)); Spacer() }
            ForEach(Array(r.dimensions.enumerated()), id: \.offset) { _, d in
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(d.label).font(.footnote).foregroundStyle(RColors.text); Spacer(); Num("\(d.score)", color: PulseRadarColors.score(d.score), size: 13, bold: true) }
                    PulseBar(fraction: Double(d.coveragePct) / 100, color: RColors.muted.opacity(0.6))
                    Muted("\(d.coveragePct)% of holdings with data")
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dimension_\(d.key)")
            }
            Muted("\(r.coveredPositionCount) of \(r.positionCount) positions with enough fundamentals" + (r.listedMvBase.map { " · \(Fmt.money($0, r.baseCurrency, hide: hide, scale: 0)) MV" } ?? "")).padding(.top, 6)
            Muted("Larger shape = stronger fundamentals. Colour reflects overall quality.")
        }
    }

    private func healthCard(_ r: PulseRadar) -> some View {
        let maxScore = r.healthMax ?? 5
        return RCard {
            SectionTitle("How healthy is this portfolio?")
            if let h = r.healthScore {
                HStack { Spacer(); PulseHealthGauge(score: h, maxScore: maxScore).accessibilityIdentifier("health_gauge"); Spacer() }
            }
            Muted("Portfolio health, 1 to \(NSDecimalNumber(decimal: maxScore).intValue)").frame(maxWidth: .infinity).multilineTextAlignment(.center)
            Spacer().frame(height: 6)
            ForEach(Array(r.ratingBuckets.enumerated()), id: \.offset) { _, b in
                let open = openBucket == b.key
                Button { if b.stockCount > 0 { openBucket = open ? nil : b.key } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Circle().fill(PulseRadarColors.bucket(b.key)).frame(width: 10, height: 10)
                            Text(b.label).font(.footnote).foregroundStyle(RColors.text).frame(maxWidth: .infinity, alignment: .leading)
                            Muted("\(b.mvPct)% MV · \(Fmt.plural(b.stockCount, "holding"))" + (b.stockCount > 0 ? (open ? "  ▾" : "  ▸") : ""))
                        }
                        if open { Muted(b.tickers.joined(separator: ", ")).padding(.leading, 18).padding(.top, 2) }
                    }
                    .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(b.stockCount <= 0)
                .accessibilityIdentifier("bucket_\(b.key)")
            }
        }
    }
}

// MARK: - News

private struct PulseNewsTab: View {
    @ObservedObject var model: PulseNewsModel
    @Environment(\.openURL) private var openURL
    @State private var open = Set<String>()
    @State private var filter: String?

    var body: some View {
        let s = model.state
        let n = s.data?.value
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Portfolio news").font(.subheadline.weight(.semibold)).foregroundStyle(RColors.text)
                        Muted("Holdings plus watchlist symbols with Fetch news on, grouped by company.")
                    }
                    Spacer(minLength: 8)
                    Chip(text: s.loading ? "Refreshing…" : "Refresh") { Task { await model.forceRefresh() } }.accessibilityIdentifier("news_refresh")
                }
                AsOfBar(asOf: s.data?.fetchedAt, error: s.error, hasData: n != nil, loading: s.loading,
                        label: n.map { "Updated \(Fmt.stamp(iso: $0.lastSyncedAt))" + ($0.stale ? " · tap Refresh for latest" : "") })
                if let n { content(n) }
                else if let e = s.error { ErrorState(message: e) { Task { await model.refresh() } } }
                else { Muted("Loading portfolio news…") }
            }
            .padding(16)
        }
        .refreshable { await model.forceRefresh() }
        .task { model.load() }
    }

    @ViewBuilder private func content(_ n: PulseNews) -> some View {
        if let m = n.message { Banner(text: m) }
        if n.cachedOnly { Muted("Showing cached headlines only (live fetch disabled).") }
        let groups = n.groups.filter { !$0.items.isEmpty }
        let total = groups.reduce(0) { $0 + $1.items.count }
        if total == 0 {
            Muted(PulseNewsView.emptyText(symbols: n.symbols)).accessibilityIdentifier("news_empty")
        } else {
            let active = groups.contains { $0.key == filter } ? filter : nil
            if groups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(text: "All (\(total))", selected: active == nil) { filter = nil }.accessibilityIdentifier("news_filter_all")
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                            Chip(text: "\(g.label) (\(g.items.count))", selected: active == g.key) { filter = g.key }.accessibilityIdentifier("news_filter_\(g.key)")
                        }
                    }
                }
            }
            let shown = active == nil ? groups : groups.filter { $0.key == active }
            ForEach(Array(shown.enumerated()), id: \.offset) { idx, g in
                let isOpen = PulseNewsView.isOpen(key: g.key, index: idx, open: open, filter: active)
                RCard {
                    Button { if open.contains(g.key) { open.remove(g.key) } else { open.insert(g.key) } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.label).font(.subheadline.weight(.semibold)).foregroundStyle(RColors.text)
                                    Muted(g.symbol ?? "Market-wide")
                                }
                                Spacer(minLength: 8)
                                Muted("\(g.items.count) \(isOpen ? "▲" : "▼")")
                            }
                            if !isOpen, let first = g.items.first { Muted(first.title).padding(.top, 4) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("news_group_\(g.key)")
                    if isOpen { ForEach(Array(g.items.enumerated()), id: \.offset) { _, item in headline(item) } }
                }
            }
        }
    }

    private func headline(_ it: PulseNewsItem) -> some View {
        let safe = PulseSafeUrl.httpOrNull(it.url)   // third-party feed data: only http(s) is ever opened
        let meta = [pulseSourceLabel(it.source), it.publisher, Optional(Fmt.stamp(iso: it.publishedAt)).flatMap { $0 == Fmt.dash ? nil : $0 }]
            .compactMap { $0 }.joined(separator: " · ")
        return Button { if let safe { openURL(safe) } } label: {
            VStack(alignment: .leading, spacing: 2) {
                Muted(meta)
                Text(PulseNewsText.plain(it.title)).font(.footnote).foregroundStyle(RColors.text).multilineTextAlignment(.leading)
                if let sm = PulseNewsText.summary(it.title, it.summary, it.publisher) {
                    Text(sm).font(.caption).foregroundStyle(RColors.muted).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(safe == nil)
        .accessibilityIdentifier("news_item_\(it.id)")
    }
}

/// Pure rules of the news list, shared with tests.
enum PulseNewsView {
    static func emptyText(symbols: [String]) -> String {
        if symbols.isEmpty { return "No symbols to fetch yet. Add holdings, or add watchlist symbols with Fetch news on, then tap Refresh." }
        return "No headlines in the current window for \(symbols.prefix(6).joined(separator: ", "))\(symbols.count > 6 ? " (+\(symbols.count - 6) more)" : ""). Turn on Fetch news for watchlist symbols or tap Refresh."
    }
    /// A company card is open when tapped open, when filtered to one company, or (nothing opened yet) when it is the first.
    static func isOpen(key: String, index: Int, open: Set<String>, filter: String?) -> Bool {
        open.contains(key) || filter != nil || (filter == nil && index == 0 && open.isEmpty)
    }
}

// MARK: - Watchlists

private struct PulseWatchlistTab: View {
    @ObservedObject var model: PulseWatchlistsModel
    @State private var newName = ""
    @State private var open = Set<Int>()
    @State private var adding: Int?
    @State private var fetchNewsOnAdd = true
    @State private var confirmDelete: PulseWatchlist?

    var body: some View {
        let s = model.state, r = model.refreshUi, e = model.edit
        let w = s.data?.value
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Watchlists").font(.subheadline.weight(.semibold)).foregroundStyle(RColors.text)
                Muted("Pull down to fetch the latest quotes and fundamentals. Tick News to include a symbol in Pulse → News.")
                AsOfBar(asOf: s.data?.fetchedAt, error: s.error, hasData: w != nil, loading: s.loading,
                        label: s.data.map { "Updated \(Fmt.stamp($0.fetchedAt)) · prices are end-of-day/cached" })
                if let m = r.message { Banner(text: m, color: r.failed ? RColors.loss : RColors.accent).accessibilityIdentifier("watch_refresh_message") }
                if let m = e.message { Banner(text: m, color: RColors.accent).accessibilityIdentifier("watch_edit_message") }
                if let m = e.error { Banner(text: m, color: RColors.loss).accessibilityIdentifier("watch_edit_error") }
                if let w { content(w, busy: e.busy) }
                else if let err = s.error { ErrorState(message: err) { Task { await model.refresh() } } }
                else { Muted("Loading watchlists…") }
            }
            .padding(16)
        }
        .refreshable { await model.forceRefresh() }
        .task { model.load() }
        .task(id: e.message) {
            guard let m = e.message else { return }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled, model.edit.message == m { model.clearEditMessage() }
        }
        .alert("Delete watchlist?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), presenting: confirmDelete) { l in
            Button("Delete", role: .destructive) { confirmDelete = nil; Task { await model.deleteList(l.id) } }.accessibilityIdentifier("watch_delete_ok")
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: { l in Text("Delete \"\(l.name)\" and all its symbols? This cannot be undone.") }
    }

    @ViewBuilder private func content(_ w: PulseWatchlists, busy: Bool) -> some View {
        let capped = PulseWatchlistRules.atListCap(w)
        HStack(spacing: 8) {
            TextField("", text: Binding(get: { newName }, set: { if $0.count <= PulseWatchlistRules.nameMax { newName = $0 } }),
                      prompt: Text(capped ? "Maximum lists reached" : "New watchlist name").foregroundColor(RColors.muted))
                .pulseField().disabled(capped || busy).accessibilityIdentifier("watch_new_name")
                .accessibilityLabel(capped ? "Maximum lists reached" : "New watchlist name")
            Button("Create") { let n = newName; newName = ""; Task { await model.createList(n) } }
                .buttonStyle(.borderedProminent).tint(RColors.accent)
                .disabled(!PulseWatchlistRules.canCreate(w, newName) || busy).accessibilityIdentifier("watch_create")
        }
        if w.watchlists.isEmpty { Muted("Create a watchlist, then search for a company to add your first symbol.") }
        ForEach(w.watchlists, id: \.id) { list in listCard(w, list, busy: busy) }
        Muted("Metrics are cached for \(w.cache.cacheHours)h to respect data-provider limits.")
    }

    private func listCard(_ w: PulseWatchlists, _ list: PulseWatchlist, busy: Bool) -> some View {
        let isOpen = open.contains(list.id)
        let news = PulseWatchlistRules.newsCount(list)
        return RCard {
            Button { if isOpen { open.remove(list.id) } else { open.insert(list.id) } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.name).font(.subheadline.weight(.semibold)).foregroundStyle(RColors.text)
                        Muted(Fmt.plural(list.items.count, "symbol") + (news > 0 ? " · \(news) in News" : ""))
                    }
                    Spacer(minLength: 8)
                    Muted(isOpen ? "▲" : "▼")
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("watchlist_\(list.id)")
            if isOpen {
                HStack(spacing: 8) {
                    Chip(text: adding == list.id ? "Close search" : "+ Add symbol") {
                        if adding == list.id { adding = nil; model.clearSearch() }
                        else if !PulseWatchlistRules.atItemCap(w, list) { adding = list.id }
                    }.accessibilityIdentifier("watch_add_\(list.id)")
                    Button { confirmDelete = list } label: { Text("Delete list").font(.footnote).foregroundStyle(RColors.loss).padding(8) }
                        .buttonStyle(.plain).disabled(busy).accessibilityIdentifier("watch_delete_\(list.id)")
                }.padding(.top, 6)
                if PulseWatchlistRules.atItemCap(w, list) { Muted("This list is full (\(w.maxItemsPerWatchlist) symbols).") }
                if adding == list.id {
                    PulseSymbolSearch(model: model, fetchNews: $fetchNewsOnAdd) { hit in adding = nil; Task { await model.addSymbol(list, hit, fetchNews: fetchNewsOnAdd) } }
                }
                if list.items.isEmpty { Muted("No symbols yet.").padding(.top, 6) }
                ForEach(list.items, id: \.id) { item in
                    PulseWatchItemCard(item: item, busy: busy, onToggleNews: { Task { await model.toggleNews(list, item) } }, onRemove: { Task { await model.removeSymbol(list, item) } })
                }
            }
        }
    }
}

private extension View {
    func pulseField() -> some View {
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(10).foregroundStyle(RColors.text)
            .background(RColors.variant, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PulseSymbolSearch: View {
    @ObservedObject var model: PulseWatchlistsModel
    @Binding var fetchNews: Bool
    var onPick: (SymbolHit) -> Void

    var body: some View {
        let sr = model.search
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: Binding(get: { model.search.query }, set: { model.onQuery($0) }),
                      prompt: Text("Search company or ticker, e.g. Apple or AAPL").foregroundColor(RColors.muted))
                .pulseField().accessibilityLabel("Search company or ticker").accessibilityIdentifier("watch_search")
            Toggle(isOn: $fetchNews) { Muted("Fetch news for this symbol") }
                .tint(RColors.accent).accessibilityIdentifier("watch_fetch_news_default")
            if sr.searching { Muted("Searching…") }
            ForEach(Array(sr.results.enumerated()), id: \.offset) { _, h in
                Button { onPick(h) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.name ?? h.symbol).font(.footnote).foregroundStyle(RColors.text)
                        Muted([h.symbol, h.exchange].compactMap { $0 }.joined(separator: " · "))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("hit_\(h.symbol)")
            }
        }
        .padding(.top, 6)
    }
}

private struct PulseMetricRow: View {
    let labelA: String, valueA: String
    var b: (String, String)?
    var subA: String?, subB: String?
    var colorB: Color = RColors.text

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Muted(labelA); Num(valueA, size: 13)
                if let subA { Text(subA).font(.caption2).foregroundStyle(RColors.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if let b {
                    Muted(b.0); Num(b.1, color: colorB, size: 13)
                    if let subB { Text(subB).font(.caption2).foregroundStyle(RColors.muted) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private struct PulseWatchItemCard: View {
    let item: PulseWatchItem
    let busy: Bool
    var onToggleNews: () -> Void
    var onRemove: () -> Void

    var body: some View {
        let it = item, F = PulseWatchlistFormat.self
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Num(it.yahooSymbol, size: 14, bold: true)
                        if F.isIndexLike(it.quoteType) { Text("INDEX / FUND").font(.r(9)).foregroundStyle(RColors.accent) }
                    }
                    if let n = it.companyName { Muted(n) }
                    if let n = it.industry { Muted(n) }
                }
                Spacer(minLength: 8)
                Button(action: onRemove) { Text("×  Remove").font(.caption).foregroundStyle(RColors.muted).padding(8) }
                    .buttonStyle(.plain).disabled(busy).accessibilityIdentifier("watch_remove_\(it.yahooSymbol)")
            }
            PulseMetricRow(labelA: "Now", valueA: F.price(it.lastPrice, it.currency), b: ("Return", F.returnText(it.changePct)), colorB: RColors.pnl(it.changePct))
            PulseMetricRow(labelA: "Added", valueA: it.addedAt.map { Fmt.stamp(iso: $0).components(separatedBy: ",")[0] } ?? Fmt.dash,
                           b: ("Price at add", F.price(it.priceAtAdd, it.currency)), subB: it.exchange.map { "Exchange \($0)" })
            PulseMetricRow(labelA: "P/E (trail)", valueA: F.peText(it), b: ("P/B", F.valuationRatio(it.pbRatio)),
                           subA: F.industryHint(it.industryPeMedian, it.industryPeerCount), subB: F.industryHint(it.industryPbMedian, it.industryPeerCount))
            PulseMetricRow(labelA: "PEG", valueA: F.valuationRatio(it.pegRatio), b: ("P/S", F.valuationRatio(it.priceToSales)))
            PulseMetricRow(labelA: "Rev (YoY)", valueA: F.percentPlain(it.revenueGrowthPct), b: ("EPS", Fmt.number(it.eps)))
            PulseMetricRow(labelA: "ROE", valueA: F.roe(it.roe), b: ("Profit margin", F.percentPlain(it.profitMargin)))
            PulseMetricRow(labelA: "D/E · cash", valueA: F.valuationRatio(it.debtToEquity), b: ("Market cap", F.compactMoney(it.marketCap)), subA: F.netCashLine(it.netCash))
            PulseMetricRow(labelA: "52-week range", valueA: F.range52(it.week52Low, it.week52High), b: ("Dividend yield", F.dividendPct(it.dividendYield)))
            Toggle(isOn: Binding(get: { it.fetchNews }, set: { _ in onToggleNews() })) { Muted("Fetch news") }
                .tint(RColors.accent).disabled(busy).padding(.top, 2)
                .accessibilityIdentifier("watch_news_\(it.yahooSymbol)")
        }
        .padding(.top, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch_item_\(it.yahooSymbol)")
    }
}
