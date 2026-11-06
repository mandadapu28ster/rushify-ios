import XCTest
import SwiftUI
import UIKit
@testable import Rushify

final class PaletteTests: XCTestCase {
    private func lum(_ c: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (x, y) = (lum(a), lum(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    private let surfaces: [Color] = [RColors.bg, RColors.surface, RColors.variant]

    override func tearDown() { RPalette.set(colorBlindFriendly: false) }

    func testTextAndMutedReadableOnEverySurface() {
        for s in surfaces {
            XCTAssertGreaterThanOrEqual(contrast(RColors.text, s), 7)
            XCTAssertGreaterThanOrEqual(contrast(RColors.muted, s), 7)
        }
    }
    func testRolesMeetAAOnEverySurface() {
        for cb in [false, true] {
            RPalette.set(colorBlindFriendly: cb)
            for s in surfaces {
                for c in [RColors.accent, RColors.warn, RColors.gain, RColors.loss] {
                    XCTAssertGreaterThanOrEqual(contrast(c, s), 4.5, "cb=\(cb)")
                }
            }
        }
    }
    func testChartColoursVisibleAgainstCards() {
        for c in RColors.categorical { XCTAssertGreaterThanOrEqual(contrast(c, RColors.surface), 3) }
    }
    func testCategoricalColoursAreNeverGreenOrRed() {
        for c in RColors.categorical {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let deg = Double(h) * 360
            let greenish = deg > 75 && deg < 170, reddish = deg < 15 || deg > 345
            XCTAssertFalse(s > 0.25 && (greenish || reddish), "hue \(deg)")
        }
    }
    func testColourBlindPaletteSwapsGainAndLoss() {
        let g0 = lum(RColors.gain), l0 = lum(RColors.loss)
        RPalette.set(colorBlindFriendly: true)
        XCTAssertNotEqual(lum(RColors.gain), g0); XCTAssertNotEqual(lum(RColors.loss), l0)
        XCTAssertGreaterThan(contrast(RColors.gain, RColors.loss), 2)
    }
    func testPnlColourAndArrow() {
        XCTAssertEqual(RColors.arrow(5), "▲"); XCTAssertEqual(RColors.arrow(-5), "▼"); XCTAssertEqual(RColors.arrow(0), "")
    }
    func testMotionRespectsReduceMotion() {
        XCTAssertEqual(RMotion.stagger(3, reduce: true), 0)
        XCTAssertGreaterThan(RMotion.stagger(3, reduce: false), 0)
        XCTAssertEqual(RMotion.stagger(50, reduce: false), RMotion.stagger(6, reduce: false))
    }
    func testWrapperAndCashColoursStable() {
        XCTAssertEqual(UIColor(HoldingsPalette.cashColor("Cash Foo")), UIColor(HoldingsPalette.cashColor("Cash Foo")))
    }
}
