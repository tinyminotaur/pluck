import CoreGraphics
import PluckCore
import XCTest

final class StretchGainTests: XCTestCase {
    func testMonotonicAndNeverStopsDeadBeforeTheCap() {
        var last: CGFloat = -1
        for d in stride(from: CGFloat(0), through: 1500, by: 5) {
            let v = GestureMath.virtualLength(d, gainBoost: 1.3, maxLength: 700)
            XCTAssertGreaterThanOrEqual(v, last - 1e-6, "monotonic at \(d)")
            XCTAssertLessThanOrEqual(v, 700 + 1e-3)
            last = v
        }
        // Still growing at 400 pt of pointer travel (no hard stop).
        XCTAssertGreaterThan(GestureMath.virtualLength(420, gainBoost: 1.3, maxLength: 700),
                             GestureMath.virtualLength(400, gainBoost: 1.3, maxLength: 700) + 0.5)
    }

    func testNearPinIsOneToOneAndFartherIsExaggerated() {
        XCTAssertEqual(GestureMath.virtualLength(8, gainBoost: 1.3, maxLength: 700), 8, accuracy: 0.5)
        XCTAssertGreaterThan(GestureMath.virtualLength(140, gainBoost: 1.3, maxLength: 700), 140 * 2.0)
        // A short 80 pt pull already reads clearly longer than 80.
        XCTAssertGreaterThan(GestureMath.virtualLength(80, gainBoost: 1.3, maxLength: 700), 100)
    }

    func testZeroBoostIsPlain() {
        XCTAssertEqual(GestureMath.virtualLength(90, gainBoost: 0, maxLength: 700), 90, accuracy: 1e-6)
    }

    func testVirtualHeadKeepsDirection() {
        let pin = CGPoint(x: 100, y: 100)
        let h = GestureMath.virtualHead(pin: pin, pointer: CGPoint(x: 100, y: 160), gainBoost: 1.3, maxLength: 700)
        XCTAssertEqual(h.x, 100, accuracy: 1e-6)
        XCTAssertGreaterThan(h.y, 160)
    }
}
