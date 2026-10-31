import Foundation

struct Health: Equatable { var status = ""; var app = ""; var version = ""; var gitSha: String? }
extension Health: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        status = f.str("status") ?? ""; app = f.str("app") ?? ""; version = f.str("version") ?? ""; gitSha = f.str("git_sha")
    }
}

struct TokenResponse: Equatable { var accessToken = ""; var tokenType = "bearer" }
extension TokenResponse: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        accessToken = f.str("access_token") ?? ""; tokenType = f.str("token_type") ?? "bearer"
    }
}

struct Me: Equatable {
    var id = 0; var email = ""; var username = ""; var role = "user"; var baseCurrency = "GBP"; var snaptradeConfigured = false
}
extension Me: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        id = f.int("id") ?? 0; email = f.str("email") ?? ""; username = f.str("username") ?? ""; role = f.str("role") ?? "user"
        baseCurrency = f.str("base_currency") ?? "GBP"; snaptradeConfigured = f.bool("snaptrade_configured") ?? false
    }
}

struct SectorSlice: Equatable { var sector = ""; var valueBase: Decimal?; var weightPct: Decimal? }
extension SectorSlice: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        sector = f.str("sector") ?? ""; valueBase = f.dec("value_base"); weightPct = f.dec("weight_pct")
    }
}

struct BreakdownSlice: Equatable { var bucket = ""; var valueBase: Decimal?; var weightPct: Decimal? }
extension BreakdownSlice: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        bucket = f.str("bucket") ?? ""; valueBase = f.dec("value_base"); weightPct = f.dec("weight_pct")
    }
}

struct HoldingRow: Equatable {
    var ticker = ""
    var instrumentName: String?
    var source = ""
    var brokerLabel: String?
    var accountKind: String?
    var sector: String?
    var assetKind: String?
    var manualHoldingId: Int?
    var snaptradeAccountId: String?
    var brokerAccountRef: String?
    var quantity: Decimal?
    var avgPrice: Decimal?
    var currentPrice: Decimal?
    var currency: String?
    var marketValueBase: Decimal?
    var costBase: Decimal?
    var pnlStockBase: Decimal?
    var peRatio: Decimal?
    var dividendYield: Decimal?
    var roe: Decimal?
    var debtToEquity: Decimal?
    var profitMargin: Decimal?
    var pbRatio: Decimal?
    var pegRatio: Decimal?
    var priceToSales: Decimal?
    var revenue: Decimal?
    var pnlCurrencyEffect: Decimal?
    var costBaseGbp: Decimal?
    var fxToBase: Decimal?
    var manualBrokerName: String?
    var quoteType: String?
    var purchaseDate: String?
    var soldOutAt: String?
}
extension HoldingRow: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        ticker = f.str("ticker") ?? ""; instrumentName = f.str("instrument_name"); source = f.str("source") ?? ""
        brokerLabel = f.str("broker_label"); accountKind = f.str("account_kind"); sector = f.str("sector"); assetKind = f.str("asset_kind")
        manualHoldingId = f.int("manual_holding_id"); snaptradeAccountId = f.str("snaptrade_account_id"); brokerAccountRef = f.str("broker_account_ref")
        quantity = f.dec("quantity"); avgPrice = f.dec("avg_price"); currentPrice = f.dec("current_price"); currency = f.str("currency")
        marketValueBase = f.dec("market_value_base"); costBase = f.dec("cost_base"); pnlStockBase = f.dec("pnl_stock_base")
        peRatio = f.dec("pe_ratio"); dividendYield = f.dec("dividend_yield"); roe = f.dec("roe"); debtToEquity = f.dec("debt_to_equity")
        profitMargin = f.dec("profit_margin"); pbRatio = f.dec("pb_ratio"); pegRatio = f.dec("peg_ratio"); priceToSales = f.dec("price_to_sales")
        revenue = f.dec("revenue"); pnlCurrencyEffect = f.dec("pnl_currency_effect"); costBaseGbp = f.dec("cost_base_gbp"); fxToBase = f.dec("fx_to_base")
        manualBrokerName = f.str("manual_broker_name"); quoteType = f.str("quote_type"); purchaseDate = f.str("purchase_date"); soldOutAt = f.str("sold_out_at")
    }
}

struct Dashboard: Equatable {
    var baseCurrency = "GBP"
    var totalMarketValueBase: Decimal?
    var totalCostBase: Decimal?
    var totalPnlBase: Decimal?
    var totalRealisedPnlBase: Decimal?
    var portfolioXirrAnnual: Decimal?
    var portfolioXirrNote: String?
    var dividendIncomeTotalBase: Decimal?
    var dividendIncomeBrokerCashBase: Decimal?
    var sectorAllocation: [SectorSlice] = []
    var rows: [HoldingRow] = []
    var netWorthTotalBase: Decimal?
    var netWorthBreakdown: [BreakdownSlice] = []
    var tickerMapAttentionCount = 0
    var manualBasisIncompleteCount = 0
    var nonEquityManualGainTotalBase: Decimal?
    var nonEquityManualBasisLines = 0
    var nonEquityManualAnnualizedPct: Decimal?
    var brokerListedMarketValueBase: Decimal?
    var manualListedMarketValueBase: Decimal?
    var listedEodCloseAsOf: String?
    var asOf: String?
}
extension Dashboard: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        baseCurrency = f.str("base_currency") ?? "GBP"
        totalMarketValueBase = f.dec("total_market_value_base"); totalCostBase = f.dec("total_cost_base"); totalPnlBase = f.dec("total_pnl_base")
        totalRealisedPnlBase = f.dec("total_realised_pnl_base"); portfolioXirrAnnual = f.dec("portfolio_xirr_annual"); portfolioXirrNote = f.str("portfolio_xirr_note")
        dividendIncomeTotalBase = f.dec("dividend_income_total_base"); dividendIncomeBrokerCashBase = f.dec("dividend_income_broker_cash_base")
        sectorAllocation = f.list("sector_allocation"); rows = f.list("rows")
        netWorthTotalBase = f.dec("net_worth_total_base"); netWorthBreakdown = f.list("net_worth_breakdown")
        tickerMapAttentionCount = f.int("ticker_map_attention_count") ?? 0; manualBasisIncompleteCount = f.int("manual_basis_incomplete_count") ?? 0
        nonEquityManualGainTotalBase = f.dec("non_equity_manual_gain_total_base"); nonEquityManualBasisLines = f.int("non_equity_manual_basis_lines") ?? 0
        nonEquityManualAnnualizedPct = f.dec("non_equity_manual_annualized_pct")
        brokerListedMarketValueBase = f.dec("broker_listed_market_value_base"); manualListedMarketValueBase = f.dec("manual_listed_market_value_base")
        listedEodCloseAsOf = f.str("listed_eod_close_as_of"); asOf = f.str("as_of")
    }
}
