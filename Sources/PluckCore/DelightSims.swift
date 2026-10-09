import CoreGraphics
import Foundation

/// Pearls: a beaded necklace hung between the pin and the head on rope physics. Slack coils and sags under gravity;
/// pulled taut it straightens and the beads spread. The end beads are the (mass-conserving) pin and head; the beads
/// between them are small pearls that swell toward the ends. Commit flings the pearls along the pull.
public struct PearlSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 32
        public var beads: Int = 26
        public var sag: CGFloat = 900
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    private struct Bead { var p: CGPoint; var prev: CGPoint }
    public var params: Params
    private var chain: [Bead] = []
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var flow: DumbbellMass.Solution?
    private var sol = DumbbellMass.Solution(pin: 1, head: 1, waist: 1)
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.6 }
    public var beadCount: Int { chain.count }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; flow = nil
        chain = (0..<max(2, params.beads)).map { _ in Bead(p: pin, prev: pin) }
        sol = DumbbellMass.solve(params.dumbbell, length: 0)
    }

    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0, chain.count > 1 else { return }
        time += dt
        pin = newPin; head = newHead
        let n = chain.count
        let chord = hypot(head.x - pin.x, head.y - pin.y)
        let target = DumbbellMass.solve(params.dumbbell, length: chord)
        var f = flow ?? target
        let k = CGFloat(1 - exp(-Double(dt) / 0.05))
        f = .init(pin: f.pin + (target.pin - f.pin) * k, head: f.head + (target.head - f.head) * k, waist: target.waist)
        flow = f
        let rs = params.bodyRadius / params.dumbbell.restRadius
        sol = .init(pin: f.pin * rs, head: f.head * rs, waist: f.waist)

        // Rope: a little longer than the chord so it bows; coils up (stays short) near the pin.
        let ropeLen = max(chord * 1.035, params.bodyRadius * 2.6)
        let seg = ropeLen / CGFloat(n - 1)
        let steps = max(1, Int((dt / 0.004).rounded(.up)))
        let h = dt / CGFloat(steps)
        let collapse: CGFloat = releaseT >= 0 ? 0 : 1
        for _ in 0..<steps {
            for i in 1..<(n - 1) {
                let c = chain[i].p
                var vx = (c.x - chain[i].prev.x) * 0.992, vy = (c.y - chain[i].prev.y) * 0.992
                vy -= params.sag * h * h * collapse
                chain[i].prev = c
                chain[i].p = CGPoint(x: c.x + vx, y: c.y + vy)
                _ = (vx, vy); vx = 0; vy = 0
            }
            chain[0].p = pin; chain[0].prev = pin
            chain[n - 1].p = head; chain[n - 1].prev = head
            for _ in 0..<6 {
                for i in 0..<(n - 1) {
                    let a = chain[i].p, b = chain[i + 1].p
                    let dx = b.x - a.x, dy = b.y - a.y
                    let d = max(0.0001, hypot(dx, dy))
                    if d <= seg { continue }                    // slack: beads may bunch, never overstretch
                    let corr = (d - seg) / d * 0.5
                    let wa: CGFloat = i == 0 ? 0 : 1, wb: CGFloat = i + 1 == n - 1 ? 0 : 1
                    let tw = wa + wb
                    if tw == 0 { continue }
                    chain[i].p.x += dx * corr * 2 * wa / tw; chain[i].p.y += dy * corr * 2 * wa / tw
                    chain[i + 1].p.x -= dx * corr * 2 * wb / tw; chain[i + 1].p.y -= dy * corr * 2 * wb / tw
                }
            }
        }
        if releaseT >= 0 { releaseT += dt }
    }

    public mutating func release(commit direction: CGPoint?) {
        releaseT = 0
        guard let d = direction else { return }
        for i in chain.indices where i > 0 && i < chain.count - 1 {
            let kick = 220 + 420 * StyleHash.unit(i, 41)
            chain[i].prev.x -= d.x * kick / 120 + (StyleHash.unit(i, 42) - 0.5) * 2
            chain[i].prev.y -= d.y * kick / 120 + (StyleHash.unit(i, 43) - 0.5) * 2
        }
    }

    public func primitives(emerge: CGFloat, headGlow: CGFloat = 0) -> [ShapePrim] {
        let e = max(0, min(1.15, emerge))
        guard e > 0.01, !chain.isEmpty else { return [] }
        let n = chain.count
        let fade = releaseT >= 0 ? max(0, 1 - releaseT / 0.5) : 1
        var out: [ShapePrim] = []
        let pearl = max(2.6, params.bodyRadius * 0.15)
        for i in 1..<(n - 1) {
            let t = CGFloat(i) / CGFloat(n - 1)
            let toPin = CGFloat(exp(Double(-5 * t))), toHead = CGFloat(exp(Double(-5 * (1 - t))))
            let r = (pearl + (sol.pin * 0.55 - pearl) * toPin + (max(sol.head, pearl) * 0.55 - pearl) * toHead) * e * fade
            out.append(ShapePrim(kind: .circle, a: chain[i].p, ra: r, blend: .tight))
        }
        out.append(ShapePrim(kind: .circle, a: pin, ra: sol.pin * e * (0.4 + 0.6 * fade), blend: .soft))
        out.append(ShapePrim(kind: .circle, a: head, ra: max(sol.head, pearl) * e * (1 + 0.12 * headGlow) * (0.4 + 0.6 * fade),
                             blend: .soft, emphasis: headGlow))
        return out
    }
}

/// Swarm: fireflies. A cloud of glowing motes hovers around the pin; as the head pulls away they stream out along a
/// wandering band between the two points, thicker near the ends, blinking as they go. Commit scatters them.
public struct SwarmSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 26
        public var motes: Int = 70
        /// Insects drawn when rendered as real fireflies (the first N motes).
        public var fireflies: Int = 15
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    private struct Mote { var p: CGPoint; var v: CGPoint; var s: CGFloat; var lane: CGFloat; var size: CGFloat; var phase: CGFloat; var heading: CGFloat = 0 }
    public var params: Params
    private var motes: [Mote] = []
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var flow: DumbbellMass.Solution?
    private var sol = DumbbellMass.Solution(pin: 1, head: 1, waist: 1)
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.6 }
    public var moteCount: Int { motes.count }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; flow = nil
        sol = DumbbellMass.solve(params.dumbbell, length: 0)
        motes = (0..<max(1, params.motes)).map { i in
            let a = 2 * .pi * StyleHash.unit(i, 51), r = params.bodyRadius * (0.8 + 2.2 * StyleHash.unit(i, 52))
            let p = CGPoint(x: pin.x + cos(a) * r, y: pin.y + sin(a) * r)
            // Motes are biased toward the ends of the band (a real swarm clusters at the two lights).
            let u = StyleHash.unit(i, 53)
            let s = u < 0.5 ? pow(u * 2, 2.2) * 0.5 : 1 - pow((1 - u) * 2, 2.2) * 0.5
            return Mote(p: p, v: .zero, s: s, lane: StyleHash.unit(i, 54) * 2 - 1,
                        size: 2.2 + 3.0 * StyleHash.unit(i, 55), phase: 6.28 * StyleHash.unit(i, 56))
        }
    }

    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt
        pin = newPin; head = newHead
        let dx = head.x - pin.x, dy = head.y - pin.y
        let chord = hypot(dx, dy)
        let target = DumbbellMass.solve(params.dumbbell, length: chord)
        var f = flow ?? target
        let k = CGFloat(1 - exp(-Double(dt) / 0.05))
        f = .init(pin: f.pin + (target.pin - f.pin) * k, head: f.head + (target.head - f.head) * k, waist: target.waist)
        flow = f
        let rs = params.bodyRadius / params.dumbbell.restRadius
        sol = .init(pin: f.pin * rs, head: f.head * rs, waist: f.waist)

        let dir = chord > 1 ? CGPoint(x: dx / chord, y: dy / chord) : CGPoint(x: 1, y: 0)
        let nrm = CGPoint(x: -dir.y, y: dir.x)
        let spread = StyleHash.smoothstep(40, 260, chord)
        let hold: CGFloat = releaseT >= 0 ? 0 : 1
        for i in motes.indices {
            var m = motes[i]
            // Where this mote wants to be: a point on the band, wandering with a slow personal orbit.
            let wob = CGFloat(sin(Double(time * 0.9 + m.phase))), wob2 = CGFloat(cos(Double(time * 1.3 + m.phase * 1.7)))
            let ends = sol.pin * (1 - m.s) + max(sol.head, 6) * m.s
            let insect: CGFloat = i < params.fireflies ? 2.3 : 1
            let bandW = (ends * 1.5 + 14 * wob) * (0.35 + 0.65 * (1 - abs(m.s - 0.5) * 0.9)) * insect
            let base = CGPoint(x: pin.x + dx * m.s * spread, y: pin.y + dy * m.s * spread)
            let loop = (1 - spread) * params.bodyRadius * (i < params.fireflies ? 3.0 : 1.8)     // with no pull they hover around the pin
            let tgt = CGPoint(x: base.x + nrm.x * m.lane * bandW + wob * loop + dir.x * wob2 * 6 * spread,
                              y: base.y + nrm.y * m.lane * bandW + wob2 * loop + dir.y * wob * 6 * spread)
            let w: CGFloat = 7 + 5 * StyleHash.unit(i, 57)
            let ax = (w * w * (tgt.x - m.p.x) - 2 * 0.5 * w * m.v.x) * hold
            let ay = (w * w * (tgt.y - m.p.y) - 2 * 0.5 * w * m.v.y) * hold
            m.v.x += ax * dt; m.v.y += ay * dt
            m.v.x *= hold == 1 ? 1 : CGFloat(exp(Double(-1.2 * dt)))
            m.v.y *= hold == 1 ? 1 : CGFloat(exp(Double(-1.2 * dt)))
            m.p.x += m.v.x * dt; m.p.y += m.v.y * dt
            // Insects face the way they fly (slowly turning when nearly still).
            let sp = hypot(m.v.x, m.v.y)
            if sp > 8 {
                var dA = atan2(m.v.y, m.v.x) - m.heading
                while dA > .pi { dA -= 2 * .pi }
                while dA < -.pi { dA += 2 * .pi }
                m.heading += dA * min(1, 7 * dt)
            }
            motes[i] = m
        }
        if releaseT >= 0 { releaseT += dt }
    }

    public mutating func release(commit direction: CGPoint?) {
        releaseT = 0
        for i in motes.indices {
            let a = 2 * .pi * StyleHash.unit(i, 58)
            var kx = cos(a) * 160, ky = sin(a) * 160
            if let d = direction { kx += d.x * (220 + 300 * StyleHash.unit(i, 59)); ky += d.y * (220 + 300 * StyleHash.unit(i, 59)) }
            motes[i].v.x += kx; motes[i].v.y += ky
        }
    }

    public func primitives(emerge: CGFloat, headGlow: CGFloat = 0) -> [ShapePrim] {
        let e = max(0, min(1.15, emerge))
        guard e > 0.01 else { return [] }
        let fade = releaseT >= 0 ? max(0, 1 - releaseT / 0.5) : 1
        var out: [ShapePrim] = []
        out.append(ShapePrim(kind: .circle, a: pin, ra: sol.pin * 0.75 * e * (0.4 + 0.6 * fade), blend: .soft))
        out.append(ShapePrim(kind: .circle, a: head, ra: max(sol.head, 5) * 0.75 * e * (1 + 0.12 * headGlow) * (0.4 + 0.6 * fade),
                             blend: .soft, emphasis: headGlow))
        for m in motes {
            let blink = 0.5 + 0.5 * CGFloat(sin(Double(time * 3.2 + m.phase * 5)))
            let r = m.size * (0.7 + 0.5 * blink) * e * fade
            if r > 0.6 { out.append(ShapePrim(kind: .circle, a: m.p, ra: r, blend: .tight, emphasis: blink * 0.8)) }
        }
        return out
    }
}

/// One firefly for the sprite renderer.
public struct FireflyState: Equatable, Sendable {
    public var position: CGPoint
    /// Direction the insect faces (radians, y-up).
    public var heading: CGFloat
    /// Body length in points.
    public var length: CGFloat
    /// 0...1 lantern brightness (a slow flash with long dark pauses).
    public var glow: CGFloat
    /// Wing-beat phase (radians).
    public var wingPhase: CGFloat
    public var alpha: CGFloat
    /// Speed (points/second) and a colour index 0...2 (warm, mint, peach).
    public var speed: CGFloat = 0
    public var tint: Int = 0

    public init(position: CGPoint, heading: CGFloat, length: CGFloat, glow: CGFloat, wingPhase: CGFloat, alpha: CGFloat,
                speed: CGFloat = 0, tint: Int = 0) {
        self.position = position; self.heading = heading; self.length = length; self.glow = glow
        self.wingPhase = wingPhase; self.alpha = alpha; self.speed = speed; self.tint = tint
    }
}

extension SwarmSim {
    /// The insects to draw (pin and head are drawn separately as lanterns).
    public func fireflyStates(emerge: CGFloat) -> [FireflyState] {
        let e = max(0, min(1, emerge))
        let fade = releaseT >= 0 ? max(0, 1 - releaseT / 0.5) : 1
        let scale = params.bodyRadius / 26
        var out: [FireflyState] = []
        for (i, m) in motes.prefix(max(0, params.fireflies)).enumerated() {
            // Each insect flashes on its own rhythm: a quick swell, a glow, a fade, then a long dark pause.
            let period = 2.4 + 2.2 * StyleHash.unit(i, 61)
            let ph = (time / period + StyleHash.unit(i, 62)).truncatingRemainder(dividingBy: 1)
            let on = StyleHash.smoothstep(0.0, 0.12, ph) * (1 - StyleHash.smoothstep(0.30, 0.52, ph))
            let rest = 0.12 + 0.06 * CGFloat(sin(Double(time * 1.7 + m.phase)))
            out.append(FireflyState(position: m.p, heading: m.heading, length: (13 + 6 * m.size / 5) * scale,
                                    glow: max(rest * 0.6, on), wingPhase: time * (70 + 25 * StyleHash.unit(i, 63)) + m.phase,
                                    alpha: e * fade, speed: hypot(m.v.x, m.v.y), tint: i % 3))
        }
        return out
    }

    public var pinLantern: (center: CGPoint, radius: CGFloat) { (pin, sol.pin * 1.05) }
    public var headLantern: (center: CGPoint, radius: CGFloat) { (head, max(sol.head, 5) * 1.05) }
}

/// Tendrils: a possessed mass in the manner of the cursed gods of Princess Mononoke. Many black, glistening worms
/// boil out of the pin and are never still: they thrash and knot around each other whether or not the cursor
/// moves. They lash toward the cursor and coil around it, tightening and loosening, with sudden whip-like lunges.
/// Commit: the whole mass convulses and whips toward the pull, then dies away. Release: they writhe back and slacken.
public struct TendrilSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 28
        public var tentacles: Int = 15
        public var links: Int = 26
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    private var tent: [[CGPoint]] = []
    private var tentV: [[CGPoint]] = []
    public var params: Params
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var mass = MassFlow()
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    private var grip: CGFloat = 0
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.9 }
    public var tentacleCount: Int { tent.count }
    /// 0...1 how tightly the tentacles have closed around the head.
    public var gripAmount: CGFloat { grip }
    fileprivate var sol: DumbbellMass.Solution { mass.sol }

    /// Per-tentacle personality: thickness, writhe speed, length, which way it coils, and when it thrashes.
    private func trait(_ t: Int) -> (thick: CGFloat, speed: CGFloat, length: CGFloat, dir: CGFloat, phase: CGFloat, lunge: CGFloat) {
        (0.45 + 1.1 * StyleHash.unit(t, 501), 0.8 + 1.5 * StyleHash.unit(t, 502), 0.75 + 0.5 * StyleHash.unit(t, 503),
         StyleHash.unit(t, 504) > 0.5 ? 1 : -1, 6.28 * StyleHash.unit(t, 505), 1.2 + 2.6 * StyleHash.unit(t, 506))
    }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; mass = MassFlow(); grip = 0
        mass.sol = DumbbellMass.solve(params.dumbbell, length: 0)
        tent = (0..<max(1, params.tentacles)).map { _ in Array(repeating: pin, count: max(4, params.links)) }
        tentV = tent.map { $0.map { _ in CGPoint.zero } }
    }

    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt
        pin = newPin; head = newHead
        let dx = head.x - pin.x, dy = head.y - pin.y
        let chord = hypot(dx, dy)
        mass.update(chord: chord, dt: dt, params: params.dumbbell, bodyRadius: params.bodyRadius)

        let dir = chord > 1 ? CGPoint(x: dx / chord, y: dy / chord) : CGPoint(x: 0, y: 1)
        let nrm = CGPoint(x: -dir.y, y: dir.x)
        let nT = tent.count
        let reach = StyleHash.smoothstep(10, 150, chord)
        // They always swarm the head. Far away they first lunge to it; close in they simply boil around it.
        let wrapTarget = (0.62 + 0.38 * StyleHash.smoothstep(60, 220, chord)) * (releaseT >= 0 ? 0 : 1)
        grip += (wrapTarget - grip) * (1 - CGFloat(exp(Double(-7 * dt))))
        let headR = max(sol.head * 0.8, 9)
        let hold: CGFloat = releaseT >= 0 ? 0 : 1
        let toPin = atan2(-dy, -dx)
        let uW: CGFloat = 0.5
        let commitT = releaseT >= 0 ? releaseT : 0

        for t in 0..<nT {
            let tr = trait(t)
            let L = tent[t].count
            let fan = (CGFloat(t) / CGFloat(max(1, nT - 1)) - 0.5) * 2
            let root = CGPoint(x: pin.x + nrm.x * fan * sol.pin * 0.55, y: pin.y + nrm.y * fan * sol.pin * 0.55)
            tent[t][0] = root
            // A periodic thrash: this worm suddenly whips (a sharp bump in its writhing amplitude).
            let cycle = tr.lunge + 1.4
            let tc = (time + tr.phase).truncatingRemainder(dividingBy: cycle) / cycle
            let thrash = max(0, 1 - abs(tc - 0.12) / 0.07)
            let theta0 = toPin + fan * 1.6 + 0.5 * CGFloat(sin(Double(time * 0.7 + tr.phase)))
            let entryR = headR * (2.2 + 0.5 * CGFloat(sin(Double(time * 1.3 + tr.phase))))
            let entry = CGPoint(x: head.x + cos(theta0) * entryR, y: head.y + sin(theta0) * entryR)
            let turns = 1.2 + 0.8 * StyleHash.unit(t, 507)
            let reachLen = (chord * (0.5 + 0.45 * tr.length) + params.bodyRadius * 1.4) * reach + params.bodyRadius * (1.6 * tr.length) * (1 - reach)
            let seg = max(3, reachLen / CGFloat(L - 1))
            for j in 1..<L {
                let u = CGFloat(j) / CGFloat(L - 1)
                // Endless writhing: two travelling waves of different speeds plus a pulse, bigger toward the tip.
                let k1 = 7 + 5 * StyleHash.unit(t, 508), k2 = 13 + 6 * StyleHash.unit(t, 509)
                let amp = (9 + 22 * u) * tr.thick * (0.7 + 0.6 * thrash * 2.2 + 0.2)
                let w1 = CGFloat(sin(Double(time * 3.1 * tr.speed - u * k1 + tr.phase)))
                let w2 = CGFloat(sin(Double(time * 5.3 * tr.speed - u * k2 + tr.phase * 1.7)))
                let writhe = amp * (w1 + 0.55 * w2) * (0.6 + 0.4 * u)
                // Relaxed: they lie along the reach direction, fanning a little, wriggling sideways.
                let spreadAng = fan * 1.3 * (1 - reach * 0.7)
                let ca = CGFloat(cos(Double(spreadAng))), sa = CGFloat(sin(Double(spreadAng)))
                let fdir = CGPoint(x: dir.x * ca - dir.y * sa, y: dir.x * sa + dir.y * ca)
                let relaxed = CGPoint(x: root.x + fdir.x * seg * CGFloat(j) + nrm.x * writhe, y: root.y + fdir.y * seg * CGFloat(j) + nrm.y * writhe)
                // Grabbing: out along a writhing path to the head, then a coiling spiral that breathes in and out.
                var grab: CGPoint
                if u <= uW {
                    let w = u / uW
                    let lash = writhe * (0.6 + 0.8 * sin(.pi * w))
                    grab = CGPoint(x: root.x + (entry.x - root.x) * w + nrm.x * lash, y: root.y + (entry.y - root.y) * w + nrm.y * lash)
                } else {
                    let w = (u - uW) / (1 - uW)
                    let ang = theta0 + tr.dir * (w * turns * 2 * .pi) + CGFloat(sin(Double(time * 2.0 * tr.speed + tr.phase))) * 0.9 + time * 0.6 * tr.dir
                    let pulse = 1 + 0.28 * CGFloat(sin(Double(time * 6 * tr.speed + w * 5 + tr.phase))) + 0.35 * thrash
                    let r = headR * (2.3 - 1.2 * w) * pulse + 5 * CGFloat(sin(Double(time * 9 * tr.speed + w * 11))) * tr.thick
                    grab = CGPoint(x: head.x + cos(ang) * r, y: head.y + sin(ang) * r)
                }
                var aim = CGPoint(x: relaxed.x + (grab.x - relaxed.x) * grip, y: relaxed.y + (grab.y - relaxed.y) * grip)
                if releaseT >= 0 {                                               // commit: a convulsing lunge along the pull, then slack
                    let kick = max(0, 1 - commitT / 0.5)
                    aim.x += dir.x * 160 * u * kick; aim.y += dir.y * 160 * u * kick
                    aim.y -= 90 * u * u * (1 - kick)
                }
                let omega: CGFloat = (hold == 1 ? 24 : 6) - 8 * u
                let zeta: CGFloat = 0.34
                let ax = omega * omega * (aim.x - tent[t][j].x) - 2 * zeta * omega * tentV[t][j].x
                let ay = omega * omega * (aim.y - tent[t][j].y) - 2 * zeta * omega * tentV[t][j].y
                tentV[t][j].x += ax * dt; tentV[t][j].y += ay * dt
                tent[t][j].x += tentV[t][j].x * dt; tent[t][j].y += tentV[t][j].y * dt
            }
        }
        if releaseT >= 0 { releaseT += dt }
    }

    public mutating func release(commit direction: CGPoint?) {
        releaseT = 0
    }

    public func primitives(emerge: CGFloat, headGlow: CGFloat = 0) -> [ShapePrim] {
        let e = max(0, min(1.15, emerge))
        guard e > 0.01 else { return [] }
        let fade = releaseT >= 0 ? max(0, 1 - max(0, releaseT - 0.35) / 0.5) : 1
        var out: [ShapePrim] = []
        // The mass itself seethes: it swells and sags unevenly.
        let breathe = 1 + 0.07 * CGFloat(sin(Double(time * 3.2))) + 0.04 * CGFloat(sin(Double(time * 7.1)))
        out.append(ShapePrim(kind: .circle, a: pin, ra: sol.pin * e * breathe * (0.5 + 0.5 * fade), blend: .soft))
        out.append(ShapePrim(kind: .circle, a: head, ra: max(sol.head, 5) * 0.8 * e * (1 + 0.12 * headGlow) * (0.5 + 0.5 * fade), blend: .soft, emphasis: headGlow))
        for t in tent.indices {
            let tr = trait(t)
            let L = tent[t].count
            for j in 0..<(L - 1) {
                let u = CGFloat(j) / CGFloat(L - 1)
                let u2 = u + 1 / CGFloat(L - 1)
                // Thick at the root, thinning to a whip-fine tip; a slow swell travels along each worm.
                let swell = 1 + 0.18 * CGFloat(sin(Double(time * 4 * tr.speed - u * 9 + tr.phase)))
                let base = max(1.4, (sol.pin * 0.2 * (1 - u) * (1 - u) + 3.0) * tr.thick * swell)
                let tip = max(0.9, (sol.pin * 0.2 * (1 - u2) * (1 - u2) + 3.0) * tr.thick * (1 + 0.18 * CGFloat(sin(Double(time * 4 * tr.speed - u2 * 9 + tr.phase)))))
                out.append(ShapePrim(kind: .cone, a: tent[t][j], b: tent[t][j + 1], ra: base * e * fade, rb: tip * e * fade, blend: .soft))
            }
        }
        return out
    }
}

/// Jump rope: the pin and head are the two turners, the rope swings between them in a vertical plane (seen side-on:
/// a loop that rises over, then dips under the middle), and a little round critter with floppy ears stands at the
/// centre of the span and hops the rope each time it sweeps under its feet, landing with a squash. The ears and
/// tail lag the body. Commit: the critter bounds off along the pull and the rope falls slack.
public struct JumpRopeSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 30
        public var links: Int = 28
        /// Rope turns per second.
        public var turnRate: CGFloat = 1.15
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    public var params: Params
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var flow: DumbbellMass.Solution?
    private var sol = DumbbellMass.Solution(pin: 1, head: 1, waist: 1)
    private var phase: CGFloat = 0
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    private var releaseDir = CGPoint(x: 1, y: 0)
    private var earLag: CGFloat = 0, earLagV: CGFloat = 0
    private var lastLift: CGFloat = 0
    private var squash: CGFloat = 0, squashV: CGFloat = 0
    private var lift: CGFloat = 0
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.7 }
    /// 0...1 how much of the toy is shown (grows in as the head pulls away).
    public var reachAmount: CGFloat { StyleHash.smoothstep(40, 220, hypot(head.x - pin.x, head.y - pin.y)) }
    public var critterLift: CGFloat { lift }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; phase = 0; time = 0; releaseT = -1; flow = nil
        earLag = 0; earLagV = 0; lastLift = 0; squash = 0; squashV = 0; lift = 0
        sol = DumbbellMass.solve(params.dumbbell, length: 0)
    }

    private func axes() -> (mid: CGPoint, along: CGPoint, up: CGPoint, chord: CGFloat) {
        let dx = head.x - pin.x, dy = head.y - pin.y
        let chord = hypot(dx, dy)
        let along = chord > 1 ? CGPoint(x: dx / chord, y: dy / chord) : CGPoint(x: 1, y: 0)
        var up = CGPoint(x: -along.y, y: along.x)
        if up.y < 0 || (abs(up.y) < 1e-6 && up.x < 0) { up = CGPoint(x: -up.x, y: -up.y) }   // "up" is the screen's up
        return (CGPoint(x: (pin.x + head.x) / 2, y: (pin.y + head.y) / 2), along, up, chord)
    }

    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt
        pin = newPin; head = newHead
        let ax = axes()
        let target = DumbbellMass.solve(params.dumbbell, length: ax.chord)
        var f = flow ?? target
        let k = CGFloat(1 - exp(-Double(dt) / 0.05))
        f = .init(pin: f.pin + (target.pin - f.pin) * k, head: f.head + (target.head - f.head) * k, waist: target.waist)
        flow = f
        let rs = params.bodyRadius / params.dumbbell.restRadius
        sol = .init(pin: f.pin * rs, head: f.head * rs, waist: f.waist)

        // The rope turns; the critter hops as it sweeps under (rope phase 3*pi/2: rising through the feet).
        phase += 2 * .pi * params.turnRate * dt * (releaseT >= 0 ? 0.2 : 1)
        var p = phase.truncatingRemainder(dividingBy: 2 * .pi)
        if p < 0 { p += 2 * .pi }
        let toPass = p - 1.5 * .pi                              // 0 at the instant the rope is under the feet
        let hop = abs(toPass) < 0.55 * .pi ? 1 - pow(abs(toPass) / (0.55 * .pi), 2) : 0
        // Lead the jump a touch so the feet leave before the rope arrives.
        let air = max(0, hop)
        let rest = params.bodyRadius * 0.9
        lift = air * rest * 1.15 * reachAmount
        // Landing squash when the lift falls back to the ground, and ears lag the vertical motion.
        let vy = (lift - lastLift) / dt
        lastLift = lift
        if lift < 0.5 && vy < -1 { squashV += min(2, -vy * 0.004) }
        var sq = CGPoint(x: squash, y: 0), sv = CGPoint(x: squashV, y: 0)
        RecoilSpring.step(x: &sq, v: &sv, omega: 22, zeta: 0.28, h: dt)
        squash = sq.x; squashV = sv.x
        let earTarget = -vy * 0.012
        var d = CGPoint(x: earLag - earTarget, y: 0), dv = CGPoint(x: earLagV, y: 0)
        RecoilSpring.step(x: &d, v: &dv, omega: 16, zeta: 0.25, h: dt)
        earLag = earTarget + d.x; earLagV = dv.x
        if releaseT >= 0 { releaseT += dt }
    }

    public mutating func release(commit direction: CGPoint?) {
        releaseT = 0
        releaseDir = direction ?? .zero
    }

    public func primitives(emerge: CGFloat, headGlow: CGFloat = 0) -> [ShapePrim] {
        let e = max(0, min(1.15, emerge))
        guard e > 0.01 else { return [] }
        let fade = releaseT >= 0 ? max(0, 1 - releaseT / 0.6) : 1
        let ax = axes()
        let reach = reachAmount
        var out: [ShapePrim] = []
        // The turners.
        out.append(ShapePrim(kind: .circle, a: pin, ra: sol.pin * 0.8 * e * (0.5 + 0.5 * fade), blend: .soft))
        out.append(ShapePrim(kind: .circle, a: head, ra: max(sol.head, 6) * 0.8 * e * (1 + 0.12 * headGlow) * (0.5 + 0.5 * fade),
                             blend: .soft, emphasis: headGlow))
        guard reach > 0.02 else { return out }

        // The rope: a loop in the vertical plane. Height at s along the span, sagging slightly behind the turn.
        let amp = min(ax.chord * 0.32, 150) * reach * (releaseT >= 0 ? max(0, 1 - releaseT / 0.4) : 1)
        let L = params.links
        func ropePoint(_ s: CGFloat) -> CGPoint {
            let swing = CGFloat(cos(Double(phase - 0.25 * sin(Double(.pi * s)))))
            let v = amp * CGFloat(sin(Double(.pi * s))) * swing
            let hang: CGFloat = releaseT >= 0 ? min(1, releaseT * 2) * 0.35 * ax.chord * CGFloat(sin(Double(.pi * s))) : 0
            return CGPoint(x: pin.x + (head.x - pin.x) * s + ax.up.x * (v - hang),
                           y: pin.y + (head.y - pin.y) * s + ax.up.y * (v - hang))
        }
        let rr = max(2.0, params.bodyRadius * 0.09) * e * fade
        var prev = ropePoint(0)
        for j in 1...L {
            let cur = ropePoint(CGFloat(j) / CGFloat(L))
            out.append(ShapePrim(kind: .cone, a: prev, b: cur, ra: rr, rb: rr, blend: .tight))
            prev = cur
        }

        // The critter, standing on the span's centre line and hopping the rope.
        let R = params.bodyRadius * 0.85 * e * reach
        let sqx = 1 + 0.22 * squash, sqy = 1 - 0.22 * squash
        var base = CGPoint(x: ax.mid.x + ax.up.x * (R * 0.95 * sqy + lift), y: ax.mid.y + ax.up.y * (R * 0.95 * sqy + lift))
        if releaseT >= 0 {
            let t = releaseT
            base.x += releaseDir.x * 380 * t; base.y += releaseDir.y * 380 * t + (300 * t - 900 * t * t) * 0.3
        }
        let cf = (releaseT >= 0 ? fade : 1)
        func at(_ u: CGFloat, _ w: CGFloat) -> CGPoint {   // u along the span, w along "up" from the body centre
            CGPoint(x: base.x + ax.along.x * u * sqx + ax.up.x * w * sqy, y: base.y + ax.along.y * u * sqx + ax.up.y * w * sqy)
        }
        out.append(ShapePrim(kind: .circle, a: base, ra: R * cf * (1 + 0.04 * (sqy - 1)), blend: .soft))
        // Ears: two small round ears that flop with the hop.
        let flop = max(-R * 0.6, min(R * 0.6, earLag * R))
        out.append(ShapePrim(kind: .cone, a: at(-R * 0.45, R * 0.7), b: at(-R * 0.75, R * 1.45 + flop), ra: R * 0.30 * cf, rb: R * 0.18 * cf, blend: .soft))
        out.append(ShapePrim(kind: .cone, a: at(R * 0.45, R * 0.7), b: at(R * 0.75, R * 1.45 + flop), ra: R * 0.30 * cf, rb: R * 0.18 * cf, blend: .soft))
        // Feet and a little tail.
        let tuck = lift > 1 ? 0.5 : 0
        out.append(ShapePrim(kind: .circle, a: at(-R * 0.45, -R * (0.95 - tuck)), ra: R * 0.30 * cf, blend: .soft))
        out.append(ShapePrim(kind: .circle, a: at(R * 0.45, -R * (0.95 - tuck)), ra: R * 0.30 * cf, blend: .soft))
        out.append(ShapePrim(kind: .circle, a: at(-R * 1.1, -R * 0.15 - flop * 0.4), ra: R * 0.22 * cf, blend: .soft))
        // Eyes: two glints on the front of the body.
        out.append(ShapePrim(kind: .circle, a: at(-R * 0.30, R * 0.15), ra: R * 0.13 * cf, blend: .hard, emphasis: 1))
        out.append(ShapePrim(kind: .circle, a: at(R * 0.30, R * 0.15), ra: R * 0.13 * cf, blend: .hard, emphasis: 1))
        return out
    }
}

/// Everything the paper-craft renderer needs for the jump rope, in screen points (y-up).
public struct PaperRopeScene: Equatable, Sendable {
    public var rope: [CGPoint]
    /// 0...1 how far the rope is toward the viewer (swing > 0 means up and behind, < 0 means down and in front).
    public var ropeInFront: Bool
    public var ropeWidth: CGFloat
    public var handlePin: CGPoint
    public var handleHead: CGPoint
    public var handlePinSize: CGFloat
    public var handleHeadSize: CGFloat
    public var handleAngle: CGFloat
    public var armed: CGFloat
    public var groundCenter: CGPoint
    public var groundAngle: CGFloat
    public var groundWidth: CGFloat
    public var critterCenter: CGPoint
    /// Rotation so the critter's up is the span's up (radians).
    public var critterAngle: CGFloat
    public var critterSize: CGFloat
    public var squash: CGFloat
    public var lift: CGFloat
    public var earFlop: CGFloat
    public var blink: CGFloat
    public var alpha: CGFloat
    public var hopping: Bool
}

extension JumpRopeSim {
    public func paperScene(emerge: CGFloat, headGlow: CGFloat = 0) -> PaperRopeScene {
        let e = max(0, min(1, emerge))
        let fade = releaseT >= 0 ? max(0, 1 - releaseT / 0.6) : 1
        let ax = axes()
        let reach = reachAmount
        let amp = min(ax.chord * 0.32, 150) * reach * (releaseT >= 0 ? max(0, 1 - releaseT / 0.4) : 1)
        let L = params.links
        var pts: [CGPoint] = []
        for j in 0...L {
            let s = CGFloat(j) / CGFloat(L)
            let swing = CGFloat(cos(Double(phase - 0.25 * sin(Double(.pi * s)))))
            let v = amp * CGFloat(sin(Double(.pi * s))) * swing
            let hang: CGFloat = releaseT >= 0 ? min(1, releaseT * 2) * 0.35 * ax.chord * CGFloat(sin(Double(.pi * s))) : 0
            pts.append(CGPoint(x: pin.x + (head.x - pin.x) * s + ax.up.x * (v - hang),
                               y: pin.y + (head.y - pin.y) * s + ax.up.y * (v - hang)))
        }
        let midSwing = CGFloat(cos(Double(phase - 0.25)))
        let R = params.bodyRadius * 1.1 * reach
        let sqy = 1 - 0.22 * squash
        var c = CGPoint(x: ax.mid.x + ax.up.x * (R * 0.95 * sqy + lift), y: ax.mid.y + ax.up.y * (R * 0.95 * sqy + lift))
        if releaseT >= 0 {
            let t = releaseT
            c.x += releaseDir.x * 380 * t; c.y += releaseDir.y * 380 * t + (300 * t - 900 * t * t) * 0.3
        }
        // Blink every few seconds.
        let bp = time.truncatingRemainder(dividingBy: 3.4)
        let blink: CGFloat = bp < 0.13 ? CGFloat(sin(Double(bp / 0.13 * .pi))) : 0
        let along = atan2(ax.along.y, ax.along.x)
        return PaperRopeScene(
            rope: pts, ropeInFront: midSwing < 0, ropeWidth: max(6, params.bodyRadius * 0.26),
            handlePin: pin, handleHead: head,
            handlePinSize: max(12, sol.pin * 1.25), handleHeadSize: max(12, max(sol.head, 6) * 1.25 * (1 + 0.12 * headGlow)),
            handleAngle: along, armed: headGlow,
            groundCenter: ax.mid, groundAngle: along, groundWidth: R * 3.2,
            critterCenter: c, critterAngle: atan2(ax.up.y, ax.up.x) - .pi / 2, critterSize: R,
            squash: squash, lift: lift, earFlop: max(-0.7, min(0.7, earLag * 1.4)), blink: blink,
            alpha: e * fade * (reach > 0.02 ? 1 : 0), hopping: lift > 1
        )
    }
}
