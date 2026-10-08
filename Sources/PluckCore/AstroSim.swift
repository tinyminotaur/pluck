import CoreGraphics
import Foundation

/// Two bodies under gravity. The pinned body is the heavy one, so its pull dominates: a swarm of dust and moonlets
/// orbits it, and as the light body (the cursor) is pulled away the swarm is stretched into a tidal stream between
/// them. Mass is conserved: the bodies' sizes come from `DumbbellMass` (the pin drains as the head recedes, refills
/// as it returns), and grains that fall into the light body are re-fed to the heavy one, so matter keeps flowing
/// pin -> head -> pin. Each body's pull is proportional to its mass (radius squared).
public struct AstroSim: Sendable {
    public struct Params: Equatable, Sendable {
        /// Rest radius of the heavy body (points).
        public var bodyRadius: CGFloat = 32
        public var grains: Int = 44
        /// Circular orbital speed at two body radii from the heavy body at rest (points/second).
        public var orbitSpeed: CGFloat = 210
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }

    private struct Grain {
        var p: CGPoint
        var v: CGPoint
        var size: CGFloat
        var seed: CGFloat
        var heat: CGFloat   // 0...1 glow after a close pass
    }

    public var params: Params
    private var pin: CGPoint = .zero
    private var head: CGPoint = .zero
    private var grains: [Grain] = []
    private var sol = DumbbellMass.Solution(pin: 1, head: 0, waist: 0)
    private var flow: DumbbellMass.Solution?
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    private var releaseDir = CGPoint(x: 1, y: 0)
    private var respawnCount = 0

    public init(params: Params = Params()) { self.params = params }

    public var pinRadius: CGFloat { sol.pin }
    public var headRadius: CGFloat { max(sol.head, params.bodyRadius * 0.16) }
    public var headPosition: CGPoint { head }
    public var isFinished: Bool { releaseT > 0.6 }
    public var grainCount: Int { grains.count }

    /// Pull strengths (GM) of the two bodies, in points^3 / s^2. Proportional to mass (radius squared).
    public func gravity() -> (pin: CGFloat, head: CGFloat) {
        let R = params.bodyRadius
        let gmRest = params.orbitSpeed * params.orbitSpeed * 2 * R     // v^2 r at r = 2R
        let mRest = R * R
        let scale = gmRest / mRest
        // A floor keeps the swarm bound while the pin is drained; the pin still always out-pulls the head.
        return (scale * max(sol.pin * sol.pin, 0.55 * R * R), scale * headRadius * headRadius)
    }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin
        head = pin
        time = 0; releaseT = -1; respawnCount = 0
        flow = nil
        sol = DumbbellMass.solve(params.dumbbell, length: 0)
        grains = (0..<max(0, params.grains)).map { i in spawn(index: i, around: pin) }
    }

    private func spawn(index i: Int, around c: CGPoint) -> Grain {
        let R = params.bodyRadius
        let a = 2 * .pi * StyleHash.unit(i, 11 &+ respawnCount)
        let r = R * (1.45 + 1.7 * StyleHash.unit(i, 12 &+ respawnCount))
        let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        let (gm, _) = gravityAtRest()
        let vc = (gm / max(1, r)).squareRoot() * (0.85 + 0.2 * StyleHash.unit(i, 13 &+ respawnCount))
        let dir: CGFloat = StyleHash.unit(i, 14) > 0.12 ? 1 : -1      // a few retrograde grains
        return Grain(p: p, v: CGPoint(x: -sin(a) * vc * dir, y: cos(a) * vc * dir),
                     size: 2.0 + 3.2 * StyleHash.unit(i, 15), seed: StyleHash.unit(i, 16), heat: 0)
    }

    private func gravityAtRest() -> (CGFloat, CGFloat) {
        let R = params.bodyRadius
        return (params.orbitSpeed * params.orbitSpeed * 2 * R, 0)
    }

    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt
        let pinShift = CGPoint(x: newPin.x - pin.x, y: newPin.y - pin.y)
        pin = newPin
        head = newHead
        _ = pinShift
        let chord = hypot(head.x - pin.x, head.y - pin.y)

        // Mass flows between the bodies with a little lag (conserved by DumbbellMass).
        let target = DumbbellMass.solve(params.dumbbell, length: chord)
        var f = flow ?? target
        let k = CGFloat(1 - exp(-Double(dt) / 0.05))
        f = .init(pin: f.pin + (target.pin - f.pin) * k, head: f.head + (target.head - f.head) * k, waist: target.waist)
        flow = f
        let radiusScale = params.bodyRadius / params.dumbbell.restRadius
        sol = .init(pin: f.pin * radiusScale, head: f.head * radiusScale, waist: f.waist)
        let (gmPin, gmHead) = gravity()

        let collapse: CGFloat = releaseT >= 0 ? max(0, 1 - releaseT / 0.5) : 1
        let steps = max(1, Int((dt / 0.004).rounded(.up)))
        let h = dt / CGFloat(steps)
        let soft: CGFloat = 12
        let pr = pinRadius * 0.9, hr = headRadius * 0.9
        for i in grains.indices {
            var g = grains[i]
            for _ in 0..<steps {
                var ax: CGFloat = 0, ay: CGFloat = 0
                let dxp = pin.x - g.p.x, dyp = pin.y - g.p.y
                let rp2 = dxp * dxp + dyp * dyp + soft * soft
                let ip = gmPin * collapse / (rp2 * rp2.squareRoot())
                ax += dxp * ip; ay += dyp * ip
                let dxh = head.x - g.p.x, dyh = head.y - g.p.y
                let rh2 = dxh * dxh + dyh * dyh + soft * soft
                let ih = gmHead * collapse / (rh2 * rh2.squareRoot())
                ax += dxh * ih; ay += dyh * ih
                g.v.x += ax * h; g.v.y += ay * h
                let drag = CGFloat(exp(Double(-0.45 * h)))      // a whisper of drag so orbits tidy over time
                g.v.x *= drag; g.v.y *= drag
                g.p.x += g.v.x * h; g.p.y += g.v.y * h
            }
            let dp = hypot(g.p.x - pin.x, g.p.y - pin.y)
            let dh = hypot(g.p.x - head.x, g.p.y - head.y)
            g.heat = max(0, g.heat - dt * 1.4)
            if dh < 3 * hr { g.heat = max(g.heat, 1 - dh / (3 * hr)) }
            let far = chord * 1.12 + params.bodyRadius * 3.2
            if dp < pr || dh < hr || dp > far {
                // Accreted by a body (or flung away): the matter returns to orbit the heavy one.
                respawnCount &+= 1
                g = spawn(index: i &+ respawnCount, around: pin)
                g.p.x += (pin.x - g.p.x) * 0.0
            }
            grains[i] = g
        }
        if releaseT >= 0 { releaseT += dt }
    }

    public mutating func release(commit direction: CGPoint?) {
        releaseT = 0
        if let d = direction {
            releaseDir = d
            for i in grains.indices {
                let kick = 200 + 380 * StyleHash.unit(i, 21)
                grains[i].v.x += d.x * kick; grains[i].v.y += d.y * kick
            }
        }
    }

    public func primitives(emerge: CGFloat, headGlow: CGFloat = 0) -> [ShapePrim] {
        let e = max(0, min(1.15, emerge))
        guard e > 0.01 else { return [] }
        let fade = releaseT >= 0 ? max(0, 1 - releaseT / 0.5) : 1
        var out: [ShapePrim] = []
        let breathe = 1 + 0.012 * CGFloat(sin(Double(time * 1.4)))
        out.append(ShapePrim(kind: .circle, a: pin, ra: pinRadius * e * breathe * (0.35 + 0.65 * fade), blend: .soft))
        out.append(ShapePrim(kind: .circle, a: head, ra: headRadius * e * (1 + 0.12 * headGlow) * (0.35 + 0.65 * fade),
                             blend: .soft, emphasis: headGlow))
        for g in grains {
            let r = g.size * e * fade * (1 + 0.5 * g.heat)
            if r > 0.6 { out.append(ShapePrim(kind: .circle, a: g.p, ra: r, blend: .tight, emphasis: g.heat)) }
        }
        return out
    }
}
