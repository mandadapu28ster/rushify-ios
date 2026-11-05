import Foundation
import SwiftUI

/// Display rules for the watchlist metrics (same as the web's watchlistFormat.ts and the Android app).
enum PulseWatchlistFormat {
    static let nm = "NM"
    private static let hundred = Decimal(100)

    /// Rounds half-up (away from zero on ties) to `dp` decimals and prints plain digits, never a negative zero.
    static func fixed(_ v: Decimal, _ dp: Int) -> String {
        var src = v, rounded = Decimal()
        NSDecimalRound(&rounded, &src, dp, .plain)
        if rounded == 0 { rounded = 0 }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.roundingMode = .halfUp
        f.minimumFractionDigits = dp
        f.maximumFractionDigits = dp
        return f.string(from: NSDecimalNumber(decimal: rounded)) ?? "\(rounded)"
    }

    private static func sign(_ v: Decimal) -> Int { v == 0 ? 0 : (v > 0 ? 1 : -1) }

    /// Ratios: nil gives a dash; zero or negative gives "NM"; 100 or more has no decimals, else 2.
    static func valuationRatio(_ v: Decimal?) -> String {
        guard let v else { return Fmt.dash }
        if v <= 0 { return nm }
        return v >= hundred ? fixed(v, 0) : fixed(v, 2)
    }

    /// ROE is already a percent number (23.52). Negative is "NM".
    static func roe(_ v: Decimal?) -> String {
        guard let v else { return Fmt.dash }
        return v < 0 ? nm : fixed(v, 2) + "%"
    }

    static func compactMoney(_ v: Decimal?) -> String {
        guard let v else { return Fmt.dash }
        let a = abs(v), s = v < 0 ? "-" : ""
        func scaled(_ div: Decimal) -> Decimal {
            var q = a / div, out = Decimal()
            NSDecimalRound(&out, &q, 6, .plain)
            return out
        }
        if a >= 1_000_000_000_000 { return s + fixed(scaled(1_000_000_000_000), 2) + "T" }
        if a >= 1_000_000_000 { return s + fixed(scaled(1_000_000_000), 2) + "B" }
        if a >= 1_000_000 { return s + fixed(scaled(1_000_000), 2) + "M" }
        if a >= 1_000 { return s + fixed(scaled(1_000), 1) + "K" }
        return s + fixed(a, 0)
    }

    static func netCashLine(_ v: Decimal?) -> String? {
        guard let v else { return nil }
        switch sign(v) {
        case 1: return "Net cash \(compactMoney(v))"
        case -1: return "Net debt \(compactMoney(abs(v)))"
        default: return "Net cash neutral"
        }
    }

    /// "ind 61.4x (2)": the median among watchlist peers in the same industry; only with 2+ peers and a positive median.
    static func industryHint(_ median: Decimal?, _ peers: Int, suffix: String = "x") -> String? {
        guard peers >= 2, let median, median > 0 else { return nil }
        let label = median >= hundred ? fixed(median, 0) : fixed(median, 1)
        return "ind \(label)\(suffix) (\(peers))"
    }

    static func isIndexLike(_ quoteType: String?) -> Bool {
        let q = (quoteType ?? "").uppercased()
        return q == "ETF" || q == "MUTUALFUND"
    }

    /// "12.60 / 9.80 fwd": trailing P/E, forward only when it is shown and differs.
    static func peText(_ item: PulseWatchItem) -> String {
        let trail = valuationRatio(item.peRatio), fwd = valuationRatio(item.forwardPeRatio)
        return fwd != Fmt.dash && fwd != trail ? "\(trail) / \(fwd) fwd" : trail
    }

    /// A value of 1 or less is a fraction (0.0459) and is shown x100; larger values are already percent.
    static func dividendPct(_ v: Decimal?) -> String {
        guard let v else { return Fmt.dash }
        return fixed(abs(v) <= 1 ? v * hundred : v, 2) + "%"
    }

    static func percentPlain(_ v: Decimal?) -> String { v.map { fixed($0, 2) + "%" } ?? Fmt.dash }

    static func price(_ v: Decimal?, _ ccy: String?) -> String {
        guard let v else { return Fmt.dash }
        return Fmt.number(v, scale: 2) + (ccy.map { " \($0)" } ?? "")
    }

    static func range52(_ low: Decimal?, _ high: Decimal?) -> String {
        low == nil && high == nil ? Fmt.dash : "\(Fmt.number(low, scale: 0))–\(Fmt.number(high, scale: 0))"
    }

    /// "Return" cell: plain percent, with a "+" when positive.
    static func returnText(_ v: Decimal?) -> String {
        let s = percentPlain(v)
        if let v, v > 0 { return "+" + s }
        return s
    }
}

/// Limits and rules for creating lists and adding symbols, as the server enforces them.
enum PulseWatchlistRules {
    static let nameMax = 64

    static func canCreate(_ w: PulseWatchlists?, _ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || n.count > nameMax { return false }
        guard let w else { return true }
        return w.limitsUnlimited || w.watchlists.count < w.maxWatchlists
    }
    static func atListCap(_ w: PulseWatchlists?) -> Bool {
        guard let w else { return false }
        return !w.limitsUnlimited && w.watchlists.count >= w.maxWatchlists
    }
    static func atItemCap(_ w: PulseWatchlists?, _ list: PulseWatchlist) -> Bool {
        guard let w else { return false }
        return !w.limitsUnlimited && list.items.count >= w.maxItemsPerWatchlist
    }
    static func newsCount(_ list: PulseWatchlist) -> Int { list.items.filter(\.fetchNews).count }
    static func hasAnyItems(_ w: PulseWatchlists?) -> Bool { w?.watchlists.contains { !$0.items.isEmpty } ?? false }
    /// Search starts at 2 characters.
    static func searchable(_ q: String) -> Bool { q.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }
}

/// Same wording as the web watchlist panel.
enum PulseRefreshMessage {
    static func of(_ r: PulseWatchlistRefresh) -> String {
        let base: String
        if r.allFresh && r.refreshed == 0 { base = "Up to date (within \(r.cacheHours)h)." }
        else if r.refreshed > 0 { base = "Refreshed \(r.refreshed) symbol\(r.refreshed == 1 ? "" : "s"). Open Pulse → News and tap Refresh there for headlines." }
        else { base = "No symbols to refresh." }
        return r.errors.isEmpty ? base : "\(base) \(r.errors.count) could not be refreshed."
    }
}

func pulseSourceLabel(_ src: String?) -> String? {
    switch src?.lowercased() {
    case "yahoo": return "Yahoo"
    case "google": return "Google News"
    case nil, "": return nil
    default: return src
    }
}

/// News feeds send HTML-flavoured text (e.g. "&nbsp;"); show it as plain text.
enum PulseNewsText {
    private static let tag = try! NSRegularExpression(pattern: "<[^>]*>")
    private static let numeric = try! NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);")
    private static let named: [(String, String)] = [("nbsp", " "), ("amp", "&"), ("lt", "<"), ("gt", ">"), ("quot", "\""), ("apos", "'"), ("#39", "'")]

    static func plain(_ s: String) -> String {
        var t = tag.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        // Numeric entities, replaced back to front so ranges stay valid.
        let ns = t as NSString
        var out = t
        for m in numeric.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
            let v = ns.substring(with: m.range(at: 1))
            let cp: UInt32? = v.lowercased().hasPrefix("x") ? UInt32(v.dropFirst(), radix: 16) : UInt32(v)
            guard let cp, let scalar = Unicode.Scalar(cp), let r = Range(m.range, in: out) else { continue }
            out.replaceSubrange(r, with: String(Character(scalar)))
        }
        t = out
        for (k, v) in named { t = t.replacingOccurrences(of: "&\(k);", with: v) }
        t = t.replacingOccurrences(of: "\u{00A0}", with: " ")
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func norm(_ s: String) -> String { String(plain(s).lowercased().filter { $0.isLetter || $0.isNumber }) }

    /// Summary worth showing under `title`: nil when blank or it only repeats the headline (optionally plus the publisher).
    static func summary(_ title: String, _ summary: String?, _ publisher: String? = nil) -> String? {
        guard let summary else { return nil }
        let s = plain(summary)
        if s.isEmpty { return nil }
        let ns = norm(s), nt = norm(title)
        if ns == nt { return nil }
        if !nt.isEmpty, ns.hasPrefix(nt), let publisher, String(ns.dropFirst(nt.count)) == norm(publisher) { return nil }
        return s
    }
}

/// News links come from third-party feeds. Only absolute http/https URLs with a host may be opened.
enum PulseSafeUrl {
    static func httpOrNull(_ raw: String?) -> URL? {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return nil }
        guard var c = URLComponents(string: text), let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = c.host, !host.isEmpty else { return nil }
        c.scheme = scheme; c.host = host.lowercased()
        if c.path.isEmpty { c.path = "/" }
        return c.url
    }
}

/// Score bands and bucket colours, as on the web (hex values so they can be tested).
enum PulseRadarColors {
    static func scoreHex(_ v: Int) -> UInt32 {
        if v >= 72 { return 0x22C55E }; if v >= 58 { return 0x84CC16 }; if v >= 45 { return 0xEAB308 }; if v >= 32 { return 0xF97316 }
        return 0xEF4444
    }
    static func bucketHex(_ key: String) -> UInt32 {
        switch key {
        case "strong_buy": return 0x15803D
        case "buy": return 0x4ADE80
        case "neutral": return 0xEAB308
        case "sell": return 0xF87171
        case "strong_sell": return 0xB91C1C
        case "index_fund": return 0x6366F1
        default: return 0x64748B
        }
    }
    static func score(_ v: Int) -> Color { Color(hex: scoreHex(v)) }
    static func bucket(_ key: String) -> Color { Color(hex: bucketHex(key)) }
}

/// Health gauge fraction (1.00 to max) and radar geometry, kept pure for tests.
enum PulseChartMath {
    static func gaugeFraction(score: Double, max: Double) -> Double {
        guard max > 1 else { return 0 }
        return Swift.min(1, Swift.max(0, (score - 1) / (max - 1)))
    }
    /// Point for axis `i` of `n` at fraction `f` of the radius (axis 0 points up, clockwise).
    static func radarPoint(center: CGPoint, radius: Double, i: Int, n: Int, f: Double, extra: Double = 0) -> CGPoint {
        let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(n)
        return CGPoint(x: center.x + (radius * f + extra) * cos(a), y: center.y + (radius * f + extra) * sin(a))
    }
}
