import Foundation

// Pure logic behind the Performance screen (ports of PeriodOptions, GrowthMath, BenchmarkMath, EquityTrend, DividendStacks, DividendMath).

private func performanceRound(_ v: Decimal, _ scale: Int) -> Decimal {
    var x = v, out = Decimal()
    NSDecimalRound(&out, &x, scale, .plain)
    return out
}

/// Fixed decimals, no grouping, no "-0.00".
func performanceFixed(_ v: Decimal, _ scale: Int) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.numberStyle = .decimal; f.usesGroupingSeparator = false
    f.minimumFractionDigits = scale; f.maximumFractionDigits = scale; f.roundingMode = .halfUp
    return f.string(from: NSDecimalNumber(decimal: performanceRound(v, scale))) ?? "0"
}

/// Period choices, identical to the web toolbars (Growth/Benchmarks: 6/12/18/24 months or 3/5/8/10 years; Dividends history is wider).
enum PerformancePeriodOptions {
    static func growth(_ granularity: String) -> [Int] { granularity == "yearly" ? [3, 5, 8, 10] : [6, 12, 18, 24] }
    static func dividends(_ granularity: String) -> [Int] { granularity == "yearly" ? [3, 4, 5, 8, 10, 15] : [6, 12, 18, 24, 36] }
    /// Switching Monthly/Yearly resets to the web default: 12 months or 5 years.
    static func `default`(_ granularity: String) -> Int { granularity == "yearly" ? 5 : 12 }
    static func label(_ granularity: String, _ n: Int) -> String { granularity == "yearly" ? "\(n) yr" : "\(n) mo" }
}

struct PerformanceGrowthSummary: Equatable {
    var total: Decimal, price: Decimal, interaction: Decimal, income: Decimal, currency: Decimal
    /// "12.3% of total", or a dash when the total is about zero.
    func share(_ part: Decimal) -> String {
        if abs(total) < Decimal(string: "0.000000001")! { return Fmt.dash }
        return performanceFixed(part * 100 / total, 1) + "% of total"
    }
}

enum PerformanceGrowthMath {
    static func summary(_ periods: [PerformanceGrowthPeriod]) -> PerformanceGrowthSummary {
        func sum(_ f: (PerformanceGrowthPeriod) -> Decimal?) -> Decimal { periods.reduce(0) { $0 + (f($1) ?? 0) } }
        return PerformanceGrowthSummary(total: sum { $0.totalGrowthBase }, price: sum { $0.priceGainBase }, interaction: sum { $0.interactionGainBase },
                                        income: sum { $0.incomeBase }, currency: sum { $0.currencyGainBase })
    }

    static func stackSum(_ p: PerformanceGrowthPeriod) -> Decimal {
        (p.priceGainBase ?? 0) + (p.interactionGainBase ?? 0) + (p.incomeBase ?? 0) + (p.currencyGainBase ?? 0)
    }

    /// The readout only mentions the stack sum when rounding makes it differ from the period total by more than 0.02.
    static func stackDiffers(_ p: PerformanceGrowthPeriod) -> Bool { abs(stackSum(p) - (p.totalGrowthBase ?? 0)) > Decimal(string: "0.02")! }

    static let interactionNote = "Each bar splits the period into pieces. Price is the effect of share-price moves while exchange rates are fixed at the start of that month or year. " +
        "Currency is the effect of exchange-rate moves while prices are fixed at the start. In real life both move together, so those two pieces do not add up to the exact change " +
        "in your portfolio value; the difference is Interaction. It is not extra money on top of the other parts; it is the remainder so the coloured segments add up to the total. " +
        "It often looks larger when you hold overseas stocks or assets in another currency."
}

enum PerformanceBenchmarkMath {
    /// Portfolio return minus index return, in percentage points; nil when either is missing.
    static func points(_ portfolio: Decimal?, _ index: Decimal?) -> Decimal? {
        guard let portfolio, let index else { return nil }
        return portfolio - index
    }
    static func pointsText(_ v: Decimal?) -> String {
        guard let v else { return Fmt.dash }
        return (v >= 0 ? "+" : "") + performanceFixed(v, 2) + " pp"
    }
    static func verdict(_ v: Decimal?, _ indexName: String) -> String? {
        guard let v else { return nil }
        return v >= 0 ? "Portfolio total return exceeded \(indexName) over the same dates." : "Portfolio total return trailed \(indexName) over the same dates."
    }
    /// Index value as the readout shows it ("%.2f").
    static func indexText(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? Fmt.dash }
}

// MARK: Listed equity over time (per broker lines)

struct PerformanceEquityPoint: Equatable {
    var label: String
    var mv: Decimal?
    var invested: Decimal?
    var brokers: [PerformanceGrowthBroker] = []
}
struct PerformanceEquityLine: Equatable {
    var name: String
    var values: [Decimal?]
    var dashed: Bool
    var colorIndex: Int
    var isTotal: Bool
}
struct PerformanceEquitySeries: Equatable { var lines: [PerformanceEquityLine]; var deltaMv: Decimal? }

enum PerformanceEquityTrend {
    static func isPartial(_ selected: Set<String>, _ all: [String]) -> Bool { selected.count < Set(all).count && !selected.isEmpty }

    /// Per selected broker a market-value line and a dashed book-cost line, plus (optional) totals.
    /// Totals are the aggregate fields when every broker is selected, else the sum over the selected brokers.
    static func series(_ points: [PerformanceEquityPoint], selected: Set<String>, allLabels: [String], totals: Bool) -> PerformanceEquitySeries {
        let partial = isPartial(selected, allLabels)
        var chosen = allLabels.filter { selected.contains($0) }
        if chosen.isEmpty { chosen = allLabels }
        var lines: [PerformanceEquityLine] = []
        if totals {
            let mv = points.map { p in partial ? sel(p, chosen) { $0.listedEquityMvEndBase } : p.mv }
            let bk = points.map { p in partial ? sel(p, chosen) { $0.investedCapitalEndBase } : p.invested }
            lines.append(PerformanceEquityLine(name: partial ? "MV (selected)" : "MV", values: mv, dashed: false, colorIndex: -1, isTotal: true))
            lines.append(PerformanceEquityLine(name: partial ? "Book (selected)" : "Book", values: bk, dashed: true, colorIndex: -2, isTotal: true))
        }
        for (i, label) in chosen.enumerated() {
            lines.append(PerformanceEquityLine(name: "\(label) · mv", values: points.map { p in p.brokers.first { $0.brokerLabel == label }?.listedEquityMvEndBase }, dashed: false, colorIndex: i, isTotal: false))
            lines.append(PerformanceEquityLine(name: "\(label) · book", values: points.map { p in p.brokers.first { $0.brokerLabel == label }?.investedCapitalEndBase }, dashed: true, colorIndex: i, isTotal: false))
        }
        let totalMv = lines.first { $0.isTotal && !$0.dashed }?.values ?? points.map { p in partial ? sel(p, chosen) { $0.listedEquityMvEndBase } : p.mv }
        let first = totalMv.compactMap { $0 }.first, last = totalMv.compactMap { $0 }.last
        return PerformanceEquitySeries(lines: lines, deltaMv: (first != nil && last != nil) ? last! - first! : nil)
    }

    private static func sel(_ p: PerformanceEquityPoint, _ chosen: [String], _ f: (PerformanceGrowthBroker) -> Decimal?) -> Decimal? {
        let parts = p.brokers.filter { chosen.contains($0.brokerLabel) }.compactMap(f)
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }
}

/// Chart label for the listed-equity broker picker: brokers that hold (or once held) listed equity.
enum PerformanceBrokerLabels {
    static func listedEquity(_ rows: [HoldingRow]) -> [String] {
        func blank(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var seen: [String] = []
        for r in rows {
            if let k = r.assetKind, k != "listed" { continue }
            let qty = r.quantity ?? 0
            let soldOutManual = r.source == "manual" && (!blank(r.soldOutAt) || (qty <= 0 && r.manualHoldingId != nil))
            let openManual = r.source == "manual" && r.manualHoldingId != nil && qty > 0 && blank(r.soldOutAt)
            if !soldOutManual && !openManual {
                guard let mv = r.marketValueBase, mv > 0 else { continue }
            }
            let lbl = (r.brokerLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !lbl.isEmpty && !seen.contains(lbl) { seen.append(lbl) }
        }
        return seen.enumerated().sorted {
            let c = $0.element.caseInsensitiveCompare($1.element)
            return c == .orderedSame ? $0.offset < $1.offset : c == .orderedAscending
        }.map { $0.element }
    }
}

// MARK: Dividends

struct PerformanceDividendBar: Equatable {
    var label: String, kind: String
    var total: Decimal
    var actual: [Decimal], forecast: [Decimal]
    var forecastZone: Bool
}
struct PerformanceDividendStackData: Equatable { var tickers: [String]; var bars: [PerformanceDividendBar]; var average: Decimal? }

enum PerformanceDividendStacks {
    private static let top = 5

    /// Segments are the biggest payers over the whole range (top 5) plus "Other", in a fixed order so a ticker keeps its colour.
    /// Each bar keeps actual and estimated amounts apart; the average is the mean total of bars outside the forecast zone.
    static func build(_ series: [PerformanceDividendPoint]) -> PerformanceDividendStackData {
        var order: [String] = [], totals: [String: Decimal] = [:]
        for p in series { for l in p.layers {
            if totals[l.ticker] == nil { order.append(l.ticker) }
            totals[l.ticker, default: 0] += l.amountBase ?? 0
        } }
        let topTickers = order.enumerated().sorted { (totals[$0.element]!, $1.offset) > (totals[$1.element]!, $0.offset) }.prefix(top).map { $0.element }
        let tickers = order.count > top ? topTickers + ["Other"] : topTickers
        func slot(_ t: String) -> Int { topTickers.contains(t) ? tickers.firstIndex(of: t)! : tickers.count - 1 }
        let bars = series.map { p -> PerformanceDividendBar in
            var actual = [Decimal](repeating: 0, count: tickers.count), forecast = actual
            for l in p.layers {
                let i = slot(l.ticker), a = l.amountBase ?? 0
                if l.layer == "forecast" { forecast[i] += a } else { actual[i] += a }
            }
            return PerformanceDividendBar(label: p.label, kind: p.kind, total: p.totalBase ?? 0, actual: actual, forecast: forecast, forecastZone: p.forecastZone || p.kind == "forecast_forward")
        }
        let hist = bars.filter { !$0.forecastZone }
        var avg: Decimal?
        if !hist.isEmpty { avg = performanceRound(hist.reduce(0) { $0 + $1.total } / Decimal(hist.count), 2) }
        return PerformanceDividendStackData(tickers: tickers, bars: bars, average: avg)
    }
}

enum PerformanceDividendMath {
    /// Short x-axis label; the server's "Next 6 mo est." is too wide for a bar slot.
    static func axisLabel(_ p: PerformanceDividendPoint) -> String { p.kind == "forecast_forward" ? "Next 6m" : p.label }

    struct Summary: Equatable { var received: Decimal; var forecast: Decimal }

    static func summary(_ d: PerformanceDividends) -> Summary {
        var received: Decimal = 0, forecast: Decimal = 0
        for p in d.series {
            let v = p.totalBase ?? 0
            if p.kind == "forecast_forward" { forecast += v } else { received += v }
        }
        return Summary(received: received, forecast: forecast)
    }

    /// Largest per-ticker amounts in one period, summing actual + forecast layers.
    static func topContributors(_ p: PerformanceDividendPoint, _ n: Int) -> [(ticker: String, amount: Decimal)] {
        var order: [String] = [], sums: [String: Decimal] = [:]
        for l in p.layers {
            if sums[l.ticker] == nil { order.append(l.ticker) }
            sums[l.ticker, default: 0] += l.amountBase ?? 0
        }
        return order.enumerated().filter { sums[$0.element]! > 0 }
            .sorted { (sums[$0.element]!, $1.offset) > (sums[$1.element]!, $0.offset) }
            .prefix(n).map { ($0.element, sums[$0.element]!) }
    }
}
