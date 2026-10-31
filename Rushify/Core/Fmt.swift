import Foundation

/// Pure formatting helpers. Money stays Decimal; nothing here goes through Double.
enum Fmt {
    static let hidden = "••••"
    static let dash = "—"

    private static func group(_ v: Decimal, min: Int, max: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.roundingMode = .halfUp
        f.minimumFractionDigits = min
        f.maximumFractionDigits = max
        return f.string(from: NSDecimalNumber(decimal: v)) ?? dash
    }

    static func number(_ v: Decimal?, scale: Int = 2) -> String { v.map { group($0, min: scale, max: scale) } ?? dash }

    /// At most 4 decimals, trailing zeros dropped (0.43181800 -> 0.4318, 114.519041 -> 114.519).
    static func quantity(_ v: Decimal?) -> String { v.map { group($0, min: 0, max: 4) } ?? dash }

    static func money(_ v: Decimal?, _ ccy: String?, hide: Bool = false, scale: Int = 2) -> String {
        guard let v else { return dash }
        if hide { return hidden }
        let body = group(abs(v), min: scale, max: scale)
        let neg = v < 0 ? "-" : ""
        switch ccy {
        case nil, "GBP": return "\(neg)£\(body)"
        case "USD": return "\(neg)$\(body)"
        case "EUR": return "\(neg)€\(body)"
        default: return "\(neg)\(body) \(ccy ?? "")"
        }
    }

    static func signedMoney(_ v: Decimal?, _ ccy: String?, hide: Bool = false) -> String {
        guard let v else { return dash }
        if hide { return hidden }
        return (v > 0 ? "+" : "") + money(v, ccy)
    }

    /// For values already expressed as a percent (weight_pct = 44.41).
    static func percent(_ v: Decimal?, scale: Int = 2, signed: Bool = false) -> String {
        guard let v else { return dash }
        return (signed && v > 0 ? "+" : "") + group(v, min: scale, max: scale) + "%"
    }

    /// For fractions (XIRR 0.1079 -> 10.79%).
    static func percentFromFraction(_ v: Decimal?, scale: Int = 2, signed: Bool = false) -> String {
        percent(v.map { $0 * 100 }, scale: scale, signed: signed)
    }

    static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String { "\(n) \(n == 1 ? one : (many ?? one + "s"))" }

    static func parseInstant(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter(); withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: iso) { return d }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: iso) { return d }
        // Server timestamps without a zone are UTC.
        let local = DateFormatter(); local.locale = Locale(identifier: "en_US_POSIX"); local.timeZone = TimeZone(identifier: "UTC")
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            local.dateFormat = pattern
            if let d = local.date(from: iso) { return d }
        }
        return nil
    }

    static func stamp(_ d: Date?, zone: TimeZone = .current) -> String {
        guard let d else { return dash }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = zone; f.dateFormat = "d MMM, HH:mm"
        return f.string(from: d)
    }
    static func stamp(iso: String?, zone: TimeZone = .current) -> String { stamp(parseInstant(iso), zone: zone) }
}
