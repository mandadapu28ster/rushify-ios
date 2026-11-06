import Foundation

/*
 Pure logic behind the Home insight sections (net worth by broker, sectors, position size, wealth over time),
 ported from InsightsLogic.kt. No UI types here.
 */

/// Rounds half away from zero (Java HALF_UP) to `scale` decimal places.
func holdingsRound(_ v: Decimal, _ scale: Int) -> Decimal {
    var x = v, out = Decimal()
    NSDecimalRound(&out, &x, scale, .plain)
    return out
}

private func holdingsPctOf(_ v: Decimal, _ total: Decimal) -> Decimal { total == 0 ? 0 : holdingsRound(v * 100 / total, 2) }

// MARK: Net worth by broker

struct HoldingsNamedAmount: Equatable { var account: String; var value: Decimal }

struct HoldingsCustodianRow: Equatable {
    var name: String
    var equity: Decimal, cash: Decimal, property: Decimal, other: Decimal
    var listedByAccount: [HoldingsNamedAmount]
    var cashByAccount: [HoldingsNamedAmount]
    /// Listed equity split by account wrapper, keys: Invest, ISA, SIPP, LISA, JISA, JSIPP, Other.
    var wrappers: [String: Decimal]
    var total: Decimal { equity + cash + property + other }
}

enum HoldingsCustodian {
    static let wrapperKeys = ["Invest", "ISA", "SIPP", "LISA", "JISA", "JSIPP", "Other"]

    static func institutionLabelForReport(_ raw: String) -> String {
        let t = raw.holdingsTrimmed
        return t == "Manual entry" ? "No institution name" : (t.isEmpty ? "Other" : t)
    }

    private static let suffixRe = holdingsRegex("\\s*\\((?:csv|import)\\)\\s*$", ignoreCase: true)
    private static func peelBrokerLabelSuffix(_ raw: String) -> String {
        suffixRe.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "").holdingsTrimmed
    }

    private static let wrapperA = holdingsRegex("^(ISA|SIPP|Invest|GIA|Unspecified|LISA|JISA|JSIPP|TFSA|RRSP|RESP|RRIF|LIF|LIRA|401\\(k\\)|403\\(b\\)|457\\(b\\)|Roth IRA|Traditional IRA|SEP IRA|HSA|Margin|Joint|Trust|Corporate|UGMA|UTMA)$", ignoreCase: true)
    private static let wrapperB = holdingsRegex("^(lifetime\\s*isa|cash\\s*isa|stocks\\s*(and|&)\\s*shares\\s*isa|flexible\\s*isa|help\\s*to\\s*buy\\s*isa|innovation\\s*isa|junior\\s*isa|junior\\s*sipp)$", ignoreCase: true)

    private static func isWrapperSuffix(_ suffix: String) -> Bool {
        let last = peelBrokerLabelSuffix(suffix)
        return !last.isEmpty && (holdingsFullMatch(wrapperA, last) || holdingsFullMatch(wrapperB, last))
    }

    private static let trailing = [
        "\\s+stocks\\s+and\\s+shares\\s+isa$", "\\s+cash\\s+isa$", "\\s+lifetime\\s+isa$", "\\s+flexible\\s+isa$", "\\s+junior\\s+isa$", "\\s+junior\\s+sipp$",
        "\\s+(invest|isa|sipp|lisa|jisa|jsipp|gia)$",
    ].map { holdingsRegex($0, ignoreCase: true) }

    private static func peelTrailingWrapper(_ name: String) -> String {
        let t = name.holdingsTrimmed
        for p in trailing {
            if let m = p.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), m.range.location > 0, let r = Range(m.range, in: t) {
                return String(t[t.startIndex..<r.lowerBound]).holdingsTrimmed
            }
        }
        return t
    }

    private static func institutionFromBrokerLabel(_ bl: String, _ source: String?) -> String {
        let parts = holdingsSplitDot(bl)
        if parts.count >= 2 {
            let last = parts[parts.count - 1].holdingsTrimmed
            let head = parts.dropLast().joined(separator: " · ")
            if isWrapperSuffix(last) { return institutionLabelForReport(head) }
            if source == "snaptrade" || source == "csv" { return institutionLabelForReport(head) }
        }
        return institutionLabelForReport(peelTrailingWrapper(bl))
    }

    private static let t212Prefix = holdingsRegex("^Trading 212\\s+", ignoreCase: true)

    /// One bar per broker/bank: "Trading 212 · ISA" -> "Trading 212".
    static func institutionKey(_ r: HoldingRow) -> String {
        switch r.assetKind { case "real_estate": return "Property"; case "other": return "Other assets"; default: break }
        let manual = (r.manualBrokerName ?? "").holdingsTrimmed
        if !manual.isEmpty {
            if manual.contains("·") { return institutionFromBrokerLabel(manual, r.source) }
            if t212Prefix.firstMatch(in: manual, range: NSRange(manual.startIndex..., in: manual)) != nil { return institutionLabelForReport(peelTrailingWrapper(manual)) }
            return institutionLabelForReport(manual)
        }
        let bl = (r.brokerLabel ?? "").holdingsTrimmed
        if bl.isEmpty {
            switch r.source {
            case "t212": return institutionLabelForReport("Trading 212")
            case "snaptrade": return institutionLabelForReport("SnapTrade")
            default: let s = r.source.holdingsTrimmed; return institutionLabelForReport(s.isEmpty ? "Other" : s)
            }
        }
        return institutionFromBrokerLabel(bl, r.source)
    }

    /// Wrapper bucket for listed equity (detail and stack colours).
    static func listedAccountLabel(_ r: HoldingRow) -> String {
        if let k = r.assetKind, k != "listed" { return "" }
        switch (r.accountKind ?? "").holdingsTrimmed.lowercased() {
        case "isa": return "ISA"; case "sipp": return "SIPP"; case "invest": return "Invest"; case "lisa": return "LISA"; case "jisa": return "JISA"; case "jsipp": return "JSIPP"
        case "lifetime_isa", "lifetimeisa": return "LISA"
        case "cash_isa", "cashisa", "flexible_isa", "flexibleisa", "help_to_buy_isa", "innovation_isa", "stocks_and_shares_isa", "stocksandsharesisa": return "ISA"
        case "junior_isa", "juniorisa": return "JISA"
        case "junior_sipp", "juniorsipp": return "JSIPP"
        default: return "Other"
        }
    }

    /// Cash bucket: broker cash by account kind; manual cash by the account part of "Bank · account type".
    static func cashBucketLabel(_ r: HoldingRow) -> String {
        if r.assetKind != "cash" { return "" }
        if r.source != "manual" {
            let k = (r.accountKind ?? "").holdingsTrimmed.lowercased()
            switch k {
            case "current": return "Current account"; case "joint": return "Joint account"; case "young": return "Young account"; case "rewards": return "Rewards"
            case "savings": return "Savings"; case "pot": return "Pot"; case "isa": return "ISA"; case "cash_isa": return "Cash ISA"; case "sipp": return "SIPP"
            case "invest": return "Invest"; case "lisa": return "LISA"; case "jisa": return "JISA"; case "jsipp": return "JSIPP"
            default: break
            }
            if !k.isEmpty { let t = k.replacingOccurrences(of: "_", with: " ").holdingsTrimmed; return t.isEmpty ? "Other" : t }
        }
        let raw = (r.instrumentName ?? "").holdingsTrimmed
        if raw.isEmpty { return "Other" }
        let parts = holdingsSplitDot(raw)
        if parts.count >= 2 { let l = parts[parts.count - 1].holdingsTrimmed; return l.isEmpty ? "Other" : l }
        return raw
    }

    static func isOpenManualListed(_ r: HoldingRow) -> Bool {
        (r.assetKind == nil || r.assetKind == "listed") && r.source == "manual" && r.manualHoldingId != nil
            && (r.quantity ?? 0) > 0 && (r.soldOutAt ?? "").holdingsTrimmed.isEmpty
    }

    /// Quoted MV when positive; an open manual lot without a quote falls back to cost, then average price x quantity x FX.
    static func marketValue(_ r: HoldingRow) -> Decimal {
        if let mv = r.marketValueBase, mv > 0 { return mv }
        if !isOpenManualListed(r) { return 0 }
        for c in [r.costBase, r.costBaseGbp] { if let c, c > 0 { return c } }
        let qty = r.quantity ?? 0
        if let avg = r.avgPrice, avg > 0, qty > 0 {
            let fx = (r.fxToBase.map { $0 > 0 ? $0 : nil } ?? nil) ?? 1
            return avg * qty * fx
        }
        return 0
    }

    private struct Acc {
        var equity: Decimal = 0, cash: Decimal = 0, property: Decimal = 0, other: Decimal = 0
        var listed: [(String, Decimal)] = [], cashBy: [(String, Decimal)] = []
        static func merge(_ list: inout [(String, Decimal)], _ k: String, _ v: Decimal) {
            if let i = list.firstIndex(where: { $0.0 == k }) { list[i].1 += v } else { list.append((k, v)) }
        }
    }

    static func build(_ rows: [HoldingRow]) -> [HoldingsCustodianRow] {
        var order: [String] = []
        var map: [String: Acc] = [:]
        for r in rows {
            let mv = marketValue(r)
            if mv <= 0 { continue }
            let key = institutionKey(r)
            if map[key] == nil { order.append(key); map[key] = Acc() }
            var acc = map[key]!
            switch r.assetKind {
            case "cash":
                acc.cash += mv
                let l = cashBucketLabel(r)
                if !l.isEmpty { Acc.merge(&acc.cashBy, l, mv) }
            case "real_estate": acc.property += mv
            case "other": acc.other += mv
            case nil, "listed":
                acc.equity += mv; Acc.merge(&acc.listed, listedAccountLabel(r), mv)
            default: break
            }
            map[key] = acc
        }
        func detail(_ m: [(String, Decimal)], _ total: Decimal) -> [HoldingsNamedAmount] {
            if total <= 0 { return [] }
            let list = holdingsStableSorted(m.filter { $0.1 > 0 }.map { HoldingsNamedAmount(account: $0.0, value: $0.1) }) { $0.value > $1.value }
            return (list.count == 1 && list[0].account == "Other") ? [] : list
        }
        let built: [HoldingsCustodianRow] = order.map { name in
            let a = map[name]!
            var wrappers: [String: Decimal] = [:]
            for k in wrapperKeys { wrappers[k] = a.listed.first(where: { $0.0 == k })?.1 ?? 0 }
            if a.listed.isEmpty && a.equity > 0 { wrappers["Other"] = a.equity }
            return HoldingsCustodianRow(name: name, equity: a.equity, cash: a.cash, property: a.property, other: a.other,
                                        listedByAccount: detail(a.listed, a.equity), cashByAccount: detail(a.cashBy, a.cash), wrappers: wrappers)
        }
        return holdingsStableSorted(built) { $0.total > $1.total }
    }

    /// Brokers that hold (or once held) listed equity, case-insensitively sorted.
    static func listedEquityBrokerLabels(_ rows: [HoldingRow]) -> [String] {
        var seen: [String] = []
        for r in rows {
            if let k = r.assetKind, k != "listed" { continue }
            let qty = r.quantity ?? 0
            let soldOutManual = r.source == "manual" && (!(r.soldOutAt ?? "").holdingsTrimmed.isEmpty || (qty <= 0 && r.manualHoldingId != nil))
            let openManual = r.source == "manual" && r.manualHoldingId != nil && qty > 0 && (r.soldOutAt ?? "").holdingsTrimmed.isEmpty
            if !soldOutManual && !openManual {
                guard let mv = r.marketValueBase, mv > 0 else { continue }
            }
            let lbl = (r.brokerLabel ?? "").holdingsTrimmed
            if !lbl.isEmpty && !seen.contains(lbl) { seen.append(lbl) }
        }
        return holdingsStableSorted(seen) { $0.caseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: Sectors + position bars

struct HoldingsSectorHolding: Equatable { var ticker: String; var name: String?; var value: Decimal; var cost: Decimal; var gain: Decimal; var shareOfSectorPct: Decimal }

struct HoldingsSectorRow: Equatable {
    var sector: String; var value: Decimal; var cost: Decimal; var gain: Decimal; var gainPct: Decimal?
    var allocPct: Decimal; var holdings: [HoldingsSectorHolding]
}

enum HoldingsSectors {
    /// Listed rows only, sector defaults to "Unknown", holdings merge per upper-cased ticker.
    static func isListedPosition(_ r: HoldingRow) -> Bool {
        HoldingsLogic.isListedAssetKind(r.assetKind) && r.source != "monzo" && !r.ticker.hasPrefix("CASH.")
    }

    private struct H { var name: String?; var value: Decimal = 0; var cost: Decimal = 0; var pnl: Decimal? }

    static func build(_ rows: [HoldingRow]) -> [HoldingsSectorRow] {
        var sectorOrder: [String] = []
        var tickerOrder: [String: [String]] = [:]
        var by: [String: [String: H]] = [:]
        for r in rows {
            if !isListedPosition(r) { continue }
            guard let v = r.marketValueBase, v > 0 else { continue }
            let s = (r.sector ?? "").holdingsTrimmed
            let sector = s.isEmpty ? "Unknown" : s
            let t = HoldingsLogic.displayTicker(r, nil).uppercased()
            if by[sector] == nil { by[sector] = [:]; sectorOrder.append(sector); tickerOrder[sector] = [] }
            if by[sector]![t] == nil { by[sector]![t] = H(name: r.instrumentName); tickerOrder[sector]!.append(t) }
            by[sector]![t]!.value += v
            by[sector]![t]!.cost += r.costBase ?? 0
            if let p = r.pnlStockBase { by[sector]![t]!.pnl = (by[sector]![t]!.pnl ?? 0) + p }
        }
        let total = by.values.reduce(Decimal(0)) { $0 + $1.values.reduce(Decimal(0)) { $0 + $1.value } }
        let out: [HoldingsSectorRow] = sectorOrder.map { sector in
            let hs = tickerOrder[sector]!.map { ($0, by[sector]![$0]!) }
            let value = hs.reduce(Decimal(0)) { $0 + $1.1.value }
            let cost = hs.reduce(Decimal(0)) { $0 + $1.1.cost }
            let gain = hs.reduce(Decimal(0)) { $0 + ($1.1.pnl ?? ($1.1.value - $1.1.cost)) }
            let holdings = holdingsStableSorted(hs.map { t, h in
                HoldingsSectorHolding(ticker: t, name: h.name, value: h.value, cost: h.cost, gain: h.pnl ?? (h.value - h.cost), shareOfSectorPct: holdingsPctOf(h.value, value))
            }) { $0.value > $1.value }
            return HoldingsSectorRow(sector: sector, value: value, cost: cost, gain: gain, gainPct: cost > 0 ? holdingsPctOf(gain, cost) : nil,
                                     allocPct: holdingsPctOf(value, total), holdings: holdings)
        }
        return holdingsStableSorted(out) { $0.value > $1.value }
    }
}

struct HoldingsPositionBar: Equatable { var ticker: String; var name: String?; var value: Decimal; var cost: Decimal; var pnl: Decimal }

enum HoldingsPositionBars {
    /// One bar per upper-cased ticker (lots and brokers merged), largest market value first. P/L = value - cost, else the row's own P/L.
    static func build(_ rows: [HoldingRow]) -> [HoldingsPositionBar] {
        struct A { var name: String?; var value: Decimal = 0; var cost: Decimal = 0; var pnl: Decimal = 0 }
        var order: [String] = []
        var by: [String: A] = [:]
        for r in rows {
            if !HoldingsSectors.isListedPosition(r) { continue }
            guard let v = r.marketValueBase, v > 0 else { continue }
            let t = HoldingsLogic.displayTicker(r, nil).uppercased()
            if by[t] == nil { order.append(t); by[t] = A(name: r.instrumentName) }
            by[t]!.value += v
            if let c = r.costBase { by[t]!.cost += c; by[t]!.pnl += v - c } else { by[t]!.pnl += r.pnlStockBase ?? 0 }
        }
        let bars = order.map { t in HoldingsPositionBar(ticker: t, name: by[t]!.name, value: by[t]!.value, cost: by[t]!.cost, pnl: by[t]!.pnl) }
        return holdingsStableSorted(bars) { a, b in
            if a.value != b.value { return a.value > b.value }
            return a.ticker.utf16.lexicographicallyPrecedes(b.ticker.utf16)
        }
    }
}

// MARK: Manual wealth over time

enum HoldingsWealthFilter: CaseIterable {
    case all, cash, property, other
    var label: String { switch self { case .all: return "All"; case .cash: return "Cash"; case .property: return "Property"; case .other: return "Other" } }
    var idSuffix: String { switch self { case .all: return "All"; case .cash: return "Cash"; case .property: return "Property"; case .other: return "Other" } }
}

struct HoldingsWealthChart: Equatable {
    var dates: [String]
    var lines: [(name: String, values: [Decimal])]
    static func == (a: HoldingsWealthChart, b: HoldingsWealthChart) -> Bool {
        a.dates == b.dates && a.lines.count == b.lines.count && zip(a.lines, b.lines).allSatisfy { $0.name == $1.name && $0.values == $1.values }
    }
}

enum HoldingsWealthMath {
    static func eligible(_ d: HoldingsWealthSeries) -> [HoldingsWealthAsset] { d.assets.filter { $0.chartEligible && $0.showOnWealthChart } }
    /// The whole section is hidden unless at least one line qualifies (5+ updates over 1+ year by default).
    static func visible(_ d: HoldingsWealthSeries?) -> Bool { d != nil && !eligible(d!).isEmpty }
    static func ineligibleCount(_ d: HoldingsWealthSeries) -> Int { d.assets.filter { !$0.chartEligible && $0.showOnWealthChart }.count }

    static func chart(_ d: HoldingsWealthSeries, _ filter: HoldingsWealthFilter) -> HoldingsWealthChart {
        let assets = eligible(d).filter {
            switch filter {
            case .all: return true
            case .cash: return $0.assetKind == "cash"
            case .property: return $0.assetKind == "real_estate"
            case .other: return $0.assetKind == "other"
            }
        }
        let dates = Array(Set(assets.flatMap { $0.snapshots.map { $0.asOf } })).sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        // Each line carries its last snapshot forward to every date.
        let lines: [(name: String, values: [Decimal])] = assets.map { a in
            (a.label, dates.map { day in
                var best: HoldingsWealthSnapshot?
                for s in a.snapshots where !day.utf16.lexicographicallyPrecedes(s.asOf.utf16) {   // asOf <= day
                    if best == nil || best!.asOf.utf16.lexicographicallyPrecedes(s.asOf.utf16) { best = s }
                }
                return best?.valueGbp ?? 0
            })
        }
        return HoldingsWealthChart(dates: dates, lines: lines)
    }

    /// Sum of each line's latest value over every eligible line (the section's collapsed total).
    static func totalNow(_ d: HoldingsWealthSeries) -> Decimal { chart(d, .all).lines.reduce(0) { $0 + ($1.values.last ?? 0) } }
}

// MARK: collapsed-summary text (what Android shows while a Home section is closed)

enum HoldingsHomeSummaries {
    static func sectors(rows: [HoldingRow], ccy: String, hide: Bool) -> String? {
        let s = HoldingsSectors.build(rows)
        if s.isEmpty { return nil }
        let total = s.reduce(Decimal(0)) { $0 + $1.value }
        return "\(Fmt.plural(s.count, "sector")) · listed total \(Fmt.money(total, ccy, hide: hide, scale: 0))."
    }

    static func positions(rows: [HoldingRow]) -> String? {
        let bars = HoldingsPositionBars.build(rows)
        if bars.isEmpty { return nil }
        return "\(Fmt.plural(bars.count, "position")) — bars ordered by market value."
    }

    static func custodian(rows: [HoldingRow], ccy: String, hide: Bool) -> String? {
        let list = HoldingsCustodian.build(rows)
        if list.isEmpty { return nil }
        let grand = list.reduce(Decimal(0)) { $0 + $1.total }
        return "\(Fmt.plural(list.count, "institution")) · total \(Fmt.money(grand, ccy, hide: hide))."
    }

    /// The web only asks for the wealth series when manual non-listed lines (property, cash, other) exist.
    static func wealthShouldLoad(rows: [HoldingRow]) -> Bool {
        rows.contains { $0.source == "manual" && $0.manualHoldingId != nil && !HoldingsLogic.isListedAssetKind($0.assetKind) }
    }

    static func wealth(_ d: HoldingsWealthSeries?, hide: Bool) -> String? {
        guard let d, HoldingsWealthMath.visible(d) else { return nil }
        return "\(Fmt.plural(HoldingsWealthMath.eligible(d).count, "line")) · \(Fmt.money(HoldingsWealthMath.totalNow(d), d.baseCurrency, hide: hide, scale: 0)) total."
    }
}
