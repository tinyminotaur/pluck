import CoreGraphics
import TwangCore
import XCTest

final class MagnetPullTests: XCTestCase {
    func testStiffestAtContactAndRelaxesWithDistance() {
        var last = CGFloat.greatestFiniteMagnitude
        for d in stride(from: CGFloat(0), through: 400, by: 10) {
            let w = MagnetPull.omega(distance: d, base: 50, stick: 0.9)
            XCTAssertLessThanOrEqual(w, last + 1e-6)
            last = w
        }
        XCTAssertEqual(MagnetPull.omega(distance: 0, base: 50, stick: 0.9), 95, accuracy: 0.01)
        XCTAssertEqual(MagnetPull.omega(distance: 1000, base: 50, stick: 0.9), 50, accuracy: 0.01)
    }

    func testZeroStickIsAPlainSpring() {
        XCTAssertEqual(MagnetPull.omega(distance: 0, base: 50, stick: 0), 50, accuracy: 1e-6)
        XCTAssertEqual(MagnetPull.omega(distance: 30, base: 50, stick: 0), 50, accuracy: 1e-6)
    }

    func testSpringTracksTargetWithBoundedLag() {
        // Drive a head toward a target moving at 800 pt/s with the real spring step.
        var head = CGPoint.zero
        var v = CGPoint.zero
        let h: CGFloat = 1.0 / 240
        var t: CGFloat = 0
        while t < 1.0 {
            let target = CGPoint(x: 800 * t, y: 0)
            var x = CGPoint(x: head.x - target.x, y: head.y - target.y)
            let omega = MagnetPull.omega(distance: hypot(x.x, x.y), base: 52, stick: 0.9)
            RecoilSpring.step(x: &x, v: &v, omega: omega, zeta: 0.62, h: h)
            head = CGPoint(x: target.x + x.x, y: target.y + x.y)
            t += h
        }
        let lag = 800 * 1.0 - head.x
        XCTAssertGreaterThan(lag, 5, "the liquid should trail a fast pull")
        XCTAssertLessThan(lag, 60, "but not feel detached from the cursor")
    }
}
