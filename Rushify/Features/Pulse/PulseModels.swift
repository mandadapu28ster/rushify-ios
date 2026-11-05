import Foundation

// MARK: Radar

struct PulseRadarDimension: Equatable { var key = ""; var label = ""; var score = 0; var coveragePct = 0 }
extension PulseRadarDimension: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        key = f.str("key") ?? ""; label = f.str("label") ?? ""; score = f.int("score") ?? 0; coveragePct = f.int("coverage_pct") ?? 0
    }
}

struct PulseRadarNote: Equatable { var kind = ""; var text = "" }
extension PulseRadarNote: Decodable {
    init(from decoder: Decoder) throws { let f = try Fields(decoder); kind = f.str("kind") ?? ""; text = f.str("text") ?? "" }
}

struct PulseRadarAccount: Equatable { var key = ""; var label = ""; var listedMvBase: Decimal?; var positionCount = 0 }
extension PulseRadarAccount: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        key = f.str("key") ?? ""; label = f.str("label") ?? ""; listedMvBase = f.dec("listed_mv_base"); positionCount = f.int("position_count") ?? 0
    }
}

struct PulseRadarBucket: Equatable { var key = ""; var label = ""; var stockCount = 0; var mvPct = 0; var tickers: [String] = [] }
extension PulseRadarBucket: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        key = f.str("key") ?? ""; label = f.str("label") ?? ""; stockCount = f.int("stock_count") ?? 0; mvPct = f.int("mv_pct") ?? 0
        tickers = f.list("tickers")
    }
}

struct PulseRadar: Equatable {
    var scopeKey = "overall"; var scopeLabel = ""
    var headline: String?; var summary: String?
    var healthScore: Decimal?; var healthMax: Decimal?
    var dimensions: [PulseRadarDimension] = []
    var rewards: [PulseRadarNote] = []; var risks: [PulseRadarNote] = []
    var accounts: [PulseRadarAccount] = []
    var ratingBuckets: [PulseRadarBucket] = []
    var positionCount = 0; var coveredPositionCount = 0
    var scoredMvPct = 100; var indexFundMvPct = 0; var notCoveredMvPct = 0
    var listedMvBase: Decimal?
    var baseCurrency = "GBP"
    var message: String?
}
extension PulseRadar: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        scopeKey = f.str("scope_key") ?? "overall"; scopeLabel = f.str("scope_label") ?? ""
        headline = f.str("headline"); summary = f.str("summary")
        healthScore = f.dec("health_score"); healthMax = f.dec("health_max")
        dimensions = f.list("dimensions"); rewards = f.list("rewards"); risks = f.list("risks"); accounts = f.list("accounts")
        ratingBuckets = f.list("rating_buckets")
        positionCount = f.int("position_count") ?? 0; coveredPositionCount = f.int("covered_position_count") ?? 0
        scoredMvPct = f.int("scored_mv_pct") ?? 100; indexFundMvPct = f.int("index_fund_mv_pct") ?? 0; notCoveredMvPct = f.int("not_covered_mv_pct") ?? 0
        listedMvBase = f.dec("listed_mv_base"); baseCurrency = f.str("base_currency") ?? "GBP"; message = f.str("message")
    }
}

// MARK: News

struct PulseNewsItem: Equatable {
    var id = 0; var symbol: String?; var source: String?; var title = ""; var url: String?
    var publisher: String?; var publishedAt: String?; var summary: String?
}
extension PulseNewsItem: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        id = f.int("id") ?? 0; symbol = f.str("symbol"); source = f.str("source"); title = f.str("title") ?? ""; url = f.str("url")
        publisher = f.str("publisher"); publishedAt = f.str("published_at"); summary = f.str("summary")
    }
}

struct PulseNewsGroup: Equatable {
    var key = ""; var symbol: String?; var label = ""; var companyName: String?; var headlineCount = 0; var items: [PulseNewsItem] = []
}
extension PulseNewsGroup: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        key = f.str("key") ?? ""; symbol = f.str("symbol"); label = f.str("label") ?? ""; companyName = f.str("company_name")
        headlineCount = f.int("headline_count") ?? 0; items = f.list("items")
    }
}

struct PulseNews: Equatable {
    var groups: [PulseNewsGroup] = []; var lastSyncedAt: String?; var stale = false; var cachedOnly = false
    var symbols: [String] = []; var message: String?
}
extension PulseNews: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        groups = f.list("groups"); lastSyncedAt = f.str("last_synced_at"); stale = f.bool("stale") ?? false
        cachedOnly = f.bool("cached_only") ?? false; symbols = f.list("symbols"); message = f.str("message")
    }
}

// MARK: Watchlists

struct PulseWatchItem: Equatable {
    var id = 0; var yahooSymbol = ""; var companyName: String?; var exchange: String?; var industry: String?; var currency: String?
    var fetchNews = false; var addedAt: String?
    var priceAtAdd: Decimal?; var lastPrice: Decimal?; var changePct: Decimal?
    var week52High: Decimal?; var week52Low: Decimal?
    var peRatio: Decimal?; var forwardPeRatio: Decimal?; var industryPeMedian: Decimal?; var industryPbMedian: Decimal?
    var industryPeerCount = 0
    var pbRatio: Decimal?; var pegRatio: Decimal?; var priceToSales: Decimal?; var revenueGrowthPct: Decimal?
    var eps: Decimal?; var roe: Decimal?; var profitMargin: Decimal?; var debtToEquity: Decimal?; var netCash: Decimal?; var marketCap: Decimal?
    var dividendYield: Decimal?
    var quoteType: String?; var dataFetchedAt: String?
}
extension PulseWatchItem: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        id = f.int("id") ?? 0; yahooSymbol = f.str("yahoo_symbol") ?? ""; companyName = f.str("company_name"); exchange = f.str("exchange")
        industry = f.str("industry"); currency = f.str("currency"); fetchNews = f.bool("fetch_news") ?? false; addedAt = f.str("added_at")
        priceAtAdd = f.dec("price_at_add"); lastPrice = f.dec("last_price"); changePct = f.dec("change_pct")
        week52High = f.dec("week52_high"); week52Low = f.dec("week52_low")
        peRatio = f.dec("pe_ratio"); forwardPeRatio = f.dec("forward_pe_ratio")
        industryPeMedian = f.dec("industry_pe_median"); industryPbMedian = f.dec("industry_pb_median")
        industryPeerCount = f.int("industry_peer_count") ?? 0
        pbRatio = f.dec("pb_ratio"); pegRatio = f.dec("peg_ratio"); priceToSales = f.dec("price_to_sales")
        revenueGrowthPct = f.dec("revenue_growth_pct"); eps = f.dec("eps"); roe = f.dec("roe"); profitMargin = f.dec("profit_margin")
        debtToEquity = f.dec("debt_to_equity"); netCash = f.dec("net_cash"); marketCap = f.dec("market_cap")
        dividendYield = f.dec("dividend_yield"); quoteType = f.str("quote_type"); dataFetchedAt = f.str("data_fetched_at")
    }
}

struct PulseWatchlist: Equatable { var id = 0; var name = ""; var items: [PulseWatchItem] = [] }
extension PulseWatchlist: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        id = f.int("id") ?? 0; name = f.str("name") ?? ""; items = f.list("items")
    }
}

struct PulseWatchCache: Equatable { var allFresh = false; var cacheHours = 2 }
extension PulseWatchCache: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        allFresh = f.bool("all_fresh") ?? false; cacheHours = f.int("cache_hours") ?? 2
    }
}

struct PulseWatchlists: Equatable {
    var watchlists: [PulseWatchlist] = []
    var maxWatchlists = 5; var maxItemsPerWatchlist = 30; var limitsUnlimited = false
    var cache = PulseWatchCache()
}
extension PulseWatchlists: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        watchlists = f.list("watchlists"); maxWatchlists = f.int("max_watchlists") ?? 5
        maxItemsPerWatchlist = f.int("max_items_per_watchlist") ?? 30
        limitsUnlimited = f.bool("watchlist_limits_unlimited") ?? false
        cache = f.obj("cache") ?? PulseWatchCache()
    }
}

/// Reply of POST /pulse/watchlists/refresh. A summary, not a watchlist.
struct PulseWatchlistRefresh: Equatable { var refreshed = 0; var skipped = 0; var errors: [String] = []; var cacheHours = 2; var allFresh = false }
extension PulseWatchlistRefresh: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        refreshed = f.int("refreshed") ?? 0; skipped = f.int("skipped") ?? 0; errors = f.list("errors")
        cacheHours = f.int("cache_hours") ?? 2; allFresh = f.bool("all_fresh") ?? false
    }
}
