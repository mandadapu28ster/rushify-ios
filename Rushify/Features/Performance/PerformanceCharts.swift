import Charts
import SwiftUI

/// Touch handling shared by the charts: maps a touch to a slot with PerformanceChartMath.slotAt over the plot area.
private struct PerformanceSlotOverlay: View {
    let proxy: ChartProxy
    let count: Int
    let drag: Bool
    let onSelect: (Int) -> Void
    var body: some View {
        GeometryReader { geo in
            let pick: (CGPoint) -> Void = { p in
                guard let anchor = proxy.plotFrame else { return }
                let r = geo[anchor]
                let i = PerformanceChartMath.slotAt(Double(p.x - r.minX), Double(r.width), count)
                if i >= 0 { onSelect(i) }
            }
            let base = Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { pick($0.location) })
            if drag { base.simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { pick($0.location) }) } else { base }
        }
    }
}

struct PerformanceLegendDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 9, height: 9); Muted(text) }
    }
}

struct PerformanceBarSeg: Identifiable { let id: Int; let x: Double; let start: Double; let end: Double; let color: Color }

struct PerformanceBarSegmentMark: ChartContent {
    let seg: PerformanceBarSeg
    let half: Double
    var body: some ChartContent {
        let x0: PlottableValue<Double> = .value("From", seg.x - half)
        let x1: PlottableValue<Double> = .value("To", seg.x + half)
        let y0: PlottableValue<Double> = .value("Start", seg.start)
        let y1: PlottableValue<Double> = .value("End", seg.end)
        RectangleMark(xStart: x0, xEnd: x1, yStart: y0, yEnd: y1).foregroundStyle(seg.color)
    }
}

/// Bars stacked from a zero line: positives upwards, negatives downwards. Tap a bar to select it.
/// Faded segments (forecasts) are drawn translucent so estimates are never mistaken for actuals.
struct PerformanceStackedBarChart: View {
    let bars: [PerformanceStackedBar]
    let colors: [Color]
    let selected: Int?
    let onSelect: (Int) -> Void
    var height: CGFloat = 190
    var description = "Bar chart"
    var seriesNames: [String] = []
    var averageLine: Double?
    var zoneFromIndex: Int?
    var identifier = "stacked_chart"


    private func xText(_ v: Double?) -> String {
        guard let v, bars.indices.contains(Int(v)) else { return "" }
        return PerformanceChartMath.shortLabel(bars[Int(v)].label)
    }

    private func barSegments() -> [PerformanceBarSeg] {
        var out: [PerformanceBarSeg] = []
        for (i, b) in bars.enumerated() {
            for (k, seg) in PerformanceChartMath.stackSegments(b.values).enumerated() {
                let faded = b.faded || k >= b.fadedFrom
                let base: Color = colors[k % colors.count]
                out.append(PerformanceBarSeg(id: i * 1000 + k, x: Double(i), start: seg.start, end: seg.end, color: base.opacity(faded ? 0.45 : 1)))
            }
        }
        return out
    }

    var body: some View {
        let n = bars.count
        let ext = PerformanceChartMath.stackExtent(bars.map { $0.values })
        let top = PerformanceChartMath.niceCeil(max(ext.hi, 0.0001))
        let bottom = ext.lo < 0 ? -PerformanceChartMath.niceCeil(-ext.lo) : 0
        let step = PerformanceChartMath.labelStep(n)
        let half = min(0.31, 13 / (300.0 / Double(max(n, 1))))   // bar width: 62% of a slot, capped at about 26pt
        let xs = stride(from: 0, to: n, by: step).map(Double.init)
        let segments = barSegments()
        Group {
            if n == 0 { Color.clear.frame(height: height) } else {
                Chart {
                    if let z = zoneFromIndex, bars.indices.contains(z) {
                        RectangleMark(xStart: .value("Zone start", Double(z) - 0.5), xEnd: .value("Zone end", Double(n) - 0.5),
                                      yStart: .value("Bottom", bottom), yEnd: .value("Top", top))
                            .foregroundStyle(RColors.muted.opacity(0.10))
                    }
                    if let s = selected, bars.indices.contains(s) {
                        RectangleMark(xStart: .value("Sel start", Double(s) - 0.5), xEnd: .value("Sel end", Double(s) + 0.5),
                                      yStart: .value("Bottom", bottom), yEnd: .value("Top", top))
                            .foregroundStyle(RColors.text.opacity(0.14))
                    }
                    ForEach(segments) { seg in
                        PerformanceBarSegmentMark(seg: seg, half: half)
                    }
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(RColors.muted).lineStyle(StrokeStyle(lineWidth: 1))
                    if let a = averageLine {
                        RuleMark(y: .value("Average", a)).foregroundStyle(RColors.warn).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                    }
                }
                .chartXScale(domain: -0.5...(Double(n) - 0.5))
                .chartYScale(domain: bottom...top)
                .chartXAxis {
                    AxisMarks(values: xs) { v in
                        AxisValueLabel(xText(v.as(Double.self))).font(.system(size: 10)).foregroundStyle(RColors.muted)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: PerformanceChartMath.ticks(bottom, top, 3)) { v in
                        AxisGridLine().foregroundStyle(RColors.variant)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.compact(d)).font(.system(size: 10)).foregroundStyle(RColors.muted) } }
                    }
                }
                .chartOverlay { proxy in PerformanceSlotOverlay(proxy: proxy, count: n, drag: false, onSelect: onSelect) }
                .frame(height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .accessibilityValue(PerformanceChartText.stacked(bars, names: seriesNames, selected: selected))
        .accessibilityIdentifier(identifier)
        .accessibilityAdjustableAction { dir in
            guard n > 0 else { return }
            let cur = selected ?? n - 1
            onSelect(dir == .increment ? min(n - 1, cur + 1) : max(0, cur - 1))
        }
    }
}

/// Multi-series line chart. Tap or drag to move the cursor; the caller shows the values for `selected`.
struct PerformanceLineChart: View {
    let xLabels: [String]
    let lines: [PerformanceChartLine]
    let selected: Int?
    let onSelect: (Int) -> Void
    var height: CGFloat = 190
    var description = "Line chart"
    var identifier = "line_chart"

    private func xText(_ v: Double?) -> String {
        guard let v, xLabels.indices.contains(Int(v)) else { return "" }
        return xLabels[Int(v)]
    }

    private var n: Int { xLabels.count }
    private var bounds: (lo: Double, hi: Double) { PerformanceChartMath.lineBounds(lines.map { $0.values }) }
    private var xTicks: [Double] { stride(from: 0, to: n, by: PerformanceChartMath.labelStep(n)).map(Double.init) }

    // The chart is built from small pieces: one large expression takes older Swift compilers too long to type-check.
    @ChartContentBuilder private var lineMarks: some ChartContent {
        ForEach(Array(lines.enumerated()), id: \.offset) { li, ln in
            let segs = PerformanceChartMath.segments(ln.values)
            ForEach(Array(segs.enumerated()), id: \.offset) { si, seg in
                ForEach(seg) { pt in
                    LineMark(x: .value("x", pt.i), y: .value(ln.name, pt.v), series: .value("series", "\(li)-\(si)"))
                        .foregroundStyle(ln.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: ln.dashed ? [7, 5] : []))
                }
            }
        }
    }

    @ChartContentBuilder private var cursorMarks: some ChartContent {
        if let s = selected, xLabels.indices.contains(s) {
            RuleMark(x: .value("Cursor", s)).foregroundStyle(RColors.text.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(Array(lines.enumerated()), id: \.offset) { _, ln in
                if ln.values.indices.contains(s), let v = ln.values[s] {
                    PointMark(x: .value("x", s), y: .value(ln.name, v)).foregroundStyle(ln.color).symbolSize(40)
                }
            }
        }
    }

    @AxisContentBuilder private var xAxisMarks: some AxisContent {
        AxisMarks(values: xTicks) { v in
            AxisValueLabel(xText(v.as(Double.self))).font(.system(size: 10)).foregroundStyle(RColors.muted)
        }
    }

    @AxisContentBuilder private var yAxisMarks: some AxisContent {
        AxisMarks(values: PerformanceChartMath.ticks(bounds.lo, bounds.hi, 3)) { v in
            AxisGridLine().foregroundStyle(RColors.variant)
            AxisValueLabel { yLabel(v.as(Double.self)) }
        }
    }

    @ViewBuilder private func yLabel(_ d: Double?) -> some View {
        if let d { Text(Fmt.compact(d)).font(.system(size: 10)).foregroundStyle(RColors.muted) }
    }

    private var chart: some View {
        let lo = bounds.lo, hi = bounds.hi, count = n
        return Chart { lineMarks; cursorMarks }
            .chartXScale(domain: 0...Double(count - 1), range: .plotDimension(padding: 6))
            .chartYScale(domain: lo...hi)
            .chartXAxis { xAxisMarks }
            .chartYAxis { yAxisMarks }
            .chartOverlay { proxy in PerformanceSlotOverlay(proxy: proxy, count: count, drag: true, onSelect: onSelect) }
            .frame(height: height)
    }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(description)
            .accessibilityValue(PerformanceChartText.lines(xLabels, lines, at: selected))
            .accessibilityIdentifier(identifier)
            .accessibilityAdjustableAction { dir in
                guard n > 0 else { return }
                let cur = selected ?? n - 1
                onSelect(dir == .increment ? min(n - 1, cur + 1) : max(0, cur - 1))
            }
    }

    @ViewBuilder private var content: some View {
        if n < 2 { Color.clear.frame(height: height) } else { chart }
    }
}
