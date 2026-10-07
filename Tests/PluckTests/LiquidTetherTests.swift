import CoreGraphics
import PluckCore
import XCTest

final class LiquidTetherTests: XCTestCase {
    private func run(dt: CGFloat, until T: CGFloat, path: (CGFloat) -> CGPoint) -> LiquidTether {
        var t = LiquidTether()
        t.begin(pin: CGPoint(x: 500, y: 500), roles: CompassRole.allCases)
        t.setBloom(true)
        var time: CGFloat = 0
        while time < T {
            t.setTarget(path(time))
            t.advance(dt: dt)
            time += dt
        }
        return t
    }

    private func sweep(_ time: CGFloat) -> CGPoint {
        CGPoint(x: 500 + min(1, time / 0.3) * 180, y: 500 + sin(time * 5) * 20)
    }

    func testFrameRateIndependence() {
        let a = run(dt: 1.0 / 60, until: 0.6, path: sweep)
        let b = run(dt: 1.0 / 120, until: 0.6, path: sweep)
        let c = run(dt: 1.0 / 144, until: 0.6, path: sweep)
        XCTAssertEqual(a.headPosition.x, b.headPosition.x, accuracy: 6)
        XCTAssertEqual(b.headPosition.x, c.headPosition.x, accuracy: 6)
        XCTAssertEqual(a.headPosition.y, b.headPosition.y, accuracy: 6)
    }

    func testHeadSettlesOnTarget() {
        let t = run(dt: 1.0 / 120, until: 1.5) { _ in CGPoint(x: 640, y: 560) }
        XCTAssertEqual(t.headPosition.x, 640, accuracy: 0.5)
        XCTAssertEqual(t.headPosition.y, 560, accuracy: 0.5)
    }

    func testHeadLagIsSmall() {
        // Steady 600 pt/s pull: the visible head should trail the target by well under a tenth of a second of travel.
        let t = run(dt: 1.0 / 120, until: 0.5) { time in CGPoint(x: 500 + 600 * time, y: 500) }
        let target = CGPoint(x: 500 + 600 * 0.5, y: 500)
        XCTAssertLessThan(GestureMath.distance(t.headPosition, target), 600 * 0.06)
    }

    func testNoNaNsAndBoundedRadii() {
        var t = LiquidTether()
        t.begin(pin: .zero, roles: CompassRole.allCases)
        t.setBloom(true)
        for i in 0..<600 {
            let a = CGFloat(i) * 0.37
            t.setTarget(CGPoint(x: cos(a) * 340, y: sin(a * 1.3) * 340))
            t.advance(dt: 1.0 / 60)
            for p in t.primitives() {
                XCTAssertFalse(p.a.x.isNaN || p.a.y.isNaN || p.ra.isNaN || p.rb.isNaN)
                XCTAssertLessThan(p.ra, 120)
                XCTAssertLessThan(p.rb, 120)
            }
        }
    }

    func testAreaStaysNearConservedWhileStretching() {
        var t = LiquidTether(params: LiquidTetherParams(slosh: 0))
        t.begin(pin: .zero, roles: [])
        for _ in 0..<120 {
            t.setTarget(CGPoint(x: 220, y: 0))
            t.advance(dt: 1.0 / 120)
        }
        let prims = t.primitives()
        XCTAssertFalse(prims.isEmpty)
        let radii = prims.map(\.ra) + [prims.last!.rb]
        let len = hypot(prims.last!.b.x - prims.first!.a.x, prims.last!.b.y - prims.first!.a.y)
        let area = BlobMass.approximateArea(radii: radii, length: len)
        let target = t.params.mass.totalArea
        XCTAssertEqual(area, target, accuracy: target * 0.35) // end floors deliberately add a little mass
    }

    func testCancelFinishes() {
        var t = run(dt: 1.0 / 120, until: 0.4) { _ in CGPoint(x: 600, y: 500) }
        t.release(commit: nil, role: nil)
        var time: CGFloat = 0
        while !t.isFinished && time < 2 { t.advance(dt: 1.0 / 120); time += 1.0 / 120 }
        XCTAssertTrue(t.isFinished)
        XCTAssertLessThan(time, 1.2)
        XCTAssertTrue(t.primitives().isEmpty)
    }

    func testCommitSpawnsDropletThenFinishes() {
        var t = run(dt: 1.0 / 120, until: 0.4) { _ in CGPoint(x: 620, y: 500) }
        t.release(commit: CGPoint(x: 1, y: 0), role: .east)
        t.advance(dt: 1.0 / 120)
        XCTAssertFalse(t.primitives().isEmpty)
        var time: CGFloat = 0
        while !t.isFinished && time < 2 { t.advance(dt: 1.0 / 120); time += 1.0 / 120 }
        XCTAssertTrue(t.isFinished)
        XCTAssertLessThan(time, 1.2)
    }

    func testReduceMotionHasNoOvershoot() {
        var params = LiquidTetherParams()
        params.reduceMotion = true
        var t = LiquidTether(params: params)
        t.begin(pin: .zero, roles: CompassRole.allCases)
        t.setBloom(true)
        t.setTarget(CGPoint(x: 150, y: 0))
        t.advance(dt: 1.0 / 60)
        XCTAssertEqual(t.headPosition.x, 150, accuracy: 0.001)
        XCTAssertEqual(t.emergence, 1, accuracy: 0.001)
    }

    func testLobesBloomOnlyForAvailableRoles() {
        var t = LiquidTether()
        t.begin(pin: .zero, roles: [.north, .east])
        t.setBloom(true)
        for _ in 0..<90 { t.advance(dt: 1.0 / 120) }
        let anchors = t.lobeAnchors()
        XCTAssertEqual(Set(anchors.map(\.role)), [.north, .east])
        let north = anchors.first { $0.role == .north }!
        XCTAssertGreaterThan(north.center.y, 60, "north lobe is above the pin (y up)")
        XCTAssertGreaterThan(north.presence, 0.8)
    }
}
