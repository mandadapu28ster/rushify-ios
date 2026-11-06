import SwiftUI

private let performanceGrowthColors: [Color] = [0x5AA9FF, 0xF5B84B, 0x7DD3FC, 0xA78BFA].map { Color(hex: $0) }   // price, interaction, income, currency
private var performanceTickerColors: [Color] { RColors.categorical }

private func performanceDouble(_ d: Decimal?) -> Double { d.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0 }

/// Performance & income: Growth (with the listed-equity trend), Benchmarks and Dividends. Pushed inside the More NavigationStack.
struct PerformanceScreen: View {
    let repo: Repository
    @ObservedObject var session: SessionManager
    @ObservedObject private var events: DataEvents
    @StateObject private var growth: PerformanceGrowthModel
    @StateObject private var bench: PerformanceBenchmarksModel
    @StateObject private var dividends: PerformanceDividendsModel
    @StateObject private var equity: PerformanceEquityModel
    @StateObject private var dashboard: CachedLoader<Dashboard>
    @State private var tab = 0

    init(repo: Repository, session: SessionManager) {
        self.repo = repo; self.session = session
        _events = ObservedObject(wrappedValue: repo.events)
        _growth = StateObject(wrappedValue: PerformanceGrowthModel(repo: repo))
        _bench = StateObject(wrappedValue: PerformanceBenchmarksModel(repo: repo))
        _dividends = StateObject(wrappedValue: PerformanceDividendsModel(repo: repo))
        _equity = StateObject(wrappedValue: PerformanceEquityModel(repo: repo))
        _dashboard = StateObject(wrappedValue: CachedLoader(read: { await repo.dashboardCached() }, fetch: { try await repo.dashboard() }))
    }

    var body: some View {
        VStack(spacing: 0) {
            RSegmented(titles: ["Growth", "Benchmarks", "Dividends"], selection: $tab, idPrefix: "performance_tab")
                .padding(.horizontal, 16).padding(.vertical, 8)
            Group {
                switch tab {
                case 0: PerformanceGrowthTab(vm: growth, dashboard: dashboard, equity: equity)
                case 1: PerformanceBenchmarksTab(vm: bench)
                default: PerformanceDividendsTab(vm: dividends)
                }
            }
            .transition(.opacity).id(tab)
        }
        .animation(RMotion.fade, value: tab)
        .background(RColors.bg)
        .navigationTitle("Performance & income").navigationBarTitleDisplayMode(.inline)
        .onChange(of: events.version) { _ in
            // Portfolio data changed: refresh whatever has been opened, keeping the current data on screen meanwhile.
            Task {
                if growth.didLoad { await growth.refresh() }
                if bench.didLoad { await bench.refresh() }
                if dividends.didLoad { await dividends.refresh() }
                if dashboard.state.data != nil || dashboard.state.loading { await dashboard.refresh() }
                if equity.didLoad && equity.prefs.daily { await equity.refresh() }
            }
        }
    }
}

// MARK: Shared bits

private struct PerformanceReadoutRow: View {
    let label: String, value: String
    var color: Color = RColors.text
    var bold = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) { Muted(label); Spacer(minLength: 8); Num(value, color: color, size: 13, bold: bold) }.padding(.vertical, 2)
    }
}

private struct PerformanceSummaryTile: View {
    let label: String, value: String
    var sub: String?
    var color: Color
    var dot: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) { if let dot { Circle().fill(dot).frame(width: 8, height: 8) }; Muted(label) }
            Num(value, color: color, size: 14, bold: true)
            if let sub { Muted(sub) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }
}

private struct PerformanceMetricCard: View {
    let title: String, value: String, note: String
    var color: Color = RColors.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) { Muted(title); Num(value, color: color, size: 15, bold: true); Muted(note) }.padding(.vertical, 5)
    }
}

/// Row of "6 mo / 12 mo ..." chips for the selected granularity.
private struct PerformancePeriodChips: View {
    let granularity: String, options: [Int], selected: Int
    let onPick: (Int) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Muted("Periods")
                ForEach(options, id: \.self) { n in
                    Chip(text: PerformancePeriodOptions.label(granularity, n), selected: n == selected) { onPick(n) }.accessibilityIdentifier("period_\(n)")
                }
            }
        }
    }
}

private struct PerformanceTabScaffold<Content: View>: View {
    let refresh: () async -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content() }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await refresh() }
    }
}

// MARK: Growth

private struct PerformanceEquitySyncKey: Hashable { var daily: Bool; var granularity: String; var count: Int; var selected: [String]; var labels: [String] }

private struct PerformanceGrowthTab: View {
    @ObservedObject var vm: PerformanceGrowthModel
    @ObservedObject var dashboard: CachedLoader<Dashboard>
    @ObservedObject var equity: PerformanceEquityModel
    @Environment(\.hideBalances) private var hide
    @State private var sel: Int?

    private var labels: [String] { PerformanceBrokerLabels.listedEquity(dashboard.state.data?.value.rows ?? []) }
    /// Web default: the first broker alphabetically.
    private var selected: Set<String> {
        let chosen = Set((equity.prefs.selected ?? []).filter { labels.contains($0) })
        return chosen.isEmpty ? Set(labels.prefix(1)) : chosen
    }

    var body: some View {
        let s = vm.state, g = s.data?.value
        let key = PerformanceEquitySyncKey(daily: equity.prefs.daily, granularity: vm.granularity, count: vm.count, selected: labels.filter { selected.contains($0) }, labels: labels)
        PerformanceTabScaffold(refresh: { await vm.refresh() }) {
            HStack(spacing: 8) {
                Chip(text: "Monthly", selected: vm.granularity == "monthly") { sel = nil; vm.select("monthly") }.accessibilityIdentifier("granularity_monthly")
                Chip(text: "Yearly", selected: vm.granularity == "yearly") { sel = nil; vm.select("yearly") }.accessibilityIdentifier("granularity_yearly")
            }
            PerformancePeriodChips(granularity: vm.granularity, options: PerformancePeriodOptions.growth(vm.granularity), selected: vm.count) { sel = nil; vm.select(n: $0) }
            AsOfBar(asOf: s.data?.fetchedAt, error: s.error, hasData: g != nil, loading: s.loading)
            if let g {
                if g.periods.isEmpty { Muted("No growth data yet. Sync positions and make sure prices load.") } else { content(g) }
            } else if let e = s.error {
                ErrorState(message: e) { Task { await vm.refresh() } }
            } else {
                Muted("Loading growth… the server calculates this on first use and it can take several seconds.")
            }
        }
        .task { vm.load(); dashboard.load() }
        .task(id: key) { if equity.prefs.daily && !labels.isEmpty { equity.sync(vm.granularity, vm.count, selected: labels.filter { selected.contains($0) }) } }
    }

    @ViewBuilder private func content(_ g: PerformanceGrowth) -> some View {
        let ccy = g.baseCurrency
        let pick = min(max(sel ?? g.periods.count - 1, 0), g.periods.count - 1)
        let p = g.periods[pick]
        let sum = PerformanceGrowthMath.summary(g.periods)
        let unit = vm.granularity == "yearly" ? "years" : "months"
        let colors = performanceGrowthColors
        RCard {
            SectionTitle("Growth attribution")
            Muted("How change splits across price, currency, dividends and interaction, in \(ccy). Totals for the range (\(g.periods.count) \(unit)):")
            PerformanceSummaryTile(label: "Total change", value: Fmt.signedMoney(sum.total, ccy, hide: hide), sub: nil, color: RColors.pnl(sum.total), dot: nil)
                .accessibilityIdentifier("growth_total")
            HStack(spacing: 12) {
                PerformanceSummaryTile(label: "Price (× FX₀)", value: Fmt.signedMoney(sum.price, ccy, hide: hide), sub: sum.share(sum.price), color: RColors.pnl(sum.price), dot: colors[0])
                PerformanceSummaryTile(label: "Interaction", value: Fmt.signedMoney(sum.interaction, ccy, hide: hide), sub: sum.share(sum.interaction), color: RColors.pnl(sum.interaction), dot: colors[1])
            }
            HStack(spacing: 12) {
                PerformanceSummaryTile(label: "Income (dividends)", value: Fmt.signedMoney(sum.income, ccy, hide: hide), sub: sum.share(sum.income), color: RColors.pnl(sum.income), dot: colors[2])
                PerformanceSummaryTile(label: "Currency (FX)", value: Fmt.signedMoney(sum.currency, ccy, hide: hide), sub: sum.share(sum.currency), color: RColors.pnl(sum.currency), dot: colors[3])
            }
            if hide { Muted("Charts are hidden while balances are hidden.").padding(.top, 8) } else {
                PerformanceStackedBarChart(
                    bars: g.periods.map { PerformanceStackedBar(label: $0.label, values: [performanceDouble($0.priceGainBase), performanceDouble($0.interactionGainBase), performanceDouble($0.incomeBase), performanceDouble($0.currencyGainBase)]) },
                    colors: colors, selected: pick, onSelect: { sel = $0 }, description: "Growth attribution chart",
                    seriesNames: ["Price", "Interaction", "Income", "Currency"], identifier: "growth_chart")
                    .padding(.top, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    PerformanceLegendDot(color: colors[0], text: "Price (× FX₀)"); PerformanceLegendDot(color: colors[1], text: "Interaction")
                    PerformanceLegendDot(color: colors[2], text: "Income"); PerformanceLegendDot(color: colors[3], text: "Currency")
                }
            }
            Muted("Positive effects stack above zero and negative effects below, not as one running total. The four parts still add up to the period total.").padding(.top, 4)
            Text(p.label).font(.r(15, .semibold)).foregroundStyle(RColors.text).padding(.top, 8).accessibilityIdentifier("growth_selected")
            PerformanceReadoutRow(label: "Total", value: Fmt.signedMoney(p.totalGrowthBase, ccy, hide: hide), color: RColors.pnl(p.totalGrowthBase), bold: true)
            PerformanceReadoutRow(label: "Price (× FX₀)", value: Fmt.signedMoney(p.priceGainBase, ccy, hide: hide), color: RColors.pnl(p.priceGainBase))
            PerformanceReadoutRow(label: "Interaction", value: Fmt.signedMoney(p.interactionGainBase, ccy, hide: hide), color: RColors.pnl(p.interactionGainBase))
            PerformanceReadoutRow(label: "Income (dividends)", value: Fmt.signedMoney(p.incomeBase, ccy, hide: hide), color: RColors.pnl(p.incomeBase))
            PerformanceReadoutRow(label: "Currency (FX)", value: Fmt.signedMoney(p.currencyGainBase, ccy, hide: hide), color: RColors.pnl(p.currencyGainBase))
            if PerformanceGrowthMath.stackDiffers(p) { Muted("Stack sum \(Fmt.money(PerformanceGrowthMath.stackSum(p), ccy, hide: hide)) (rounding)") }
            if !p.purchaseEvents.isEmpty {
                Muted("Purchases: " + String(p.purchaseEvents.map { $0.label ?? $0.ticker }.joined(separator: ", ").prefix(160)))
            }
            Muted("Note on Interaction: " + PerformanceGrowthMath.interactionNote).padding(.top, 8).accessibilityIdentifier("interaction_note")
        }
        PerformanceEquityCard(g: g, dailyData: equity.state.data?.value, dailyLoading: equity.state.loading, labels: labels, selected: selected,
                              vm: equity, ccy: ccy, hide: hide, pick: pick)
        Muted("Values are end-of-day reconstructions, not live prices.")
    }
}

private struct PerformanceEquityCard: View {
    let g: PerformanceGrowth
    let dailyData: PerformanceGrowth?
    let dailyLoading: Bool
    let labels: [String]
    let selected: Set<String>
    @ObservedObject var vm: PerformanceEquityModel
    let ccy: String
    let hide: Bool
    let pick: Int
    @State private var cursor: Int?

    var body: some View {
        let prefs = vm.prefs
        let usingDaily = prefs.daily && dailyData?.equityDaily != nil
        let points: [PerformanceEquityPoint] = usingDaily
            ? dailyData!.equityDaily!.map { PerformanceEquityPoint(label: $0.asOf, mv: $0.listedEquityMvEndBase, invested: $0.investedCapitalEndBase, brokers: $0.brokers) }
            : g.periods.map { PerformanceEquityPoint(label: $0.label, mv: $0.listedEquityMvEndBase, invested: $0.investedCapitalEndBase, brokers: $0.brokers) }
        let series = PerformanceEquityTrend.series(points, selected: selected, allLabels: labels, totals: prefs.totals)
        let partial = PerformanceEquityTrend.isPartial(selected, labels)
        let last = max(points.count - 1, 0)
        let idx = usingDaily ? last : min(max(pick, 0), last)
        let at = min(max(cursor ?? idx, 0), last)
        RCard {
            SectionTitle("Listed equity over time")
            Muted("Market value (solid) and book cost (dashed). Listed equities only.")
            HStack(spacing: 8) {
                Chip(text: "Period", selected: !prefs.daily) { cursor = nil; vm.update { $0.daily = false } }.accessibilityIdentifier("equity_period")
                Chip(text: "Daily", selected: prefs.daily) { cursor = nil; vm.update { $0.daily = true } }.accessibilityIdentifier("equity_daily")
                Chip(text: prefs.totals ? "Totals ✓" : "Totals", selected: prefs.totals) { vm.update { $0.totals.toggle() } }.accessibilityIdentifier("equity_totals")
            }.padding(.top, 6)
            if !labels.isEmpty {
                Muted("Accounts").padding(.top, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(labels, id: \.self) { l in
                            let on = selected.contains(l)
                            Chip(text: l, selected: on) {
                                var next = selected
                                if on { next.remove(l) } else { next.insert(l) }
                                if !next.isEmpty { vm.update { $0.selected = next } }       // the last remaining account cannot be unticked
                            }.accessibilityIdentifier("equity_account_\(l)")
                        }
                        Chip(text: "Select all", selected: false) { vm.update { $0.selected = Set(labels) } }.accessibilityIdentifier("equity_select_all")
                    }
                }
            }
            Group {
                if hide { Muted("Hidden while balances are hidden.") }
                else if prefs.daily && dailyLoading && dailyData == nil { Muted("Loading daily points… this can take several seconds.") }
                else if points.count < 2 { Muted("No data for this range.") }
                else { chart(points, series, partial, at, usingDaily) }
            }.padding(.top, 8)
        }
        .accessibilityIdentifier("equity_card")
    }

    @ViewBuilder private func chart(_ points: [PerformanceEquityPoint], _ series: PerformanceEquitySeries, _ partial: Bool, _ at: Int, _ usingDaily: Bool) -> some View {
        let lines = series.lines.map { ln -> PerformanceChartLine in
            let c: Color = ln.colorIndex == -1 ? Color(hex: 0xF8FAFC) : (ln.colorIndex == -2 ? Color(hex: 0xFACC15) : RColors.chart[ln.colorIndex % RColors.chart.count])
            return PerformanceChartLine(name: ln.name, color: c, values: ln.values.map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }, dashed: ln.dashed)
        }
        PerformanceLineChart(xLabels: points.map { usingDaily ? PerformanceChartMath.lastChars($0.label, 5) : PerformanceChartMath.shortLabel($0.label) },
                             lines: lines, selected: at, onSelect: { cursor = $0 }, description: "Listed equity over time", identifier: "equity_chart")
        if let d = series.deltaMv {
            HStack { Muted("Δ MV (first → last)"); Spacer(); Num(Fmt.signedMoney(d, ccy, hide: hide), color: RColors.pnl(d), size: 13).accessibilityIdentifier("equity_delta") }.padding(.top, 4)
        }
        let p = points[at]
        Text(p.label + (partial ? " · selected accounts only" : "")).font(.r(15, .semibold)).foregroundStyle(RColors.text).padding(.top, 6)
            .accessibilityIdentifier("equity_selected")
        ForEach(Array(series.lines.filter { $0.isTotal }.enumerated()), id: \.offset) { _, ln in
            PerformanceReadoutRow(label: ln.name, value: Fmt.money(ln.values.indices.contains(at) ? ln.values[at] : nil, ccy, hide: hide))
        }
        if let mv = series.lines.first(where: { $0.isTotal && !$0.dashed })?.values[safe: at] ?? nil,
           let bk = series.lines.first(where: { $0.isTotal && $0.dashed })?.values[safe: at] ?? nil {
            PerformanceReadoutRow(label: "MV − book", value: Fmt.signedMoney(mv - bk, ccy, hide: hide), color: RColors.pnl(mv - bk))
        }
        ForEach(Array(series.lines.filter { !$0.isTotal && !$0.dashed }.enumerated()), id: \.offset) { _, ln in
            let name = ln.name.hasSuffix(" · mv") ? String(ln.name.dropLast(5)) : ln.name
            PerformanceReadoutRow(label: name, value: Fmt.money(ln.values[safe: at] ?? nil, ccy, hide: hide))
        }
        Muted("Reconstructed from stored end-of-day prices and synced cost basis, not live broker tiles, so real-time totals can differ.").padding(.top, 6)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: Benchmarks

private struct PerformanceBenchmarksTab: View {
    @ObservedObject var vm: PerformanceBenchmarksModel
    @Environment(\.hideBalances) private var hide
    @State private var sel: Int?

    var body: some View {
        let s = vm.state, b = s.data?.value
        PerformanceTabScaffold(refresh: { await vm.refresh() }) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([("monthly", "Monthly"), ("yearly", "Yearly"), ("week", "1 week"), ("day", "1 day")], id: \.0) { k, l in
                        Chip(text: l, selected: vm.mode == k) { sel = nil; vm.select(k) }.accessibilityIdentifier("benchmark_mode_\(k)")
                    }
                }
            }
            if vm.mode == "monthly" || vm.mode == "yearly" {
                PerformancePeriodChips(granularity: vm.mode, options: PerformancePeriodOptions.growth(vm.mode), selected: vm.count) { sel = nil; vm.select(n: $0) }
            }
            AsOfBar(asOf: s.data?.fetchedAt, error: s.error, hasData: b != nil, loading: s.loading)
            if let b {
                if b.emptyPortfolio {
                    Muted("Benchmarks need at least one listed investment (stock or ETF) so we can build a price series. If your portfolio is only cash, property or other assets, this section stays empty.")
                } else if b.series.isEmpty {
                    Muted("No portfolio history to compare yet.")
                } else { content(b) }
            } else if let e = s.error {
                ErrorState(message: e) { Task { await vm.refresh() } }
            } else {
                Muted("Loading benchmarks…")
            }
        }
        .task { vm.load() }
    }

    @ViewBuilder private func content(_ b: PerformanceBenchmarks) -> some View {
        let pick = min(max(sel ?? b.series.count - 1, 0), b.series.count - 1)
        let pt = b.series[pick]
        let ccy = b.baseCurrency
        RCard {
            SectionTitle("Return vs FTSE 100 and S&P 100")
            Muted("Each series is set to 100 on the first day of the range: your portfolio in \(ccy), FTSE 100 (^FTSE) and S&P 100 (^OEX).")
            HStack(spacing: 12) {
                Stat(label: "Portfolio", value: Fmt.percent(b.portfolioReturnPct, signed: true), color: RColors.pnl(b.portfolioReturnPct))
                Stat(label: "FTSE 100", value: Fmt.percent(b.ftse100ReturnPct, signed: true), color: RColors.pnl(b.ftse100ReturnPct))
                Stat(label: "S&P 100", value: Fmt.percent(b.sp100ReturnPct, signed: true), color: RColors.pnl(b.sp100ReturnPct))
            }.padding(.top, 6)
            PerformanceLineChart(
                xLabels: b.series.map { PerformanceChartMath.lastChars($0.date, 5) },
                lines: [PerformanceChartLine(name: "Portfolio", color: RColors.chart[0], values: b.series.map { $0.portfolioIndex }),
                        PerformanceChartLine(name: "FTSE 100", color: RColors.chart[2], values: b.series.map { $0.ftse100Index }),
                        PerformanceChartLine(name: "S&P 100", color: RColors.chart[3], values: b.series.map { $0.sp100Index })],
                selected: pick, onSelect: { sel = $0 }, description: "Benchmark comparison chart", identifier: "benchmark_chart").padding(.top, 10)
            HStack(spacing: 14) {
                PerformanceLegendDot(color: RColors.chart[0], text: "Portfolio"); PerformanceLegendDot(color: RColors.chart[2], text: "FTSE 100"); PerformanceLegendDot(color: RColors.chart[3], text: "S&P 100")
            }
            Text(pt.date).font(.r(15, .semibold)).foregroundStyle(RColors.text).padding(.top, 8).accessibilityIdentifier("benchmark_selected")
            PerformanceReadoutRow(label: "Portfolio (index)", value: PerformanceBenchmarkMath.indexText(pt.portfolioIndex))
            PerformanceReadoutRow(label: "FTSE 100", value: PerformanceBenchmarkMath.indexText(pt.ftse100Index))
            PerformanceReadoutRow(label: "S&P 100", value: PerformanceBenchmarkMath.indexText(pt.sp100Index))
        }
        let rangeLabel = vm.mode == "day" || vm.mode == "week" ? "selected \(vm.mode)"
            : "selected \(vm.count) \(vm.mode == "monthly" ? "month" : "year")\(vm.count == 1 ? "" : "s")"
        RCard {
            SectionTitle("Portfolio vs the indices")
            ForEach([("FTSE 100", b.ftse100ReturnPct, "FTSE 100"), ("S&P 100", b.sp100ReturnPct, "S&P 100 (^OEX)")], id: \.0) { name, ret, verdictName in
                let gap = PerformanceBenchmarkMath.points(b.portfolioReturnPct, ret)
                VStack(alignment: .leading, spacing: 2) {
                    Muted("Portfolio vs \(name) (\(rangeLabel))")
                    Num(PerformanceBenchmarkMath.pointsText(gap), color: RColors.pnl(gap), size: 16, bold: true)
                    if let v = PerformanceBenchmarkMath.verdict(gap, verdictName) { Muted(v) }
                }.padding(.vertical, 5)
            }
        }
        .accessibilityIdentifier("vs_cards")
        RCard {
            SectionTitle("Where the period P/L came from")
            PerformanceMetricCard(title: "Period total Δ (\(ccy))", value: Fmt.signedMoney(b.periodTotalPnlBase, ccy, hide: hide), note: "First → last day in range (portfolio value)", color: RColors.pnl(b.periodTotalPnlBase))
            PerformanceMetricCard(title: "Price effect (\(ccy), est.)", value: Fmt.signedMoney(b.periodPricePnlBase, ccy, hide: hide), note: "Local move × FX at period start")
            PerformanceMetricCard(title: "Currency / FX effect (\(ccy), est.)", value: Fmt.signedMoney(b.periodFxPnlBase, ccy, hide: hide), note: "FX move × local value at start")
            PerformanceMetricCard(title: "Interaction (est.)", value: Fmt.signedMoney(b.periodCrossPnlBase, ccy, hide: hide), note: "Same idea as Interaction in Growth attribution: the remainder when price and FX both move")
        }
    }
}

// MARK: Dividends

private struct PerformanceDividendsTab: View {
    @ObservedObject var vm: PerformanceDividendsModel
    @Environment(\.hideBalances) private var hide
    @State private var sel: Int?
    @State private var howTo = false

    var body: some View {
        let s = vm.state, d = s.data?.value
        PerformanceTabScaffold(refresh: { await vm.refresh() }) {
            HStack(spacing: 8) {
                Chip(text: "Monthly", selected: vm.granularity == "monthly") { sel = nil; vm.select("monthly") }.accessibilityIdentifier("granularity_monthly")
                Chip(text: "Yearly", selected: vm.granularity == "yearly") { sel = nil; vm.select("yearly") }.accessibilityIdentifier("granularity_yearly")
            }
            PerformancePeriodChips(granularity: vm.granularity, options: PerformancePeriodOptions.dividends(vm.granularity), selected: vm.count) { sel = nil; vm.select(n: $0) }
            if let d, !d.symbols.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(text: "All holdings", selected: vm.symbol == nil) { sel = nil; vm.select(symbol: .some(nil)) }.accessibilityIdentifier("dividend_symbol_all")
                        ForEach(d.symbols, id: \.self) { sym in
                            Chip(text: sym, selected: vm.symbol == sym) { sel = nil; vm.select(symbol: .some(sym)) }.accessibilityIdentifier("dividend_symbol_\(sym)")
                        }
                    }
                }
            }
            AsOfBar(asOf: s.data?.fetchedAt, error: s.error, hasData: d != nil, loading: s.loading)
            if let d {
                if d.series.isEmpty { Muted(d.note ?? "No dividend data for this view. Widen the history, clear the stock filter, or sync your portfolio.") } else { content(d) }
            } else if let e = s.error {
                ErrorState(message: e) { Task { await vm.refresh() } }
            } else {
                Muted("Loading dividends…")
            }
        }
        .task { vm.load() }
    }

    @ViewBuilder private func content(_ d: PerformanceDividends) -> some View {
        let ccy = d.baseCurrency
        let summary = PerformanceDividendMath.summary(d)
        let stacks = PerformanceDividendStacks.build(d.series)
        let pick = min(max(sel ?? d.series.lastIndex(where: { $0.kind == "current_partial" }) ?? d.series.count - 1, 0), d.series.count - 1)
        let colors = stacks.tickers.indices.map { performanceTickerColors[$0 % performanceTickerColors.count] }
        let p = d.series[pick]
        RCard {
            SectionTitle("Cash dividends")
            HStack(spacing: 12) {
                Stat(label: "Received (shown)", value: Fmt.money(summary.received, ccy, hide: hide)).accessibilityIdentifier("dividend_received")
                Stat(label: "Forward estimate", value: Fmt.money(summary.forecast, ccy, hide: hide)).accessibilityIdentifier("dividend_forecast")
            }
            if hide { Muted("Hidden while balances are hidden.").padding(.top, 10) } else {
                PerformanceStackedBarChart(
                    bars: stacks.bars.enumerated().map { i, b in
                        PerformanceStackedBar(label: PerformanceDividendMath.axisLabel(d.series[i]), values: (b.actual + b.forecast).map { performanceDouble($0) }, fadedFrom: stacks.tickers.count)
                    },
                    colors: colors, selected: pick, onSelect: { sel = $0 }, description: "Dividend income chart",
                    seriesNames: stacks.tickers + stacks.tickers.map { $0 + " (estimate)" },
                    averageLine: stacks.average.map { performanceDouble($0) }, zoneFromIndex: stacks.bars.firstIndex { $0.forecastZone }, identifier: "dividend_chart")
                    .padding(.top, 10)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(stacks.tickers.enumerated()), id: \.offset) { i, t in PerformanceLegendDot(color: colors[i], text: t) }
                    PerformanceLegendDot(color: RColors.warn, text: "Average" + (stacks.average.map { " " + Fmt.money($0, ccy, hide: hide, scale: 0) } ?? ""))
                }
            }
            Muted("Solid = paid, translucent = estimate, shaded = forward estimate.").padding(.top, 2)
            Text(p.label + (p.kind == "current_partial" ? " (so far)" : (p.kind == "forecast_forward" ? " (estimate)" : "")))
                .font(.r(15, .semibold)).foregroundStyle(RColors.text).padding(.top, 8).accessibilityIdentifier("dividend_selected")
            PerformanceReadoutRow(label: "Total", value: Fmt.money(p.totalBase, ccy, hide: hide), bold: true)
            if let g = p.growthPctPrior { PerformanceReadoutRow(label: "vs prior period", value: Fmt.percent(g, scale: 1, signed: true), color: RColors.pnl(g)) }
            ForEach(Array(PerformanceDividendMath.topContributors(p, 5).enumerated()), id: \.offset) { _, c in
                PerformanceReadoutRow(label: c.ticker, value: Fmt.money(c.amount, ccy, hide: hide))
            }
        }
        if d.note != nil || d.forecastMethod != nil {
            RCard {
                Button { howTo.toggle() } label: {
                    HStack { Text("How to read this chart").font(.r(15, .semibold)).foregroundStyle(RColors.text); Spacer(); Muted(howTo ? "▲" : "▼") }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("dividend_howto")
                if howTo {
                    if let n = d.note { Muted(n).padding(.top, 4) }
                    if let m = d.forecastMethod { Muted("Estimates: \(m)").padding(.top, 4) }
                }
            }
        }
    }
}
