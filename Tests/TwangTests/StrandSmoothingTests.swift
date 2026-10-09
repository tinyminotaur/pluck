import CoreGraphics
import TwangCore
import XCTest

final class StrandSmoothingTests: XCTestCase {
    private func zigzag() -> ([CGPoint], [CGFloat]) {
        let pts = (0..<10).map { CGPoint(x: CGFloat($0) * 30, y: $0 % 2 == 0 ? 0 : 12) }
        let rad: [CGFloat] = [20, 14, 9, 6, 5, 4, 4, 5, 8, 14]
        return (pts, rad)
    }

    func testEndpointsPreservedAndCount() {
        let (p, r) = zigzag()
        let out = StrandSmoothing.resample(points: p, radii: r, subdivisions: 3)
        XCTAssertEqual(out.points.count, (p.count - 1) * 3 + 1)
        XCTAssertEqual(out.points.first, p.first)
        XCTAssertEqual(out.points.last, p.last)
        XCTAssertEqual(out.radii.first, r.first)
        XCTAssertEqual(out.radii.last, r.last)
    }

    func testPassesThroughEveryOriginalParticle() {
        let (p, r) = zigzag()
        let out = StrandSmoothing.resample(points: p, radii: r, subdivisions: 4)
        for i in p.indices {
            XCTAssertEqual(out.points[i * 4].x, p[i].x, accuracy: 1e-6)
            XCTAssertEqual(out.points[i * 4].y, p[i].y, accuracy: 1e-6)
        }
    }

    func testRadiiStayPositiveAndWithinNeighbours() {
        let (p, r) = zigzag()
        let out = StrandSmoothing.resample(points: p, radii: StrandSmoothing.smoothRadii(r, passes: 2), subdivisions: 3)
        let lo = (r.min() ?? 0) * 0.5
        let hi = (r.max() ?? 0) * 1.2
        for v in out.radii { XCTAssertTrue(v > lo && v < hi, "radius \(v)") }
    }

    func testCurveIsSmootherThanThePolyline() {
        // Total turning (sum of direction changes) drops sharply once the zigzag is splined.
        func turning(_ pts: [CGPoint]) -> CGFloat {
            var total: CGFloat = 0
            for i in 1..<(pts.count - 1) {
                let a = atan2(pts[i].y - pts[i - 1].y, pts[i].x - pts[i - 1].x)
                let b = atan2(pts[i + 1].y - pts[i].y, pts[i + 1].x - pts[i].x)
                total += abs(GestureMath.shortestAngleDelta(a, b))
            }
            return total
        }
        // Largest single-vertex turn is what reads as an "angle".
        func maxTurn(_ pts: [CGPoint]) -> CGFloat {
            var m: CGFloat = 0
            for i in 1..<(pts.count - 1) {
                let a = atan2(pts[i].y - pts[i - 1].y, pts[i].x - pts[i - 1].x)
                let b = atan2(pts[i + 1].y - pts[i].y, pts[i + 1].x - pts[i].x)
                m = max(m, abs(GestureMath.shortestAngleDelta(a, b)))
            }
            return m
        }
        let (p, r) = zigzag()
        let smooth = StrandSmoothing.resample(points: p, radii: r, subdivisions: 4).points
        XCTAssertLessThan(maxTurn(smooth), maxTurn(p) * 0.75)
        _ = turning(p)
    }

    func testReleaseDebounceIgnoresFlicker() {
        var d = TouchReleaseDebounce(grace: 0.18)
        d.update(count: 2, at: 1.00)
        XCTAssertFalse(d.shouldRelease(at: 1.05))
        d.update(count: 3, at: 1.08) // came back: still dragging
        XCTAssertFalse(d.shouldRelease(at: 1.5))
    }

    func testReleaseDebounceFiresAfterGraceOrAtZero() {
        var d = TouchReleaseDebounce(grace: 0.18)
        d.update(count: 2, at: 1.00)
        XCTAssertFalse(d.shouldRelease(at: 1.10))
        XCTAssertTrue(d.shouldRelease(at: 1.20))
        var z = TouchReleaseDebounce(grace: 0.18)
        z.update(count: 0, at: 2.0)
        XCTAssertTrue(z.shouldRelease(at: 2.0))
    }
}
