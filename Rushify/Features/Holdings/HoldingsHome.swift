import Charts
import Combine
import SwiftUI

// MARK: palette + small chart pieces

enum HoldingsPalette {
    static let sectorPie: [Color] = [0x0072B2, 0xE69F00, 0x009E73, 0xD55E00, 0xCC79A7, 0x785EF0, 0x56B4E9, 0x0E7490].map { Color(hex: $0) }
    static let wrapper: [String: Color] = [
        "Invest": Color(hex: 0x005A9C), "ISA": Color(hex: 0x007A53), "SIPP": Color(hex: 0x5E3F99), "LISA": Color(hex: 0xC2410C),
        "JISA": Color(hex: 0xBE185D), "JSIPP": Color(hex: 0x0C6E87), "Other": Color(hex: 0x475569),
    ]
    static let property = Color(hex: 0x785EF0)
    static let otherAssets = Color(hex: 0x64748B)
    private static let cash: [String: Color] = [
        "Invest": Color(hex: 0xD97706), "ISA": Color(hex: 0x2563EB), "Cash ISA": Color(hex: 0x7C3AED), "SIPP": Color(hex: 0x0D9488),
        "LISA": Color(hex: 0x0284C7), "JISA": Color(hex: 0x059669), "JSIPP": Color(hex: 0xEA580C), "Other": Color(hex: 0x64748B),
    ]
    private static let cashFallback: [Color] = [0xDB2777, 0x65A30D, 0x0891B2, 0x9333EA, 0xCA8A04, 0x4F46E5].map { Color(hex: $0) }
    static func cashColor(_ label: String) -> Color {
        if let c = cash[label] { return c }
        // Stable across launches (String.hashValue is randomised): sum of UTF-16 units.
        let h = label.lowercased().utf16.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fffffff }
        return cashFallback[h % cashFallback.count]
    }
    static let wealthLines: [Color] = [0x34D399, 0x60A5FA, 0xF472B6, 0xFBBF24, 0xA78BFA, 0xFB7185, 0x2DD4BF, 0x818CF8].map { Color(hex: $0) }
}

private func holdingsDouble(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }

private struct HoldingsDot: View {
    let color: Color
    var body: some View { Circle().fill(color).frame(width: 10, height: 10) }
}

/// Horizontal stacked bar; `scale` is the value that fills the full width.
struct HoldingsHBar: View {
    let segments: [(value: Double, color: Color)]
    let scale: Double
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                    Rectangle().fill(s.color).frame(width: scale > 0 ? max(0, geo.size.width * s.value / scale) : 0)
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: 10, alignment: .leading)
            .background(RColors.variant, in: Capsule())
            .clipShape(Capsule())
        }.frame(height: 10)
    }
}

private struct HoldingsDonut: View {
    let slices: [(label: String, value: Double, color: Color)]
    var body: some View {
        Chart(Array(slices.enumerated()), id: \.offset) { _, s in
            SectorMark(angle: .value("Value", max(0, s.value)), innerRadius: .ratio(0.62), angularInset: 1).foregroundStyle(s.color)
        }
        .frame(width: 150, height: 150)
        .accessibilityHidden(true)
    }
}

private struct HoldingsGainText: View {
    let gain: Decimal, pct: Decimal?, ccy: String, hide: Bool
    var size: CGFloat = 12
    var body: some View {
        let arrow = gain >= 0 ? "▲" : "▼"
        let text = hide ? Fmt.hidden : Fmt.signedMoney(gain, ccy) + (pct.map { " \(arrow) \(Fmt.percent(abs($0), scale: 2))" } ?? "")
        Num(text, color: RColors.pnl(gain), size: size)
    }
}

// MARK: sectors

struct HoldingsHomeSectorsContent: View {
    let rows: [HoldingRow]
    let ccy: String
    @Environment(\.hideBalances) private var hide
    @State private var picked: String?

    var body: some View {
        let sectors = HoldingsSectors.build(rows)
        if !sectors.isEmpty {
            let current = sectors.first { $0.sector == picked }
            let total = sectors.reduce(Decimal(0)) { $0 + $1.value }
            VStack(alignment: .leading, spacing: 6) {
                if let current { detail(current) } else { overview(sectors, total) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func overview(_ sectors: [HoldingsSectorRow], _ total: Decimal) -> some View {
        Muted("\(sectors.count) sectors · listed total \(Fmt.money(total, ccy, hide: hide, scale: 0)). Tap a sector to see its holdings.")
        HStack { Spacer(); HoldingsDonut(slices: sectors.enumerated().map { i, s in (s.sector, holdingsDouble(s.value), HoldingsPalette.sectorPie[i % HoldingsPalette.sectorPie.count]) }); Spacer() }
        ForEach(Array(sectors.enumerated()), id: \.offset) { i, s in
            Button { picked = s.sector } label: {
                HStack(alignment: .center, spacing: 8) {
                    HoldingsDot(color: HoldingsPalette.sectorPie[i % HoldingsPalette.sectorPie.count])
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.sector).font(.system(size: 13)).foregroundStyle(RColors.text)
                        Muted(Fmt.plural(s.holdings.count, "holding"))
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Num(Fmt.money(s.value, ccy, hide: hide), size: 12)
                        HoldingsGainText(gain: s.gain, pct: s.gainPct, ccy: ccy, hide: hide, size: 11)
                        Num(Fmt.percent(s.allocPct, scale: 1), color: RColors.muted, size: 11)
                    }
                }
                .padding(.vertical, 7).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sector_\(s.sector)")
        }
    }

    @ViewBuilder private func detail(_ cur: HoldingsSectorRow) -> some View {
        Button { picked = nil } label: {
            HStack(spacing: 0) {
                Text("← Back").font(.system(size: 13)).foregroundStyle(RColors.accent)
                Muted("   Portfolio / \(cur.sector)")
                Spacer(minLength: 0)
            }.padding(.bottom, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("sector_back")
        HStack { Spacer(); HoldingsDonut(slices: cur.holdings.enumerated().map { i, h in (h.ticker, holdingsDouble(h.value), HoldingsPalette.sectorPie[i % HoldingsPalette.sectorPie.count]) }); Spacer() }
        if cur.holdings.isEmpty { Muted("No listed holdings in this sector.") }
        ForEach(Array(cur.holdings.enumerated()), id: \.offset) { i, h in
            HStack(alignment: .center, spacing: 8) {
                HoldingsDot(color: HoldingsPalette.sectorPie[i % HoldingsPalette.sectorPie.count])
                VStack(alignment: .leading, spacing: 1) {
                    Num(h.ticker, size: 13, bold: true)
                    if let n = h.name { Muted(n) }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Num(Fmt.money(h.value, ccy, hide: hide), size: 12)
                    HoldingsGainText(gain: h.gain, pct: h.cost > 0 ? holdingsRound(h.gain * 100 / h.cost, 2) : nil, ccy: ccy, hide: hide, size: 11)
                    Num(Fmt.percent(h.shareOfSectorPct, scale: 1) + " of sector", color: RColors.muted, size: 11)
                }
            }.padding(.vertical, 6)
        }
    }
}

// MARK: position size

struct HoldingsHomePositionSizeContent: View {
    let rows: [HoldingRow]
    let ccy: String
    @Environment(\.hideBalances) private var hide
    @State private var showAll = false

    var body: some View {
        let bars = HoldingsPositionBars.build(rows)
        if !bars.isEmpty {
            let shown = showAll ? bars : Array(bars.prefix(12))
            let scale = bars.map { holdingsDouble(max($0.value, $0.cost)) }.max() ?? 0
            VStack(alignment: .leading, spacing: 6) {
                Muted("\(Fmt.plural(bars.count, "position")), largest value first. Blue = value that is cost, green = gain, red = loss (the part of cost that is gone). Scale in \(ccy).")
                ForEach(Array(shown.enumerated()), id: \.offset) { _, b in
                    let cost = holdingsDouble(b.cost), value = holdingsDouble(b.value)
                    let segs: [(value: Double, color: Color)] = {
                        if b.cost <= 0 { return [(value, RColors.chart[0])] }
                        if b.pnl >= 0 { return [(min(cost, value), RColors.chart[0]), (max(value - cost, 0), RColors.gain)] }
                        return [(value, RColors.chart[0]), (max(cost - value, 0), RColors.loss)]
                    }()
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Num(b.ticker, size: 12, bold: true); Spacer(); Num(Fmt.money(b.value, ccy, hide: hide), size: 12) }
                        HoldingsHBar(segments: segs, scale: scale)
                        HStack { Muted("Cost \(Fmt.money(b.cost, ccy, hide: hide, scale: 0))"); Spacer(); Num(Fmt.signedMoney(b.pnl, ccy, hide: hide), color: RColors.pnl(b.pnl), size: 11) }
                    }.padding(.vertical, 4)
                }
                if bars.count > 12 {
                    Chip(text: showAll ? "Show top 12" : "Show all \(bars.count)", selected: false) { showAll.toggle() }.accessibilityIdentifier("position_show_all")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: net worth by broker

struct HoldingsHomeCustodianContent: View {
    let rows: [HoldingRow]
    let ccy: String
    @Environment(\.hideBalances) private var hide
    @State private var open: Set<String> = []

    var body: some View {
        let list = HoldingsCustodian.build(rows)
        if !list.isEmpty {
            let grand = list.reduce(Decimal(0)) { $0 + $1.total }
            let maxTotal = list.map { holdingsDouble($0.total) }.max() ?? 0
            VStack(alignment: .leading, spacing: 6) {
                Muted("\(Fmt.plural(list.count, "institution")) · total \(Fmt.money(grand, ccy, hide: hide)). One bar per broker; tap for the listed and cash split by account type.")
                ForEach(list, id: \.name) { r in
                    let isOpen = open.contains(r.name)
                    Button { if isOpen { open.remove(r.name) } else { open.insert(r.name) } } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(r.name).font(.system(size: 13, weight: .medium)).foregroundStyle(RColors.text); Spacer(minLength: 8); Num(Fmt.money(r.total, ccy, hide: hide), size: 12) }
                            HoldingsHBar(segments: Self.segments(r), scale: maxTotal)
                            Muted("\(Fmt.percent(holdingsRound(r.total * 100 / grand, 1), scale: 1)) of net worth \(isOpen ? "▲" : "▼")")
                            if isOpen { breakdown(r) }
                        }
                        .padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("custodian_\(r.name)")
                }
                HStack { Muted("Grand total"); Spacer(); Num(Fmt.money(grand, ccy, hide: hide), size: 13, bold: true) }.padding(.top, 6)
                legend(list).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func segments(_ r: HoldingsCustodianRow) -> [(value: Double, color: Color)] {
        var out: [(value: Double, color: Color)] = []
        for k in HoldingsCustodian.wrapperKeys { if let v = r.wrappers[k], v > 0 { out.append((holdingsDouble(v), HoldingsPalette.wrapper[k] ?? HoldingsPalette.otherAssets)) } }
        if r.property > 0 { out.append((holdingsDouble(r.property), HoldingsPalette.property)) }
        let cash = r.cashByAccount.isEmpty ? (r.cash > 0 ? [HoldingsNamedAmount(account: "Other", value: r.cash)] : []) : r.cashByAccount
        for c in holdingsStableSorted(cash, { $0.account.utf16.lexicographicallyPrecedes($1.account.utf16) }) { out.append((holdingsDouble(c.value), HoldingsPalette.cashColor(c.account))) }
        if r.other > 0 { out.append((holdingsDouble(r.other), HoldingsPalette.otherAssets)) }
        return out
    }

    @ViewBuilder private func breakdown(_ r: HoldingsCustodianRow) -> some View {
        if r.equity > 0 { line("Listed", r.equity, r.listedByAccount.map { ("Listed · \($0.account)", $0.value, HoldingsPalette.wrapper[$0.account]) }) }
        if r.property > 0 { line("Property", r.property, []) }
        if r.cash > 0 { line("Cash", r.cash, r.cashByAccount.map { ("Cash · \($0.account)", $0.value, HoldingsPalette.cashColor($0.account)) }) }
        if r.other > 0 { line("Other assets", r.other, []) }
    }

    @ViewBuilder private func line(_ title: String, _ total: Decimal, _ parts: [(String, Decimal, Color?)]) -> some View {
        HStack { Muted(title); Spacer(); Num(Fmt.money(total, ccy, hide: hide), size: 12) }.padding(.top, 4)
        ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
            HStack(spacing: 6) {
                HoldingsDot(color: p.2 ?? HoldingsPalette.otherAssets); Muted(p.0); Spacer()
                Num(Fmt.money(p.1, ccy, hide: hide), color: RColors.muted, size: 11)
            }.padding(.leading, 12)
        }
    }

    private func legend(_ list: [HoldingsCustodianRow]) -> some View {
        let wrappers = HoldingsCustodian.wrapperKeys.filter { k in list.contains { ($0.wrappers[k] ?? 0) > 0 } }
        var cashSet: [String] = []
        for r in list {
            for c in r.cashByAccount where !cashSet.contains(c.account) { cashSet.append(c.account) }
            if r.cashByAccount.isEmpty && r.cash > 0 && !cashSet.contains("Other") { cashSet.append("Other") }
        }
        let cash = cashSet.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        return VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(wrappers, id: \.self) { w in legendItem(HoldingsPalette.wrapper[w] ?? HoldingsPalette.otherAssets, "Listed · \(w)") }
                    if list.contains(where: { $0.property > 0 }) { legendItem(HoldingsPalette.property, "Property") }
                    if list.contains(where: { $0.other > 0 }) { legendItem(HoldingsPalette.otherAssets, "Other assets") }
                }
            }
            if !cash.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) { ForEach(cash, id: \.self) { legendItem(HoldingsPalette.cashColor($0), "Cash · \($0)") } }
                }
            }
        }
    }

    private func legendItem(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 5) { HoldingsDot(color: c); Muted(text).fixedSize() }
    }
}

// MARK: wealth over time

/// Loads the manual wealth series. The Home shell can use `isVisible` / `summary(hide:)` to hide the whole section until a line qualifies.
@MainActor
final class HoldingsHomeWealthLoader: ObservableObject {
    private let loader: CachedLoader<HoldingsWealthSeries>
    private var bag: AnyCancellable?

    init(repo: Repository) {
        loader = CachedLoader(read: { await repo.holdingsWealthCached() }, fetch: { try await repo.holdingsWealth() })
        bag = loader.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var state: LoadState<HoldingsWealthSeries> { loader.state }
    var series: HoldingsWealthSeries? { loader.state.data?.value }
    func load() { loader.load() }
    func refresh() async { await loader.refresh() }
    func reload() { loader.reload() }

    /// True once a line qualifies (5+ updates over 1+ year by default); the section is hidden until then.
    var isVisible: Bool { HoldingsWealthMath.visible(series) }
    func summary(hide: Bool) -> String? { HoldingsHomeSummaries.wealth(series, hide: hide) }
}

struct HoldingsHomeWealthContent: View {
    @StateObject private var loader: HoldingsHomeWealthLoader
    @Environment(\.hideBalances) private var hide
    @State private var filter: HoldingsWealthFilter = .all
    @State private var sel: Int?

    init(repo: Repository) { _loader = StateObject(wrappedValue: HoldingsHomeWealthLoader(repo: repo)) }
    /// Share a loader with the shell so the section is fetched once.
    init(loader: HoldingsHomeWealthLoader) { _loader = StateObject(wrappedValue: loader) }

    var body: some View {
        content
            .task { loader.load() }
    }

    @ViewBuilder private var content: some View {
        if let data = loader.series, HoldingsWealthMath.visible(data) {
            let chart = HoldingsWealthMath.chart(data, filter)
            let ineligible = HoldingsWealthMath.ineligibleCount(data)
            VStack(alignment: .leading, spacing: 6) {
                Muted("Property, cash savings and other manual assets (\(data.minSnapshotsForChart)+ updates over \(data.minHoldDaysForChart / 365)+ year). Separate from listed equity.")
                HStack(spacing: 8) {
                    ForEach(HoldingsWealthFilter.allCases, id: \.self) { f in
                        Chip(text: f.label, selected: filter == f) { sel = nil; filter = f }.accessibilityIdentifier("wealth_filter_\(f.idSuffix)")
                    }
                }
                if hide {
                    Muted("Hidden while balances are hidden.")
                } else if chart.lines.isEmpty {
                    Muted("No lines match this filter.")
                } else {
                    let pick = min(max(sel ?? (chart.dates.count - 1), 0), chart.dates.count - 1)
                    HoldingsWealthChartView(chart: chart, pick: pick) { sel = $0 }
                    Text(chart.dates[pick]).font(.system(size: 15, weight: .semibold)).foregroundStyle(RColors.text)
                    ForEach(Array(chart.lines.enumerated()), id: \.offset) { i, l in
                        HStack(spacing: 6) {
                            HoldingsDot(color: HoldingsPalette.wealthLines[i % HoldingsPalette.wealthLines.count]); Muted(l.name); Spacer()
                            Num(Fmt.money(l.values[pick], data.baseCurrency, hide: hide, scale: 0), size: 12)
                        }
                    }
                }
                if ineligible > 0 { Muted("\(ineligible) line\(ineligible == 1 ? "" : "s") still building history.").padding(.top, 6) }
                Muted("Manual property (net equity), cash savings and other assets. Broker cash is excluded. Opt a line out under Holdings → Edit values.").padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HoldingsWealthChartView: View {
    let chart: HoldingsWealthChart
    let pick: Int
    var onPick: (Int) -> Void
    @State private var dragIndex: Int?

    var body: some View {
        let points: [(line: String, idx: Int, value: Double, color: Int)] = chart.lines.enumerated().flatMap { i, l in
            l.values.enumerated().map { (l.name, $0.offset, holdingsDouble($0.element), i) }
        }
        let names = chart.lines.map { $0.name }
        let colors = chart.lines.indices.map { HoldingsPalette.wealthLines[$0 % HoldingsPalette.wealthLines.count] }
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Date", p.idx), y: .value("Value", p.value), series: .value("Line", p.line)).foregroundStyle(by: .value("Line", p.line))
            }
            RuleMark(x: .value("Selected", pick)).foregroundStyle(RColors.muted.opacity(0.6))
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(1, chart.dates.count - 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel {
                    if let i = v.as(Int.self), i >= 0, i < chart.dates.count { Text(String(chart.dates[i].suffix(5))).font(.system(size: 10)).foregroundStyle(RColors.muted) }
                }
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.compact(d)).font(.system(size: 10)).foregroundStyle(RColors.muted) } }
                AxisGridLine().foregroundStyle(RColors.variant)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        let origin = geo[proxy.plotAreaFrame].origin
                        if let x: Double = proxy.value(atX: g.location.x - origin.x) {
                            onPick(min(max(Int(x.rounded()), 0), chart.dates.count - 1))
                        }
                    })
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Wealth over time")
    }
}
