import Foundation

/*
 Pure holdings logic, ported from the Android app (HoldingsLogic.kt) which was ported from the web HoldingsPage,
 so all platforms show the same groups, matches and totals. Nothing here touches UI.
 */

enum HoldingsExposureFilter: CaseIterable {
    case all, openFull, openPartial, closed
    var label: String {
        switch self {
        case .all: return "All"
        case .openFull: return "Open (no sells)"
        case .openPartial: return "Open (reduced)"
        case .closed: return "Closed (history)"
        }
    }
    var hint: String {
        switch self {
        case .all: return "Default list (still respects \"Show sold positions\" for manual lots)."
        case .openFull: return "Broker line with quantity and no sell fills in stored history."
        case .openPartial: return "Still holding shares but at least one sell fill is stored."
        case .closed: return "Exited in the broker app: no open line. Closed instruments appear inside each broker account below."
        }
    }
}

enum HoldingsGroupKind: Int, CaseIterable { case t212, snaptrade, csv, monzo, manualListed, manualCash, manualProperty, manualOther, other }

enum HoldingsSort: CaseIterable {
    case value, pnl, name
    var label: String { switch self { case .value: return "Value"; case .pnl: return "P/L"; case .name: return "Name" } }
}

// MARK: small helpers (private to this feature)

extension String {
    var holdingsTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    fileprivate var holdingsCapFirst: String { prefix(1).uppercased() + dropFirst() }
}

func holdingsRegex(_ pattern: String, ignoreCase: Bool = false) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
}

/// Kotlin-style `Regex.matches` (whole string).
func holdingsFullMatch(_ re: NSRegularExpression, _ s: String) -> Bool {
    let r = NSRange(s.startIndex..., in: s)
    guard let m = re.firstMatch(in: s, options: [.anchored], range: r) else { return false }
    return m.range.length == r.length
}

/// Kotlin `split(Regex("\\s*·\\s*"))`.
func holdingsSplitDot(_ s: String) -> [String] { s.components(separatedBy: "·").map { $0.holdingsTrimmed } }

func holdingsStableSorted<T>(_ a: [T], _ less: (T, T) -> Bool) -> [T] {
    a.enumerated().sorted { l, r in
        if less(l.element, r.element) { return true }
        if less(r.element, l.element) { return false }
        return l.offset < r.offset
    }.map { $0.element }
}

private func sumDec(_ items: [Decimal]) -> Decimal { items.reduce(Decimal(0), +) }

// MARK: HoldingsLogic

enum HoldingsLogic {
    /// Same order as the backend's venue map; longer `_WBAG_EQ` before `_WB_EQ`.
    private static let t212Suffixes = [
        "_PA_EQ", "_FR_EQ", "_US_EQ", "_GB_EQ", "_L_EQ", "_DE_EQ", "_AS_EQ", "_ST_EQ", "_MI_EQ", "_MC_EQ",
        "_SW_EQ", "_BR_EQ", "_TO_EQ", "_AU_EQ", "_HK_EQ", "_JP_EQ", "_VI_EQ", "_WBAG_EQ", "_WB_EQ",
    ]

    /// `INFY_US_EQ` -> `INFY` (best effort, no network).
    static func stripT212VenueSuffix(_ raw: String?) -> String {
        let t = (raw ?? "").holdingsTrimmed
        if t.isEmpty { return t }
        let u = t.uppercased()
        for suf in t212Suffixes where u.hasSuffix(suf) { return String(t.dropLast(suf.count)) }
        if u.contains("_US_EQ") {
            if let cut = u.firstIndex(of: "_"), cut != u.startIndex { return String(t.prefix(u.distance(from: u.startIndex, to: cut))) }
        }
        if u.contains("_EQ") && u.contains("_") {
            if let cut = t.firstIndex(of: "_"), cut != t.startIndex { return String(t[t.startIndex..<cut]) }
        }
        return t
    }

    static func rollupDisplaySymbol(_ r: HoldingsRollupLine) -> String {
        var s = (r.displayTicker ?? r.yahooTicker ?? "").holdingsTrimmed
        if s.isEmpty { return "" }
        if s.uppercased().contains("_EQ") {
            let stripped = stripT212VenueSuffix(s).holdingsTrimmed
            if !stripped.isEmpty { s = stripped }
        }
        return s
    }

    /// Ticker shown on a row: the rollup's display symbol when linked, else the raw ticker without the `_EQ` venue suffix.
    static func displayTicker(_ r: HoldingRow, _ rollup: HoldingsRollupLine?) -> String {
        if let rollup { let s = rollupDisplaySymbol(rollup); if !s.isEmpty { return s } }
        let raw = r.ticker.holdingsTrimmed
        if raw.isEmpty { return raw }
        if (r.source == "t212" || r.source == "snaptrade") && raw.uppercased().contains("_EQ") {
            let s = stripT212VenueSuffix(raw).holdingsTrimmed
            if !s.isEmpty { return s }
        }
        return raw
    }

    static func isListedAssetKind(_ kind: String?) -> Bool {
        let k = (kind ?? "").holdingsTrimmed.lowercased()
        return k.isEmpty || k == "listed" || k == "equity"
    }

    private static let brokerSources: Set<String> = ["t212", "snaptrade", "csv"]

    static func isBrokerCash(_ r: HoldingRow) -> Bool { (brokerSources.contains(r.source) || r.source == "monzo") && r.assetKind == "cash" }

    /// Listed equity from a broker (excludes synthetic CASH.* rows).
    static func isBrokerListedEquityRow(_ r: HoldingRow) -> Bool {
        brokerSources.contains(r.source) && isListedAssetKind(r.assetKind) && !r.ticker.hasPrefix("CASH.")
    }

    /// A manual listed lot that is fully sold: a sold date, or no quantity left.
    static func isManualListedSold(_ r: HoldingRow) -> Bool {
        guard r.source == "manual", isListedAssetKind(r.assetKind) else { return false }
        if r.soldOutAt != nil { return true }
        if let q = r.quantity, q <= 0 { return true }
        return false
    }

    static func normalizeCsvRef(_ ref: String) -> String { ref.holdingsTrimmed.lowercased().replacingOccurrences(of: "trading-212", with: "trading212") }

    static func csvAccountRefFromRow(_ r: HoldingRow) -> String {
        let ref = (r.brokerAccountRef ?? "").holdingsTrimmed.lowercased()
        if !ref.isEmpty { return normalizeCsvRef(ref) }
        var ak = (r.accountKind ?? "invest").holdingsTrimmed.lowercased()
        if ak.isEmpty { ak = "invest" }
        let label = r.brokerLabel ?? "broker"
        let head = label.components(separatedBy: "·").first ?? label
        let slug = head.holdingsTrimmed.lowercased().replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        return normalizeCsvRef("csv:\(slug):\(ak)")
    }

    static func rowTickerMatchesRollup(_ rowTicker: String, _ rollup: HoldingsRollupLine) -> Bool {
        func normClass(_ s: String) -> String { stripT212VenueSuffix(s).holdingsTrimmed.uppercased().replacingOccurrences(of: "-", with: ".") }
        let rowU = rowTicker.holdingsTrimmed.uppercased()
        let disp = rollupDisplaySymbol(rollup)
        let dispU = disp.uppercased()
        let broU = (rollup.brokerTicker ?? "").holdingsTrimmed.uppercased()
        let yhU = (rollup.yahooTicker ?? "").holdingsTrimmed.uppercased()
        if rowU == dispU || rowU == broU { return true }
        if !rowU.isEmpty && !yhU.isEmpty && rowU == yhU { return true }
        let rowS = stripT212VenueSuffix(rowTicker).holdingsTrimmed.uppercased()
        let dispS = stripT212VenueSuffix(disp).holdingsTrimmed.uppercased()
        let broS = stripT212VenueSuffix(rollup.brokerTicker).holdingsTrimmed.uppercased()
        let yhS = stripT212VenueSuffix(rollup.yahooTicker).holdingsTrimmed.uppercased()
        if !rowS.isEmpty && (rowS == dispS || rowS == broS || (!yhS.isEmpty && rowS == yhS)) { return true }
        let rn = normClass(rowTicker)
        return !rn.isEmpty && (rn == normClass(disp) || rn == normClass(rollup.brokerTicker ?? "") || rn == normClass(rollup.yahooTicker ?? ""))
    }

    static func rollupMatchesListedRow(_ rollup: HoldingsRollupLine, _ r: HoldingRow) -> Bool {
        if r.source == "manual" && isListedAssetKind(r.assetKind) {
            if rollup.source != "manual" { return false }
            guard let id = r.manualHoldingId else { return false }
            return rollup.accountRef.holdingsTrimmed.lowercased() == "manual:\(id)"
        }
        if !isBrokerListedEquityRow(r) { return false }
        if !rowTickerMatchesRollup(r.ticker, rollup) { return false }
        if rollup.source == "csv" { return normalizeCsvRef(csvAccountRefFromRow(r)) == normalizeCsvRef(rollup.accountRef) }
        if rollup.source == "t212" {
            var ak = (r.accountKind ?? "invest").lowercased()
            if ak.isEmpty { ak = "invest" }
            return rollup.accountRef.holdingsTrimmed.lowercased() == "t212:\(ak)"
        }
        let aid = (r.snaptradeAccountId ?? "").holdingsTrimmed
        return !aid.isEmpty && rollup.accountRef.holdingsTrimmed.lowercased() == "snaptrade:\(aid.lowercased())"
    }

    /// Lower is better when several rollups match one dashboard ticker.
    static func rollupRowMatchRank(_ r: HoldingRow, _ rollup: HoldingsRollupLine) -> Int {
        let rowT = r.ticker.holdingsTrimmed
        let rowU = rowT.uppercased()
        let rowS = stripT212VenueSuffix(rowT).holdingsTrimmed.uppercased()
        let broU = (rollup.brokerTicker ?? "").holdingsTrimmed.uppercased()
        let disp = rollupDisplaySymbol(rollup).holdingsTrimmed
        let dispU = disp.uppercased()
        let broS = stripT212VenueSuffix(rollup.brokerTicker).holdingsTrimmed.uppercased()
        let dispS = stripT212VenueSuffix(disp).holdingsTrimmed.uppercased()
        if !rowU.isEmpty && rowU == broU { return 0 }
        if !rowU.isEmpty && rowU == dispU { return 1 }
        if !rowS.isEmpty && !broS.isEmpty && rowS == broS { return 2 }
        if !rowS.isEmpty && !dispS.isEmpty && rowS == dispS { return 3 }
        return 50
    }

    static func rollupMatchesExposure(_ rollup: HoldingsRollupLine, _ exposure: HoldingsExposureFilter) -> Bool {
        switch exposure {
        case .all: return true
        case .closed: return rollup.exposure == "closed_history"
        case .openFull: return rollup.exposure == "open_full"
        case .openPartial: return rollup.exposure == "open_partial"
        }
    }

    static func findRollupForRow(_ r: HoldingRow, _ lines: [HoldingsRollupLine], _ exposure: HoldingsExposureFilter = .all) -> HoldingsRollupLine? {
        let candidates = lines.filter { rollupMatchesListedRow($0, r) && rollupMatchesExposure($0, exposure) }
        if candidates.count <= 1 { return candidates.first }
        return holdingsStableSorted(candidates) { a, b in
            let ra = rollupRowMatchRank(r, a), rb = rollupRowMatchRank(r, b)
            if ra != rb { return ra < rb }
            if a.fillRowCount != b.fillRowCount { return a.fillRowCount > b.fillRowCount }
            return (a.brokerTicker ?? "").utf16.lexicographicallyPrecedes((b.brokerTicker ?? "").utf16)
        }.first
    }

    static func rollupIdentityKey(_ ru: HoldingsRollupLine?) -> String {
        guard let ru else { return "" }
        return "\(ru.source)|\(ru.accountRef.holdingsTrimmed.lowercased())|\((ru.brokerTicker ?? "").holdingsTrimmed.uppercased())"
    }

    static func rowSlotId(_ r: HoldingRow) -> String {
        if let id = r.manualHoldingId { return "mh:\(id)" }
        return "\(r.source):\(r.ticker.holdingsTrimmed):\((r.snaptradeAccountId ?? "").holdingsTrimmed):\((r.accountKind ?? "").holdingsTrimmed):\((r.currency ?? "").holdingsTrimmed)"
    }

    /// Which rows survive the exposure filter. Broker cash rows are hidden in every mode except All.
    static func applyExposureFilter(_ rows: [HoldingRow], _ lines: [HoldingsRollupLine], _ exposure: HoldingsExposureFilter, _ showSold: Bool) -> [HoldingRow] {
        if exposure == .all { return rows }
        let base = rows.filter { !isBrokerCash($0) }
        if exposure == .closed {
            return base.filter { r in
                if isBrokerListedEquityRow(r) { return false }
                if r.source == "manual" && isListedAssetKind(r.assetKind) && !isManualListedSold(r) { return false }
                if isManualListedSold(r) { return showSold }
                return true
            }
        }
        return base.filter { r in !isBrokerListedEquityRow(r) || findRollupForRow(r, lines, exposure) != nil }
    }

    /// One card per account x display symbol; the one with more fills wins.
    static func dedupeClosedHistory(_ closed: [HoldingsRollupLine]) -> [HoldingsRollupLine] {
        var order: [String] = []
        var byKey: [String: HoldingsRollupLine] = [:]
        for r in closed {
            let k = "\(r.source)|\(r.accountRef.holdingsTrimmed.lowercased())|\(rollupDisplaySymbol(r).holdingsTrimmed.uppercased())"
            if let prev = byKey[k] {
                if r.fillRowCount > prev.fillRowCount { byKey[k] = r }
            } else { order.append(k); byKey[k] = r }
        }
        return holdingsStableSorted(order.map { byKey[$0]! }) { rollupDisplaySymbol($0).utf16.lexicographicallyPrecedes(rollupDisplaySymbol($1).utf16) }
    }

    static func rollupExposureLabel(_ exposure: String) -> String {
        switch exposure {
        case "open_full": return "Open (synced)"
        case "open_partial": return "Open (reduced)"
        case "closed_history": return "Closed (history)"
        default: return exposure
        }
    }

    // MARK: labels

    static func snaptradeLabelsFromRows(_ rows: [HoldingRow]) -> [String: String] {
        var m: [String: String] = [:]
        for r in rows where r.source == "snaptrade" {
            let id = (r.snaptradeAccountId ?? "").holdingsTrimmed
            let label = (r.brokerLabel ?? "").holdingsTrimmed
            if id.isEmpty || label.isEmpty { continue }
            if let prev = m[id], label.count <= prev.count { continue }
            m[id] = label
        }
        return m
    }

    private static let kindShort = ["invest": "Invest", "isa": "ISA", "cash_isa": "Cash ISA", "sipp": "SIPP", "lisa": "LISA", "jisa": "JISA", "jsipp": "JSIPP"]

    static func formatRollupAccountLabel(_ ref: String, _ snaptradeLabels: [String: String] = [:]) -> String {
        if ref.hasPrefix("t212:") { return "Trading 212 · \(String(ref.dropFirst(5)).uppercased())" }
        if ref.hasPrefix("csv:") {
            let tail = String(ref.dropFirst(4))
            var slug = tail, kind = "invest"
            if let colon = tail.firstIndex(of: ":") { slug = String(tail[tail.startIndex..<colon]); kind = String(tail[tail.index(after: colon)...]) }
            let name = slug == "trading212" ? "Trading 212" : slug.components(separatedBy: "-").map { $0.holdingsCapFirst }.joined(separator: " ")
            return "\(name) · \(kindShort[kind] ?? kind.uppercased()) (CSV)"
        }
        if ref.hasPrefix("snaptrade:") {
            let id = String(ref.dropFirst(10))
            if let l = snaptradeLabels[id] { return "\(l) · SnapTrade" }
            let short = id.count > 14 ? "\(id.prefix(8))…\(id.suffix(4))" : id
            return "SnapTrade · \(short)"
        }
        return ref
    }

    // MARK: manual grouping (same keys/titles/badges as the web)

    private static func normPart(_ s: String?) -> String { let t = (s ?? "").holdingsTrimmed.lowercased(); return t.isEmpty ? "unspecified" : t }

    static func manualGroupKey(_ r: HoldingRow) -> String {
        let kind = (r.assetKind ?? "listed").holdingsTrimmed.lowercased()
        if kind == "listed" || r.assetKind == nil { return "listed__" + (r.brokerLabel ?? r.manualBrokerName ?? "Manual entry").holdingsTrimmed.lowercased() }
        if kind == "cash" {
            let fromManual = r.manualBrokerName.flatMap { $0.holdingsTrimmed.isEmpty ? nil : $0 }
            let bank = normPart(fromManual ?? ((r.brokerLabel ?? "").components(separatedBy: "·").first ?? ""))
            let inst = (r.instrumentName ?? "").holdingsTrimmed
            let parts = holdingsSplitDot(inst)
            let acct: String
            if parts.count >= 2 { acct = parts.dropFirst().joined(separator: " · ").holdingsTrimmed } else { acct = inst.isEmpty ? (r.instrumentName ?? "cash") : inst }
            return "cash__\(bank)__\(acct.lowercased())"
        }
        if kind == "real_estate" { return "property__" + (r.manualBrokerName ?? r.brokerLabel ?? "Manual entry").holdingsTrimmed.lowercased() }
        return "other__" + (r.manualBrokerName ?? r.brokerLabel ?? "Manual entry").holdingsTrimmed.lowercased()
    }

    static func manualGroupTitle(_ key: String, _ head: HoldingRow) -> String {
        if key.hasPrefix("listed__") { return (head.brokerLabel ?? head.manualBrokerName ?? "Manual entry").holdingsTrimmed }
        if key.hasPrefix("cash__") { return (head.instrumentName ?? "Cash savings").holdingsTrimmed }
        if key.hasPrefix("property__") { let t = (head.manualBrokerName ?? "Manual entry").holdingsTrimmed; return t == "Manual entry" ? "Property (manual)" : "\(t) · Property" }
        let t = (head.manualBrokerName ?? "Manual entry").holdingsTrimmed
        return t == "Manual entry" ? "Other assets (manual)" : "\(t) · Other"
    }

    static func manualKind(_ key: String) -> HoldingsGroupKind {
        if key.hasPrefix("listed__") { return .manualListed }
        if key.hasPrefix("cash__") { return .manualCash }
        if key.hasPrefix("property__") { return .manualProperty }
        return .manualOther
    }

    static func manualBadge(_ kind: HoldingsGroupKind) -> String {
        switch kind {
        case .manualListed: return "Manual listed"
        case .manualCash: return "Cash savings"
        case .manualProperty: return "Property"
        default: return "Other assets"
        }
    }

    // MARK: Monzo

    /// 0 = Accounts, 1 = Savings & ISAs, 2 = Pots.
    static func monzoSection(_ r: HoldingRow) -> Int {
        switch (r.accountKind ?? "").holdingsTrimmed.lowercased() { case "isa", "savings": return 1; case "pot": return 2; default: return 0 }
    }
    static let monzoSectionTitles = ["Accounts", "Savings & ISAs", "Pots"]

    static func monzoKindBadge(_ kind: String?) -> String? {
        switch (kind ?? "").holdingsTrimmed.lowercased() {
        case "isa": return "ISA"; case "savings": return "Savings"; case "joint": return "Joint"; case "young": return "Young"
        case "rewards": return "Rewards"; case "pot": return "Pot"; default: return nil
        }
    }

    static func monzoSections(_ rows: [HoldingRow]) -> [(title: String, rows: [HoldingRow])] {
        monzoSectionTitles.enumerated().compactMap { i, title in
            let inSection = holdingsStableSorted(rows.filter { monzoSection($0) == i }) { ($0.marketValueBase ?? 0) > ($1.marketValueBase ?? 0) }
            return inSection.isEmpty ? nil : (title, inSection)
        }
    }

    /// Monzo row name without the "Monzo ·" prefix.
    static func monzoRowName(_ r: HoldingRow) -> String {
        (r.instrumentName ?? r.ticker).replacingOccurrences(of: "^Monzo\\s*·\\s*", with: "", options: .regularExpression)
    }
}

// MARK: groups

struct HoldingsGroup {
    var key: String
    var name: String
    var rows: [HoldingRow]
    var kind: HoldingsGroupKind = .other
    var badge: String?
    var accountRef: String?
    var account: HoldingsRollupAccount?
    var closed: [HoldingsRollupLine] = []

    private static func isCash(_ r: HoldingRow) -> Bool { r.assetKind == "cash" }
    var brokerLike: Bool { kind == .t212 || kind == .snaptrade || kind == .csv }
    var listedRows: [HoldingRow] { rows.filter { HoldingsLogic.isListedAssetKind($0.assetKind) } }
    var positionCount: Int { rows.filter { !Self.isCash($0) }.count }
    var cashValue: Decimal { rows.filter(Self.isCash).reduce(0) { $0 + ($1.marketValueBase ?? 0) } }
    var totalValue: Decimal { rows.reduce(0) { $0 + ($1.marketValueBase ?? 0) } }
    var totalQty: Decimal { listedRows.reduce(0) { $0 + ($1.quantity ?? 0) } }
    /// Sum of listed-row P/L; zero (not a dash) when there is none, like the web.
    var totalPnl: Decimal { listedRows.compactMap { $0.pnlStockBase }.reduce(0, +) }
    var hasCash: Bool { rows.contains(where: Self.isCash) }
}

/// What the list renders inside a group: a single line, or several lines of the same ticker under one summary.
enum HoldingsItem {
    case single(HoldingRow)
    case multi(ticker: String, rows: [HoldingRow])
}

enum HoldingsGroups {
    private static func matchesQuery(_ q: String, _ fields: [String?]) -> Bool {
        q.isEmpty || fields.contains { $0?.range(of: q, options: .caseInsensitive) != nil }
    }

    private static func rowKey(_ r: HoldingRow) -> (String, HoldingsGroupKind) {
        switch r.source {
        case "t212":
            var ak = (r.accountKind ?? "invest").lowercased(); if ak.isEmpty { ak = "invest" }
            return ("t212:" + ak, .t212)
        case "snaptrade":
            let id = r.snaptradeAccountId ?? ""
            return ("st:" + (id.isEmpty ? (r.brokerLabel ?? "") : id), .snaptrade)
        case "csv": return ("csv:" + HoldingsLogic.csvAccountRefFromRow(r), .csv)
        case "monzo": return ("monzo", .monzo)
        case "manual": let k = HoldingsLogic.manualGroupKey(r); return (k, HoldingsLogic.manualKind(k))
        default: return ("other:\(r.source):\(r.brokerLabel ?? "null")", .other)
        }
    }

    private static func accountRefFor(_ kind: HoldingsGroupKind, _ head: HoldingRow) -> String? {
        switch kind {
        case .t212:
            var ak = (head.accountKind ?? "invest").lowercased(); if ak.isEmpty { ak = "invest" }
            return "t212:" + ak
        case .snaptrade:
            guard let id = head.snaptradeAccountId, !id.holdingsTrimmed.isEmpty else { return nil }
            return "snaptrade:\(id.holdingsTrimmed.lowercased())"
        case .csv: return HoldingsLogic.csvAccountRefFromRow(head)
        default: return nil
        }
    }

    private static func title(_ kind: HoldingsGroupKind, _ key: String, _ head: HoldingRow) -> String {
        switch kind {
        case .snaptrade: return (head.brokerLabel ?? "SnapTrade") + " · SnapTrade"
        case .monzo: return "Monzo"
        case .manualListed, .manualCash, .manualProperty, .manualOther: return HoldingsLogic.manualGroupTitle(key, head)
        default:
            if let l = head.brokerLabel, !l.holdingsTrimmed.isEmpty { return l }
            return head.source.prefix(1).uppercased() + head.source.dropFirst()
        }
    }

    private static func orderOf(_ g: HoldingsGroup) -> Int {
        switch g.kind {
        case .t212: return 0; case .snaptrade: return 1; case .csv: return 2; case .monzo: return 3
        case .manualListed: return 4; case .manualProperty: return 5; case .manualCash: return 6; case .manualOther: return 7; case .other: return 8
        }
    }

    private static func t212Rank(_ g: HoldingsGroup) -> Int {
        let r = g.accountRef.map { $0.hasPrefix("t212:") ? String($0.dropFirst(5)) : $0 }
        switch r { case "invest": return 0; case "isa": return 1; case "sipp": return 2; default: return 3 }
    }

    static func sortRows(_ rows: [HoldingRow], _ sort: HoldingsSort) -> [HoldingRow] {
        switch sort {
        case .value: return holdingsStableSorted(rows) { ($0.marketValueBase ?? 0) > ($1.marketValueBase ?? 0) }
        case .pnl: return holdingsStableSorted(rows) { ($0.pnlStockBase ?? 0) > ($1.pnlStockBase ?? 0) }
        case .name: return holdingsStableSorted(rows) { (($0.instrumentName ?? $0.ticker).lowercased()).utf16.lexicographicallyPrecedes((($1.instrumentName ?? $1.ticker).lowercased()).utf16) }
        }
    }

    /// Groups dashboard rows like the web Holdings page: one block per broker account, then Monzo, then manual groups.
    /// Search and sort are mobile extras applied inside each block.
    static func build(rows: [HoldingRow], query: String = "", sort: HoldingsSort = .value, rollups: HoldingsRollups = HoldingsRollups(),
                      exposure: HoldingsExposureFilter = .all, showSold: Bool = false) -> [HoldingsGroup] {
        let q = query.holdingsTrimmed
        let lines = rollups.lines
        var accounts: [String: HoldingsRollupAccount] = [:]
        for a in rollups.accounts { accounts[a.accountRef.holdingsTrimmed.lowercased()] = a }
        let stLabels = HoldingsLogic.snaptradeLabelsFromRows(rows)

        let visible = HoldingsLogic.applyExposureFilter(rows.filter { !HoldingsLogic.isManualListedSold($0) || showSold }, lines, exposure, showSold)
            .filter { matchesQuery(q, [$0.ticker, $0.instrumentName, $0.sector, $0.brokerLabel]) }

        var order: [String] = []
        var groups: [String: [HoldingRow]] = [:]
        var kinds: [String: HoldingsGroupKind] = [:]
        for r in visible {
            let (k, kind) = rowKey(r)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(r); kinds[k] = kind
        }

        // In Closed mode the open rows are gone, so the "already shown on an open line" suppression must see none of them.
        let bucketRows = exposure == .closed ? [] : rows
        let brokerSources: Set<String> = ["t212", "snaptrade", "csv"]
        let closedAll = lines.filter { $0.exposure == "closed_history" && brokerSources.contains($0.source) }
        let showClosed = exposure == .all || exposure == .closed

        var result: [HoldingsGroup] = []
        var usedRefs = Set<String>()
        for k in order {
            let list = groups[k]!, kind = kinds[k]!
            let head = list[0]
            let ref = accountRefFor(kind, head)
            if let ref { usedRefs.insert(ref.lowercased()) }
            let closed = (showClosed && ref != nil) ? closedFor(ref!, closedAll, bucketRows, q) : []
            var badge: String?
            switch kind {
            case .monzo: badge = "Bank (synced)"
            case .manualListed, .manualCash, .manualProperty, .manualOther: badge = HoldingsLogic.manualBadge(kind)
            default: badge = nil
            }
            result.append(HoldingsGroup(key: k, name: title(kind, k, head), rows: sortRows(list, sort), kind: kind, badge: badge,
                                        accountRef: ref, account: ref.flatMap { accounts[$0.lowercased()] }, closed: closed))
        }
        // Accounts that only have closed history still get a block.
        if showClosed {
            var seen = Set<String>(), closedRefs: [String] = []
            for l in closedAll { let r = l.accountRef.holdingsTrimmed.lowercased(); if !seen.contains(r) { seen.insert(r); closedRefs.append(r) } }
            for ref in closedRefs where !usedRefs.contains(ref) {
                let closed = closedFor(ref, closedAll, bucketRows, q)
                if closed.isEmpty { continue }
                let kind: HoldingsGroupKind = ref.hasPrefix("t212:") ? .t212 : (ref.hasPrefix("snaptrade:") ? .snaptrade : .csv)
                result.append(HoldingsGroup(key: "closed:\(ref)", name: HoldingsLogic.formatRollupAccountLabel(ref, stLabels), rows: [], kind: kind,
                                            accountRef: ref, account: accounts[ref], closed: closed))
            }
        }
        return holdingsStableSorted(result) { a, b in
            let oa = orderOf(a), ob = orderOf(b)
            if oa != ob { return oa < ob }
            let ra = a.kind == .t212 ? t212Rank(a) : 0, rb = b.kind == .t212 ? t212Rank(b) : 0
            if ra != rb { return ra < rb }
            let na = (a.kind == .t212 || a.kind == .monzo) ? "" : a.name.lowercased()
            let nb = (b.kind == .t212 || b.kind == .monzo) ? "" : b.name.lowercased()
            return na.utf16.lexicographicallyPrecedes(nb.utf16)
        }
    }

    private static func closedFor(_ ref: String, _ closedAll: [HoldingsRollupLine], _ bucketRows: [HoldingRow], _ q: String) -> [HoldingsRollupLine] {
        let mine = closedAll.filter { $0.accountRef.holdingsTrimmed.lowercased() == ref.holdingsTrimmed.lowercased() }
        let notOnListedRows = mine.filter { ru in !bucketRows.contains { r in HoldingsLogic.isListedAssetKind(r.assetKind) && HoldingsLogic.rollupMatchesListedRow(ru, r) } }
        return HoldingsLogic.dedupeClosedHistory(notOnListedRows)
            .filter { matchesQuery(q, [HoldingsLogic.rollupDisplaySymbol($0), $0.instrumentName, $0.brokerTicker]) }
    }

    /// Several lines with the same ticker collapse under one summary; cash, Monzo and non-listed manual rows stay single.
    static func items(_ group: HoldingsGroup, _ rollups: HoldingsRollups, _ exposure: HoldingsExposureFilter) -> [HoldingsItem] {
        if [.monzo, .manualCash, .manualProperty, .manualOther].contains(group.kind) { return group.rows.map { .single($0) } }
        enum Slot { case item(HoldingsItem), ticker(String) }
        var byTicker: [String: [HoldingRow]] = [:]
        var order: [Slot] = []
        for r in group.rows {
            if r.assetKind == "cash" || !HoldingsLogic.isListedAssetKind(r.assetKind) { order.append(.item(.single(r))); continue }
            let t = HoldingsLogic.displayTicker(r, HoldingsLogic.findRollupForRow(r, rollups.lines, exposure)).uppercased()
            if byTicker[t] == nil { order.append(.ticker(t)) }
            byTicker[t, default: []].append(r)
        }
        return order.map { o in
            switch o {
            case .item(let i): return i
            case .ticker(let t):
                let rs = byTicker[t]!
                return rs.count == 1 ? .single(rs[0]) : .multi(ticker: t, rows: rs)
            }
        }
    }

    /// First row (in display order) per rollup identity shows fees and dividends once, so a split position is not double counted.
    static func primaryMetricRows(_ displayOrder: [HoldingRow], _ lines: [HoldingsRollupLine], _ exposure: HoldingsExposureFilter) -> [String: String] {
        var m: [String: String] = [:]
        for r in displayOrder {
            let k = HoldingsLogic.rollupIdentityKey(HoldingsLogic.findRollupForRow(r, lines, exposure))
            if !k.isEmpty && m[k] == nil { m[k] = HoldingsLogic.rowSlotId(r) }
        }
        return m
    }

    static func displayOrder(_ items: [HoldingsItem]) -> [HoldingRow] {
        items.flatMap { i -> [HoldingRow] in
            switch i { case .single(let r): return [r]; case .multi(_, let rs): return rs }
        }
    }
}

// MARK: account summaries

struct HoldingsAccountSummary {
    var ref: String
    var label: String
    var source: String
    var account: HoldingsRollupAccount?
    var monzoBalances = 0
    var monzoTotal: Decimal?
}

struct HoldingsAccountTotals: Equatable {
    var investments, realised, unrealised, tax, fxFees, brokerCost, interest, dividends, payout: Decimal
}

enum HoldingsAccountSummaries {
    private static let sourceOrder = ["csv", "monzo", "snaptrade", "t212"]

    /// Rollup accounts ordered csv, monzo, snaptrade, t212 like the web table. The server already sends one Monzo
    /// account (`monzo:all`); only when it does not do we build a line from the dashboard's Monzo rows.
    static func build(_ rollups: HoldingsRollups, _ rows: [HoldingRow]) -> [HoldingsAccountSummary] {
        let st = HoldingsLogic.snaptradeLabelsFromRows(rows)
        let monzoRows = rows.filter { $0.source == "monzo" }
        let monzoSum = monzoRows.reduce(Decimal(0)) { $0 + ($1.marketValueBase ?? 0) }
        var list: [HoldingsAccountSummary] = rollups.accounts.map { a in
            let custom = a.displayLabel.flatMap { $0.holdingsTrimmed.isEmpty ? nil : $0 }
            if a.source == "monzo" {
                return HoldingsAccountSummary(ref: a.accountRef, label: custom ?? "Monzo · \(monzoRows.count) balances", source: "monzo", account: a,
                                              monzoBalances: monzoRows.count, monzoTotal: a.listedInvestmentsMvBaseSum ?? monzoSum)
            }
            return HoldingsAccountSummary(ref: a.accountRef, label: custom ?? HoldingsLogic.formatRollupAccountLabel(a.accountRef, st), source: a.source, account: a)
        }
        if !monzoRows.isEmpty && !list.contains(where: { $0.source == "monzo" }) {
            list.append(HoldingsAccountSummary(ref: "monzo", label: "Monzo · \(monzoRows.count) balance\(monzoRows.count == 1 ? "" : "s")", source: "monzo", account: nil,
                                               monzoBalances: monzoRows.count, monzoTotal: monzoSum))
        }
        func idx(_ s: HoldingsAccountSummary) -> Int { sourceOrder.firstIndex(of: s.source) ?? 99 }
        return holdingsStableSorted(list) { idx($0) < idx($1) }
    }

    /// Totals over every non-Monzo account; nil when there is none (the web hides the total row then).
    static func totals(_ summaries: [HoldingsAccountSummary]) -> HoldingsAccountTotals? {
        let accs = summaries.filter { $0.source != "monzo" }.compactMap { $0.account }
        if accs.isEmpty { return nil }
        func sum(_ f: (HoldingsRollupAccount) -> Decimal?) -> Decimal { accs.reduce(0) { $0 + (f($1) ?? 0) } }
        return HoldingsAccountTotals(
            investments: sum { $0.listedInvestmentsMvBaseSum }, realised: sum { $0.realisedGainBaseSum }, unrealised: sum { $0.unrealisedPnlBaseSum },
            tax: sum { $0.fillTaxBaseSum }, fxFees: sum { $0.fillFxFeesBaseSum }, brokerCost: sum { $0.fillBrokerFeesBaseSum },
            interest: sum { $0.interestOnCashBaseSum }, dividends: sum { $0.dividendPayoutBaseSum }, payout: sum { $0.combinedBrokerPayoutBaseSum })
    }
}
