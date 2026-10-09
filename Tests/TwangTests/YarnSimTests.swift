import CoreGraphics
import TwangCore
import XCTest

final class YarnSimTests: XCTestCase {
    private func stretched(to x: CGFloat, seconds: CGFloat = 1.5) -> YarnLassoSim {
        var sim = YarnLassoSim()
        sim.base.bodyRadius = 40
        sim.reset(pin: .zero)
        let dt: CGFloat = 1.0 / 120
        var t: CGFloat = 0
        while t < seconds {
            let k = min(1, t / 0.6)
            sim.step(dt: dt, pin: .zero, head: CGPoint(x: x * k, y: 0))
            t += dt
        }
        return sim
    }

    func testBallShrinksAsThreadIsLetOut() {
        let near = stretched(to: 20).scene(emerge: 1)
        let far = stretched(to: 700).scene(emerge: 1)
        XCTAssertGreaterThan(near.ballRadius, far.ballRadius)
        XCTAssertGreaterThan(far.ballRadius, 10)   // never vanishes
    }

    func testThreadRunsFromBallToLoop() {
        let s = stretched(to: 300).scene(emerge: 1)
        let first = s.thread.first!, last = s.thread.last!
        XCTAssertEqual(hypot(first.x - s.ballCenter.x, first.y - s.ballCenter.y), s.ballRadius * 0.95, accuracy: 1.0)
        XCTAssertEqual(hypot(last.x - s.loopCenter.x, last.y - s.loopCenter.y), s.loopRadius, accuracy: 1.5)
    }

    func testBallRollsWhileThreadFeeds() {
        XCTAssertGreaterThan(abs(stretched(to: 400).scene(emerge: 1).ballSpin), 1)
    }

    func testCommitThrowsCinchesAndRewinds() {
        var sim = stretched(to: 300)
        let before = sim.scene(emerge: 1).loopRadius
        sim.release(commit: CGPoint(x: 1, y: 0))
        let dt: CGFloat = 1.0 / 120
        var radiusAtSwell: CGFloat = 0, radiusAfterCinch: CGFloat = 1e9, t: CGFloat = 0
        while t < 0.6 {
            sim.step(dt: dt, pin: .zero, head: CGPoint(x: 300, y: 0)); t += dt
            let r = sim.scene(emerge: 1).loopRadius
            if abs(t - 0.14) < dt { radiusAtSwell = r }
            if t > 0.34 { radiusAfterCinch = min(radiusAfterCinch, r) }
        }
        XCTAssertGreaterThan(radiusAtSwell, before)          // the loop swells as it is thrown
        XCTAssertLessThan(radiusAfterCinch, before * 0.4)    // then cinches shut
        while !sim.isFinished { sim.step(dt: dt, pin: .zero, head: CGPoint(x: 300, y: 0)) }
        XCTAssertLessThan(sim.scene(emerge: 1).alpha, 0.05)
    }

    func testCancelJustRewinds() {
        var sim = stretched(to: 300)
        sim.release(commit: nil)
        var t: CGFloat = 0
        while t < 0.6 { sim.step(dt: 1.0 / 120, pin: .zero, head: CGPoint(x: 300, y: 0)); t += 1.0 / 120 }
        let s = sim.scene(emerge: 1)
        XCTAssertLessThan(hypot(s.loopCenter.x, s.loopCenter.y), 40)   // the loop is back at the ball
        XCTAssertEqual(s.flash, 0)                                      // no landing flash on a cancel
    }

    func testZeroChordIsFinite() {
        var sim = YarnLassoSim()
        sim.reset(pin: CGPoint(x: 5, y: 5))
        sim.step(dt: 1.0 / 60, pin: CGPoint(x: 5, y: 5), head: CGPoint(x: 5, y: 5))
        let s = sim.scene(emerge: 1)
        for p in s.thread + s.tail { XCTAssertTrue(p.x.isFinite && p.y.isFinite) }
        XCTAssertTrue(s.ballRadius.isFinite && s.loopRadius.isFinite)
    }
}
