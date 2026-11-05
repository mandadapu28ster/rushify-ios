import XCTest
@testable import Rushify

final class PerformanceChartMathTests: XCTestCase {
    typealias M = PerformanceChartMath

    func testStackExtentSplitsPositiveAndNegativeSums() {
        let e = M.stackExtent([[100, -20, 5], [-300, 40], [876, -58, 12]])
        XCTAssertEqual(e.lo, -300, accuracy: 0.001); XCTAssertEqual(e.hi, 888, accuracy: 0.001)
    }
    func testStackExtentAlwaysSpansZero() {
        XCTAssertTrue(M.stackExtent([]) == (0, 0))
        XCTAssertTrue(M.stackExtent([[5]]) == (0, 5))
        XCTAssertTrue(M.stackExtent([[-5]]) == (-5, 0))
    }
    func testNiceCeilUsesOneTwoFive() {
        XCTAssertEqual(M.niceCeil(0.7), 1, accuracy: 1e-9); XCTAssertEqual(M.niceCeil(1.3), 2, accuracy: 1e-9); XCTAssertEqual(M.niceCeil(3.2), 5, accuracy: 1e-9)
        XCTAssertEqual(M.niceCeil(7), 10, accuracy: 1e-9); XCTAssertEqual(M.niceCeil(436), 500, accuracy: 1e-9); XCTAssertEqual(M.niceCeil(13_000), 20_000, accuracy: 1e-6)
    }
    func testNiceCeilHandlesZeroAndNegative() { XCTAssertEqual(M.niceCeil(0), 1); XCTAssertEqual(M.niceCeil(-4), 1) }
    func testLineBoundsPadAndIgnoreNils() {
        let b = M.lineBounds([[100, nil, 110], [nil, 90]])
        XCTAssertEqual(b.lo, 89, accuracy: 0.001); XCTAssertEqual(b.hi, 111, accuracy: 0.001)
    }
    func testLineBoundsFlatDataGetsABand() {
        let b = M.lineBounds([[100, 100]])
        XCTAssertTrue(b.lo < 100 && b.hi > 100)
    }
    func testLineBoundsEmpty() { XCTAssertTrue(M.lineBounds([[], [nil]]) == (0, 1)) }
    func testFractionClampsAndHandlesDegenerateRange() {
        XCTAssertEqual(M.fraction(5, 0, 10), 0.5); XCTAssertEqual(M.fraction(-3, 0, 10), 0); XCTAssertEqual(M.fraction(99, 0, 10), 1)
        XCTAssertEqual(M.fraction(1, 2, 2), 0.5)
    }
    func testSlotAtMapsTapsToBars() {
        XCTAssertEqual(M.slotAt(0, 300, 3), 0); XCTAssertEqual(M.slotAt(150, 300, 3), 1); XCTAssertEqual(M.slotAt(299, 300, 3), 2)
        XCTAssertEqual(M.slotAt(999, 300, 3), 2); XCTAssertEqual(M.slotAt(-50, 300, 3), 0); XCTAssertEqual(M.slotAt(5, 300, 0), -1)
        XCTAssertEqual(M.slotAt(5, 0, 3), -1)
    }
    func testLabelStepKeepsAtMostSixLabels() {
        XCTAssertEqual(M.labelStep(5), 1); XCTAssertEqual(M.labelStep(12), 2); XCTAssertEqual(M.labelStep(93), 16)
        XCTAssertTrue(Array(stride(from: 0, to: 93, by: M.labelStep(93))).count <= 6)
    }
    func testTicksAreEvenlySpaced() { XCTAssertEqual(M.ticks(0, 30, 3), [0, 10, 20, 30]) }
    func testFlatDetection() { XCTAssertTrue(M.isFlat([0, 0])); XCTAssertFalse(M.isFlat([0, 1])); XCTAssertTrue(M.isFlat([])) }
    func testCompactAxisLabels() {
        XCTAssertEqual(Fmt.compact(950), "950"); XCTAssertEqual(Fmt.compact(1200), "1.2k"); XCTAssertEqual(Fmt.compact(20000), "20k")
        XCTAssertEqual(Fmt.compact(-10000), "-10k"); XCTAssertEqual(Fmt.compact(3_400_000), "3.4M"); XCTAssertEqual(Fmt.compact(112_345), "112k")
    }

    // Swift-side additions: line gaps, stack positions, labels, text readout.
    func testSegmentsBreakAtNilsLikeAndroidPaths() {
        let s = M.segments([1, 2, nil, 4, nil, nil, 7, 8])
        XCTAssertEqual(s.map { $0.map { $0.i } }, [[0, 1], [3], [6, 7]])
        XCTAssertEqual(s[0][1].v, 2); XCTAssertTrue(M.segments([nil, nil]).isEmpty)
    }
    func testStackSegmentsPutPositivesUpAndNegativesDown() {
        let s = M.stackSegments([10, -4, 5, -1])
        XCTAssertTrue(s[0] == (0, 10)); XCTAssertTrue(s[1] == (0, -4)); XCTAssertTrue(s[2] == (10, 15)); XCTAssertTrue(s[3] == (-4, -5))
    }
    func testAxisLabelShortening() {
        XCTAssertEqual(M.shortLabel("Aug 2026"), "Aug '26"); XCTAssertEqual(M.shortLabel("Next 6m"), "Next 6m"); XCTAssertEqual(M.lastChars("2026-07-14", 5), "07-14")
    }
    func testChartsReadableAsText() {
        let bars = [PerformanceStackedBar(label: "Aug 2026", values: [90, 10]), PerformanceStackedBar(label: "Sep 2026", values: [-290.5, 40.25])]
        let t = PerformanceChartText.stacked(bars, names: ["Price", "FX"], selected: 1)
        XCTAssertTrue(t.contains("2 bars")); XCTAssertTrue(t.contains("Selected Sep 2026: Price -290.50, FX 40.25"), t)
        XCTAssertEqual(PerformanceChartText.stacked([], names: [], selected: nil), "No data")
        let lt = PerformanceChartText.lines(["a", "b", "c"], [PerformanceChartLine(name: "P", color: .red, values: [1, nil, 3])], at: 1)
        XCTAssertTrue(lt.contains("3 points from a to c")); XCTAssertTrue(lt.contains("P no data"), lt)
    }
}
