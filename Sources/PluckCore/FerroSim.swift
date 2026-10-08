import CoreGraphics
import Foundation

/// Ferrofluid under a magnet. The magnet is the cursor (the head): the dark fluid at the pin bristles into a fan of
/// conical spikes aimed at it (the Rosensweig instability), the fan swings around with some lag and overshoot as the
/// magnet moves, and a swarm of iron-filing beads strings out along curved field lines between the two. A smaller
/// fluid mass at the head bristles back toward the pin. All of it is deliberately rigid and crisp, unlike the
/// liquid style's softness.
public struct FerroSim: Sendable {
    public struct Params: Equatable, Sendable {
        /// Radius of the fluid mass at the pin (points).
        public var bodyRadius: CGFloat = 30
        /// Spikes either side of the centre one (so 2K+1 in the fan).
        public var spikesEachSide: Int = 5
        /// Spike length at full field, as a multiple of the body radius.
        public var spikeLength: CGFloat = 1.55
        /// Total fan angle (radians).
        public var spread: CGFloat = 2.3
        /// Iron-filing beads strung along the field.
        public var beads: Int = 22
        public init() {}
    }

    private struct Bead {
        var p: CGPoint
        var v: CGPoint
        var s: CGFloat       // position along the field, 0 (pin) ... 1 (head)
        var lane: CGFloat    // which field line (-1...1)
        var size: CGFloat
        var omega: CGFloat
    }

    public var params: Params
    private var pin: CGPoint = .zero
    private var head: CGPoint = .zero
    private var fan: CGFloat = 0, fanV: CGFloat = 0
    private var headFan: CGFloat = .pi, headFanV: CGFloat = 0
    private var field: CGFloat = 0
    private var shock: CGFloat = 0
    private var time: CGFloat = 0
    private var beads: [Bead] = []
    private var releaseT: CGFloat = -1
    private var releaseDir = CGPoint(x: 1, y: 0)

    public init(params: Params = Params()) { self.params = params }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin
        head = pin
        fan = 0; fanV = 0; headFan = .pi; headFanV = 0
        field = 0; shock = 0; time = 0; releaseT = -1
        beads = (0..<max(0, params.beads)).map { i in
            Bead(p: pin, v: .zero,
                 s: (CGFloat(i) + 0.5) / CGFloat(params.beads),
                 lane: ((CGFloat((i * 5) % 7) - 3) / 3),
                 size: 1.8 + 2.7 * StyleHash.unit(i, 1),
                 omega: 12 + 12 * StyleHash.unit(i, 2))
        }
    }

    /// Field strength 0...1 (how hard the fluid is bristling).
    public var fieldStrength: CGFloat { field }
    public var headPosition: CGPoint { head }
    public var headRadius: CGFloat { params.bodyRadius * 0.62 }

    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt
        let prevHead = head
        pin = newPin
        head = newHead
        let dx = head.x - pin.x, dy = head.y - pin.y
        let chord = hypot(dx, dy)
        let R = params.bodyRadius

        // Speed of the magnet excites the fluid: it bristles harder while you move.
        let speed = hypot(head.x - prevHead.x, head.y - prevHead.y) / dt
        shock = min(1.2, shock + min(0.5, speed / 4000)) * CGFloat(exp(Double(-3.5 * dt)))

        // Field strength follows how far the magnet is, with a little smoothing.
        let targetField = StyleHash.smoothstep(0.5 * R, 3.0 * R, chord)
        field += (targetField - field) * (1 - CGFloat(exp(Double(-9 * dt))))

        if chord > 4 {
            let bearing = atan2(dy, dx)
            Self.angularSpring(&fan, &fanV, target: bearing, omega: 11, zeta: 0.42, dt: dt)
            Self.angularSpring(&headFan, &headFanV, target: bearing + .pi, omega: 13, zeta: 0.45, dt: dt)
        }

        // Filings: each bead is pulled to its place on a curved field line (a bowed arc, different per lane).
        let n = chord > 1 ? CGPoint(x: -dy / chord, y: dx / chord) : .zero
        for i in beads.indices {
            let s = beads[i].s
            let bow = chord * 0.11 * CGFloat(sin(Double(.pi * s))) * (0.65 + 0.35 * CGFloat(sin(Double(time * 0.8 + CGFloat(i)))))
            let target = CGPoint(
                x: pin.x + dx * s + n.x * beads[i].lane * bow,
                y: pin.y + dy * s + n.y * beads[i].lane * bow
            )
            let w = beads[i].omega
            let ax = w * w * (target.x - beads[i].p.x) - 2 * 0.55 * w * beads[i].v.x
            let ay = w * w * (target.y - beads[i].p.y) - 2 * 0.55 * w * beads[i].v.y
            beads[i].v.x += ax * dt; beads[i].v.y += ay * dt
            beads[i].p.x += beads[i].v.x * dt; beads[i].p.y += beads[i].v.y * dt
        }

        if releaseT >= 0 { releaseT += dt }
    }

    /// Commit: the filings are flung along `direction` and the spikes collapse.
    public mutating func release(commit direction: CGPoint?) {
        releaseT = 0
        if let d = direction {
            releaseDir = d
            for i in beads.indices {
                let kick = 260 + 380 * StyleHash.unit(i, 3)
                beads[i].v.x += d.x * kick + (StyleHash.unit(i, 4) - 0.5) * 120
                beads[i].v.y += d.y * kick + (StyleHash.unit(i, 5) - 0.5) * 120
            }
        }
    }

    public var isFinished: Bool { releaseT > 0.55 }

    private static func angularSpring(_ x: inout CGFloat, _ v: inout CGFloat, target: CGFloat, omega: CGFloat, zeta: CGFloat, dt: CGFloat) {
        var diff = target - x
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        // sub-step for stability at coarse frame times
        let steps = max(1, Int((dt / 0.004).rounded(.up)))
        let h = dt / CGFloat(steps)
        var d = diff
        for _ in 0..<steps {
            let a = omega * omega * d - 2 * zeta * omega * v
            v += a * h
            x += v * h
            d = target - x
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
        }
    }

    /// Everything to draw. `emerge` scales the whole thing in and out; `headGlow` lights the head when armed.
    public func primitives(emerge: CGFloat, headGlow: CGFloat = 0) -> [ShapePrim] {
        let e = max(0, min(1.15, emerge))
        guard e > 0.01 else { return [] }
        let R = params.bodyRadius
        let dx = head.x - pin.x, dy = head.y - pin.y
        let chord = hypot(dx, dy)
        let dir = chord > 1 ? CGPoint(x: dx / chord, y: dy / chord) : CGPoint(x: cos(fan), y: sin(fan))
        let collapse = releaseT >= 0 ? max(0, 1 - releaseT / 0.28) : 1       // spikes fall away on release
        let F = field * collapse
        let boost = 1 + 0.55 * shock

        var out: [ShapePrim] = []
        // The fluid leans toward the magnet.
        let lean = min(R * 0.5, chord * 0.07) * F
        let pinCenter = CGPoint(x: pin.x + dir.x * lean, y: pin.y + dir.y * lean)
        let breathe = 1 + 0.015 * CGFloat(sin(Double(time * 1.6)))
        out.append(ShapePrim(kind: .circle, a: pinCenter, ra: R * e * breathe, blend: .soft))

        func fanSpikes(center: CGPoint, angle: CGFloat, velocity: CGFloat, radius: CGFloat, each: Int, lengthScale: CGFloat, salt: Int) {
            let K = max(1, each)
            let spacing = params.spread / CGFloat(2 * K)
            for k in -K...K {
                let kk = CGFloat(k)
                let fall = max(0, 1 - pow(abs(kk) / CGFloat(K + 1), 2))
                let jitter = 0.8 + 0.2 * StyleHash.unit(k + 20, salt)
                let amp = F * params.spikeLength * lengthScale * fall * jitter * boost
                if amp * radius < 2.0 { continue }
                let tremble = 0.018 * CGFloat(sin(Double(time * 7 + kk * 1.7))) * F
                // The fan flares while it swings (outer spikes trail).
                let theta = angle + kk * spacing * (1 + min(0.5, abs(velocity) * 0.03)) + tremble
                let d = CGPoint(x: cos(theta), y: sin(theta))
                let base = CGPoint(x: center.x + d.x * radius * 0.45, y: center.y + d.y * radius * 0.45)
                let tipDist = radius * (1 + amp) * e
                let tip = CGPoint(x: center.x + d.x * tipDist, y: center.y + d.y * tipDist)
                let baseR = radius * 0.30 * (1 - 0.35 * abs(kk) / CGFloat(K + 1)) * e
                out.append(ShapePrim(kind: .cone, a: base, b: tip, ra: baseR, rb: 0.9, blend: .soft, emphasis: 0))
            }
        }
        fanSpikes(center: pinCenter, angle: fan, velocity: fanV, radius: R, each: params.spikesEachSide, lengthScale: 1, salt: 1)

        // The magnet end: a smaller mass that bristles back toward the pin.
        let hr = headRadius
        out.append(ShapePrim(kind: .circle, a: head, ra: hr * e * (1 + 0.1 * headGlow), blend: .soft, emphasis: headGlow))
        fanSpikes(center: head, angle: headFan, velocity: headFanV, radius: hr, each: max(1, params.spikesEachSide - 2), lengthScale: 0.85, salt: 2)

        // Iron filings along the field lines (only once the magnet is well away).
        let engage = StyleHash.smoothstep(2.2 * R, 4.4 * R, chord) * (releaseT >= 0 ? max(0, 1 - releaseT / 0.5) : 1)
        if engage > 0.02 {
            for b in beads {
                let r = b.size * engage * e
                if r > 0.7 { out.append(ShapePrim(kind: .circle, a: b.p, ra: r, blend: .tight)) }
            }
        }
        return out
    }
}
