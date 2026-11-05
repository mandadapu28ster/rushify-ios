import Foundation

// Rollup + manual-wealth DTOs (GET api/portfolio/holdings-rollups, api/portfolio/manual-wealth-series). Lenient like Models.swift.

struct HoldingsDividendByCurrency: Equatable { var currency = ""; var amount: Decimal? }
extension HoldingsDividendByCurrency: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        currency = f.str("currency") ?? ""; amount = f.dec("amount")
    }
}

/// One broker account's local-history totals (fills, fees, payouts, XIRR).
struct HoldingsRollupAccount: Equatable {
    var source = ""
    var accountRef = ""
    var displayLabel: String?
    var fillRowCount = 0
    var realisedGainBaseSum: Decimal?
    var dividendPayoutCount = 0
    var dividendPayoutBaseSum: Decimal?
    var interestOnCashBaseSum: Decimal?
    var combinedBrokerPayoutBaseSum: Decimal?
    var unrealisedPnlBaseSum: Decimal?
    var listedInvestmentsMvBaseSum: Decimal?
    var xirrAnnual: Decimal?
    var xirrNote: String?
    var fillTaxBaseSum: Decimal?
    var fillFxFeesBaseSum: Decimal?
    var fillBrokerFeesBaseSum: Decimal?
}
extension HoldingsRollupAccount: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        source = f.str("source") ?? ""; accountRef = f.str("account_ref") ?? ""; displayLabel = f.str("display_label")
        fillRowCount = f.int("fill_row_count") ?? 0; realisedGainBaseSum = f.dec("realised_gain_base_sum")
        dividendPayoutCount = f.int("dividend_payout_count") ?? 0; dividendPayoutBaseSum = f.dec("dividend_payout_base_sum")
        interestOnCashBaseSum = f.dec("interest_on_cash_base_sum"); combinedBrokerPayoutBaseSum = f.dec("combined_broker_payout_base_sum")
        unrealisedPnlBaseSum = f.dec("unrealised_pnl_base_sum"); listedInvestmentsMvBaseSum = f.dec("listed_investments_mv_base_sum")
        xirrAnnual = f.dec("xirr_annual"); xirrNote = f.str("xirr_note")
        fillTaxBaseSum = f.dec("fill_tax_base_sum"); fillFxFeesBaseSum = f.dec("fill_fx_fees_base_sum"); fillBrokerFeesBaseSum = f.dec("fill_broker_fees_base_sum")
    }
}

/// One instrument inside an account. `exposure` is open_full, open_partial or closed_history.
struct HoldingsRollupLine: Equatable {
    var source = ""
    var accountRef = ""
    var brokerTicker: String?
    var yahooTicker: String?
    var displayTicker: String?
    var openQuantity: Decimal?
    var exposure = ""
    var buyFillQty: Decimal?
    var sellFillQty: Decimal?
    var fillRowCount = 0
    var fifoRealisedBase: Decimal?
    var fillTaxBaseSum: Decimal?
    var fillFxFeesBaseSum: Decimal?
    var fillBrokerFeesBaseSum: Decimal?
    var instrumentName: String?
    var dividendPayoutCount = 0
    var dividendsByCurrency: [HoldingsDividendByCurrency] = []
    var dividendPayoutBaseSum: Decimal?
}
extension HoldingsRollupLine: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        source = f.str("source") ?? ""; accountRef = f.str("account_ref") ?? ""; brokerTicker = f.str("broker_ticker")
        yahooTicker = f.str("yahoo_ticker"); displayTicker = f.str("display_ticker"); openQuantity = f.dec("open_quantity")
        exposure = f.str("exposure") ?? ""; buyFillQty = f.dec("buy_fill_qty"); sellFillQty = f.dec("sell_fill_qty")
        fillRowCount = f.int("fill_row_count") ?? 0; fifoRealisedBase = f.dec("fifo_realised_base")
        fillTaxBaseSum = f.dec("fill_tax_base_sum"); fillFxFeesBaseSum = f.dec("fill_fx_fees_base_sum"); fillBrokerFeesBaseSum = f.dec("fill_broker_fees_base_sum")
        instrumentName = f.str("instrument_name"); dividendPayoutCount = f.int("dividend_payout_count") ?? 0
        dividendsByCurrency = f.list("dividends_by_currency"); dividendPayoutBaseSum = f.dec("dividend_payout_base_sum")
    }
}

struct HoldingsRollups: Equatable { var lines: [HoldingsRollupLine] = []; var accounts: [HoldingsRollupAccount] = [] }
extension HoldingsRollups: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        lines = f.list("lines"); accounts = f.list("accounts")
    }
}

struct HoldingsWealthSnapshot: Equatable { var asOf = ""; var valueGbp: Decimal?; var source = "" }
extension HoldingsWealthSnapshot: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        asOf = f.str("as_of") ?? ""; valueGbp = f.dec("value_gbp"); source = f.str("source") ?? ""
    }
}

struct HoldingsWealthAsset: Equatable {
    var manualHoldingId = 0
    var label = ""
    var assetKind = ""
    var showOnWealthChart = true
    var snapshotCount = 0
    var chartEligible = false
    var exited = false
    var snapshots: [HoldingsWealthSnapshot] = []
}
extension HoldingsWealthAsset: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        manualHoldingId = f.int("manual_holding_id") ?? 0; label = f.str("label") ?? ""; assetKind = f.str("asset_kind") ?? ""
        showOnWealthChart = f.bool("show_on_wealth_chart") ?? true; snapshotCount = f.int("snapshot_count") ?? 0
        chartEligible = f.bool("chart_eligible") ?? false; exited = f.bool("exited") ?? false; snapshots = f.list("snapshots")
    }
}

struct HoldingsWealthSeries: Equatable {
    var baseCurrency = "GBP"
    var minSnapshotsForChart = 5
    var minHoldDaysForChart = 365
    var assets: [HoldingsWealthAsset] = []
}
extension HoldingsWealthSeries: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        baseCurrency = f.str("base_currency") ?? "GBP"; minSnapshotsForChart = f.int("min_snapshots_for_chart") ?? 5
        minHoldDaysForChart = f.int("min_hold_days_for_chart") ?? 365; assets = f.list("assets")
    }
}

extension Repository {
    func holdingsRollupsCached() async -> Cached<HoldingsRollups>? { await cached("rollups") }
    func holdingsRollups() async throws -> Cached<HoldingsRollups> {
        try await refresh("rollups", path: "api/portfolio/holdings-rollups") { (r: HoldingsRollups) in r.lines.isEmpty && r.accounts.isEmpty }
    }
    func holdingsWealthCached() async -> Cached<HoldingsWealthSeries>? { await cached("manual-wealth") }
    func holdingsWealth() async throws -> Cached<HoldingsWealthSeries> {
        try await refresh("manual-wealth", path: "api/portfolio/manual-wealth-series")
    }
}
