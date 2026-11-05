import XCTest
@testable import Rushify

private let TODAY = ManualDay(2026, 10, 31)
private func ok(_ b: ManualBuilt, file: StaticString = #filePath, line: UInt = #line) -> [String: Any] {
    guard case .ok(let body) = b else { XCTFail("expected ok but was \(b)", file: file, line: line); return [:] }
    return body
}
private func err(_ b: ManualBuilt, file: StaticString = #filePath, line: UInt = #line) -> String {
    guard case .err(let m) = b else { XCTFail("expected err but was \(b)", file: file, line: line); return "" }
    return m
}
private func s(_ b: [String: Any], _ k: String) -> String? { b[k] as? String }
private func keys(_ b: [String: Any]) -> Set<String> { Set(b.keys) }
private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

final class ManualRulesTests: XCTestCase {
    func testListedCreateBodyMatchesTheWeb() {
        let b = ok(ManualRules.listedCreate(symbol: " VOD.L ", label: "Vodafone", qty: "1,000", broker: " Hargreaves ", kind: "isa", purchaseDate: "2024-05-01", cost: "£1,234.50", today: TODAY))
        XCTAssertEqual(keys(b), ["asset_kind", "symbol", "label", "quantity", "broker_name", "purchase_date", "cost_base_gbp", "account_kind"])
        XCTAssertEqual(s(b, "asset_kind"), "listed"); XCTAssertEqual(s(b, "symbol"), "VOD.L"); XCTAssertEqual(s(b, "label"), "Vodafone"); XCTAssertEqual(s(b, "quantity"), "1000")
        XCTAssertEqual(s(b, "broker_name"), "Hargreaves"); XCTAssertEqual(s(b, "purchase_date"), "2024-05-01"); XCTAssertEqual(s(b, "cost_base_gbp"), "1234.5"); XCTAssertEqual(s(b, "account_kind"), "isa")
        XCTAssertNil(b["currency"], "currency is never sent for listed lots")
    }
    func testBlankLabelIsNull() {
        XCTAssertTrue(ok(ManualRules.listedCreate(symbol: "A", label: "  ", qty: "1", broker: "B", kind: "sipp", purchaseDate: "2024-01-01", cost: "10", today: TODAY))["label"] is NSNull)
    }
    func testListedCreateMissingFields() {
        let rows: [[String]] = [
            ["", "", "1", "B", "sipp", "2024-01-01", "10"], ["A", "", "", "B", "sipp", "2024-01-01", "10"], ["A", "", "0", "B", "sipp", "2024-01-01", "10"],
            ["A", "", "1", " ", "sipp", "2024-01-01", "10"], ["A", "", "1", "B", "", "2024-01-01", "10"], ["A", "", "1", "B", "sipp", "", "10"], ["A", "", "1", "B", "sipp", "2024-01-01", "x"],
        ]
        for a in rows {
            XCTAssertEqual(err(ManualRules.listedCreate(symbol: a[0], label: a[1], qty: a[2], broker: a[3], kind: a[4], purchaseDate: a[5], cost: a[6], today: TODAY)), ManualRules.msgListedMissing, "\(a)")
        }
    }
    func testListedCreatePurchaseDateWindow() {
        func c(_ d: String) -> ManualBuilt { ManualRules.listedCreate(symbol: "A", label: "", qty: "1", broker: "B", kind: "sipp", purchaseDate: d, cost: "10", today: TODAY) }
        XCTAssertEqual(err(c("2026-11-01")), ManualRules.msgListedDate)
        XCTAssertEqual(err(c("1996-10-30")), ManualRules.msgListedDate)
        XCTAssertEqual(err(c("31/10/2025")), ManualRules.msgListedDate)
        XCTAssertEqual(err(c("2025-02-30")), ManualRules.msgListedDate)
        _ = ok(c("2026-10-31")); _ = ok(c("1996-10-31"))
    }
    func testAccountKindOptions() {
        XCTAssertEqual(ManualRules.listedCreateKinds.map(\.value), ["sipp", "isa", "invest", "lisa", "jisa", "jsipp"])
        XCTAssertTrue(ManualRules.listedEditKinds.contains { $0.value == "unspecified" })
        XCTAssertFalse(ManualRules.listedEditKinds.contains { $0.value == "cash_isa" }, "the backend rejects cash_isa on edit")
    }
    func testListedEditUnspecifiedSendsNullKind() {
        let b = ok(ManualRules.listedEdit(label: "L", qty: "5", broker: "Broker", kind: "unspecified", purchaseDate: "2024-01-01", cost: "100", today: TODAY))
        XCTAssertTrue(b["account_kind"] is NSNull); XCTAssertEqual(s(b, "quantity"), "5"); XCTAssertEqual(s(b, "cost_base_gbp"), "100"); XCTAssertNil(b["symbol"])
        XCTAssertEqual(s(ok(ManualRules.listedEdit(label: "", qty: "5", broker: "Broker", kind: "sipp", purchaseDate: "2024-01-01", cost: "100", today: TODAY)), "account_kind"), "sipp")
    }
    func testListedEditMessages() {
        func e(_ q: String, _ br: String, _ d: String, _ c: String) -> String { err(ManualRules.listedEdit(label: "", qty: q, broker: br, kind: "sipp", purchaseDate: d, cost: c, today: TODAY)) }
        XCTAssertEqual(e("5", "B", "", "100"), ManualRules.msgEditBasis)
        XCTAssertEqual(e("5", "B", "2024-01-01", ""), ManualRules.msgEditBasis)
        XCTAssertEqual(e("5", " ", "2024-01-01", "100"), ManualRules.msgBroker)
        XCTAssertEqual(e("0", "B", "2024-01-01", "100"), "quantity must be greater than zero")
    }

    func testSellBody() {
        let b = ok(ManualRules.sell(held: 10, purchaseDate: "2024-01-01", qty: "4", executedAt: "2025-06-01", price: "12.5", today: TODAY))
        XCTAssertEqual(keys(b), ["quantity_sold", "executed_at", "price_per_share_gbp"]); XCTAssertEqual(s(b, "quantity_sold"), "4"); XCTAssertEqual(s(b, "executed_at"), "2025-06-01"); XCTAssertEqual(s(b, "price_per_share_gbp"), "12.5")
        XCTAssertEqual(s(ok(ManualRules.sell(held: 10, purchaseDate: "2024-01-01", qty: "10", executedAt: "2025-06-01", price: "1", today: TODAY)), "quantity_sold"), "10")
    }
    func testSellMessages() {
        func x(_ h: Decimal?, _ pd: String?, _ q: String, _ d: String, _ p: String) -> String { err(ManualRules.sell(held: h, purchaseDate: pd, qty: q, executedAt: d, price: p, today: TODAY)) }
        let closed = "Nothing left to sell — this position is already closed"
        XCTAssertEqual(x(nil, "2024-01-01", "1", "2025-01-01", "1"), closed)
        XCTAssertEqual(x(0, "2024-01-01", "1", "2025-01-01", "1"), closed)
        XCTAssertTrue(x(5, nil, "1", "2025-01-01", "1").hasPrefix("Purchase date required before recording a sale"))
        XCTAssertEqual(x(5, "2024-01-01", "", "2025-01-01", "1"), "Quantity sold is required.")
        XCTAssertEqual(x(5, "2024-01-01", "0", "2025-01-01", "1"), "Enter a valid quantity sold (greater than zero).")
        XCTAssertEqual(x(5, "2024-01-01", "abc", "2025-01-01", "1"), "Enter a valid quantity sold (greater than zero).")
        XCTAssertEqual(x(5, "2024-01-01", "6", "2025-01-01", "1"), "Sold quantity cannot exceed current holding (5).")
        XCTAssertEqual(x(5, "2024-01-01", "1", "2025-01-01", ""), "GBP price per share is required.")
        XCTAssertEqual(x(5, "2024-01-01", "1", "2025-01-01", "0"), "Enter the GBP price per share (must be greater than zero).")
        XCTAssertEqual(x(5, "2024-01-01", "1", "", "1"), "Sell date is required.")
        XCTAssertEqual(x(5, "2024-01-01", "1", "01/02/2025", "1"), "Sell date must be a date like 2025-01-31.")
        XCTAssertEqual(x(5, "2024-06-01", "1", "2024-05-31", "1"), "Sell date cannot be before the lot purchase date")
        XCTAssertEqual(x(5, "2024-01-01", "1", "2026-11-01", "1"), "Sell date cannot be in the future.")
    }

    private func base(_ k: ManualKind) -> ManualRules.NonListed { var f = ManualRules.NonListed(kind: k); f.openedDate = "2020-01-01"; f.openingValue = "100000"; return f }
    private func with(_ f: ManualRules.NonListed, _ m: (inout ManualRules.NonListed) -> Void) -> ManualRules.NonListed { var c = f; m(&c); return c }

    func testPropertyCreate() {
        let b = ok(ManualRules.nonListedCreate(with(base(.property)) { $0.label = "Home"; $0.homeValue = "350,000"; $0.mortgage = "120000"; $0.notes = " n " }, today: TODAY))
        XCTAssertEqual(s(b, "asset_kind"), "real_estate"); XCTAssertEqual(s(b, "label"), "Home"); XCTAssertEqual(s(b, "home_value"), "350000"); XCTAssertEqual(s(b, "mortgage_balance"), "120000")
        XCTAssertEqual(s(b, "currency"), "GBP"); XCTAssertEqual(s(b, "notes"), "n"); XCTAssertEqual(s(b, "opened_date"), "2020-01-01"); XCTAssertEqual(s(b, "opening_value_gbp"), "100000")
        XCTAssertNil(b["exit_date"]); XCTAssertNil(b["other_value"])
    }
    func testCashCreateUsesBankAndAccountType() {
        let b = ok(ManualRules.nonListedCreate(with(base(.cash)) { $0.broker = "Nationwide"; $0.cashBalance = "5000" }, today: TODAY))
        XCTAssertEqual(s(b, "asset_kind"), "cash"); XCTAssertEqual(s(b, "broker_name"), "Nationwide"); XCTAssertEqual(s(b, "label"), "Savings account"); XCTAssertEqual(s(b, "cash_balance"), "5000")
        let other = ok(ManualRules.nonListedCreate(with(base(.cash)) { $0.broker = "N"; $0.cashType = "Other"; $0.cashTypeOther = " Cash box "; $0.cashBalance = "1" }, today: TODAY))
        XCTAssertEqual(s(other, "label"), "Cash box")
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(base(.cash)) { $0.broker = "N"; $0.cashType = "Other"; $0.cashBalance = "1" }, today: TODAY)), "Choose an account type, or enter a description if you selected Other.")
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(base(.cash)) { $0.cashBalance = "1" }, today: TODAY)), "Enter the bank or building society name.")
        XCTAssertEqual(ManualRules.cashTypes.count, 10)
    }
    func testOtherCreateAndRequired() {
        let b = ok(ManualRules.nonListedCreate(with(base(.other)) { $0.label = "Car"; $0.otherValue = "8000" }, today: TODAY)); XCTAssertEqual(s(b, "asset_kind"), "other"); XCTAssertEqual(s(b, "other_value"), "8000")
        let req = "Fill in all required fields for this entry type."
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(base(.other)) { $0.otherValue = "8000" }, today: TODAY)), req)
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(base(.property)) { $0.label = "H"; $0.homeValue = "1" }, today: TODAY)), req)
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(base(.other)) { $0.label = "Car"; $0.otherValue = "1"; $0.openedDate = "" }, today: TODAY)), req)
    }
    func testCreateDatesAndOpening() {
        let f = with(base(.other)) { $0.label = "Car"; $0.otherValue = "1" }
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(f) { $0.openedDate = "2026-11-01" }, today: TODAY)), "Opened date cannot be in the future.")
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(f) { $0.openingValue = "-1" }, today: TODAY)), "Enter a valid non-negative opening amount in GBP.")
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(f) { $0.openingValue = "abc" }, today: TODAY)), "Enter a valid non-negative opening amount in GBP.")
    }
    func testCreateExitRules() {
        let f = with(base(.other)) { $0.label = "Car"; $0.otherValue = "1" }
        let b = ok(ManualRules.nonListedCreate(with(f) { $0.exitDate = "2024-01-01"; $0.exitValue = "5000" }, today: TODAY)); XCTAssertEqual(s(b, "exit_date"), "2024-01-01"); XCTAssertEqual(s(b, "exit_value_gbp"), "5000")
        let both = "Exit date and exit amount (GBP) must both be set or both left blank."
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(f) { $0.exitDate = "2024-01-01" }, today: TODAY)), both)
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(f) { $0.exitValue = "5" }, today: TODAY)), both)
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(f) { $0.exitDate = "2026-12-01"; $0.exitValue = "5" }, today: TODAY)), "Exit date cannot be in the future.")
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(f) { $0.exitDate = "2019-12-31"; $0.exitValue = "5" }, today: TODAY)), "Exit date must be on or after the opened date.")
        XCTAssertEqual(err(ManualRules.nonListedCreate(with(f) { $0.exitDate = "2024-01-01"; $0.exitValue = "-5" }, today: TODAY)), "Enter a valid non-negative exit amount in GBP.")
    }

    private func edit(_ f: ManualRules.NonListed, exited: Bool = false, chart: Bool = true, mode: String = "update", update: String = "") -> ManualBuilt {
        ManualRules.nonListedEdit(.init(form: f, exited: exited, showOnChart: chart, mode: mode, updateDate: update), today: TODAY)
    }
    func testEditUpdateModeSendsNewValueAsOfDate() {
        let b = ok(edit(with(base(.property)) { $0.label = "Home"; $0.homeValue = "360000"; $0.mortgage = "" }, update: "2026-10-01"))
        XCTAssertEqual(s(b, "save_mode"), "update"); XCTAssertEqual(s(b, "update_date"), "2026-10-01"); XCTAssertEqual(s(b, "home_value"), "360000"); XCTAssertEqual(s(b, "mortgage_balance"), "0")
        XCTAssertEqual(b["show_on_wealth_chart"] as? Bool, true); XCTAssertNil(b["exit_date"])
        XCTAssertNil(ok(edit(with(base(.other)) { $0.otherValue = "5" }))["update_date"], "blank update date is omitted so the server uses today")
    }
    func testEditExitModeClosesTheLine() {
        let b = ok(edit(with(base(.other)) { $0.label = "Car"; $0.otherValue = "5"; $0.exitDate = "2026-01-01"; $0.exitValue = "4000" }, mode: "exit"))
        XCTAssertEqual(s(b, "save_mode"), "exit"); XCTAssertEqual(s(b, "exit_date"), "2026-01-01"); XCTAssertEqual(s(b, "exit_value_gbp"), "4000"); XCTAssertNil(b["update_date"])
        XCTAssertEqual(err(edit(with(base(.other)) { $0.otherValue = "5" }, mode: "exit")), "exit_date and exit_value_gbp are required when updating property, cash savings, and other manual assets")
    }
    func testExitedLineOnlyChangesNotesCurrencyAndChartFlag() {
        let b = ok(edit(with(base(.cash)) { $0.currency = "gbp"; $0.notes = "closed" }, exited: true, chart: false))
        XCTAssertEqual(keys(b), ["currency", "notes", "show_on_wealth_chart", "save_mode"]); XCTAssertEqual(s(b, "currency"), "GBP"); XCTAssertEqual(s(b, "save_mode"), "update"); XCTAssertEqual(b["show_on_wealth_chart"] as? Bool, false)
    }
    func testEditDateRules() {
        let f = with(base(.other)) { $0.otherValue = "5" }
        XCTAssertEqual(err(edit(f, update: "2026-11-02")), "update_date cannot be in the future")
        XCTAssertEqual(err(edit(f, update: "2019-01-01")), "update_date must be on or after opened_date")
        XCTAssertEqual(err(edit(f, update: "nope")), "Update date must be a date like 2025-01-31.")
        XCTAssertEqual(err(edit(with(f) { $0.openingValue = "" })), "Opened date and opening amount (GBP) are required.")
        XCTAssertEqual(err(edit(with(f) { $0.openedDate = "2027-01-01" })), "Opened date cannot be in the future.")
        XCTAssertEqual(err(edit(with(f) { $0.openingValue = "-3" })), "Enter a valid non-negative opening amount in GBP.")
    }
    func testPropertyEditNeedsNonNegativeValues() {
        XCTAssertEqual(err(edit(with(base(.property)) { $0.homeValue = "-1" })), "Enter valid non-negative home and mortgage values.")
        XCTAssertEqual(err(edit(with(base(.property)) { $0.homeValue = "1"; $0.mortgage = "x" })), "Enter valid non-negative home and mortgage values.")
    }
    func testCashEditAllowsNegativeBalance() { XCTAssertEqual(s(ok(edit(with(base(.cash)) { $0.broker = "Bank"; $0.cashBalance = "-50" })), "cash_balance"), "-50") }

    func testFormPrefillFromServerRow() {
        var m = ManualHoldingOut(id: 3, assetKind: "cash", label: "Cash ISA", brokerName: "Nationwide", currency: "GBP", cashBalance: dec("5000.00"), openedDate: "2021-02-03", openingValueGbp: dec("4000.0"))
        let f = ManualRules.formFrom(m)
        XCTAssertEqual(f.kind, .cash); XCTAssertEqual(f.cashType, "Cash ISA"); XCTAssertEqual(f.cashTypeOther, ""); XCTAssertEqual(f.cashBalance, "5000"); XCTAssertEqual(f.openingValue, "4000"); XCTAssertEqual(f.broker, "Nationwide")
        m.label = "Offset pot"; let custom = ManualRules.formFrom(m); XCTAssertEqual(custom.cashType, "Other"); XCTAssertEqual(custom.cashTypeOther, "Offset pot")
        m.label = nil; XCTAssertEqual(ManualRules.formFrom(m).cashType, "Savings account")
        let prop = ManualRules.formFrom(ManualHoldingOut(assetKind: "real_estate", label: "Flat", homeValue: dec("1E+5"))); XCTAssertEqual(prop.label, "Flat"); XCTAssertEqual(prop.homeValue, "100000")
    }
    func testSectorBodyAndTicker() {
        let b = ok(ManualRules.sectorBody(ticker: " AAPL ", sector: " Technology ")); XCTAssertEqual(s(b, "ticker"), "AAPL"); XCTAssertEqual(s(b, "sector"), "Technology")
        XCTAssertEqual(err(ManualRules.sectorBody(ticker: " ", sector: "Energy")), "Invalid ticker"); XCTAssertEqual(err(ManualRules.sectorBody(ticker: "X", sector: " ")), "Sector is required")
        XCTAssertEqual(ManualRules.sectors.count, 15); XCTAssertEqual(ManualRules.sectors.first, "ETFs & funds")
        XCTAssertEqual(ManualRules.sectorTicker(displayTicker: "AAPL_EQ"), "AAPL"); XCTAssertEqual(ManualRules.sectorTicker(displayTicker: "VOD.L"), "VOD.L")
    }
    func testWhichRowsAreEditable() {
        let listed = HoldingRow(ticker: "VOD.L", source: "manual", assetKind: "listed", manualHoldingId: 5)
        XCTAssertTrue(ManualRules.isListedManual(listed)); XCTAssertFalse(ManualRules.isNonListedManual(listed))
        var prop = listed; prop.assetKind = "real_estate"; XCTAssertTrue(ManualRules.isNonListedManual(prop)); XCTAssertFalse(ManualRules.isListedManual(prop))
        var t212 = listed; t212.source = "trading212"; XCTAssertFalse(ManualRules.isListedManual(t212))
        var noId = listed; noId.manualHoldingId = nil; XCTAssertFalse(ManualRules.isListedManual(noId))
    }
    func testActionButtonsPerRow() {
        var lot = HoldingRow(ticker: "MSFT", source: "manual", assetKind: "listed", manualHoldingId: 11); lot.quantity = 1
        XCTAssertEqual(ManualRules.actions(for: lot, isPrimaryLot: true), .init(sector: true, editLot: true, sell: true, values: false, remove: true))
        XCTAssertEqual(ManualRules.actions(for: lot, isPrimaryLot: false), .init(sector: false, editLot: true, sell: true, values: false, remove: true))
        var sold = lot; sold.soldOutAt = "2025-01-01"
        XCTAssertEqual(ManualRules.actions(for: sold, isPrimaryLot: true), .init(sector: false, editLot: false, sell: false, values: false, remove: true))
        var prop = lot; prop.assetKind = "real_estate"
        XCTAssertEqual(ManualRules.actions(for: prop, isPrimaryLot: true), .init(sector: false, editLot: false, sell: false, values: true, remove: true))
        let broker = HoldingRow(ticker: "INFY", source: "t212", assetKind: "equity")
        XCTAssertEqual(ManualRules.actions(for: broker, isPrimaryLot: true), .init(sector: true))
        XCTAssertFalse(ManualRules.actions(for: broker, isPrimaryLot: false).any)
        XCTAssertFalse(ManualRules.actions(for: HoldingRow(ticker: "X", source: "monzo", assetKind: "listed"), isPrimaryLot: true).sector)
        XCTAssertFalse(ManualRules.actions(for: HoldingRow(ticker: "X", source: "t212", assetKind: "cash"), isPrimaryLot: true).any)
    }
    func testSanitizeDecimalAndStrictParsing() {
        XCTAssertEqual(ManualRules.sanitizeDecimal(" £1,234.5 "), "1234.5"); XCTAssertNil(ManualRules.parseDec("")); XCTAssertNil(ManualRules.parseDec("abc")); XCTAssertEqual(ManualRules.parseDec("12.5"), dec("12.5"))
        XCTAssertNil(ManualRules.parseDec("12abc")); XCTAssertNil(ManualRules.parseDec("1.2.3")); XCTAssertEqual(ManualRules.parseDec("-50"), -50); XCTAssertEqual(ManualRules.parseDec(".5"), dec("0.5"))
        XCTAssertEqual(ManualRules.str(dec("12.50")), "12.5"); XCTAssertEqual(ManualRules.str(dec("0.00")), "0"); XCTAssertEqual(ManualRules.str(dec("123456789012.345678")), "123456789012.345678")
    }
    func testDays() {
        XCTAssertEqual(ManualDay.parse("2024-02-29")?.iso, "2024-02-29"); XCTAssertNil(ManualDay.parse("2025-02-29")); XCTAssertNil(ManualDay.parse("2025-13-01")); XCTAssertNil(ManualDay.parse("2025-1-01"))
        XCTAssertEqual(ManualDay(2024, 2, 29).minusYears(30), ManualDay(1994, 2, 28))
        XCTAssertEqual(ManualRules.parseDate(" 2025-01-31 "), ManualDay(2025, 1, 31))
    }
    func testManualHoldingOutDecodesLeniently() throws {
        let m = try JSONDecoder().decode([ManualHoldingOut].self, from: json(#"[{"id":1,"asset_kind":"real_estate","label":"Living Home","broker_name":null,"home_value":"350000","mortgage_balance":120000,"opened_date":"2020-01-01","show_on_wealth_chart":true,"chart_eligible":false,"snapshot_count":6}]"#))
        XCTAssertEqual(m[0].id, 1); XCTAssertEqual(m[0].homeValue, 350000); XCTAssertEqual(m[0].mortgageBalance, 120000); XCTAssertNil(m[0].brokerName); XCTAssertEqual(m[0].showOnWealthChart, true); XCTAssertEqual(m[0].chartEligible, false); XCTAssertEqual(m[0].snapshotCount, 6)
        XCTAssertEqual(try JSONDecoder().decode(ManualHoldingOut.self, from: json("{}")).assetKind, "listed")
    }
}

/// The write calls: exact method, path and body on the wire, success handling, and failures that must change nothing.
@MainActor
final class ManualViewModelTests: XCTestCase {
    private var env: TestEnv!
    private var vm: ManualViewModel!
    private var done = 0

    override func setUp() {
        MockURLProtocol.reset(); env = TestEnv(); done = 0
        vm = ManualViewModel(repo: env.repo); vm.today = { TODAY }; vm.searchDelay = .milliseconds(20)
    }
    override func tearDown() { MockURLProtocol.reset() }

    private func stub(_ status: Int = 200, _ body: String = "{}") { MockURLProtocol.reset { _ in .init(status: status, body: json(body)) } }
    private func valid() -> ManualBuilt { ManualRules.listedCreate(symbol: "VOD.L", label: "Vodafone", qty: "10", broker: "HL", kind: "isa", purchaseDate: "2024-01-01", cost: "100", today: TODAY) }
    private func bodyText(_ r: URLRequest) -> String {
        let d = r.httpBody ?? r.httpBodyStream.map { st in st.open(); defer { st.close() }; var d = Data(); var buf = [UInt8](repeating: 0, count: 512); while st.hasBytesAvailable { let n = st.read(&buf, maxLength: 512); if n <= 0 { break }; d.append(buf, count: n) }; return d }
        return String(decoding: d ?? Data(), as: UTF8.self)
    }
    private func bodyObj(_ r: URLRequest) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(bodyText(r).utf8))) as? [String: Any] ?? [:] }
    private var onDone: () -> Void { { [unowned self] in done += 1 } }

    func testCreatePostsToManualAndRefreshes() async {
        stub(201, #"{"id":1}"#)
        await vm.create(valid(), onDone: onDone)?.value
        let r = MockURLProtocol.seen()[0]
        XCTAssertEqual(r.httpMethod, "POST"); XCTAssertEqual(r.url?.path, "/api/portfolio/manual"); XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-token")
        XCTAssertEqual(bodyObj(r)["symbol"] as? String, "VOD.L"); XCTAssertEqual(done, 1); XCTAssertFalse(vm.ui.busy); XCTAssertNil(vm.ui.error); XCTAssertEqual(vm.ui.message, "Saved. Home and Holdings will refresh shortly.")
    }
    func testWireFormatKeepsStringsNullsAndBooleans() async {
        stub()
        await vm.create(ManualRules.listedCreate(symbol: "A", label: " ", qty: "1,000", broker: "B", kind: "sipp", purchaseDate: "2024-01-01", cost: "£1.50", today: TODAY), onDone: onDone)?.value
        let t = bodyText(MockURLProtocol.seen()[0])
        XCTAssertTrue(t.contains(#""label":null"#), t); XCTAssertTrue(t.contains(#""quantity":"1000""#), t); XCTAssertTrue(t.contains(#""cost_base_gbp":"1.5""#), t)
        stub()
        await vm.editValues(3, ManualRules.nonListedEdit(.init(form: { var f = ManualRules.NonListed(kind: .other); f.otherValue = "5"; f.openedDate = "2020-01-01"; f.openingValue = "1"; return f }(), exited: false, showOnChart: true), today: TODAY), onDone: onDone)?.value
        let t2 = bodyText(MockURLProtocol.seen()[0])
        XCTAssertTrue(t2.contains(#""show_on_wealth_chart":true"#), t2); XCTAssertTrue(t2.contains(#""broker_name":null"#), t2); XCTAssertFalse(t2.contains("update_date"), t2)
    }
    func testCreateAlsoAcceptsEmpty200() async {
        MockURLProtocol.reset { _ in .init(status: 200, body: Data(), headers: [:]) }
        await vm.create(valid(), onDone: onDone)?.value
        XCTAssertEqual(done, 1)
    }
    func testInvalidFormNeverHitsTheServer() async {
        stub()
        let t = vm.create(ManualRules.listedCreate(symbol: "", label: "", qty: "", broker: "", kind: "", purchaseDate: "", cost: "", today: TODAY), onDone: onDone)
        XCTAssertNil(t); XCTAssertEqual(vm.ui.error, ManualRules.msgListedMissing); XCTAssertEqual(done, 0); XCTAssertTrue(MockURLProtocol.seen().isEmpty)
    }
    func testServerRejectionShowsTheServersMessageAndChangesNothing() async {
        stub(422, #"{"detail":[{"msg":"quantity must be greater than zero for listed investments"}]}"#)
        await vm.create(valid(), onDone: onDone)?.value
        XCTAssertEqual(vm.ui.error, "quantity must be greater than zero for listed investments"); XCTAssertEqual(done, 0); XCTAssertNil(vm.ui.message); XCTAssertFalse(vm.ui.busy)
    }
    func testStringDetailIsShown() async {
        stub(400, #"{"detail":"Sell date cannot be before the lot purchase date"}"#)
        await vm.sell(4, ManualRules.sell(held: 10, purchaseDate: "2024-01-01", qty: "1", executedAt: "2025-01-01", price: "5", today: TODAY), onDone: {})?.value
        XCTAssertEqual(vm.ui.error, "Sell date cannot be before the lot purchase date")
    }
    func testEditLotPatchesTheLot() async {
        stub()
        await vm.editListed(9, ManualRules.listedEdit(label: "L", qty: "5", broker: "HL", kind: "unspecified", purchaseDate: "2024-01-01", cost: "50", today: TODAY), onDone: onDone)?.value
        let r = MockURLProtocol.seen()[0]
        XCTAssertEqual(r.httpMethod, "PATCH"); XCTAssertEqual(r.url?.path, "/api/portfolio/manual/9"); XCTAssertTrue(bodyObj(r)["account_kind"] is NSNull); XCTAssertEqual(done, 1); XCTAssertEqual(vm.ui.message, "Lot updated.")
    }
    func testSellPostsToSellEndpoint() async {
        stub(200, #"{"holding":{"id":9}}"#)
        await vm.sell(9, ManualRules.sell(held: 10, purchaseDate: "2024-01-01", qty: "4", executedAt: "2025-06-01", price: "12.5", today: TODAY), onDone: {})?.value
        let r = MockURLProtocol.seen()[0]
        XCTAssertEqual(vm.ui.message, "Sale recorded."); XCTAssertEqual(r.httpMethod, "POST"); XCTAssertEqual(r.url?.path, "/api/portfolio/manual/9/sell"); XCTAssertEqual(bodyObj(r)["quantity_sold"] as? String, "4")
    }
    func testRemoveDeletesAndToleratesNoContent() async {
        MockURLProtocol.reset { _ in .init(status: 204, body: Data(), headers: [:]) }
        await vm.remove(12, onDone: onDone)?.value
        let r = MockURLProtocol.seen()[0]
        XCTAssertEqual(vm.ui.message, "Position removed."); XCTAssertEqual(r.httpMethod, "DELETE"); XCTAssertEqual(r.url?.path, "/api/portfolio/manual/12"); XCTAssertEqual(done, 1)
    }
    func testSectorOverridePutsTickerAndSector() async {
        stub(200, #"{"ticker":"AAPL","sector":"Technology"}"#)
        await vm.saveSector(ManualRules.sectorBody(ticker: "AAPL", sector: "Technology"), onDone: {})?.value
        let r = MockURLProtocol.seen()[0]; let b = bodyObj(r)
        XCTAssertEqual(vm.ui.message, "Sector saved."); XCTAssertEqual(r.httpMethod, "PUT"); XCTAssertEqual(r.url?.path, "/api/portfolio/sector-override"); XCTAssertEqual(b["ticker"] as? String, "AAPL"); XCTAssertEqual(b["sector"] as? String, "Technology")
    }
    func testEditValuesReloadsDetailsAfterSaving() async {
        MockURLProtocol.reset { r in
            r.httpMethod == "GET" ? .init(body: json(#"[{"id":3,"asset_kind":"cash","label":"Savings account","broker_name":"Bank","cash_balance":"6000"}]"#)) : .init(body: json("{}"))
        }
        var f = ManualRules.NonListed(kind: .cash); f.broker = "Bank"; f.cashBalance = "6000"; f.openedDate = "2020-01-01"; f.openingValue = "100"
        var reload: Task<Void, Never>?
        await vm.editValues(3, ManualRules.nonListedEdit(.init(form: f, exited: false, showOnChart: true), today: TODAY), onDone: { reload = nil })?.value
        for _ in 0..<200 where vm.details[3] == nil { try? await Task.sleep(for: .milliseconds(10)) }
        _ = reload
        XCTAssertEqual(vm.details[3]?.cashBalance, 6000)
        let seen = MockURLProtocol.seen(); XCTAssertEqual(seen.map { $0.httpMethod }, ["PATCH", "GET"]); XCTAssertEqual(seen[1].url?.path, "/api/portfolio/manual")
    }
    func testSessionExpiryOnAWriteIsReportedNotCrashed() async {
        stub(401, #"{"detail":"Not authenticated"}"#)
        await vm.create(valid(), onDone: onDone)?.value
        XCTAssertEqual(vm.ui.error, "Session expired. Please sign in again."); XCTAssertEqual(done, 0)
    }
    func testNetworkFailureLeavesNoSuccessMessage() async {
        MockURLProtocol.reset { _ in .init(error: .notConnectedToInternet) }
        await vm.create(valid(), onDone: onDone)?.value
        XCTAssertEqual(done, 0); XCTAssertNil(vm.ui.message); XCTAssertEqual(vm.ui.error, "No internet connection"); XCTAssertFalse(vm.ui.busy)
    }
    func testSecondTapWhileBusyIsIgnored() async {
        stub(201)
        let first = vm.create(valid(), onDone: onDone)
        XCTAssertTrue(vm.ui.busy)
        XCTAssertNil(vm.create(valid(), onDone: onDone)); XCTAssertNil(vm.remove(1, onDone: {}))
        await first?.value
        XCTAssertEqual(MockURLProtocol.seen().count, 1); XCTAssertEqual(done, 1)
    }

    func testSymbolSearchWaitsForTwoCharactersAndDebounces() async {
        stub(200, #"[{"symbol":"VOD.L","name":"Vodafone Group","exchange":"LSE","currency":"GBX"}]"#)
        vm.search("v"); XCTAssertNil(vm.searchTask); vm.search(" v ")
        try? await Task.sleep(for: .milliseconds(60)); XCTAssertTrue(MockURLProtocol.seen().isEmpty); XCTAssertTrue(vm.hits.isEmpty)
        vm.search("vo"); vm.search("vod")
        await vm.searchTask?.value
        XCTAssertEqual(vm.hits.first?.symbol, "VOD.L")
        let seen = MockURLProtocol.seen(); XCTAssertEqual(seen.count, 1); XCTAssertEqual(seen[0].url?.path, "/api/portfolio/symbol-search"); XCTAssertEqual(seen[0].url?.query, "q=vod")
    }
    func testShortQueryClearsPreviousHits() async {
        stub(200, #"[{"symbol":"VOD.L"}]"#)
        vm.search("vod"); await vm.searchTask?.value; XCTAssertFalse(vm.hits.isEmpty)
        vm.search("v"); XCTAssertTrue(vm.hits.isEmpty)
    }
    func testDefaultSearchDelayIs350ms() { XCTAssertEqual(ManualViewModel(repo: env.repo).searchDelay, .milliseconds(350)) }
    func testPickingAHitFillsSymbolThenUsesTheNormalisedOne() async {
        stub(200, #"{"normalized_symbol":"VOD.L","last_price":"72.4","currency":"GBX"}"#)
        var seen: [String] = []
        await vm.pick(SymbolHit(symbol: "VOD", name: "Vodafone")) { seen.append($0) }.value
        XCTAssertEqual(seen, ["VOD", "VOD.L"]); XCTAssertEqual(vm.quote?.lastPrice, dec("72.4"))
        let u = MockURLProtocol.seen()[0].url; XCTAssertEqual(u?.path, "/api/portfolio/symbol-quote"); XCTAssertEqual(u?.query, "symbol=VOD")
    }
    func testAFailedQuoteIsIgnored() async {
        stub(502, #"{"detail":"nope"}"#)
        var seen: [String] = []
        await vm.pick(SymbolHit(symbol: "ZZZ")) { seen.append($0) }.value
        XCTAssertEqual(seen, ["ZZZ"]); XCTAssertNil(vm.quote); XCTAssertNil(vm.ui.error)
    }
}
