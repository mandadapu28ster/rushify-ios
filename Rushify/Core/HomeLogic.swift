import Foundation

/// Pure rules behind the Home screen, ported from the Android app so both show the same numbers.
enum HomeLogic {
    private static let nonPositionKinds: Set<String> = ["cash", "real_estate", "other"]

    static func listedPositionCount(_ rows: [HoldingRow]) -> Int {
        rows.filter { $0.source != "monzo" && !nonPositionKinds.contains($0.assetKind ?? "") && $0.soldOutAt == nil }.count
    }

    /// pnl / cost as a percent, rounded half-up to 2 places; nil without a positive basis.
    static func unrealisedPct(pnl: Decimal?, cost: Decimal?) -> Decimal? {
        guard let pnl, let cost, cost != 0 else { return nil }
        var raw = pnl * 100 / cost, out = Decimal()
        NSDecimalRound(&out, &raw, 2, .plain)
        return out
    }

    /// Shown only when there are non-equity manual lines and the gain is material. Returns (gain, % p.a. blended or nil).
    static func nonEquityGain(_ d: Dashboard) -> (gain: Decimal, pct: Decimal?)? {
        guard d.nonEquityManualBasisLines > 0, let gain = d.nonEquityManualGainTotalBase, abs(gain) >= Decimal(string: "0.000000001")! else { return nil }
        return (gain, d.nonEquityManualAnnualizedPct.map { $0 * 100 })
    }

    static func bucketLabel(_ bucket: String) -> String {
        switch bucket {
        case "equity": return "Equities & funds"
        case "real_estate": return "Property (net)"
        case "cash": return "Cash savings"
        case "other": return "Other"
        default:
            let t = bucket.replacingOccurrences(of: "_", with: " ")
            return t.prefix(1).uppercased() + t.dropFirst()
        }
    }

    /// The one-line summary shown while Investments is collapsed (same parts as the web).
    static func investmentsSummary(_ d: Dashboard, hide: Bool) -> String {
        let ccy = d.baseCurrency
        var parts: [String] = []
        if let v = d.totalMarketValueBase { parts.append("Listed value: \(Fmt.money(v, ccy, hide: hide))") }
        if let v = d.totalRealisedPnlBase { parts.append("Realised P/L: \(Fmt.signedMoney(v, ccy, hide: hide))") }
        if let v = d.totalPnlBase { parts.append("Unrealised P/L: \(Fmt.signedMoney(v, ccy, hide: hide))") }
        if let v = d.dividendIncomeBrokerCashBase ?? d.dividendIncomeTotalBase { parts.append("Dividend income: \(Fmt.money(v, ccy, hide: hide))") }
        if let v = d.portfolioXirrAnnual { parts.append("XIRR: \(Fmt.percentFromFraction(v, signed: true))") }
        return parts.isEmpty ? Fmt.dash : parts.joined(separator: " · ")
    }

    static func alertsSummary(_ d: Dashboard) -> String {
        var parts: [String] = []
        if d.manualBasisIncompleteCount > 0 { parts.append("\(d.manualBasisIncompleteCount) incomplete lot\(d.manualBasisIncompleteCount == 1 ? "" : "s")") }
        if d.tickerMapAttentionCount > 0 { parts.append("\(d.tickerMapAttentionCount) ticker\(d.tickerMapAttentionCount == 1 ? "" : "s") to confirm") }
        return parts.joined(separator: " · ")
    }
}
