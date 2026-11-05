import Foundation
import SwiftUI

/// Pure helpers behind the charts, kept separate so they can be unit-tested. Double is used for chart geometry only.
enum PerformanceChartMath {
    /// (most negative stack, most positive stack) across bars; always spans zero.
    static func stackExtent(_ stacks: [[Double]]) -> (lo: Double, hi: Double) {
        var lo = 0.0, hi = 0.0
        for st in stacks {
            lo = min(lo, st.filter { $0 < 0 }.reduce(0, +))
            hi = max(hi, st.filter { $0 > 0 }.reduce(0, +))
        }
        return (lo, hi)
    }

    /// Round up to 1, 2 or 5 times a power of ten so gridlines land on tidy numbers.
    static func niceCeil(_ v: Double) -> Double {
        if v <= 0 { return 1 }
        let exp = pow(10.0, floor(log10(v)))
        let f = v / exp
        let nice: Double = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10))
        return nice * exp
    }

    /// Min/max over every non-nil value, padded 5% so lines do not touch the frame. Flat data gets a +-1 band.
    static func lineBounds(_ series: [[Double?]]) -> (lo: Double, hi: Double) {
        let all = series.flatMap { $0 }.compactMap { $0 }
        guard let lo = all.min(), let hi = all.max() else { return (0, 1) }
        if hi - lo < 1e-6 { return (lo - 1, hi + 1) }
        let pad = (hi - lo) * 0.05
        return (lo - pad, hi + pad)
    }

    static func fraction(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        hi - lo <= 0 ? 0.5 : min(1, max(0, (v - lo) / (hi - lo)))
    }

    /// Which of `count` equal-width slots a touch at x falls into; -1 when there is nothing to hit.
    static func slotAt(_ x: Double, _ width: Double, _ count: Int) -> Int {
        if count <= 0 || width <= 0 { return -1 }
        return min(count - 1, max(0, Int(x / width * Double(count))))
    }

    /// Show every k-th x label so at most `max` appear.
    static func labelStep(_ count: Int, max m: Int = 6) -> Int { count <= m ? 1 : Int((Double(count) / Double(m)).rounded(.up)) }

    /// Evenly spaced y values for gridlines.
    static func ticks(_ lo: Double, _ hi: Double, _ n: Int = 3) -> [Double] { (0...n).map { lo + (hi - lo) * Double($0) / Double(n) } }

    static func isFlat(_ values: [Double]) -> Bool { values.isEmpty || values.allSatisfy { abs($0) < 1e-9 } }

    /// Runs of consecutive non-nil values; a nil breaks the line.
    static func segments(_ values: [Double?]) -> [[PerformanceChartPoint]] {
        var out: [[PerformanceChartPoint]] = [], cur: [PerformanceChartPoint] = []
        for (i, v) in values.enumerated() {
            if let v { cur.append(PerformanceChartPoint(i: i, v: v)) } else if !cur.isEmpty { out.append(cur); cur = [] }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Where each segment of one bar sits: positives stack upwards from zero, negatives downwards.
    static func stackSegments(_ values: [Double]) -> [(start: Double, end: Double)] {
        var pos = 0.0, neg = 0.0
        return values.map { v in
            if v >= 0 { defer { pos += v }; return (pos, pos + v) }
            defer { neg += v }; return (neg, neg + v)
        }
    }

    /// Axis label: "Aug 2026" -> "Aug '26".
    static func shortLabel(_ s: String) -> String { s.replacingOccurrences(of: " 20", with: " '") }
    static func lastChars(_ s: String, _ n: Int) -> String { String(s.suffix(n)) }
}

struct PerformanceChartPoint: Identifiable, Equatable {
    let i: Int
    let v: Double
    var id: Int { i }
}

/// `fadedFrom`: segments at this index and later are drawn translucent (estimates). `faded` fades the whole bar.
struct PerformanceStackedBar: Equatable {
    var label: String
    var values: [Double]
    var faded = false
    var fadedFrom = Int.max
}

struct PerformanceChartLine {
    var name: String
    var color: Color
    var values: [Double?]
    var dashed = false
}

/// The charts as text, for VoiceOver and tests.
enum PerformanceChartText {
    static func stacked(_ bars: [PerformanceStackedBar], names: [String], selected: Int?) -> String {
        guard !bars.isEmpty else { return "No data" }
        func line(_ b: PerformanceStackedBar) -> String {
            b.label + ": " + b.values.enumerated().map { "\(k(names, $0.offset)) \(num($0.element))" }.joined(separator: ", ")
        }
        var parts = ["\(bars.count) bars"]
        if let s = selected, bars.indices.contains(s) { parts.append("Selected " + line(bars[s])) }
        return parts.joined(separator: ". ")
    }

    static func lines(_ labels: [String], _ lines: [PerformanceChartLine], at: Int?) -> String {
        guard labels.count >= 2 else { return "No data" }
        var parts = ["\(labels.count) points from \(labels[0]) to \(labels[labels.count - 1])"]
        if let s = at, labels.indices.contains(s) {
            let vals = lines.map { ln in "\(ln.name) " + (ln.values.indices.contains(s) ? ln.values[s].map(num) ?? "no data" : "no data") }
            parts.append("Selected \(labels[s]): " + vals.joined(separator: ", "))
        }
        return parts.joined(separator: ". ")
    }

    private static func k(_ names: [String], _ i: Int) -> String { names.indices.contains(i) ? names[i] : "Series \(i + 1)" }
    private static func num(_ v: Double) -> String { String(format: "%.2f", v) }
}
