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
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    private struct Mote { var p: CGPoint; var v: CGPoint; var s: CGFloat; var lane: CGFloat; var size: CGFloat; var phase: CGFloat }
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
            let bandW = (ends * 1.5 + 14 * wob) * (0.35 + 0.65 * (1 - abs(m.s - 0.5) * 0.9))
            let base = CGPoint(x: pin.x + dx * m.s * spread, y: pin.y + dy * m.s * spread)
            let loop = (1 - spread) * params.bodyRadius * 1.8     // with no pull they hover around the pin
            let tgt = CGPoint(x: base.x + nrm.x * m.lane * bandW + wob * loop + dir.x * wob2 * 6 * spread,
                              y: base.y + nrm.y * m.lane * bandW + wob2 * loop + dir.y * wob * 6 * spread)
            let w: CGFloat = 7 + 5 * StyleHash.unit(i, 57)
            let ax = (w * w * (tgt.x - m.p.x) - 2 * 0.5 * w * m.v.x) * hold
            let ay = (w * w * (tgt.y - m.p.y) - 2 * 0.5 * w * m.v.y) * hold
            m.v.x += ax * dt; m.v.y += ay * dt
            m.v.x *= hold == 1 ? 1 : CGFloat(exp(Double(-1.2 * dt)))
            m.v.y *= hold == 1 ? 1 : CGFloat(exp(Double(-1.2 * dt)))
            m.p.x += m.v.x * dt; m.p.y += m.v.y * dt
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

/// Tendrils: a sea-creature pin whose tentacles reach for the head. Each tentacle is a chain that follows the one
/// before it with lag, undulating as it goes; the tentacles fan out and taper to fine tips. Commit makes them
/// whip toward the pull and curl back.
public struct TendrilSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 28
        public var tentacles: Int = 7
        public var links: Int = 12
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    private var tent: [[CGPoint]] = []
    public var params: Params
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var flow: DumbbellMass.Solution?
    private var sol = DumbbellMass.Solution(pin: 1, head: 1, waist: 1)
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.6 }
    public var tentacleCount: Int { tent.count }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; flow = nil
        sol = DumbbellMass.solve(params.dumbbell, length: 0)
        tent = (0..<max(1, params.tentacles)).map { _ in Array(repeating: pin, count: max(3, params.links)) }
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

        let dir = chord > 1 ? CGPoint(x: dx / chord, y: dy / chord) : CGPoint(x: 0, y: -1)
        let nrm = CGPoint(x: -dir.y, y: dir.x)
        let nT = tent.count
        let reach = StyleHash.smoothstep(10, 140, chord)
        let hold: CGFloat = releaseT >= 0 ? 0 : 1
        for t in 0..<nT {
            let fan = (CGFloat(t) / CGFloat(max(1, nT - 1)) - 0.5) * 2          // -1...1
            let L = tent[t].count
            // Tip goal: reach toward the head (nearest tentacles longest), or droop around the pin at rest.
            let reachLen = (chord * (0.55 + 0.4 * (1 - abs(fan))) + params.bodyRadius * 1.2) * reach
                + params.bodyRadius * (1.3 + 0.5 * (1 - abs(fan))) * (1 - reach)
            let seg = max(3, reachLen / CGFloat(L - 1))
            tent[t][0] = CGPoint(x: pin.x + nrm.x * fan * sol.pin * 0.5, y: pin.y + nrm.y * fan * sol.pin * 0.5)
            for j in 1..<L {
                let u = CGFloat(j) / CGFloat(L - 1)
                // Each link heads for a point on a fanned, undulating curve toward the head; links follow with lag.
                let wave = CGFloat(sin(Double(time * 2.4 - u * 5 + CGFloat(t) * 1.3)))
                let spreadAng = fan * 1.2 * (1 - reach * 0.78)
                let ca = CGFloat(cos(Double(spreadAng))), sa = CGFloat(sin(Double(spreadAng)))
                let fdir = CGPoint(x: dir.x * ca - dir.y * sa, y: dir.x * sa + dir.y * ca)
                let aim = CGPoint(x: tent[t][0].x + fdir.x * seg * CGFloat(j) + nrm.x * wave * 7 * u * (0.4 + reach)
                                       + 0 * time,
                                  y: tent[t][0].y + fdir.y * seg * CGFloat(j) + nrm.y * wave * 7 * u * (0.4 + reach)
                                       - (1 - reach) * u * u * 22)
                let follow = 1 - CGFloat(exp(Double(-(10 - 5 * u) * dt)))
                let gain = hold == 1 ? follow : follow * 0.15
                tent[t][j].x += (aim.x - tent[t][j].x) * gain
                tent[t][j].y += (aim.y - tent[t][j].y) * gain
            }
        }
        if releaseT >= 0 { releaseT += dt }
    }

    public mutating func release(commit direction: CGPoint?) {
        releaseT = 0
        guard let d = direction else { return }
        for t in tent.indices {
            for j in 1..<tent[t].count {
                let u = CGFloat(j) / CGFloat(tent[t].count - 1)
                tent[t][j].x += d.x * 90 * u; tent[t][j].y += d.y * 90 * u
            }
        }
    }

    public func primitives(emerge: CGFloat, headGlow: CGFloat = 0) -> [ShapePrim] {
        let e = max(0, min(1.15, emerge))
        guard e > 0.01 else { return [] }
        let fade = releaseT >= 0 ? max(0, 1 - releaseT / 0.5) : 1
        var out: [ShapePrim] = []
        out.append(ShapePrim(kind: .circle, a: pin, ra: sol.pin * e * (0.4 + 0.6 * fade), blend: .soft))
        out.append(ShapePrim(kind: .circle, a: head, ra: max(sol.head, 5) * 0.8 * e * (1 + 0.12 * headGlow) * (0.4 + 0.6 * fade),
                             blend: .soft, emphasis: headGlow))
        for t in tent.indices {
            let L = tent[t].count
            for j in 0..<(L - 1) {
                let u = CGFloat(j) / CGFloat(L - 1)
                let base = max(1.2, sol.pin * 0.2 * (1 - u) * (1 - u) + 2.0)
                let tip = max(0.9, sol.pin * 0.2 * (1 - (u + 1 / CGFloat(L - 1))) * (1 - (u + 1 / CGFloat(L - 1))) + 2.0)
                out.append(ShapePrim(kind: .cone, a: tent[t][j], b: tent[t][j + 1], ra: base * e * fade, rb: tip * e * fade,
                                     blend: .tight))
            }
        }
        return out
    }
}
