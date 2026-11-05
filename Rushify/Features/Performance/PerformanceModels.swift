import Foundation

// DTOs for api/portfolio/growth, benchmarks and dividend-dashboard. Lenient like Models.swift; money is Decimal.

private extension Fields {
    func performanceDouble(_ k: String) -> Double? {
        if let v = (try? c.decodeIfPresent(Double.self, forKey: AnyKey(k))) ?? nil { return v }
        return str(k).flatMap { Double($0) }
    }
}

struct PerformanceGrowthBroker: Equatable {
    var brokerLabel = ""
    var listedEquityMvEndBase: Decimal?
    var investedCapitalEndBase: Decimal?
}
extension PerformanceGrowthBroker: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        brokerLabel = f.str("broker_label") ?? ""; listedEquityMvEndBase = f.dec("listed_equity_mv_end_base"); investedCapitalEndBase = f.dec("invested_capital_end_base")
    }
}

struct PerformancePurchaseEvent: Equatable { var ticker = ""; var label: String?; var source = "" }
extension PerformancePurchaseEvent: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        ticker = f.str("ticker") ?? ""; label = f.str("label"); source = f.str("source") ?? ""
    }
}

struct PerformanceGrowthPeriod: Equatable {
    var label = ""
    var periodStart: String?
    var capitalGainBase: Decimal?
    var priceGainBase: Decimal?
    var interactionGainBase: Decimal?
    var incomeBase: Decimal?
    var currencyGainBase: Decimal?
    var totalGrowthBase: Decimal?
    var listedEquityMvEndBase: Decimal?
    var investedCapitalEndBase: Decimal?
    var purchaseEvents: [PerformancePurchaseEvent] = []
    var brokers: [PerformanceGrowthBroker] = []
}
extension PerformanceGrowthPeriod: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        label = f.str("label") ?? ""; periodStart = f.str("period_start")
        capitalGainBase = f.dec("capital_gain_base"); priceGainBase = f.dec("price_gain_base"); interactionGainBase = f.dec("interaction_gain_base")
        incomeBase = f.dec("income_base"); currencyGainBase = f.dec("currency_gain_base"); totalGrowthBase = f.dec("total_growth_base")
        listedEquityMvEndBase = f.dec("listed_equity_mv_end_base"); investedCapitalEndBase = f.dec("invested_capital_end_base")
        purchaseEvents = f.list("purchase_events"); brokers = f.list("brokers")
    }
}

struct PerformanceEquityDailyPoint: Equatable {
    var asOf = ""
    var listedEquityMvEndBase: Decimal?
    var investedCapitalEndBase: Decimal?
    var brokers: [PerformanceGrowthBroker] = []
}
extension PerformanceEquityDailyPoint: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        asOf = f.str("as_of") ?? ""; listedEquityMvEndBase = f.dec("listed_equity_mv_end_base"); investedCapitalEndBase = f.dec("invested_capital_end_base")
        brokers = f.list("brokers")
    }
}

struct PerformanceGrowth: Equatable {
    var baseCurrency = "GBP"
    var granularity = "monthly"
    var periods: [PerformanceGrowthPeriod] = []
    var note: String?
    var compact = false
    var equityDaily: [PerformanceEquityDailyPoint]?
}
extension PerformanceGrowth: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        baseCurrency = f.str("base_currency") ?? "GBP"; granularity = f.str("granularity") ?? "monthly"
        periods = f.list("periods"); note = f.str("note"); compact = f.bool("compact") ?? false
        let daily: [PerformanceEquityDailyPoint]? = f.obj("equity_daily"); equityDaily = daily
    }
}

struct PerformanceBenchmarkPoint: Equatable {
    var date = ""
    var portfolioIndex: Double?
    var ftse100Index: Double?
    var sp100Index: Double?
}
extension PerformanceBenchmarkPoint: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        date = f.str("date") ?? ""; portfolioIndex = f.performanceDouble("portfolio_index")
        ftse100Index = f.performanceDouble("ftse100_index"); sp100Index = f.performanceDouble("sp100_index")
    }
}

struct PerformanceBenchmarks: Equatable {
    var range = "month"
    var baseCurrency = "GBP"
    var portfolioReturnPct: Decimal?
    var ftse100ReturnPct: Decimal?
    var sp100ReturnPct: Decimal?
    var periodTotalPnlBase: Decimal?
    var periodPricePnlBase: Decimal?
    var periodFxPnlBase: Decimal?
    var periodCrossPnlBase: Decimal?
    var series: [PerformanceBenchmarkPoint] = []
    var emptyPortfolio = false
}
extension PerformanceBenchmarks: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        range = f.str("range") ?? "month"; baseCurrency = f.str("base_currency") ?? "GBP"
        portfolioReturnPct = f.dec("portfolio_return_pct"); ftse100ReturnPct = f.dec("ftse100_return_pct"); sp100ReturnPct = f.dec("sp100_return_pct")
        periodTotalPnlBase = f.dec("period_total_pnl_base"); periodPricePnlBase = f.dec("period_price_pnl_base")
        periodFxPnlBase = f.dec("period_fx_pnl_base"); periodCrossPnlBase = f.dec("period_cross_pnl_base")
        series = f.list("series"); emptyPortfolio = f.bool("empty_portfolio") ?? false
    }
}

struct PerformanceDividendLayer: Equatable { var ticker = ""; var layer = "actual"; var amountBase: Decimal? }
extension PerformanceDividendLayer: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        ticker = f.str("ticker") ?? ""; layer = f.str("layer") ?? "actual"; amountBase = f.dec("amount_base")
    }
}

struct PerformanceDividendPoint: Equatable {
    var label = ""
    var kind = "historical"
    var totalBase: Decimal?
    var growthPctPrior: Decimal?
    var forecastZone = false
    var layers: [PerformanceDividendLayer] = []
}
extension PerformanceDividendPoint: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        label = f.str("label") ?? ""; kind = f.str("kind") ?? "historical"; totalBase = f.dec("total_base"); growthPctPrior = f.dec("growth_pct_prior")
        forecastZone = f.bool("forecast_zone") ?? false; layers = f.list("layers")
    }
}

struct PerformanceDividends: Equatable {
    var baseCurrency = "GBP"
    var granularity = "monthly"
    var forecastMethod: String?
    var note: String?
    var series: [PerformanceDividendPoint] = []
    var symbols: [String] = []
}
extension PerformanceDividends: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        baseCurrency = f.str("base_currency") ?? "GBP"; granularity = f.str("granularity") ?? "monthly"
        forecastMethod = f.str("forecast_method"); note = f.str("note"); series = f.list("series"); symbols = f.list("symbols")
    }
}

// MARK: Endpoints and cache keys (as Android: growth:g:n, growth-daily:g:n:b1|b2, benchmarks:mode:n, dividends:g:n:sym|all)

enum PerformanceQuery {
    private static func q(_ n: String, _ v: String) -> URLQueryItem { URLQueryItem(name: n, value: v) }

    /// Android always sends compact (false unless daily); equity_brokers repeats once per broker.
    static func growth(_ granularity: String, _ count: Int) -> [URLQueryItem] {
        [q("granularity", granularity), q("count", String(count)), q("compact", "false")]
    }
    static func growthDaily(_ granularity: String, _ count: Int, brokers: [String]) -> [URLQueryItem] {
        [q("granularity", granularity), q("count", String(count)), q("compact", "true"), q("equity_series_step", "daily")] + brokers.map { q("equity_brokers", $0) }
    }
    /// `range` for day/week, otherwise granularity + count; never both.
    static func benchmarks(_ mode: String, _ count: Int) -> [URLQueryItem] {
        mode == "day" || mode == "week" ? [q("range", mode)] : [q("granularity", mode), q("count", String(count))]
    }
    static func dividends(_ granularity: String, _ count: Int, symbol: String?) -> [URLQueryItem] {
        [q("granularity", granularity), q("history_count", String(count))] + (symbol.map { [q("symbol", $0)] } ?? [])
    }
}

extension Repository {
    private func performanceDailyKey(_ g: String, _ n: Int, _ brokers: [String]) -> String { "growth-daily:\(g):\(n):\(brokers.sorted().joined(separator: "|"))" }

    func performanceGrowthCached(_ g: String, _ n: Int) async -> Cached<PerformanceGrowth>? { await cached("growth:\(g):\(n)") }
    func performanceGrowth(_ g: String, _ n: Int) async throws -> Cached<PerformanceGrowth> {
        try await refresh("growth:\(g):\(n)", path: "api/portfolio/growth", query: PerformanceQuery.growth(g, n)) { (x: PerformanceGrowth) in x.periods.isEmpty }
    }

    /// Daily listed-equity points (compact), optionally limited to some brokers. Cached per selection.
    func performanceGrowthDailyCached(_ g: String, _ n: Int, brokers: [String]) async -> Cached<PerformanceGrowth>? {
        await cached(performanceDailyKey(g, n, brokers))
    }
    func performanceGrowthDaily(_ g: String, _ n: Int, brokers: [String]) async throws -> Cached<PerformanceGrowth> {
        try await refresh(performanceDailyKey(g, n, brokers), path: "api/portfolio/growth", query: PerformanceQuery.growthDaily(g, n, brokers: brokers)) { (x: PerformanceGrowth) in
            (x.equityDaily ?? []).isEmpty
        }
    }

    func performanceBenchmarksCached(_ mode: String, _ n: Int) async -> Cached<PerformanceBenchmarks>? { await cached("benchmarks:\(mode):\(n)") }
    func performanceBenchmarks(_ mode: String, _ n: Int) async throws -> Cached<PerformanceBenchmarks> {
        try await refresh("benchmarks:\(mode):\(n)", path: "api/portfolio/benchmarks", query: PerformanceQuery.benchmarks(mode, n)) { (x: PerformanceBenchmarks) in x.series.isEmpty }
    }

    func performanceDividendsCached(_ g: String, _ n: Int, symbol: String?) async -> Cached<PerformanceDividends>? {
        await cached("dividends:\(g):\(n):\(symbol ?? "all")")
    }
    func performanceDividends(_ g: String, _ n: Int, symbol: String?) async throws -> Cached<PerformanceDividends> {
        try await refresh("dividends:\(g):\(n):\(symbol ?? "all")", path: "api/portfolio/dividend-dashboard", query: PerformanceQuery.dividends(g, n, symbol: symbol)) { (x: PerformanceDividends) in x.series.isEmpty }
    }
}
