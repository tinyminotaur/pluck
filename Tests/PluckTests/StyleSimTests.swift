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
        XCTAssertEqual(AnimationStyle.allCases.count, 38)
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

    func testStarsDrawAConstellationThatScattersOnCommit() {
        var st = StarSim(); st.reset(pin: pin)
        for i in 0..<400 { st.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 80), 500)) }
        let sc = st.scene(emerge: 1)
        XCTAssertGreaterThan(sc.pin.size, sc.headStar.size)       // the pinned star is the big one
        XCTAssertEqual(sc.lines.count, sc.stars.count + 1)
        XCTAssertTrue(sc.shooting.isEmpty)
        st.release(commit: CGPoint(x: 1, y: 0))
        for _ in 0..<40 { st.step(dt: 1 / 120, pin: pin, head: head(1, 500)) }
        XCTAssertEqual(st.scene(emerge: 1).shooting.count, 1)
    }

    func testKiteTailTrailsAndReleaseFliesAway() {
        var k = KiteSim(); k.reset(pin: pin)
        for i in 0..<600 { k.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 80), 450)) }
        let sc = k.scene(emerge: 1)
        XCTAssertEqual(sc.tail.count, KiteSim.Params().tailLinks)
        XCTAssertTrue(sc.tail.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        XCTAssertGreaterThan(sc.spoolSize, 8)
        k.release(commit: CGPoint(x: 1, y: 0))
        for _ in 0..<120 { k.step(dt: 1 / 120, pin: pin, head: head(1, 450)) }
        XCTAssertGreaterThan(k.scene(emerge: 1).kite.x, pin.x + 450)
    }

    func testBubblesPopOnCommit() {
        var b = BubbleSim(); b.reset(pin: pin)
        for i in 0..<400 { b.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 80), 500)) }
        XCTAssertTrue(b.bubbleStates(emerge: 1).allSatisfy { $0.pop == 0 })
        b.release(commit: nil)
        for _ in 0..<60 { b.step(dt: 1 / 120, pin: pin, head: head(1, 500)) }
        XCTAssertTrue(b.bubbleStates(emerge: 1).allSatisfy { $0.pop > 0.9 })
        XCTAssertEqual(b.count, BubbleSim.Params().bubbles)
    }

    func testTendrilsCoilAroundTheHeadWhenFar() {
        var t = TendrilSim(); t.reset(pin: pin)
        let h = head(1, 420)
        for _ in 0..<600 { t.step(dt: 1 / 120, pin: pin, head: h) }
        XCTAssertGreaterThan(t.gripAmount, 0.9)
        let tips = t.primitives(emerge: 1).filter { $0.kind == .cone }
        let nearHead = tips.filter { hypot($0.b.x - h.x, $0.b.y - h.y) < 70 }.count
        XCTAssertGreaterThan(nearHead, 20)       // many links wrapped close around the cursor
    }

    func testLightningBoltsSpanTheTerminalsAndFlashOnCommit() {
        var l = LightningSim(); l.reset(pin: pin)
        for i in 0..<300 { l.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 60), 450)) }
        let sc = l.scene(emerge: 1)
        XCTAssertFalse(sc.bolts.isEmpty)
        XCTAssertGreaterThan(sc.pinRadius, sc.headRadius)
        XCTAssertGreaterThan(sc.bolts[0].count, 20)
        XCTAssertTrue(sc.bolts.allSatisfy { $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
        l.release(commit: nil)
        l.step(dt: 1 / 120, pin: pin, head: head(1, 450))
        XCTAssertGreaterThan(l.scene(emerge: 1).flash, 0.5)
    }

    func testMagnetHeavyPoleThrowsLinesTheLightOneCannotCatch() {
        var m = MagnetSim(); m.reset(pin: pin)
        for i in 0..<400 { m.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 60), 400)) }
        let sc = m.scene(emerge: 1)
        XCTAssertEqual(sc.lines.count, MagnetSim.Params().lines)
        XCTAssertGreaterThan(sc.escaping, 0.1)          // the heavy pin has more lines than the light head can catch
        XCTAssertLessThan(sc.escaping, 0.95)
        XCTAssertGreaterThan(sc.pinRadius, sc.headRadius)
    }

    func testSlinkyTapersFromTheHeavyEndAndRecoils() {
        var s = SlinkySim(); s.reset(pin: pin)
        for i in 0..<400 { s.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 60), 500)) }
        let sc = s.scene(emerge: 1)
        XCTAssertGreaterThan(sc.coil.count, 300)
        XCTAssertTrue(sc.coil.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        func amp(_ range: Range<Int>) -> CGFloat { range.map { abs(sc.coil[$0].y - (pin.y + 10 * CGFloat($0) / CGFloat(sc.coil.count))) }.max() ?? 0 }
        let n = sc.coil.count
        XCTAssertGreaterThan(amp(0..<(n / 5)), amp((n * 4 / 5)..<n))      // wider at the heavy pin than at the light head
    }

    func testTinCansPassNotesBackAndForth() {
        var t = TinCanSim(); t.reset(pin: pin)
        var sawFromPin = false, sawFromHead = false
        for i in 0..<720 {
            t.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500))
            let sc = t.scene(emerge: 1)
            if let n = sc.notes.first(where: { $0.alpha > 0.3 }) {
                let mid = pin.x + 250
                if (i / 120) % 4 < 2 { if n.position.x < mid + 10 { sawFromPin = true } } else if n.position.x > mid - 10 { sawFromHead = true }
            }
        }
        XCTAssertTrue(sawFromPin && sawFromHead)
    }

    func testRedThreadHeartsFloatAlongAndBurstOnCommit() {
        var r = ThreadSim(); r.reset(pin: pin)
        for i in 0..<400 { r.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 60), 450)) }
        let sc = r.scene(emerge: 1)
        XCTAssertEqual(sc.hearts.count, ThreadSim.Params().hearts)
        XCTAssertGreaterThan(sc.pinHeart.size, sc.headHeart.size)
        XCTAssertGreaterThan(sc.thread.count, 20)
        r.release(commit: CGPoint(x: 1, y: 0))
        for _ in 0..<60 { r.step(dt: 1 / 120, pin: pin, head: head(1, 450)) }
        XCTAssertTrue(r.scene(emerge: 1).hearts.allSatisfy { $0.position.x.isFinite })
    }

    func testPingPongBallTravelsBetweenThePaddles() {
        var p = PingPongSim(); p.reset(pin: pin)
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        for i in 0..<480 {
            p.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500))
            if i > 100 { let b = p.scene(emerge: 1).ball; minX = min(minX, b.x); maxX = max(maxX, b.x) }
        }
        XCTAssertLessThan(minX, pin.x + 60); XCTAssertGreaterThan(maxX, pin.x + 440)
        XCTAssertEqual(p.scene(emerge: 1).trail.count, 16)
    }

    func testBridgeWalkerCrossesTheSpan() {
        var b = BridgeSim(); b.reset(pin: pin)
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        for i in 0..<1800 {
            b.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500))
            if i > 100, i % 10 == 0 { let w = b.scene(emerge: 1).walker; minX = min(minX, w.x); maxX = max(maxX, w.x) }
        }
        XCTAssertLessThan(minX, pin.x + 100); XCTAssertGreaterThan(maxX, pin.x + 400)
        XCTAssertGreaterThan(b.scene(emerge: 1).planks.count, 10)
    }

    func testPaperPlanesFlyBothWays() {
        var s = PaperPlanesSim(); s.reset(pin: pin)
        for i in 0..<720 { s.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500)) }
        let sc = s.scene(emerge: 1)
        XCTAssertEqual(sc.planes.count, 5)
        XCTAssertTrue(sc.planes.allSatisfy { $0.position.x.isFinite && $0.size > 4 })
        XCTAssertTrue(sc.planes.contains { $0.trail.contains { $0.1 > 0.05 } })
    }

    func testWaterMovesFromTankToCupAsYouPull() {
        var near = WaterArcSim(); near.reset(pin: pin)
        var far = WaterArcSim(); far.reset(pin: pin)
        for i in 0..<400 {
            near.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 60))
            far.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 600))
        }
        let a = near.scene(emerge: 1), b = far.scene(emerge: 1)
        XCTAssertGreaterThan(a.tankLevel, b.tankLevel)         // the tank drains as you stretch
        XCTAssertGreaterThan(b.cupLevel, a.cupLevel)           // and the cup fills
        XCTAssertEqual(b.drops.count, 60)
    }

    func testTrainShuttlesAndSmokes() {
        var t = ToyTrainSim(); t.reset(pin: pin)
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        for i in 0..<1500 {
            t.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500))
            if i > 100, i % 10 == 0, let e = t.scene(emerge: 1).cars.first { minX = min(minX, e.position.x); maxX = max(maxX, e.position.x) }
        }
        XCTAssertGreaterThan(maxX - minX, 250)
        XCTAssertEqual(t.scene(emerge: 1).cars.count, 4)
        XCTAssertFalse(t.scene(emerge: 1).smoke.isEmpty)
    }

    func testEqualizerBassLivesAtTheHeavyEnd() {
        var e = EqualizerSim(); e.reset(pin: pin)
        var pinSum: CGFloat = 0, headSum: CGFloat = 0
        for i in 0..<720 {
            e.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500))
            if i > 100, i % 6 == 0 { let b = e.scene(emerge: 1).bars; pinSum += b.prefix(6).map(\.height).reduce(0, +); headSum += b.suffix(6).map(\.height).reduce(0, +) }
        }
        XCTAssertGreaterThan(pinSum, headSum)
    }

    func testDNAHasPairedRungsAndTwoStrands() {
        var d = DNASim(); d.reset(pin: pin)
        for i in 0..<300 { d.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500)) }
        let sc = d.scene(emerge: 1)
        XCTAssertEqual(sc.strandA.count, sc.strandB.count)
        XCTAssertGreaterThan(sc.rungs.count, 10)
        XCTAssertTrue(sc.rungs.allSatisfy { $0.pair >= 0 && $0.pair < 4 })
    }

    func testFishingFishLeapsNowAndThen() {
        var f = FishingSim(); f.reset(pin: pin)
        var leaped = false
        for i in 0..<1200 {
            f.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 400))
            if f.scene(emerge: 1).fishAlpha > 0.5 { leaped = true }
        }
        XCTAssertTrue(leaped)
        XCTAssertEqual(f.scene(emerge: 1).line.count, 27)
    }

    func testRibbonIsAnchoredAtBothEnds() {
        var r = RibbonSim(); r.reset(pin: pin)
        for i in 0..<400 { r.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 450)) }
        let sc = r.scene(emerge: 1)
        XCTAssertLessThan(hypot(sc.spine.first!.x - pin.x, sc.spine.first!.y - pin.y), 2)
        XCTAssertLessThan(hypot(sc.spine.last!.x - (pin.x + 450), sc.spine.last!.y - (pin.y + 10)), 2)
        XCTAssertEqual(sc.spine.count, sc.width.count)
    }

    func testTugFlagLeansTowardTheHeavyPin() {
        var t = TugOfWarSim(); t.reset(pin: pin)
        for i in 0..<500 { t.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500)) }
        let sc = t.scene(emerge: 1)
        XCTAssertLessThan(sc.flag.x, pin.x + 250)             // nearer the heavy pin than the middle
        XCTAssertGreaterThan(sc.pinSize, sc.headSize)
    }

    func testCradleBallsClickOutAtTheEnds() {
        var c = NewtonsCradleSim(); c.reset(pin: pin)
        var leftOut = false, rightOut = false
        let rest = { (sc: CradleScene) in sc.balls[2].0.x }
        for i in 0..<720 {
            c.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500))
            let sc = c.scene(emerge: 1)
            if abs(sc.balls[0].0.x - (sc.tops[0].x)) > 20 { leftOut = true }
            if abs(sc.balls[4].0.x - (sc.tops[4].x)) > 20 { rightOut = true }
            _ = rest(sc)
        }
        XCTAssertTrue(leftOut && rightOut)
    }

    func testRainbowDrawsSevenBands() {
        var r = RainbowSim(); r.reset(pin: pin)
        for i in 0..<400 { r.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500)) }
        let sc = r.scene(emerge: 1)
        XCTAssertEqual(sc.bands.count, 7)
        XCTAssertTrue(sc.bands.allSatisfy { $0.count > 30 })
        XCTAssertEqual(sc.cloudPin.count, 5)
    }

    func testDandelionLosesSeedsAsYouPull() {
        var near = DandelionSim(); near.reset(pin: pin)
        var far = DandelionSim(); far.reset(pin: pin)
        for i in 0..<500 {
            near.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 70))
            far.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 800))
        }
        XCTAssertGreaterThan(near.scene(emerge: 1).seedAngles.count, far.scene(emerge: 1).seedAngles.count)
        XCTAssertGreaterThan(far.scene(emerge: 1).sproutHeight, near.scene(emerge: 1).sproutHeight)
    }

    func testCableCarMovesAlongTheCable() {
        var c = CableCarSim(); c.reset(pin: pin)
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        for i in 0..<1500 {
            c.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 500))
            if i > 100, i % 10 == 0 { let x = c.scene(emerge: 1).car.x; minX = min(minX, x); maxX = max(maxX, x) }
        }
        XCTAssertGreaterThan(maxX - minX, 250)
    }

    func testSignalSendsWavesBothWays() {
        var s = SignalSim(); s.reset(pin: pin)
        for i in 0..<300 { s.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 400)) }
        let sc = s.scene(emerge: 1)
        XCTAssertEqual(sc.waves.count, 8)
        XCTAssertEqual(sc.packets.count, 9)
        XCTAssertGreaterThan(sc.strength, 0.5)
    }
}

final class SpectrumAnalyzerTests: XCTestCase {
    private func tone(_ hz: Double, _ n: Int, rate: Double = 48_000, amp: Float = 0.5) -> [Float] {
        (0..<n).map { amp * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    func testToneLightsTheRightBand() {
        for (hz, expectLow) in [(100.0, true), (8000.0, false)] {
            let a = SpectrumAnalyzer()
            var bands: [Float] = []
            for _ in 0..<6 { bands = a.process(tone(hz, 1024)) }
            let top = bands.indices.max { bands[$0] < bands[$1] }!
            if expectLow { XCTAssertLessThan(top, 6, "100 Hz should land in the bass bands, got \(top)") }
            else { XCTAssertGreaterThan(top, 16, "8 kHz should land in the treble bands, got \(top)") }
            XCTAssertGreaterThan(bands[top], 0.4)
        }
    }

    func testSilenceIsQuietAndBandsFallAway() {
        let a = SpectrumAnalyzer()
        for _ in 0..<6 { a.process(tone(440, 1024)) }
        let loud = a.bands.max()!
        for _ in 0..<40 { a.process([Float](repeating: 0, count: 1024)) }
        XCTAssertGreaterThan(loud, 0.4)
        XCTAssertLessThan(a.bands.max()!, 0.05)
    }

    func testEqualizerUsesTheLiveSpectrum() {
        var e = EqualizerSim(); e.reset(pin: CGPoint(x: 0, y: 0))
        var spec = [CGFloat](repeating: 0, count: 24); spec[20] = 1                   // a pure treble note
        e.spectrum = spec
        for i in 0..<300 { e.step(dt: 1 / 120, pin: .zero, head: CGPoint(x: min(500, CGFloat(i) * 10), y: 0)) }
        let bars = e.scene(emerge: 1).bars
        let tall = bars.indices.max { bars[$0].height < bars[$1].height }!
        XCTAssertGreaterThan(tall, 17)
        XCTAssertLessThan(bars[2].height, bars[tall].height * 0.3)
    }

    private let pin = CGPoint(x: 400, y: 400)
    private func head(_ k: CGFloat, _ chord: CGFloat) -> CGPoint { CGPoint(x: pin.x + chord * k, y: pin.y + 10 * k) }

    func testEveryEnergyVariantHasADistinctPaletteAndWorksInBothModes() {
        var seen = Set<String>()
        for v in EnergyVariant.allCases {
            seen.insert(v.palette.map { $0.map { String(Int($0)) }.joined(separator: ",") }.joined(separator: "|"))
            XCTAssertEqual(v.palette.count, 4)
            for charge in [false, true] {
                var e = EnergySim(); e.variant = v; e.chargeThenFire = charge; e.reset(pin: pin)
                for i in 0..<300 { e.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 450)) }
                let held = e.scene(emerge: 1)
                if charge {
                    XCTAssertTrue(held.ribbons.isEmpty && held.projectiles.isEmpty, "\(v) must not fire while charging")
                    XCTAssertFalse(held.aimLine.isEmpty)
                } else if !v.isProjectile {
                    XCTAssertFalse(held.ribbons.isEmpty, "\(v) streams while held")
                }
                e.release(commit: CGPoint(x: 1, y: 0))
                for _ in 0..<30 { e.step(dt: 1 / 120, pin: pin, head: head(1, 450)) }
                let fired = e.scene(emerge: 1)
                if charge { XCTAssertTrue(!fired.ribbons.isEmpty || !fired.projectiles.isEmpty, "\(v) fires on release") }
                XCTAssertTrue(fired.ribbons.allSatisfy { $0.centerline.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
                for _ in 0..<200 { e.step(dt: 1 / 120, pin: pin, head: head(1, 450)) }
                XCTAssertTrue(e.isFinished, "\(v) finishes")
            }
        }
        XCTAssertEqual(seen.count, EnergyVariant.allCases.count)
    }

    func testPresetFamiliesAreGrouped() {
        XCTAssertEqual(PresetLibrary.presets(for: .beam).count, EnergyVariant.allCases.count)
        XCTAssertEqual(Set(PresetLibrary.presets(for: .beam).compactMap(\.variant)).count, EnergyVariant.allCases.count)
        XCTAssertGreaterThanOrEqual(PresetLibrary.presets(for: .liquid).count, 10)
        XCTAssertEqual(PresetLibrary.presets(for: .crystal).count, 2)
        for st in AnimationStyle.allCases { XCTAssertFalse(PresetLibrary.presets(for: st).isEmpty, "\(st) has at least one look") }
    }

    func testReleaseBehaviorFollowsTheConcept() {
        XCTAssertEqual(AnimationStyle.liquid.releaseBehavior, .spring)
        XCTAssertEqual(AnimationStyle.slinky.releaseBehavior, .spring)
        XCTAssertEqual(AnimationStyle.fishing.releaseBehavior, .ease)
        XCTAssertEqual(AnimationStyle.kite.releaseBehavior, .ease)
        for st in [AnimationStyle.beam, .bubbles, .stars, .dandelion, .rainbow, .lightning] { XCTAssertEqual(st.releaseBehavior, .stay) }
    }

    func testCancelDoesNotFlingThingsOffToTheRight() {
        var k = KiteSim(); k.reset(pin: pin)
        for i in 0..<300 { k.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 400)) }
        let before = k.scene(emerge: 1).kite
        k.release(commit: nil)
        for _ in 0..<60 { k.step(dt: 1 / 120, pin: pin, head: head(1, 400)) }
        XCTAssertLessThan(abs(k.scene(emerge: 1).kite.x - before.x), 5)       // it stays with the string; only a commit releases it
    }

    func testPresentationToolsBehave() {
        var l = LassoSim(); l.reset(pin: pin)
        for i in 0..<400 { l.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 40), 450)) }
        let ls = l.scene(emerge: 1)
        XCTAssertGreaterThan(ls.rx, 20); XCTAssertEqual(ls.cinch, 0)
        l.release(commit: CGPoint(x: 1, y: 0))
        for _ in 0..<40 { l.step(dt: 1 / 120, pin: pin, head: head(1, 450)) }
        XCTAssertGreaterThan(l.scene(emerge: 1).cinch, 0.8)                    // the loop cinches shut on commit

        var p = LaserPointerSim(); p.reset(pin: pin)
        for i in 0..<300 { p.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 100), 450)) }
        XCTAssertGreaterThan(p.scene(emerge: 1).trail.count, 10)

        var m = HighlighterSim(); m.reset(pin: pin)
        for i in 0..<300 { m.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 100), 450)) }
        XCTAssertGreaterThan(m.scene(emerge: 1).segments.count, 5)

        var sp = SpotlightSim(); sp.reset(pin: pin)
        for i in 0..<300 { sp.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 60), 450)) }
        let sps = sp.scene(emerge: 1)
        XCTAssertGreaterThan(sps.dim, 0.3); XCTAssertEqual(sps.motes.count, 26)

        var c = CalloutArrowSim(); c.reset(pin: pin)
        for i in 0..<300 { c.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 60), 450)) }
        let cs = c.scene(emerge: 1)
        XCTAssertGreaterThan(cs.arrow.count, 20); XCTAssertGreaterThan(cs.scribble.count, 10)

        var t = TargetLockSim(); t.reset(pin: pin)
        for i in 0..<300 { t.step(dt: 1 / 120, pin: pin, head: head(min(1, CGFloat(i) / 60), 450)) }
        let ts = t.scene(emerge: 1)
        XCTAssertTrue(ts.readout.contains("LOCK")); XCTAssertEqual(ts.ticks.count, 24)
    }

    private func frac(_ i: Int, _ salt: Int) -> CGFloat { CGFloat(abs(sin(Double(i * 131 + salt * 17)) * 43758.5453).truncatingRemainder(dividingBy: 1)) }

    /// Erratic pointer motion (teleports, stops, wild flings) must never produce a non-finite shape in any sim.
    func testNoSimEverProducesNonFiniteGeometryUnderErraticMotion() {
        func path(_ i: Int) -> CGPoint {
            let t = CGFloat(i)
            if i % 173 == 0 { return CGPoint(x: pin.x + 1400 * frac(i, 9) - 200, y: pin.y + 900 * frac(i, 10) - 450) }   // teleport
            return CGPoint(x: pin.x + 300 + 260 * CGFloat(sin(Double(t * 0.031))) * CGFloat(cos(Double(t * 0.0113))), y: pin.y + 120 * CGFloat(sin(Double(t * 0.047))))
        }
        func finite(_ pts: [CGPoint]) -> Bool { pts.allSatisfy { $0.x.isFinite && $0.y.isFinite } }
        var star = StarSim(), kite = KiteSim(), bub = BubbleSim(), lig = LightningSim(), mag = MagnetSim(), sli = SlinkySim(), can = TinCanSim(), thr = ThreadSim()
        var ping = PingPongSim(), bri = BridgeSim(), pla = PaperPlanesSim(), wat = WaterArcSim(), tra = ToyTrainSim(), eq = EqualizerSim(), dna = DNASim()
        var fis = FishingSim(), rib = RibbonSim(), tug = TugOfWarSim(), cra = NewtonsCradleSim(), rai = RainbowSim(), dan = DandelionSim(), cab = CableCarSim(), sig = SignalSim()
        var las = LassoSim(), lsr = LaserPointerSim(), mrk = HighlighterSim(), spo = SpotlightSim(), cal = CalloutArrowSim(), tgt = TargetLockSim()
        var en: [EnergySim] = EnergyVariant.allCases.map { var e = EnergySim(); e.variant = $0; e.chargeThenFire = $0.rawValue.count % 2 == 0; return e }
        star.reset(pin: pin); kite.reset(pin: pin); bub.reset(pin: pin); lig.reset(pin: pin); mag.reset(pin: pin); sli.reset(pin: pin); can.reset(pin: pin); thr.reset(pin: pin)
        ping.reset(pin: pin); bri.reset(pin: pin); pla.reset(pin: pin); wat.reset(pin: pin); tra.reset(pin: pin); eq.reset(pin: pin); dna.reset(pin: pin)
        fis.reset(pin: pin); rib.reset(pin: pin); tug.reset(pin: pin); cra.reset(pin: pin); rai.reset(pin: pin); dan.reset(pin: pin); cab.reset(pin: pin); sig.reset(pin: pin)
        las.reset(pin: pin); lsr.reset(pin: pin); mrk.reset(pin: pin); spo.reset(pin: pin); cal.reset(pin: pin); tgt.reset(pin: pin)
        for i in 0..<900 {
            let h = path(i)
            star.step(dt: 1 / 120, pin: pin, head: h); kite.step(dt: 1 / 120, pin: pin, head: h); bub.step(dt: 1 / 120, pin: pin, head: h); lig.step(dt: 1 / 120, pin: pin, head: h)
            mag.step(dt: 1 / 120, pin: pin, head: h); sli.step(dt: 1 / 120, pin: pin, head: h); can.step(dt: 1 / 120, pin: pin, head: h); thr.step(dt: 1 / 120, pin: pin, head: h)
            ping.step(dt: 1 / 120, pin: pin, head: h); bri.step(dt: 1 / 120, pin: pin, head: h); pla.step(dt: 1 / 120, pin: pin, head: h); wat.step(dt: 1 / 120, pin: pin, head: h)
            tra.step(dt: 1 / 120, pin: pin, head: h); eq.step(dt: 1 / 120, pin: pin, head: h); dna.step(dt: 1 / 120, pin: pin, head: h); fis.step(dt: 1 / 120, pin: pin, head: h)
            rib.step(dt: 1 / 120, pin: pin, head: h); tug.step(dt: 1 / 120, pin: pin, head: h); cra.step(dt: 1 / 120, pin: pin, head: h); rai.step(dt: 1 / 120, pin: pin, head: h)
            dan.step(dt: 1 / 120, pin: pin, head: h); cab.step(dt: 1 / 120, pin: pin, head: h); sig.step(dt: 1 / 120, pin: pin, head: h); las.step(dt: 1 / 120, pin: pin, head: h)
            lsr.step(dt: 1 / 120, pin: pin, head: h); mrk.step(dt: 1 / 120, pin: pin, head: h); spo.step(dt: 1 / 120, pin: pin, head: h); cal.step(dt: 1 / 120, pin: pin, head: h)
            tgt.step(dt: 1 / 120, pin: pin, head: h)
            for k in en.indices { en[k].step(dt: 1 / 120, pin: pin, head: h) }
            if i % 60 == 0 {
                XCTAssertTrue(finite(kite.scene(emerge: 1).string + kite.scene(emerge: 1).tail), "kite \(i)")
                XCTAssertTrue(finite(sli.scene(emerge: 1).coil), "slinky \(i)")
                XCTAssertTrue(finite(thr.scene(emerge: 1).thread), "thread \(i)")
                XCTAssertTrue(finite(rib.scene(emerge: 1).spine), "ribbon \(i)")
                XCTAssertTrue(finite(wat.scene(emerge: 1).arc), "water \(i)")
                XCTAssertTrue(finite(bri.scene(emerge: 1).railA), "bridge \(i)")
                XCTAssertTrue(finite(tra.scene(emerge: 1).track), "train \(i)")
                XCTAssertTrue(finite(las.scene(emerge: 1).rope), "lasso \(i)")
                XCTAssertTrue(finite(cal.scene(emerge: 1).arrow), "callout \(i)")
                XCTAssertTrue(finite(cab.scene(emerge: 1).cableA), "cable \(i)")
                XCTAssertTrue(finite(mag.scene(emerge: 1).lines.flatMap { $0 }), "magnet \(i)")
                XCTAssertTrue(finite(lig.scene(emerge: 1).bolts.flatMap { $0 }), "lightning \(i)")
                XCTAssertTrue(finite(dna.scene(emerge: 1).strandA.map(\.0)), "dna \(i)")
                XCTAssertTrue(finite(eq.scene(emerge: 1).bars.map(\.base)) && eq.scene(emerge: 1).bars.allSatisfy { $0.height.isFinite }, "equalizer \(i)")
                for e in en { XCTAssertTrue(finite(e.scene(emerge: 1).ribbons.flatMap(\.centerline)), "energy \(e.variant) \(i)") }
            }
        }
    }
}

