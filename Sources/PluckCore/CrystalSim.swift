import CoreGraphics
import Foundation

/// A crystal that grows toward the cursor and keeps evolving. A rosette of crystals sits at the pin and slowly
/// develops (new facets, side crystals); a main needle reaches toward the head, crisp and rigid (no wobble); and the
/// distance you travel seeds branches along the needle that grow, then sprout sub-branches of their own, like frost
/// spreading along your path. Committing shatters it into flying fragments; cancelling retracts it.
public struct CrystalSim: Sendable {
    public struct Params: Equatable, Sendable {
        /// Radius of the core rosette (points).
        public var coreRadius: CGFloat = 26
        /// Distance travelled by the head between new branches (points).
        public var branchSpacing: CGFloat = 30
        /// Never more than this many shards in total.
        public var maxShards: Int = 84
        public init() {}
    }

    private struct Shard {
        var base: CGPoint
        var angle: CGFloat
        var len: CGFloat
        var target: CGFloat
        var width: CGFloat
        var tipFrac: CGFloat
        /// For branches: where along the main needle they are attached (0...1), the angle relative to it, generation.
        var attach: CGFloat?
        var relAngle: CGFloat
        var gen: Int
        var delay: CGFloat
        var glow: CGFloat
        var seed: CGFloat
        var hasChild: Bool
        var growRate: CGFloat
        /// For sub-branches: the shard they grow from and how far along it (so they stay attached as it moves).
        var parent: Int = -1
        var parentS: CGFloat = 0
    }

    private struct Fragment {
        var base: CGPoint
        var angle: CGFloat
        var len: CGFloat
        var width: CGFloat
        var vel: CGPoint
        var spin: CGFloat
        var life: CGFloat
        var seed: CGFloat
        var tipFrac: CGFloat
    }

    public var params: Params
    private var pin: CGPoint = .zero
    private var head: CGPoint = .zero
    private var shards: [Shard] = []
    private var fragments: [Fragment] = []
    private var mainAngle: CGFloat = 0, mainAngleV: CGFloat = 0
    private var mainLen: CGFloat = 0, mainLenV: CGFloat = 0
    private var pathTravel: CGFloat = 0
    private var time: CGFloat = 0
    private var evolveClock: CGFloat = 0
    private var sparkleClock: CGFloat = 0
    private var counter = 0
    private var retracting = false
    private var retractT: CGFloat = 0
    private var headScale: CGFloat = 1
    private var shattered = false
    private var shatterT: CGFloat = 0
    private var rngState: UInt64 = 0x1234_5678_9ABC_DEF0

    public init(params: Params = Params()) { self.params = params }

    // MARK: Random

    private mutating func rand() -> CGFloat {
        rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(rngState >> 40) / Double(1 << 24))
    }

    private mutating func rand(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo + (hi - lo) * rand() }

    // MARK: Lifecycle

    public mutating func reset(pin: CGPoint, seed: UInt64 = 7) {
        self.pin = pin
        head = pin
        rngState = seed &* 0x9E37_79B9_7F4A_7C15 | 1
        shards = []; fragments = []
        mainAngle = 0; mainAngleV = 0; mainLen = 0; mainLenV = 0
        pathTravel = 0; time = 0; evolveClock = 0; sparkleClock = 0; counter = 0
        retracting = false; retractT = 0; shattered = false; shatterT = 0; headScale = 1
        let R = params.coreRadius
        let n = 7
        for i in 0..<n {
            let a = 2 * .pi * CGFloat(i) / CGFloat(n) + rand(-0.25, 0.25)
            shards.append(Shard(
                base: pin, angle: a, len: 0, target: R * rand(0.55, 1.05), width: R * rand(0.13, 0.19),
                tipFrac: 0.34, attach: nil, relAngle: 0, gen: 0,
                delay: CGFloat(i) * 0.045, glow: 0, seed: rand(), hasChild: false, growRate: 0.16
            ))
        }
    }

    public var shardCount: Int { shards.count }
    public var headPosition: CGPoint { head }
    public var headRadius: CGFloat { params.coreRadius * 0.62 }
    public var isShattered: Bool { shattered }
    public var isFinished: Bool { (shattered && shatterT > 0.7) || (retracting && retractT > 0.4) }

    // MARK: Step

    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt
        let prevHead = head
        pin = newPin
        head = newHead
        let R = params.coreRadius
        let dx = head.x - pin.x, dy = head.y - pin.y
        let chord = hypot(dx, dy)

        if shattered {
            shatterT += dt
            stepFragments(dt)
            return
        }

        if retracting {
            retractT += dt
            for i in shards.indices { shards[i].len *= CGFloat(exp(Double(-14 * dt))); shards[i].glow *= 0.9 }
            mainLen *= CGFloat(exp(Double(-14 * dt)))
            headScale *= CGFloat(exp(Double(-14 * dt)))
            return
        }

        // Main needle: crisp (little overshoot).
        if chord > 4 {
            var diff = atan2(dy, dx) - mainAngle
            while diff > .pi { diff -= 2 * .pi }
            while diff < -.pi { diff += 2 * .pi }
            let w: CGFloat = 38, z: CGFloat = 0.95
            let steps = max(1, Int((dt / 0.004).rounded(.up)))
            let h = dt / CGFloat(steps)
            var d = diff
            for _ in 0..<steps {
                mainAngleV += (w * w * d - 2 * z * w * mainAngleV) * h
                mainAngle += mainAngleV * h
                d = atan2(dy, dx) - mainAngle
                while d > .pi { d -= 2 * .pi }
                while d < -.pi { d += 2 * .pi }
            }
        }
        do {
            let w: CGFloat = 34, z: CGFloat = 0.92
            let steps = max(1, Int((dt / 0.004).rounded(.up)))
            let h = dt / CGFloat(steps)
            for _ in 0..<steps {
                mainLenV += (w * w * (max(0, chord - R * 0.5) - mainLen) - 2 * z * w * mainLenV) * h
                mainLen += mainLenV * h
            }
            mainLen = max(0, mainLen)
        }

        // Growth of every shard (eased, with a start delay for the staggered bloom).
        for i in shards.indices {
            if shards[i].delay > 0 { shards[i].delay -= dt; continue }
            let rate = shards[i].growRate
            shards[i].len += (shards[i].target - shards[i].len) * (1 - CGFloat(exp(Double(-dt / rate))))
            shards[i].glow = max(0, shards[i].glow - dt * 2.4)
        }
        // Branches stay attached to the moving needle.
        let dir = CGPoint(x: cos(mainAngle), y: sin(mainAngle))
        for i in shards.indices {
            guard let s = shards[i].attach else { continue }
            shards[i].base = CGPoint(x: pin.x + dir.x * mainLen * s, y: pin.y + dir.y * mainLen * s)
            shards[i].angle = mainAngle + shards[i].relAngle
        }
        // Core crystals keep the pin as their base.
        for i in shards.indices where shards[i].attach == nil && shards[i].gen == 0 { shards[i].base = pin }
        // Sub-branches ride on their parents (parents always precede children).
        for i in shards.indices where shards[i].parent >= 0 {
            let par = shards[shards[i].parent]
            shards[i].base = CGPoint(x: par.base.x + cos(par.angle) * par.len * shards[i].parentS,
                                     y: par.base.y + sin(par.angle) * par.len * shards[i].parentS)
            shards[i].angle = par.angle + shards[i].relAngle
        }

        // Branches grow where you have travelled.
        let travel = hypot(head.x - prevHead.x, head.y - prevHead.y)
        if chord > R * 1.4 { pathTravel += travel }
        var spawned = 0
        while pathTravel > params.branchSpacing, shards.count < params.maxShards - 3, spawned < 2 {
            pathTravel -= params.branchSpacing
            spawned += 1
            let s = rand(0.18, 0.95)
            let side: CGFloat = (counter % 2 == 0) ? 1 : -1
            counter += 1
            let target = min(78, (0.08 + 0.16 * rand()) * chord + 16)
            shards.append(Shard(
                base: pin, angle: mainAngle, len: 0, target: target, width: max(2.2, R * 0.10 * rand(0.8, 1.2)),
                tipFrac: 0.40, attach: s, relAngle: side * rand(0.55, 1.1), gen: 1,
                delay: 0, glow: 1, seed: rand(), hasChild: false, growRate: 0.22
            ))
        }
        // Sub-branches: once a branch is well grown it sprouts a smaller one (the formation evolves).
        for i in shards.indices where shards[i].gen == 1 && !shards[i].hasChild && shards[i].len > 0.7 * shards[i].target && shards.count < params.maxShards {
            shards[i].hasChild = true
            let parent = shards[i]
            let s2: CGFloat = rand(0.45, 0.7)
            let tip = CGPoint(x: parent.base.x + cos(parent.angle) * parent.len * s2, y: parent.base.y + sin(parent.angle) * parent.len * s2)
            let side: CGFloat = rand() < 0.5 ? 1 : -1
            // Gen-2 shards are free-standing at spawn and then re-anchored as the parent moves.
            shards.append(Shard(
                base: tip, angle: parent.angle, len: 0, target: parent.target * rand(0.32, 0.5),
                width: max(1.8, parent.width * 0.7), tipFrac: 0.42, attach: nil, relAngle: side * rand(0.6, 0.95), gen: 2,
                delay: 0.05, glow: 1, seed: rand(), hasChild: true, growRate: 0.2, parent: i, parentS: s2
            ))
        }

        // Evolution while you hold: the core crystals keep developing, occasionally budding side crystals.
        evolveClock += dt
        if evolveClock > 0.9 {
            evolveClock = 0
            let core = shards.indices.filter { shards[$0].gen == 0 && shards[$0].attach == nil }
            if let i = core.randomElement(using: &rngAdapter) {
                shards[i].target = min(R * 1.55, shards[i].target * 1.10)
                shards[i].glow = 1
                if shards.count < params.maxShards, rand() < 0.5 {
                    let tipPos = CGPoint(x: shards[i].base.x + cos(shards[i].angle) * shards[i].len * 0.6,
                                         y: shards[i].base.y + sin(shards[i].angle) * shards[i].len * 0.6)
                    shards.append(Shard(
                        base: tipPos, angle: shards[i].angle, len: 0,
                        target: R * rand(0.3, 0.5), width: max(1.8, R * 0.07), tipFrac: 0.4, attach: nil,
                        relAngle: (rand() < 0.5 ? 1 : -1) * rand(0.5, 0.9),
                        gen: 2, delay: 0, glow: 1, seed: rand(), hasChild: true, growRate: 0.24, parent: i, parentS: 0.6
                    ))
                }
            }
        }
        // Sparkle: a random facet catches the light now and then.
        sparkleClock += dt
        if sparkleClock > 0.35, !shards.isEmpty {
            sparkleClock = 0
            shards[Int(rand() * CGFloat(shards.count)) % shards.count].glow = 1
        }
    }

    // A tiny adapter so we can use randomElement with our deterministic generator.
    private struct RNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
    private var rngAdapter: RNG {
        get { RNG(state: rngState) }
        set { rngState = newValue.state }
    }

    // MARK: Release

    /// Commit: the crystal shatters; fragments fly outward and along `direction`, shrinking away.
    public mutating func shatter(direction: CGPoint?) {
        guard !shattered else { return }
        shattered = true
        shatterT = 0
        var frags: [Fragment] = []
        func add(_ base: CGPoint, _ angle: CGFloat, _ len: CGFloat, _ width: CGFloat, _ seed: CGFloat, _ tip: CGFloat) {
            guard len > 3 else { return }
            let outward = CGPoint(x: cos(angle), y: sin(angle))
            let d = direction ?? outward
            let sp = 120 + 340 * StyleHash.unit(frags.count, 9)
            frags.append(Fragment(
                base: base, angle: angle, len: len, width: width,
                vel: CGPoint(x: outward.x * sp * 0.45 + d.x * sp, y: outward.y * sp * 0.45 + d.y * sp),
                spin: (StyleHash.unit(frags.count, 11) - 0.5) * 9, life: 1, seed: seed, tipFrac: tip
            ))
        }
        let dir = CGPoint(x: cos(mainAngle), y: sin(mainAngle))
        add(pin, mainAngle, mainLen, max(2.5, params.coreRadius * 0.16), 0.5, 0.35)
        // The main needle breaks into three pieces.
        let pieces = 3
        for k in 0..<pieces {
            let t0 = CGFloat(k) / CGFloat(pieces)
            let b = CGPoint(x: pin.x + dir.x * mainLen * t0, y: pin.y + dir.y * mainLen * t0)
            add(b, mainAngle, mainLen / CGFloat(pieces) * 0.9, max(2.2, params.coreRadius * 0.13), StyleHash.unit(k, 12), 0.4)
        }
        for s in shards { add(s.base, s.angle, s.len, s.width, s.seed, s.tipFrac) }
        fragments = frags
    }

    /// Cancel: the crystal retracts.
    public mutating func retract() {
        guard !shattered, !retracting else { return }
        retracting = true
        retractT = 0
    }

    private mutating func stepFragments(_ dt: CGFloat) {
        for i in fragments.indices {
            fragments[i].base.x += fragments[i].vel.x * dt
            fragments[i].base.y += fragments[i].vel.y * dt
            let drag = CGFloat(exp(Double(-2.2 * dt)))
            fragments[i].vel.x *= drag
            fragments[i].vel.y = fragments[i].vel.y * drag - 160 * dt
            fragments[i].angle += fragments[i].spin * dt
            fragments[i].life = max(0, fragments[i].life - dt / 0.62)
        }
    }

    // MARK: Output

    public func primitives(emerge: CGFloat, headGlow: CGFloat = 0) -> [ShapePrim] {
        let e = max(0, min(1.15, emerge))
        guard e > 0.01 else { return [] }
        var out: [ShapePrim] = []

        if shattered {
            for f in fragments where f.life > 0.02 {
                let s = f.life
                let tip = CGPoint(x: f.base.x + cos(f.angle) * f.len * s, y: f.base.y + sin(f.angle) * f.len * s)
                out.append(ShapePrim(kind: .shard, a: f.base, b: tip, ra: max(0.8, f.width * s), rb: f.tipFrac, emphasis: s * 0.7, seed: f.seed))
            }
            return out
        }

        let R = params.coreRadius
        // Core: a solid centre so the rosette reads as one crystal cluster.
        out.append(ShapePrim(kind: .circle, a: pin, ra: R * 0.30 * e, blend: .hard, seed: 0.3))
        for s in shards where s.len > 1.5 {
            let tip = CGPoint(x: s.base.x + cos(s.angle) * s.len * e, y: s.base.y + sin(s.angle) * s.len * e)
            out.append(ShapePrim(kind: .shard, a: s.base, b: tip, ra: s.width * e, rb: s.tipFrac, emphasis: s.glow, seed: s.seed))
        }
        // The main needle plus two shorter twins, like a quartz point with companions.
        if mainLen > 3 {
            let dir = CGPoint(x: cos(mainAngle), y: sin(mainAngle))
            let w = max(2.6, R * 0.20 / (1 + mainLen / (6 * R)) + 1.6)
            let tip = CGPoint(x: pin.x + dir.x * mainLen * e, y: pin.y + dir.y * mainLen * e)
            out.append(ShapePrim(kind: .shard, a: pin, b: tip, ra: w * e, rb: 0.30, emphasis: 0.2, seed: 0.62))
            for (k, off) in [(-1 as CGFloat, 0.115 as CGFloat), (1, 0.14)] {
                let a2 = mainAngle + k * off
                let l2 = mainLen * (k < 0 ? 0.72 : 0.5) * e
                let t2 = CGPoint(x: pin.x + cos(a2) * l2, y: pin.y + sin(a2) * l2)
                out.append(ShapePrim(kind: .shard, a: pin, b: t2, ra: w * 0.7 * e, rb: 0.34, emphasis: 0, seed: 0.3 + k * 0.1))
            }
        }
        // The head: a small crystal star (hosts the armed label).
        let hr = headRadius * headScale
        let toPin = atan2(pin.y - head.y, pin.x - head.x)
        out.append(ShapePrim(kind: .circle, a: head, ra: hr * 0.55 * e, blend: .hard, emphasis: headGlow, seed: 0.8))
        for (i, off) in [CGFloat(0), 0.95, -0.95, 1.9, -1.9].enumerated() {
            let a = toPin + .pi + off * 0.7
            let l = hr * (i == 0 ? 1.5 : 1.0) * e
            let tip = CGPoint(x: head.x + cos(a) * l, y: head.y + sin(a) * l)
            out.append(ShapePrim(kind: .shard, a: head, b: tip, ra: hr * 0.34 * e, rb: 0.4, emphasis: headGlow, seed: 0.1 + 0.15 * CGFloat(i)))
        }
        return out
    }
}
