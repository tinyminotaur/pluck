import CoreGraphics
import PluckCore
import XCTest

final class RecoilSpringTests: XCTestCase {
    private func simulate(zeta: CGFloat, seconds: CGFloat = 1.2) -> (minX: CGFloat, final: CGFloat) {
        let h: CGFloat = 1.0 / 240
        let omega = RecoilSpring.omega(period: 0.30)
        var x = CGPoint(x: 200, y: 0)
        var v = CGPoint.zero
        var minX = x.x
        for _ in 0..<Int(seconds / h) {
            RecoilSpring.step(x: &x, v: &v, omega: omega, zeta: zeta, h: h)
            minX = min(minX, x.x)
        }
        return (minX, x.x)
    }

    func testSettlesAtPin() {
        let r = simulate(zeta: RecoilSpring.zeta(bounce: 0.6))
        XCTAssertEqual(r.final, 0, accuracy: 1.0)
    }

    func testBouncyOvershootsPin() {
        // Negative x means the head crossed the pin.
        let r = simulate(zeta: RecoilSpring.zeta(bounce: 1.0))
        XCTAssertLessThan(r.minX, -10)
    }

    func testOverdampedDoesNotOvershoot() {
        let r = simulate(zeta: 1.2)
        XCTAssertGreaterThan(r.minX, -1)
    }

    func testBounceMapsToDampingRange() {
        XCTAssertEqual(RecoilSpring.zeta(bounce: 0), 0.72, accuracy: 1e-6)
        XCTAssertEqual(RecoilSpring.zeta(bounce: 1), 0.22, accuracy: 1e-6)
        XCTAssertEqual(RecoilSpring.zeta(bounce: 5), 0.22, accuracy: 1e-6)
    }
}
