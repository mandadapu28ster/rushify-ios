import SwiftUI

/// Five (or n) axis radar, scores 0..100, with a dashed benchmark ring at 100 on every axis.
struct PulseRadarChart: View {
    let labels: [String]
    let scores: [Int]
    var size: CGFloat = 280

    var body: some View {
        Canvas { ctx, sz in
            let n = max(labels.count, 3)
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r = Double(sz.width / 2 - 44)
            func pt(_ i: Int, _ f: Double, _ extra: Double = 0) -> CGPoint { PulseChartMath.radarPoint(center: c, radius: r, i: i, n: n, f: f, extra: extra) }
            for ring in [0.25, 0.5, 0.75, 1.0] {
                var p = Path()
                for i in 0..<n { i == 0 ? p.move(to: pt(i, ring)) : p.addLine(to: pt(i, ring)) }
                p.closeSubpath()
                if ring == 1 { ctx.stroke(p, with: .color(RColors.muted), style: StrokeStyle(lineWidth: 1.2, dash: [10, 8])) }
                else { ctx.stroke(p, with: .color(RColors.variant), lineWidth: 1) }
            }
            for i in 0..<n { var spoke = Path(); spoke.move(to: c); spoke.addLine(to: pt(i, 1)); ctx.stroke(spoke, with: .color(RColors.variant), lineWidth: 1) }
            func frac(_ s: Int) -> Double { min(1, max(0, Double(s) / 100)) }
            var poly = Path()
            for (i, s) in scores.enumerated() { i == 0 ? poly.move(to: pt(i, frac(s))) : poly.addLine(to: pt(i, frac(s))) }
            poly.closeSubpath()
            ctx.fill(poly, with: .color(RColors.accent.opacity(0.25)))
            ctx.stroke(poly, with: .color(RColors.accent), lineWidth: 2)
            for (i, s) in scores.enumerated() {
                let o = pt(i, frac(s))
                ctx.fill(Path(ellipseIn: CGRect(x: o.x - 3.5, y: o.y - 3.5, width: 7, height: 7)), with: .color(RColors.accent))
            }
            for (i, l) in labels.enumerated() {
                let t = Text("\(l)\n\(i < scores.count ? scores[i] : 0)").font(.r(10)).foregroundColor(RColors.muted)
                ctx.draw(ctx.resolve(t), at: pt(i, 1, 22), anchor: .center)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Radar chart: " + zip(labels, scores).map { "\($0.0) \($0.1)" }.joined(separator: ", "))
        .accessibilityIdentifier("radar_chart")
    }
}

/// Health gauge, 1.00 to max, drawn as a 240 degree arc.
struct PulseHealthGauge: View {
    let score: Decimal
    let maxScore: Decimal
    var size: CGFloat = 150

    var body: some View {
        let s = (score as NSDecimalNumber).doubleValue, m = (maxScore as NSDecimalNumber).doubleValue   // chart geometry only
        let frac = PulseChartMath.gaugeFraction(score: s, max: m)
        let color = frac < 0.4 ? RColors.loss : (frac < 0.65 ? RColors.warn : RColors.gain)
        ZStack {
            Canvas { ctx, sz in
                let stroke: CGFloat = 14
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2), r = (sz.width - stroke) / 2
                func arc(_ sweep: Double) -> Path {
                    var p = Path()
                    let steps = max(2, Int(sweep))
                    for k in 0...steps {
                        let a = CGFloat((150 + sweep * Double(k) / Double(steps)) * Double.pi / 180)   // explicit CGFloat: older compilers find cos/sin ambiguous
                        let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                        k == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    return p
                }
                let style = StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
                ctx.stroke(arc(240), with: .color(RColors.variant), style: style)
                if frac > 0 { ctx.stroke(arc(240 * frac), with: .color(color), style: style) }
            }
            VStack(spacing: 0) {
                Num(Fmt.number(score, scale: 2), color: color, size: 28, bold: true)
                Muted("of \(NSDecimalNumber(decimal: maxScore).intValue).00")
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score \(Fmt.number(score, scale: 2)) of \(Fmt.number(maxScore, scale: 2))")
    }
}

/// Thin horizontal bar: `fraction` 0...1 of the width is filled.
struct PulseBar: View {
    let fraction: Double
    var color: Color
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RColors.variant
                if fraction > 0 { color.frame(width: g.size.width * min(1, fraction)) }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
