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

    func testVolumeIsRoughlyConservedOnceSeparated() {
        let area0 = CGFloat.pi * p.restRadius * p.restRadius
        for L in [150, 250, 400, 600] as [CGFloat] {
            let s = DumbbellMass.solve(p, length: L)
            let total = CGFloat.pi * (s.pin * s.pin + s.head * s.head) + 2 * s.waist * L
            XCTAssertEqual(total, area0, accuracy: area0 * 0.25, "L=\(L)")
        }
    }

    func testPinKeepsMoreMassThanHead() {
        let s = DumbbellMass.solve(p, length: 300)
        XCTAssertGreaterThan(s.pin, s.head)
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
