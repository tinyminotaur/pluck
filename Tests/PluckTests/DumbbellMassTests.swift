import CoreGraphics
import PluckCore
import XCTest

final class DumbbellMassTests: XCTestCase {
    let p = DumbbellMass.Params()

    func testAtRestIsOneRoundDrop() {
        let s = DumbbellMass.solve(p, length: 0)
        XCTAssertEqual(s.pin, p.restRadius, accuracy: 0.01)
        XCTAssertEqual(s.head, p.restRadius, accuracy: 0.01)
    }

    func testBulbsShrinkMonotonicallyAsItStretches() {
        var lastPin = CGFloat.greatestFiniteMagnitude, lastHead = CGFloat.greatestFiniteMagnitude
        for L in stride(from: CGFloat(0), through: 900, by: 10) {
            let s = DumbbellMass.solve(p, length: L)
            XCTAssertLessThanOrEqual(s.pin, lastPin + 1e-6, "pin at \(L)")
            XCTAssertLessThanOrEqual(s.head, lastHead + 1e-6, "head at \(L)")
            lastPin = s.pin; lastHead = s.head
        }
    }

    func testWaistThinsButStaysVisible() {
        let a = DumbbellMass.solve(p, length: 80).waist
        let b = DumbbellMass.solve(p, length: 400).waist
        let c = DumbbellMass.solve(p, length: 3000).waist
        XCTAssertGreaterThan(a, b)
        XCTAssertGreaterThanOrEqual(c, DumbbellMass.minWaist)
    }

    func testBulbsStaySubstantialAtAnyLength() {
        // Barbell, not tadpole: even at a huge stretch each bulb is still a clear mass.
        for L in stride(from: CGFloat(150), through: 1500, by: 150) {
            let s = DumbbellMass.solve(p, length: L)
            XCTAssertGreaterThan(s.pin, 0.5 * p.restRadius, "pin at \(L)")
            XCTAssertGreaterThan(s.head, 0.5 * p.restRadius, "head at \(L)")
            XCTAssertLessThan(s.waist, 0.4 * s.pin, "thread stays delicate at \(L)")
        }
    }

    func testBulbsAreMatchedByDefaultSoItDoesNotReadAsHeadAndTail() {
        let s = DumbbellMass.solve(p, length: 300)
        XCTAssertEqual(s.pin, s.head, accuracy: 0.01)
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
