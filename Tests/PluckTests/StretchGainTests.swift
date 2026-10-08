import CoreGraphics
import PluckCore
import XCTest

final class StretchGainTests: XCTestCase {
    func testStartsAtZeroAndReachesTheEdgeExactlyAtTheEdge() {
        XCTAssertEqual(GestureMath.reachLength(0, maxDist: 900, gain: 1.8), 0, accuracy: 1e-6)
        XCTAssertEqual(GestureMath.reachLength(900, maxDist: 900, gain: 1.8), 900, accuracy: 1e-3)
        // Past the edge (e.g. pointer on another display) it simply stays at the edge.
        XCTAssertEqual(GestureMath.reachLength(1400, maxDist: 900, gain: 1.8), 900, accuracy: 1e-6)
    }

    func testStrictlyIncreasingSoItNeverStopsOrSnapsBack() {
        var last: CGFloat = -1
        for d in stride(from: CGFloat(0), through: 900, by: 3) {
            let v = GestureMath.reachLength(d, maxDist: 900, gain: 1.8)
            XCTAssertGreaterThan(v, last, "must keep growing at \(d)")
            XCTAssertLessThanOrEqual(v, 900 + 1e-3)
            last = v
        }
    }

    func testShortPullsAreExaggerated() {
        XCTAssertGreaterThan(GestureMath.reachLength(80, maxDist: 900, gain: 1.8), 80 * 1.8)
        // About half the travel already covers well over half the distance to the edge.
        XCTAssertGreaterThan(GestureMath.reachLength(450, maxDist: 900, gain: 1.8), 620)
    }

    func testZeroGainIsPlainOneToOne() {
        XCTAssertEqual(GestureMath.reachLength(300, maxDist: 900, gain: 0), 300, accuracy: 0.5)
    }

    func testRayDistanceToEachEdge() {
        let r = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let p = CGPoint(x: 400, y: 200)
        XCTAssertEqual(GestureMath.rayDistance(from: p, direction: CGPoint(x: 1, y: 0), in: r), 600, accuracy: 1e-6)
        XCTAssertEqual(GestureMath.rayDistance(from: p, direction: CGPoint(x: -1, y: 0), in: r), 400, accuracy: 1e-6)
        XCTAssertEqual(GestureMath.rayDistance(from: p, direction: CGPoint(x: 0, y: 1), in: r), 400, accuracy: 1e-6)
        XCTAssertEqual(GestureMath.rayDistance(from: p, direction: CGPoint(x: 0, y: -1), in: r), 200, accuracy: 1e-6)
    }

    func testHeadCanReachAnyPointOnScreenAndNeverLeavesIt() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let pin = CGPoint(x: 500, y: 300)
        for ang in stride(from: 0.0, to: 6.28, by: 0.4) {
            let dir = CGPoint(x: cos(ang), y: sin(ang))
            let edge = GestureMath.rayDistance(from: pin, direction: dir, in: bounds)
            // Pointer exactly at the screen edge in that direction puts the head exactly there.
            let atEdge = CGPoint(x: pin.x + dir.x * edge, y: pin.y + dir.y * edge)
            let h = GestureMath.reachHead(pin: pin, pointer: atEdge, bounds: bounds, gain: 1.8)
            XCTAssertEqual(h.x, atEdge.x, accuracy: 0.01)
            XCTAssertEqual(h.y, atEdge.y, accuracy: 0.01)
            // A pointer far beyond the screen still keeps the head on screen.
            let far = CGPoint(x: pin.x + dir.x * 5000, y: pin.y + dir.y * 5000)
            let hf = GestureMath.reachHead(pin: pin, pointer: far, bounds: bounds, gain: 1.8)
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(hf))
        }
    }

    func testHeadKeepsDirection() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let h = GestureMath.reachHead(pin: CGPoint(x: 100, y: 100), pointer: CGPoint(x: 100, y: 160), bounds: bounds, gain: 1.8)
        XCTAssertEqual(h.x, 100, accuracy: 1e-6)
        XCTAssertGreaterThan(h.y, 160)
    }
}
