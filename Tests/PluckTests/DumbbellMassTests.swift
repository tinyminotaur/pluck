import CoreGraphics
import PluckCore
import XCTest

final class DumbbellMassTests: XCTestCase {
    let p = DumbbellMass.Params()

    func testAtRestIsOneRoundDrop() {
        let s = DumbbellMass.solve(p, length: 0)
        XCTAssertEqual(s.pin, p.restRadius, accuracy: 2)
        XCTAssertLessThan(s.head, 0.3 * p.restRadius)   // the head is still hidden in the drop
    }

    func testPinShrinksAtEveryStepOutAndRegrowsComingBack() {
        var last = CGFloat.greatestFiniteMagnitude
        for L in stride(from: CGFloat(0), through: 1500, by: 5) {
            let pin = DumbbellMass.solve(p, length: L).pin
            XCTAssertLessThan(pin, last, "pin must be strictly smaller at \(L)")
            last = pin
        }
        // Coming back is the same curve in reverse: strictly growing.
        var prev = DumbbellMass.solve(p, length: 1500).pin
        for L in stride(from: CGFloat(1495), through: 0, by: -5) {
            let pin = DumbbellMass.solve(p, length: L).pin
            XCTAssertGreaterThan(pin, prev, "pin must grow back at \(L)")
            prev = pin
        }
    }

    func testMassIsConservedBetweenPinHeadAndThread() {
        let M0 = CGFloat.pi * p.restRadius * p.restRadius
        for L in stride(from: CGFloat(0), through: 700, by: 25) {
            let s = DumbbellMass.solve(p, length: L)
            let total = CGFloat.pi * (s.pin * s.pin + s.head * s.head) + 2 * s.waist * L
            // Exact except for the tiny hidden-head floor near rest.
            XCTAssertEqual(total, M0, accuracy: 0.03 * M0, "mass at \(L)")
        }
    }

    func testThePinnedBodyStaysTheHeavierOne() {
        for L in stride(from: CGFloat(60), through: 1500, by: 60) {
            let s = DumbbellMass.solve(p, length: L)
            XCTAssertGreaterThan(s.pin, s.head, "pin is the big mass at \(L)")
        }
    }

    func testHeadGainsMassAsItLeavesThePin() {
        let a = DumbbellMass.solve(p, length: 40).head
        let b = DumbbellMass.solve(p, length: 200).head
        XCTAssertGreaterThan(b, a)
    }

    func testWaistThinsButStaysVisible() {
        let a = DumbbellMass.solve(p, length: 80).waist
        let b = DumbbellMass.solve(p, length: 400).waist
        let c = DumbbellMass.solve(p, length: 3000).waist
        XCTAssertGreaterThan(a, b)
        XCTAssertGreaterThanOrEqual(c, DumbbellMass.minWaist)
    }

    func testThreadStaysDelicateAtAnyLength() {
        for L in stride(from: CGFloat(150), through: 1500, by: 150) {
            let s = DumbbellMass.solve(p, length: L)
            XCTAssertLessThan(s.waist, 0.4 * s.pin, "thread stays delicate at \(L)")
        }
    }

    func testProfileIsAWaistBetweenTwoBulbsWithConcaveFlares() {
        let (r, sol) = DumbbellMass.profile(p, length: 360, samples: 40)
        XCTAssertEqual(r.count, 40)
        XCTAssertGreaterThan(r.first!, r[r.count / 2])
        XCTAssertGreaterThan(r.last!, r[r.count / 2])
        XCTAssertGreaterThanOrEqual(r.min()!, sol.waist - 1e-6)
        // Smooth: no step between neighbours larger than a gentle fraction of the bulb.
        for i in 1..<r.count { XCTAssertLessThan(abs(r[i] - r[i - 1]), sol.pin * 0.5) }
        // Concave toward the waist on the pin side: the flare falls fast, then flattens.
        let drop1 = r[0] - r[3], drop2 = r[3] - r[6]
        XCTAssertGreaterThan(drop1, drop2)
    }

    func testThickerWaistParameterGivesAThickerThread() {
        let thin = DumbbellMass.solve(.init(waistRest: 0.12), length: 300).waist
        let thick = DumbbellMass.solve(.init(waistRest: 0.34), length: 300).waist
        XCTAssertGreaterThan(thick, thin)
    }
}
