import Charts
import SwiftUI

let freshnessNote = "After your equity data is synced from a broker or added manually, the backend usually needs 12-24 hours to fetch the latest market updates. Charts and dashboard figures roll forward on that timeline."
let adminReminder = "You're signed in as an admin. Admin tools are web-only. For your portfolio on this phone, sign in with your personal account."

enum HomeDest: Hashable { case performance, corporate }

struct HomeView: View {
    let repo: Repository
    @ObservedObject var session: SessionManager
    @ObservedObject private var events: DataEvents
    @StateObject private var vm: CachedLoader<Dashboard>
    @StateObject private var wealth: HoldingsHomeWealthLoader
    @Environment(\.hideBalances) private var hide
    @Binding var hideBalances: Bool
    @State private var investmentsOpen = true
    @State private var openSection: String?
    @State private var dismissBusy = false
    @State private var dismissError: String?

    init(repo: Repository, session: SessionManager, hideBalances: Binding<Bool>) {
        self.repo = repo; self.session = session; events = repo.events; _hideBalances = hideBalances
        _wealth = StateObject(wrappedValue: HoldingsHomeWealthLoader(repo: repo))
        _vm = StateObject(wrappedValue: CachedLoader(read: { await repo.dashboardCached() }, fetch: { try await repo.dashboard() }))
    }

    var body: some View {
        NavigationStack {
            scroll
                .navigationDestination(for: HomeDest.self) { d in
                    switch d {
                    case .performance: PerformanceScreen(repo: repo, session: session).background(RColors.bg).toolbar(.hidden, for: .tabBar)
                    case .corporate: CorporateScreen(repo: repo, session: session).background(RColors.bg).toolbar(.hidden, for: .tabBar)
                    }
                }
                .navigationTitle("Home").navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { if session.state.cleartext { HTTPPill().accessibilityIdentifier("http_chip") } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { hideBalances.toggle() } label: { Image(systemName: hideBalances ? "eye.slash" : "eye").foregroundStyle(RColors.muted) }
                            .accessibilityLabel(hideBalances ? "Show balances" : "Hide balances").accessibilityIdentifier("hide_toggle")
                            .sensoryFeedback(.selection, trigger: hideBalances)
                    }
                }
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if session.state.isAdmin { Banner(text: adminReminder, color: RColors.accent) }
                let d = vm.state.data?.value
                AsOfBar(asOf: vm.state.data?.fetchedAt, error: vm.state.error, hasData: d != nil, loading: vm.state.loading,
                        label: d.map { "Data as of \(Fmt.stamp(iso: $0.asOf)) · prices are end-of-day/cached" })
                if let d { content(d) }
                else if let e = vm.state.error { ErrorState(message: e) { Task { await vm.refresh() } } }
                else { RSkeletonCard(lines: 3); RSkeletonCard(lines: 4); RSkeletonCard(lines: 2) }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .refreshable { await vm.refresh() }
        .background(RColors.bg)
        .task { vm.load() }
        .task(id: vm.state.data?.fetchedAt) { if let d = vm.state.data?.value, HoldingsHomeSummaries.wealthShouldLoad(rows: d.rows) { wealth.load() } }
        .onChange(of: events.version) { _, _ in Task { await vm.refresh(); await wealth.refresh() } }
    }

    private func toggle(_ id: String) { withAnimation(RMotion.expand) { openSection = openSection == id ? nil : id } }
    private func section<C: View>(_ id: String, _ title: String, _ summary: String, @ViewBuilder _ content: @escaping () -> C) -> some View {
        HomeCollapsible(id: id, title: title, summary: summary, expanded: openSection == id, onToggle: { toggle(id) }, content: content)
    }

    @ViewBuilder private func content(_ d: Dashboard) -> some View {
        let ccy = d.baseCurrency
        RCard {
            Muted("Net worth")
            Num(Fmt.money(d.netWorthTotalBase, ccy, hide: hide), size: 30, bold: true).accessibilityIdentifier("net_worth")
            Muted("\(Fmt.plural(HomeLogic.listedPositionCount(d.rows), "listed position")) · \(Fmt.plural(d.rows.count, "line")) in total")
        }
        HomeCollapsible(id: "investments", title: "Investments (\(ccy))", summary: HomeLogic.investmentsSummary(d, hide: hide),
                        expanded: investmentsOpen, onToggle: { withAnimation(RMotion.expand) { investmentsOpen.toggle() } }) { investments(d) }
        alerts(d)
        pies(d)
        if let sum = HoldingsHomeSummaries.positions(rows: d.rows) {
            section("positions", "Position size: cost vs gain/loss", sum) { HoldingsHomePositionSizeContent(rows: d.rows, ccy: ccy) }
        }
        if let sum = HoldingsHomeSummaries.custodian(rows: d.rows, ccy: ccy, hide: hide) {
            section("custodian", "Net worth by broker", sum) { HoldingsHomeCustodianContent(rows: d.rows, ccy: ccy) }
        }
        if HoldingsHomeSummaries.wealthShouldLoad(rows: d.rows), wealth.isVisible, let sum = wealth.summary(hide: hide) {
            section("wealth", "Wealth over time", sum) { HoldingsHomeWealthContent(loader: wealth) }
        }
        NavigationLink(value: HomeDest.performance) {
            RCard {
                SectionTitle("Performance & income")
                Muted("Growth attribution, benchmark comparison vs FTSE 100 and S&P 100, dividend income and forecast.")
                Text("Open charts →").font(.r(13)).foregroundStyle(RColors.accent).padding(.top, 4)
            }
        }
        .buttonStyle(.plain).accessibilityIdentifier("open_performance")
        section("freshness", "Data freshness", "How recent market data and FX are for your synced holdings.") {
            Muted(freshnessNote)
            Muted("Sync or manual add → 12–24 hr pipeline → dashboards and benchmarks refresh")
        }
    }

    @ViewBuilder private func investments(_ d: Dashboard) -> some View {
        let ccy = d.baseCurrency
        let pct = HomeLogic.unrealisedPct(pnl: d.totalPnlBase, cost: d.totalCostBase)
        HStack(alignment: .top, spacing: 12) {
            Stat(label: "Listed value", value: Fmt.money(d.totalMarketValueBase, ccy, hide: hide))
            Stat(label: "Cost", value: Fmt.money(d.totalCostBase, ccy, hide: hide))
        }
        HStack(alignment: .top, spacing: 12) {
            Stat(label: "Unrealised P/L", value: Fmt.signedMoney(d.totalPnlBase, ccy, hide: hide) + (hide ? "" : (pct.map { " (\(Fmt.percent($0, signed: true)))" } ?? "")), color: RColors.pnl(d.totalPnlBase))
            Stat(label: "Realised P/L", value: Fmt.signedMoney(d.totalRealisedPnlBase, ccy, hide: hide), color: RColors.pnl(d.totalRealisedPnlBase))
        }
        HStack(alignment: .top, spacing: 12) {
            Stat(label: "XIRR (annual)", value: Fmt.percentFromFraction(d.portfolioXirrAnnual, signed: true), color: RColors.pnl(d.portfolioXirrAnnual))
            Stat(label: "Dividend income", value: Fmt.money(d.dividendIncomeBrokerCashBase ?? d.dividendIncomeTotalBase, ccy, hide: hide))
        }
        if let broker = d.brokerListedMarketValueBase, let manual = d.manualListedMarketValueBase, broker > 0, manual > 0 {
            Muted("Listed value: broker \(Fmt.money(broker, ccy, hide: hide)) · manual \(Fmt.money(manual, ccy, hide: hide))")
        } else if let manual = d.manualListedMarketValueBase, manual > 0 {
            Muted("Listed value includes manual stocks/ETFs: \(Fmt.money(manual, ccy, hide: hide))")
        }
        Muted("Realised P/L is equity only, excluding dividends (FIFO on buy/sell fills).")
        Muted(d.dividendIncomeBrokerCashBase != nil ? "Dividend income: broker payouts including cash interest." : "Dividend income: estimated from fills and market data.")
        if d.portfolioXirrNote != nil { Muted("XIRR is money-weighted (trades at FX, dividends, ending market value) and may differ from your broker's figure.") }
        if let g = HomeLogic.nonEquityGain(d) {
            VStack(alignment: .leading, spacing: 2) {
                Muted("Non-equity manual wealth gain/loss (\(ccy))")
                Num(Fmt.signedMoney(g.gain, ccy, hide: hide) + (g.pct.map { " · \(Fmt.percent($0)) p.a. blended" } ?? ""), color: RColors.pnl(g.gain))
                Muted("Property, savings and other manual lines. Change vs opening amount, not listed equity.")
            }.padding(.top, 4).accessibilityIdentifier("non_equity_gain")
        }
    }

    @ViewBuilder private func alerts(_ d: Dashboard) -> some View {
        if d.manualBasisIncompleteCount > 0 || d.tickerMapAttentionCount > 0 {
            section("alerts", "Alerts & reminders", HomeLogic.alertsSummary(d)) {
                if d.manualBasisIncompleteCount > 0 {
                    let n = d.manualBasisIncompleteCount
                    Banner(text: "\(n) manual listed lot\(n == 1 ? " is" : "s are") missing a purchase date or total GBP cost. Open each lot in Holdings and choose Edit lot so cost vs gain is correct.")
                }
                if d.tickerMapAttentionCount > 0 {
                    Text("Listings need your attention").font(.r(14, .semibold)).foregroundStyle(RColors.text)
                    Muted("\(Fmt.plural(d.tickerMapAttentionCount, "unresolved ticker")) from your broker. Open Corporate actions → Symbols to confirm and enter the listing to use.")
                    Muted("Dismiss hides this temporarily; the reminder returns until the symbols are resolved.")
                    if let e = dismissError { Banner(text: "Could not dismiss: \(e)", color: RColors.loss) }
                    HStack(spacing: 10) {
                        NavigationLink(value: HomeDest.corporate) {
                            Text("Review symbols").font(.r(14, .semibold)).foregroundStyle(RColors.bg)
                                .padding(.horizontal, 16).padding(.vertical, 9).background(RColors.accent, in: Capsule())
                        }.buttonStyle(.plain).accessibilityIdentifier("review_symbols")
                        Button(dismissBusy ? "…" : "Dismiss") { dismissTickers() }
                            .font(.r(14)).foregroundStyle(RColors.accent).disabled(dismissBusy).accessibilityIdentifier("dismiss_symbols")
                    }
                }
            }
        }
    }

    /// "Portfolio & net worth": the sector donut with drill-down plus the net worth split by asset class.
    @ViewBuilder private func pies(_ d: Dashboard) -> some View {
        let ccy = d.baseCurrency
        let sectorSummary = HoldingsHomeSummaries.sectors(rows: d.rows, ccy: ccy, hide: hide)
        if sectorSummary != nil || !d.netWorthBreakdown.isEmpty {
            section("pies", "Portfolio & net worth", sectorSummary ?? "Sector donut and optional net worth split.") {
                if sectorSummary != nil {
                    Muted("Portfolio by sector")
                    HoldingsHomeSectorsContent(rows: d.rows, ccy: ccy)
                }
                if !d.netWorthBreakdown.isEmpty {
                    Muted("Net worth by asset class")
                    HStack(spacing: 16) {
                        Chart(Array(d.netWorthBreakdown.enumerated()), id: \.offset) { i, b in
                            SectorMark(angle: .value("Value", max(0.0, (b.valueBase as NSDecimalNumber?)?.doubleValue ?? 0)), innerRadius: .ratio(0.62), angularInset: 1)
                                .foregroundStyle(RColors.chart[i % RColors.chart.count])
                        }
                        .frame(width: 130, height: 130)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(d.netWorthBreakdown.enumerated()), id: \.offset) { i, b in
                                HStack(spacing: 8) {
                                    Circle().fill(RColors.chart[i % RColors.chart.count]).frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(HomeLogic.bucketLabel(b.bucket)).font(.r(13)).foregroundStyle(RColors.text)
                                        Num("\(Fmt.money(b.valueBase, ccy, hide: hide, scale: 0)) · \(Fmt.percent(b.weightPct, scale: 1))", color: RColors.muted, size: 11)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func dismissTickers() {
        dismissBusy = true; dismissError = nil
        Task {
            defer { dismissBusy = false }
            do { try await repo.miscDismissTickerBanner(); await vm.refresh() }
            catch { dismissError = (error as? ApiError)?.message ?? error.localizedDescription }
        }
    }
}
