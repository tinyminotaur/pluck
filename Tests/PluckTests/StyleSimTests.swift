import CoreGraphics
import PluckCore
import XCTest

final class StyleSimTests: XCTestCase {
    // MARK: Ferrofluid

    private func ferro(chord: CGFloat, seconds: CGFloat = 1.5) -> FerroSim {
        var f = FerroSim()
        let pin = CGPoint(x: 300, y: 300)
        f.reset(pin: pin)
        var t: CGFloat = 0
        let dt: CGFloat = 1.0 / 120
        while t < seconds {
            let k = min(1, t / 0.25)
            f.step(dt: dt, pin: pin, head: CGPoint(x: pin.x + chord * k, y: pin.y))
            t += dt
        }
        return f
    }

    func testFerroIsSmoothAtRestAndBristlesWhenPulled() {
        let rest = ferro(chord: 0).primitives(emerge: 1)
        let pulled = ferro(chord: 220).primitives(emerge: 1)
        XCTAssertEqual(rest.filter { $0.kind == .cone }.count, 0, "a magnet-less drop has no spikes")
        XCTAssertGreaterThan(pulled.filter { $0.kind == .cone }.count, 8)
    }

    /// Length-weighted mean direction of the spikes in `cones`.
    private func meanDirection(_ cones: [ShapePrim]) -> CGFloat {
        var sx: CGFloat = 0, sy: CGFloat = 0
        for c in cones {
            let dx = c.b.x - c.a.x, dy = c.b.y - c.a.y
            let l = hypot(dx, dy)
            guard l > 0 else { continue }
            sx += dx; sy += dy
        }
        return atan2(sy, sx)
    }

    func testFerroSpikesPointAtTheMagnet() {
        let f = ferro(chord: 260)
        let cones = f.primitives(emerge: 1).filter { $0.kind == .cone && $0.a.x < 340 }   // the pin's fan
        XCTAssertFalse(cones.isEmpty)
        // The fan is centred on the magnet (+x) and symmetric about it.
        XCTAssertEqual(meanDirection(cones), 0, accuracy: 0.1)
        let upper = cones.filter { $0.b.y > 300 }.count, lower = cones.filter { $0.b.y < 300 }.count
        XCTAssertLessThanOrEqual(abs(upper - lower), 1)
    }

    func testFerroFilingsAppearOnlyWhenTheMagnetIsFar() {
        func beads(_ chord: CGFloat) -> Int { ferro(chord: chord).primitives(emerge: 1).filter { $0.kind == .circle && $0.blend == .tight }.count }
        XCTAssertEqual(beads(40), 0)
        XCTAssertGreaterThan(beads(400), 10)
    }

    func testFerroFanSwingsAroundWithLagWhenTheMagnetMoves() {
        var f = FerroSim()
        let pin = CGPoint.zero
        f.reset(pin: pin)
        for _ in 0..<240 { f.step(dt: 1.0 / 120, pin: pin, head: CGPoint(x: 250, y: 0)) }
        // Jump the magnet to the top: the fan must not snap instantly.
        f.step(dt: 1.0 / 120, pin: pin, head: CGPoint(x: 0, y: 250))
        let pinFan = { (f: FerroSim) in f.primitives(emerge: 1).filter { $0.kind == .cone && hypot($0.a.x, $0.a.y) < 30 } }
        XCTAssertLessThan(meanDirection(pinFan(f)), 0.4, "one frame later the fan has barely turned")
        for _ in 0..<420 { f.step(dt: 1.0 / 120, pin: pin, head: CGPoint(x: 0, y: 250)) }
        XCTAssertEqual(meanDirection(pinFan(f)), .pi / 2, accuracy: 0.1, "and it settles on the new bearing")
    }

    func testFerroOutputIsFiniteAndBounded() {
        var f = FerroSim()
        f.reset(pin: .zero)
        for i in 0..<600 {
            let a = CGFloat(i) * 0.31
            f.step(dt: 1.0 / 120, pin: .zero, head: CGPoint(x: cos(a) * 380, y: sin(a * 1.3) * 380))
        }
        let prims = f.primitives(emerge: 1)
        XCTAssertLessThanOrEqual(prims.count, 96)
        for p in prims {
            XCTAssertTrue(p.a.x.isFinite && p.a.y.isFinite && p.b.x.isFinite && p.ra.isFinite)
        }
    }

    // MARK: Crystal

    private func crystal(chord: CGFloat, seconds: CGFloat) -> CrystalSim {
        var c = CrystalSim()
        let pin = CGPoint(x: 300, y: 300)
        c.reset(pin: pin, seed: 5)
        var t: CGFloat = 0
        let dt: CGFloat = 1.0 / 120
        while t < seconds {
            let k = min(1, t / 0.8)
            c.step(dt: dt, pin: pin, head: CGPoint(x: pin.x + chord * k, y: pin.y + 20 * sin(k * 5)))
            t += dt
        }
        return c
    }

    func testCrystalGrowsABranchingFormationAlongYourPath() {
        let still = crystal(chord: 0, seconds: 1.5)
        let pulled = crystal(chord: 420, seconds: 2.5)
        XCTAssertGreaterThan(pulled.shardCount, still.shardCount + 5, "travel seeds branches")
        XCTAssertLessThanOrEqual(pulled.shardCount, CrystalSim.Params().maxShards)
    }

    func testCrystalEvolvesWhileHeld() {
        var c = CrystalSim()
        c.reset(pin: .zero, seed: 3)
        c.step(dt: 1.0 / 120, pin: .zero, head: CGPoint(x: 200, y: 0))
        let early = c.primitives(emerge: 1).reduce(CGFloat(0)) { $0 + hypot($1.b.x - $1.a.x, $1.b.y - $1.a.y) }
        for _ in 0..<(120 * 6) { c.step(dt: 1.0 / 120, pin: .zero, head: CGPoint(x: 200, y: 0)) }
        let late = c.primitives(emerge: 1).reduce(CGFloat(0)) { $0 + hypot($1.b.x - $1.a.x, $1.b.y - $1.a.y) }
        XCTAssertGreaterThan(late, early * 1.5, "total crystal length keeps growing while you hold")
    }

    func testCrystalNeedleReachesTheHeadAndStaysCrisp() {
        let c = crystal(chord: 300, seconds: 3)
        let main = c.primitives(emerge: 1).filter { $0.kind == .shard && $0.ra > 2.4 }
            .max { hypot($0.b.x - $0.a.x, $0.b.y - $0.a.y) < hypot($1.b.x - $1.a.x, $1.b.y - $1.a.y) }!
        XCTAssertEqual(hypot(main.b.x - main.a.x, main.b.y - main.a.y), 300 - 13, accuracy: 40)
    }

    func testCrystalShattersIntoFlyingFragmentsThatFade() {
        var c = crystal(chord: 300, seconds: 2)
        c.shatter(direction: CGPoint(x: 1, y: 0))
        XCTAssertTrue(c.isShattered)
        let start = c.primitives(emerge: 1).count
        XCTAssertGreaterThan(start, 10)
        for _ in 0..<(120) { c.step(dt: 1.0 / 120, pin: CGPoint(x: 300, y: 300), head: CGPoint(x: 600, y: 300)) }
        XCTAssertTrue(c.isFinished || c.primitives(emerge: 1).count < start)
        for _ in 0..<120 { c.step(dt: 1.0 / 120, pin: CGPoint(x: 300, y: 300), head: CGPoint(x: 600, y: 300)) }
        XCTAssertTrue(c.isFinished)
        XCTAssertTrue(c.primitives(emerge: 1).isEmpty)
    }

    func testCrystalRetractsOnCancel() {
        var c = crystal(chord: 300, seconds: 2)
        c.retract()
        for _ in 0..<80 { c.step(dt: 1.0 / 120, pin: CGPoint(x: 300, y: 300), head: CGPoint(x: 600, y: 300)) }
        XCTAssertTrue(c.isFinished)
        let long = c.primitives(emerge: 1).filter { $0.kind == .shard }.contains { hypot($0.b.x - $0.a.x, $0.b.y - $0.a.y) > 12 }
        XCTAssertFalse(long)
    }

    func testStylesCoverAllCases() {
        XCTAssertEqual(AnimationStyle.allCases.count, 8)
        for s in AnimationStyle.allCases { XCTAssertFalse(s.name.isEmpty); XCTAssertFalse(s.tagline.isEmpty) }
    }
}

final class AstroSimTests: XCTestCase {
    private func run(chord: CGFloat, seconds: CGFloat = 2) -> AstroSim {
        var a = AstroSim()
        let pin = CGPoint(x: 500, y: 500)
        a.reset(pin: pin)
        var t: CGFloat = 0
        while t < seconds {
            let k = min(1, t / 0.5)
            a.step(dt: 1.0 / 120, pin: pin, head: CGPoint(x: pin.x + chord * k, y: pin.y))
            t += 1.0 / 120
        }
        return a
    }

    func testThePinnedBodyPullsHarderAndDrainsAsTheHeadMovesAway() {
        let near = run(chord: 60), far = run(chord: 500)
        XCTAssertGreaterThan(far.gravity().pin, far.gravity().head)
        XCTAssertGreaterThan(near.pinRadius, far.pinRadius)
        XCTAssertGreaterThan(far.headRadius, near.headRadius)
    }

    func testGrainsStayFiniteAndBoundedWhileStretched() {
        let a = run(chord: 700, seconds: 6)
        let prims = a.primitives(emerge: 1)
        XCTAssertEqual(prims.count > 2, true)
        for p in prims { XCTAssertTrue(p.a.x.isFinite && p.a.y.isFinite && p.ra.isFinite) }
        XCTAssertEqual(a.grainCount, AstroSim.Params().grains)
    }

    func testReleaseFinishes() {
        var a = run(chord: 300)
        a.release(commit: CGPoint(x: 1, y: 0))
        for _ in 0..<100 { a.step(dt: 1.0 / 120, pin: CGPoint(x: 500, y: 500), head: CGPoint(x: 800, y: 500)) }
        XCTAssertTrue(a.isFinished)
    }
}

final class DelightSimTests: XCTestCase {
    private let pin = CGPoint(x: 400, y: 400)
    private func head(_ k: CGFloat, _ chord: CGFloat) -> CGPoint { CGPoint(x: pin.x + chord * k, y: pin.y + 10 * k) }

    func testPearlsHangBetweenTheEndsAndNeverOverstretch() {
        var p = PearlSim(); p.reset(pin: pin)
        for i in 0..<400 { p.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 100), 500)) }
        let prims = p.primitives(emerge: 1)
        XCTAssertEqual(prims.count, p.beadCount)          // pearls + the two ends
        for q in prims { XCTAssertTrue(q.a.x.isFinite && q.a.y.isFinite && q.ra > 0) }
    }

    func testSwarmStreamsTowardTheHead() {
        var s = SwarmSim(); s.reset(pin: pin)
        for i in 0..<600 { s.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 100), 600)) }
        let xs = s.primitives(emerge: 1).dropFirst(2).map { $0.a.x }
        XCTAssertGreaterThan(xs.max()!, pin.x + 350)
        XCTAssertEqual(xs.count > 20, true)
    }

    func testTendrilsReachTowardTheHeadAndTaper() {
        var t = TendrilSim(); t.reset(pin: pin)
        for i in 0..<500 { t.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 100), 400)) }
        let cones = t.primitives(emerge: 1).filter { $0.kind == .cone }
        XCTAssertGreaterThan(cones.map { $0.b.x }.max()!, pin.x + 150)
        XCTAssertTrue(cones.allSatisfy { $0.ra >= $0.rb - 1e-6 })
    }

    func testAllReleaseToFinished() {
        var p = PearlSim(); p.reset(pin: pin)
        var s = SwarmSim(); s.reset(pin: pin)
        var t = TendrilSim(); t.reset(pin: pin)
        p.release(commit: CGPoint(x: 1, y: 0)); s.release(commit: CGPoint(x: 1, y: 0)); t.release(commit: CGPoint(x: 1, y: 0))
        for _ in 0..<100 {
            p.step(dt: 1 / 120, pin: pin, head: head(1, 300)); s.step(dt: 1 / 120, pin: pin, head: head(1, 300))
            t.step(dt: 1 / 120, pin: pin, head: head(1, 300))
        }
        XCTAssertTrue(p.isFinished && s.isFinished && t.isFinished)
    }

    func testCritterHopsOverTheRopeAndLandsBack() {
        var j = JumpRopeSim(); j.reset(pin: pin)
        var maxLift: CGFloat = 0, grounded = 0
        for i in 0..<800 {
            j.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 60), 500))
            if i > 150 { maxLift = max(maxLift, j.critterLift); if j.critterLift < 0.5 { grounded += 1 } }
        }
        XCTAssertGreaterThan(maxLift, 15)       // it actually leaves the ground
        XCTAssertGreaterThan(grounded, 100)     // and spends time landed
        XCTAssertTrue(j.primitives(emerge: 1).allSatisfy { $0.a.x.isFinite && $0.a.y.isFinite })
    }
}
