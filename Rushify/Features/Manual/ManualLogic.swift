import Foundation

/// A calendar day without a time zone (Java's LocalDate). Injectable "today" for the rules and the view model.
struct ManualDay: Comparable, Equatable, Hashable {
    let year: Int, month: Int, day: Int
    init(_ year: Int, _ month: Int, _ day: Int) { self.year = year; self.month = month; self.day = day }

    static func today(_ now: Date = Date(), calendar: Calendar = .current) -> ManualDay {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return ManualDay(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    private static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }
    private static func daysIn(_ y: Int, _ m: Int) -> Int {
        switch m { case 2: return isLeap(y) ? 29 : 28; case 4, 6, 9, 11: return 30; default: return 31 }
    }

    /// Strict ISO yyyy-MM-dd; anything else (or an impossible date) is nil.
    static func parse(_ s: String) -> ManualDay? {
        let u = Array(s.utf8)
        guard u.count == 10, u[4] == 45, u[7] == 45 else { return nil }
        func num(_ r: Range<Int>) -> Int? {
            var v = 0
            for i in r { guard u[i] >= 48, u[i] <= 57 else { return nil }; v = v * 10 + Int(u[i] - 48) }
            return v
        }
        guard let y = num(0..<4), let m = num(5..<7), let d = num(8..<10), (1...12).contains(m), d >= 1, d <= daysIn(y, m) else { return nil }
        return ManualDay(y, m, d)
    }

    func minusYears(_ n: Int) -> ManualDay {
        let y = year - n
        return ManualDay(y, month, min(day, ManualDay.daysIn(y, month)))
    }

    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    static func < (a: ManualDay, b: ManualDay) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
}

/// Outcome of validating a form: the request body to send, or the message the web shows.
/// Bodies are JSONSerialization-ready: decimals are strings, explicit nulls are NSNull, omitted fields are absent.
enum ManualBuilt {
    case ok([String: Any])
    case err(String)
}

enum ManualKind: CaseIterable {
    case listed, property, cash, other
    var label: String {
        switch self { case .listed: return "Stock / ETF"; case .property: return "Home / property"; case .cash: return "Cash savings"; case .other: return "Other asset" }
    }
    var api: String {
        switch self { case .listed: return "listed"; case .property: return "real_estate"; case .cash: return "cash"; case .other: return "other" }
    }
    static func of(_ api: String?) -> ManualKind? { allCases.first { $0.api == api } }
}

/// One row of GET /portfolio/manual (listed lots and non-listed assets the user entered by hand).
struct ManualHoldingOut: Equatable {
    var id = 0
    var assetKind = "listed"
    var symbol: String?
    var label: String?
    var brokerName: String?
    var accountKind: String?
    var quantity: Decimal?
    var currency: String?
    var notes: String?
    var homeValue: Decimal?
    var mortgageBalance: Decimal?
    var cashBalance: Decimal?
    var otherValue: Decimal?
    var purchaseDate: String?
    var costBaseGbp: Decimal?
    var soldOutAt: String?
    var openedDate: String?
    var openingValueGbp: Decimal?
    var exitDate: String?
    var exitValueGbp: Decimal?
    var showOnWealthChart: Bool?
    var snapshotCount: Int?
    var chartEligible: Bool?
}
extension ManualHoldingOut: Decodable {
    init(from decoder: Decoder) throws {
        let f = try Fields(decoder)
        id = f.int("id") ?? 0; assetKind = f.str("asset_kind") ?? "listed"; symbol = f.str("symbol"); label = f.str("label")
        brokerName = f.str("broker_name"); accountKind = f.str("account_kind"); quantity = f.dec("quantity"); currency = f.str("currency"); notes = f.str("notes")
        homeValue = f.dec("home_value"); mortgageBalance = f.dec("mortgage_balance"); cashBalance = f.dec("cash_balance"); otherValue = f.dec("other_value")
        purchaseDate = f.str("purchase_date"); costBaseGbp = f.dec("cost_base_gbp"); soldOutAt = f.str("sold_out_at")
        openedDate = f.str("opened_date"); openingValueGbp = f.dec("opening_value_gbp"); exitDate = f.str("exit_date"); exitValueGbp = f.dec("exit_value_gbp")
        showOnWealthChart = f.bool("show_on_wealth_chart"); snapshotCount = f.int("snapshot_count"); chartEligible = f.bool("chart_eligible")
    }
}

/// Rules ported from the web manual-holdings forms and the backend schemas. Pure, so it is unit tested.
enum ManualRules {
    static let listedCreateKinds: [(value: String, label: String)] = [("sipp", "SIPP"), ("isa", "ISA"), ("invest", "GIA / Invest"), ("lisa", "LISA"), ("jisa", "JISA"), ("jsipp", "JSIPP")]
    /// Edit also allows "unspecified"; the backend rejects "cash_isa" on update, so it is not offered.
    static let listedEditKinds: [(value: String, label: String)] = listedCreateKinds + [("unspecified", "Unspecified")]
    static let cashTypes = [
        "Current account", "Easy-access savings", "Savings account", "Cash ISA", "Lifetime ISA (cash)", "Junior ISA (cash)",
        "Stocks & Shares ISA", "Fixed-term savings", "Premium Bonds", "Other",
    ]
    static let cashOther = "Other"
    static let cashDefault = "Savings account"
    static let sectors = [
        "ETFs & funds", "Technology", "Healthcare", "Financial Services", "Financials", "Consumer Cyclical", "Consumer Defensive",
        "Communication Services", "Industrials", "Energy", "Utilities", "Real Estate", "Basic Materials", "Consumer Staples", "Materials",
    ]

    static let msgListedMissing = "Fill in ticker, qty, broker, account type, purchase date, and total cost in GBP."
    static let msgListedDate = "Purchase date must be between 30 years ago and today (no future dates)."
    static let msgEditBasis = "Purchase date and total GBP cost are required."
    static let msgBroker = "Broker is required."
    private static let msgRequired = "Fill in all required fields for this entry type."
    private static let msgBothExit = "Exit date and exit amount (GBP) must both be set or both left blank."

    private static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Drops currency symbols, spaces and thousands separators the way a user types money.
    static func sanitizeDecimal(_ s: String) -> String { trim(s).replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "£", with: "").replacingOccurrences(of: " ", with: "") }

    /// Strict like Kotlin's toBigDecimalOrNull: the whole text must be a number ("12abc" is not).
    static func parseDec(_ s: String?) -> Decimal? {
        guard let s else { return nil }
        let t = sanitizeDecimal(s)
        if t.isEmpty { return nil }
        guard t.range(of: #"^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: t, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func parseDate(_ s: String?) -> ManualDay? {
        let t = trim(s ?? "")
        return t.count == 10 ? ManualDay.parse(t) : nil
    }

    /// BigDecimal.stripTrailingZeros().toPlainString(): 5000.00 -> "5000", 1E+5 -> "100000", 12.50 -> "12.5".
    static func str(_ d: Decimal) -> String {
        let s = NSDecimalNumber(decimal: d).description(withLocale: nil)
        guard s.contains("E") || s.contains("e") else { return s }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.numberStyle = .decimal; f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 30
        return f.string(from: NSDecimalNumber(decimal: d)) ?? s
    }
    static func plain(_ d: Decimal?) -> String { d.map(str) ?? "" }

    private static func nn(_ s: String?) -> String? { let t = trim(s ?? ""); return t.isEmpty ? nil : t }
    private static func orNull(_ s: String?) -> Any { s ?? NSNull() }
    private static func positive(_ s: String?) -> Decimal? { parseDec(s).flatMap { $0 > 0 ? $0 : nil } }
    private static func nonNegative(_ s: String?) -> Decimal? { parseDec(s).flatMap { $0 >= 0 ? $0 : nil } }
    private static func ccy(_ s: String) -> String { let t = trim(s); return (t.isEmpty ? "GBP" : t).uppercased() }

    static func listedCreate(symbol: String, label: String, qty: String, broker: String, kind: String, purchaseDate: String, cost: String, today: ManualDay) -> ManualBuilt {
        let q = positive(qty), c = parseDec(cost), sym = trim(symbol), br = trim(broker)
        guard !sym.isEmpty, let q, !br.isEmpty, !trim(kind).isEmpty, !trim(purchaseDate).isEmpty, let c else { return .err(msgListedMissing) }
        guard let d = parseDate(purchaseDate), !(d > today), !(d < today.minusYears(30)) else { return .err(msgListedDate) }
        if c < 0 { return .err(msgListedMissing) }
        return .ok([
            "asset_kind": "listed", "symbol": sym, "label": orNull(nn(label)), "quantity": str(q), "broker_name": br,
            "purchase_date": d.iso, "cost_base_gbp": str(c), "account_kind": kind,
        ])
    }

    static func listedEdit(label: String, qty: String, broker: String, kind: String, purchaseDate: String, cost: String, today: ManualDay) -> ManualBuilt {
        guard let q = positive(qty) else { return .err("quantity must be greater than zero") }
        if trim(purchaseDate).isEmpty || parseDec(cost) == nil { return .err(msgEditBasis) }
        if trim(broker).isEmpty { return .err(msgBroker) }
        guard let d = parseDate(purchaseDate), !(d > today), !(d < today.minusYears(30)) else { return .err(msgListedDate) }
        let c = parseDec(cost)!
        return .ok([
            "label": orNull(nn(label)), "quantity": str(q), "broker_name": trim(broker), "purchase_date": d.iso, "cost_base_gbp": str(c),
            "account_kind": (kind == "unspecified" || trim(kind).isEmpty) ? NSNull() : kind as Any,
        ])
    }

    /// Sale of part or all of a manual listed lot. Price is GBP per share (from the contract note).
    static func sell(held: Decimal?, purchaseDate: String?, qty: String, executedAt: String, price: String, today: ManualDay) -> ManualBuilt {
        guard let held, held > 0 else { return .err("Nothing left to sell — this position is already closed") }
        if (purchaseDate?.count ?? 0) < 8 { return .err("Purchase date required before recording a sale. Open Edit lot and set the purchase date first.") }
        if trim(qty).isEmpty { return .err("Quantity sold is required.") }
        guard let q = positive(qty) else { return .err("Enter a valid quantity sold (greater than zero).") }
        if q > held { return .err("Sold quantity cannot exceed current holding (\(str(held))).") }
        if trim(price).isEmpty { return .err("GBP price per share is required.") }
        guard let p = positive(price) else { return .err("Enter the GBP price per share (must be greater than zero).") }
        if trim(executedAt).isEmpty { return .err("Sell date is required.") }
        guard let d = parseDate(executedAt) else { return .err("Sell date must be a date like 2025-01-31.") }
        if d > today { return .err("Sell date cannot be in the future.") }
        if let bought = parseDate(purchaseDate), d < bought { return .err("Sell date cannot be before the lot purchase date") }
        return .ok(["quantity_sold": str(q), "executed_at": d.iso, "price_per_share_gbp": str(p)])
    }

    struct NonListed: Equatable {
        var kind: ManualKind
        var currency = "GBP"
        var notes = ""
        var label = ""
        var broker = ""
        var cashType = ManualRules.cashDefault
        var cashTypeOther = ""
        var homeValue = ""
        var mortgage = ""
        var cashBalance = ""
        var otherValue = ""
        var openedDate = ""
        var openingValue = ""
        var exitDate = ""
        var exitValue = ""
    }

    private static func cashLabel(_ f: NonListed) -> String { f.cashType == cashOther ? trim(f.cashTypeOther) : f.cashType }

    static func nonListedCreate(_ f: NonListed, today: ManualDay) -> ManualBuilt {
        let kind = f.kind
        guard kind != .listed else { return .err("Not a manual non-listed asset.") }
        switch kind {
        case .property:
            if trim(f.label).isEmpty || parseDec(f.homeValue) == nil || parseDec(f.mortgage) == nil { return .err(msgRequired) }
        case .cash:
            if trim(f.broker).isEmpty { return .err("Enter the bank or building society name.") }
            if cashLabel(f).isEmpty { return .err("Choose an account type, or enter a description if you selected Other.") }
            if parseDec(f.cashBalance) == nil { return .err(msgRequired) }
        default:
            if trim(f.label).isEmpty || parseDec(f.otherValue) == nil { return .err(msgRequired) }
        }
        if trim(f.openedDate).isEmpty || trim(f.openingValue).isEmpty { return .err(msgRequired) }
        guard let opened = parseDate(f.openedDate) else { return .err(msgRequired) }
        if opened > today { return .err("Opened date cannot be in the future.") }
        guard let opening = nonNegative(f.openingValue) else { return .err("Enter a valid non-negative opening amount in GBP.") }
        let hasExitDate = !trim(f.exitDate).isEmpty, hasExitValue = !trim(f.exitValue).isEmpty
        if hasExitDate != hasExitValue { return .err(msgBothExit) }
        var exit: ManualDay?, exitValue: Decimal?
        if hasExitDate {
            guard let e = parseDate(f.exitDate) else { return .err(msgBothExit) }
            if e > today { return .err("Exit date cannot be in the future.") }
            if e < opened { return .err("Exit date must be on or after the opened date.") }
            guard let ev = nonNegative(f.exitValue) else { return .err("Enter a valid non-negative exit amount in GBP.") }
            exit = e; exitValue = ev
        }
        var b: [String: Any] = [
            "asset_kind": kind.api, "currency": ccy(f.currency), "notes": orNull(nn(f.notes)),
            "opened_date": opened.iso, "opening_value_gbp": str(opening),
        ]
        if let exit, let exitValue { b["exit_date"] = exit.iso; b["exit_value_gbp"] = str(exitValue) }
        switch kind {
        case .property: b["label"] = trim(f.label); b["home_value"] = str(parseDec(f.homeValue)!); b["mortgage_balance"] = str(parseDec(f.mortgage)!)
        case .cash: b["broker_name"] = trim(f.broker); b["label"] = cashLabel(f); b["cash_balance"] = str(parseDec(f.cashBalance)!)
        default: b["label"] = trim(f.label); b["other_value"] = str(parseDec(f.otherValue)!)
        }
        return .ok(b)
    }

    /// "update" records a new value as of a date; "exit" closes the line. Already-exited lines only change notes/currency/chart flag.
    struct NonListedEdit {
        var form: NonListed
        var exited: Bool
        var showOnChart: Bool
        var mode = "update"
        var updateDate = ""
    }

    static func nonListedEdit(_ e: NonListedEdit, today: ManualDay) -> ManualBuilt {
        let f = e.form
        func common() -> [String: Any] { ["currency": ccy(f.currency), "notes": orNull(nn(f.notes)), "show_on_wealth_chart": e.showOnChart] }
        if e.exited { var b = common(); b["save_mode"] = "update"; return .ok(b) }
        switch f.kind {
        case .cash:
            if trim(f.broker).isEmpty { return .err("Enter the bank or building society name.") }
            if cashLabel(f).isEmpty { return .err("Choose an account type, or enter a description if you selected Other.") }
            if parseDec(f.cashBalance) == nil { return .err(msgRequired) }
        case .property:
            if nonNegative(f.homeValue) == nil || (!trim(f.mortgage).isEmpty && nonNegative(f.mortgage) == nil) { return .err("Enter valid non-negative home and mortgage values.") }
        default:
            if parseDec(f.otherValue) == nil { return .err(msgRequired) }
        }
        let basis = "Opened date and opening amount (GBP) are required."
        if trim(f.openedDate).isEmpty || trim(f.openingValue).isEmpty { return .err(basis) }
        guard let opened = parseDate(f.openedDate) else { return .err(basis) }
        if opened > today { return .err("Opened date cannot be in the future.") }
        guard let opening = nonNegative(f.openingValue) else { return .err("Enter a valid non-negative opening amount in GBP.") }
        var updateDate: ManualDay?, exit: ManualDay?, exitValue: Decimal?
        if e.mode == "exit" {
            if trim(f.exitDate).isEmpty || trim(f.exitValue).isEmpty { return .err("exit_date and exit_value_gbp are required when updating property, cash savings, and other manual assets") }
            guard let x = parseDate(f.exitDate) else { return .err("exit_date and exit_value_gbp must both be set or both omitted") }
            if x > today { return .err("Exit date cannot be in the future.") }
            if x < opened { return .err("Exit date must be on or after the opened date.") }
            guard let xv = nonNegative(f.exitValue) else { return .err("Enter a valid non-negative exit amount in GBP.") }
            exit = x; exitValue = xv
        } else if !trim(e.updateDate).isEmpty {
            guard let u = parseDate(e.updateDate) else { return .err("Update date must be a date like 2025-01-31.") }
            if u > today { return .err("update_date cannot be in the future") }
            if u < opened { return .err("update_date must be on or after opened_date") }
            updateDate = u
        }
        var b = common()
        switch f.kind {
        case .cash: b["broker_name"] = trim(f.broker); b["label"] = cashLabel(f); b["cash_balance"] = str(parseDec(f.cashBalance)!)
        case .property:
            b["label"] = orNull(nn(f.label)); b["broker_name"] = orNull(nn(f.broker))
            b["home_value"] = str(parseDec(f.homeValue)!); b["mortgage_balance"] = str(parseDec(f.mortgage) ?? 0)
        default: b["label"] = orNull(nn(f.label)); b["broker_name"] = orNull(nn(f.broker)); b["other_value"] = str(parseDec(f.otherValue)!)
        }
        b["opened_date"] = opened.iso; b["opening_value_gbp"] = str(opening); b["save_mode"] = e.mode
        if let updateDate { b["update_date"] = updateDate.iso }
        if let exit, let exitValue { b["exit_date"] = exit.iso; b["exit_value_gbp"] = str(exitValue) }
        return .ok(b)
    }

    /// Pre-fills the edit form from what the server stored.
    static func formFrom(_ m: ManualHoldingOut) -> NonListed {
        let kind = ManualKind.of(m.assetKind) ?? .other
        let type = m.label ?? ""
        let known = cashTypes.first { $0.caseInsensitiveCompare(type) == .orderedSame }
        let typeBlank = trim(type).isEmpty
        var f = NonListed(kind: kind)
        f.currency = m.currency ?? "GBP"; f.notes = m.notes ?? ""; f.label = kind == .cash ? "" : type; f.broker = m.brokerName ?? ""
        f.cashType = kind == .cash ? (known ?? (typeBlank ? cashDefault : cashOther)) : cashDefault
        f.cashTypeOther = (kind == .cash && known == nil && !typeBlank) ? type : ""
        f.homeValue = plain(m.homeValue); f.mortgage = plain(m.mortgageBalance); f.cashBalance = plain(m.cashBalance); f.otherValue = plain(m.otherValue)
        f.openedDate = m.openedDate ?? ""; f.openingValue = plain(m.openingValueGbp); f.exitDate = m.exitDate ?? ""; f.exitValue = plain(m.exitValueGbp)
        return f
    }

    /// Same as HoldingsLogic.isListedAssetKind on Android: blank, "listed" or "equity".
    static func isListedAssetKind(_ kind: String?) -> Bool {
        let k = (kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return k.isEmpty || k == "listed" || k == "equity"
    }
    static func isManualListedSold(_ r: HoldingRow) -> Bool {
        r.source == "manual" && isListedAssetKind(r.assetKind) && (r.soldOutAt != nil || (r.quantity.map { $0 <= 0 } ?? false))
    }
    static func isNonListedManual(_ r: HoldingRow) -> Bool { r.source == "manual" && r.manualHoldingId != nil && !isListedAssetKind(r.assetKind) }
    static func isListedManual(_ r: HoldingRow) -> Bool { r.source == "manual" && r.manualHoldingId != nil && isListedAssetKind(r.assetKind) }

    /// Web: only the first lot of a listed ticker offers the sector editor, keyed by the display ticker without the T212 "_EQ" suffix.
    static func sectorTicker(displayTicker: String) -> String { displayTicker.hasSuffix("_EQ") ? String(displayTicker.dropLast(3)) : displayTicker }

    static func sectorBody(ticker: String, sector: String) -> ManualBuilt {
        let t = trim(ticker), s = trim(sector)
        if t.isEmpty { return .err("Invalid ticker") }
        if s.isEmpty { return .err("Sector is required") }
        return .ok(["ticker": t, "sector": s])
    }

    /// Which edit buttons apply to a row (Android ManualActions).
    struct Actions: Equatable {
        var sector = false, editLot = false, sell = false, values = false, remove = false
        var any: Bool { sector || editLot || sell || values || remove }
    }
    static func actions(for r: HoldingRow, isPrimaryLot: Bool) -> Actions {
        let sold = isManualListedSold(r), listed = isListedManual(r), non = isNonListedManual(r)
        var a = Actions()
        a.sector = isListedAssetKind(r.assetKind) && !sold && isPrimaryLot && r.source != "monzo"
        a.editLot = listed && !sold; a.sell = listed && !sold
        a.values = non; a.remove = listed || non
        return a
    }
}
