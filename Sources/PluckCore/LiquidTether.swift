import CoreGraphics
import Foundation

/// One shape in the liquid: a round capsule from `a` to `b` (a circle when a == b).
public struct BlobPrimitive: Equatable, Sendable {
    public var a: CGPoint
    public var b: CGPoint
    public var ra: CGFloat
    public var rb: CGFloat
    /// 0...1 accent emission (a captured lobe, the head when something is captured).
    public var glow: CGFloat
    /// True for the continuous tail→head chain (hard union); false for lobes and droplets (soft union).
    public var isBody: Bool

    public init(a: CGPoint, b: CGPoint, ra: CGFloat, rb: CGFloat, glow: CGFloat = 0, isBody: Bool = false) {
        self.a = a; self.b = b; self.ra = ra; self.rb = rb; self.glow = glow; self.isBody = isBody
    }
}

/// Where a role's label belongs.
public struct LobeAnchor: Equatable, Sendable {
    public var role: CompassRole
    public var center: CGPoint
    public var radius: CGFloat
    /// 0...1 how present the lobe is (bloom).
    public var presence: CGFloat
    /// 0...1 captured emphasis.
    public var glow: CGFloat
}

public struct LiquidTetherParams: Equatable, Sendable {
    public var mass: BlobMassParams
    /// Head spring natural frequency (rad/s). Higher = tighter to the pointer.
    public var headFrequency: CGFloat
    /// Head spring damping ratio. Below ~0.8 it overshoots a little (liquid weight).
    public var headDamping: CGFloat
    /// Neck chase spring frequency (rad/s). Lower = lazier, whippier middle.
    public var neckFrequency: CGFloat
    public var neckDamping: CGFloat
    /// 0...1.5 surface slosh amount.
    public var slosh: CGFloat
    public var particleCount: Int
    public var lobeDistance: CGFloat
    /// Lobe radius as a fraction of rest radius.
    public var lobeRadiusFraction: CGFloat
    /// No overshoot, no droplet, no ripples; same angles and dead zone.
    public var reduceMotion: Bool

    public init(
        mass: BlobMassParams = BlobMassParams(restRadius: 36),
        headFrequency: CGFloat = 62,
        headDamping: CGFloat = 0.78,
        neckFrequency: CGFloat = 34,
        neckDamping: CGFloat = 0.6,
        slosh: CGFloat = 0.7,
        particleCount: Int = 18,
        lobeDistance: CGFloat = GestureMath.lobeDistance,
        lobeRadiusFraction: CGFloat = 0.34,
        reduceMotion: Bool = false
    ) {
        self.mass = mass
        self.headFrequency = headFrequency
        self.headDamping = headDamping
        self.neckFrequency = neckFrequency
        self.neckDamping = neckDamping
        self.slosh = slosh
        self.particleCount = particleCount
        self.lobeDistance = lobeDistance
        self.lobeRadiusFraction = lobeRadiusFraction
        self.reduceMotion = reduceMotion
    }
}

struct Spring1 {
    var x: CGFloat
    var v: CGFloat = 0

    mutating func step(to target: CGFloat, omega: CGFloat, zeta: CGFloat, h: CGFloat) {
        let a = omega * omega * (target - x) - 2 * zeta * omega * v
        v += a * h
        x += v * h
    }
}

/// The liquid: a pinned tail, a spring-driven head, a chase-spring neck, role lobes, and a commit droplet.
///
/// Pure value-type simulation with a fixed 240 Hz substep, so it behaves identically at 60/90/120 Hz and
/// can be unit-tested and replayed from pointer traces. y-up AppKit screen space.
public struct LiquidTether: Sendable {
    public enum Phase: Equatable, Sendable { case idle, tracking, releasing }

    public var params: LiquidTetherParams
    public private(set) var phase: Phase = .idle
    public private(set) var pin: CGPoint = .zero

    private(set) var head: CGPoint = .zero
    private var headVel: CGPoint = .zero
    private var target: CGPoint = .zero
    private var spine: [CGPoint] = []
    private var spineVel: [CGPoint] = []
    private var slosh: [CGFloat] = []
    private var sloshVel: [CGFloat] = []
    private var radii: [CGFloat] = []
    private var emerge = Spring1(x: 0)
    private var emergeTarget: CGFloat = 0
    private var lobes: [Lobe] = []
    private var bloomOn = false
    private var captured: CompassRole?
    private var capturedGlow = Spring1(x: 0)
    private var droplet: Droplet?
    private var committed = false
    private var chosen: CompassRole?
    private var accumulator: CGFloat = 0
    private var time: CGFloat = 0
    private var releaseTime: CGFloat = 0
    private var headAccFrame: CGPoint = .zero
    private var headAccSamples: CGFloat = 0
    private var headAccSmooth: CGPoint = .zero

    private struct Lobe: Sendable {
        var role: CompassRole
        var x: Spring1
        var y: Spring1
        var r: Spring1
        var glow: Spring1
    }

    private struct Droplet: Sendable {
        var p: CGPoint
        var v: CGPoint
        var r: CGFloat
    }

    public static let substep: CGFloat = 1.0 / 240.0

    public init(params: LiquidTetherParams = LiquidTetherParams()) {
        self.params = params
    }

    // MARK: Lifecycle

    public mutating func begin(pin: CGPoint, roles: [CompassRole]) {
        self.pin = pin
        head = pin
        headVel = .zero
        target = pin
        phase = .tracking
        emerge = Spring1(x: params.reduceMotion ? 1 : 0)
        emergeTarget = 1
        bloomOn = false
        captured = nil
        capturedGlow = Spring1(x: 0)
        droplet = nil
        committed = false
        chosen = nil
        accumulator = 0
        time = 0
        releaseTime = 0
        headAccSmooth = .zero
        resetSpine()
        lobes = roles.map { Lobe(role: $0, x: Spring1(x: pin.x), y: Spring1(x: pin.y), r: Spring1(x: 0), glow: Spring1(x: 0)) }
        refreshRadii()
    }

    /// Drawn head target (already gain-mapped by `GestureMath.virtualHead`).
    public mutating func setTarget(_ p: CGPoint) {
        guard phase == .tracking else { return }
        target = p
    }

    public mutating func setBloom(_ on: Bool) {
        guard phase == .tracking else { return }
        bloomOn = on
    }

    public mutating func setCaptured(_ role: CompassRole?) {
        captured = role
    }

    /// Roles may arrive late (async context). Existing lobes keep their state.
    public mutating func setRoles(_ roles: [CompassRole]) {
        lobes.removeAll { !roles.contains($0.role) }
        for role in roles where !lobes.contains(where: { $0.role == role }) {
            lobes.append(Lobe(role: role, x: Spring1(x: pin.x), y: Spring1(x: pin.y), r: Spring1(x: 0), glow: Spring1(x: 0)))
        }
    }

    /// Release. `commit` is the unit direction of the chosen role (droplet is sent that way), or nil to cancel.
    public mutating func release(commit direction: CGPoint?, role: CompassRole?) {
        guard phase == .tracking else { return }
        phase = .releasing
        releaseTime = 0
        bloomOn = false
        emergeTarget = 0
        if let dir = direction, role != nil, !params.reduceMotion {
            committed = true
            chosen = role
            let speed: CGFloat = 520 + hypot(headVel.x, headVel.y) * 0.25
            let r = max(6, (radii.last ?? 12) * 0.95)
            droplet = Droplet(
                p: head,
                v: CGPoint(x: dir.x * speed + headVel.x * 0.15, y: dir.y * speed + headVel.y * 0.15),
                r: r
            )
        } else {
            committed = false
            chosen = nil
        }
    }

    public var isFinished: Bool {
        phase == .releasing && emerge.x < 0.004 && droplet == nil && lobes.allSatisfy { $0.r.x <= 0.4 }
    }

    public var headVelocity: CGPoint { headVel }
    public var headPosition: CGPoint { head }
    public var emergence: CGFloat { max(0, min(1.2, emerge.x)) }
    /// Smoothed head acceleration (pt/s²), for lighting.
    public var headAcceleration: CGPoint { headAccSmooth }

    // MARK: Stepping

    public mutating func advance(dt: CGFloat) {
        guard phase != .idle else { return }
        accumulator += min(max(0, dt), 0.05)
        let h = Self.substep
        var steps = 0
        headAccFrame = .zero
        headAccSamples = 0
        while accumulator >= h && steps < 24 {
            step(h)
            accumulator -= h
            steps += 1
        }
        if steps == 24 { accumulator = 0 }
        if headAccSamples > 0 {
            let avg = CGPoint(x: headAccFrame.x / headAccSamples, y: headAccFrame.y / headAccSamples)
            headAccSmooth = CGPoint(
                x: headAccSmooth.x + (avg.x - headAccSmooth.x) * 0.35,
                y: headAccSmooth.y + (avg.y - headAccSmooth.y) * 0.35
            )
        }
        refreshRadii()
    }

    private mutating func resetSpine() {
        let n = max(6, min(28, params.particleCount))
        spine = (0..<n).map { i in
            let t = CGFloat(i) / CGFloat(n - 1)
            return CGPoint(x: pin.x + (head.x - pin.x) * t, y: pin.y + (head.y - pin.y) * t)
        }
        spineVel = Array(repeating: .zero, count: n)
        slosh = Array(repeating: 0, count: n)
        sloshVel = Array(repeating: 0, count: n)
        radii = Array(repeating: 0, count: n)
    }

    private mutating func step(_ h: CGFloat) {
        time += h
        let reduce = params.reduceMotion
        let n = max(6, min(28, params.particleCount))
        if spine.count != n { resetSpine() }

        // Emergence (pops slightly past 1 when tracking).
        if reduce {
            emerge.x = emergeTarget; emerge.v = 0
        } else if phase == .tracking {
            emerge.step(to: emergeTarget, omega: 46, zeta: 0.58, h: h)
        } else {
            releaseTime += h
            emerge.step(to: emergeTarget, omega: committed ? 24 : 17, zeta: 1.0, h: h)
        }

        // Head.
        let headTarget = phase == .tracking ? target : pin
        if reduce {
            head = headTarget
            headVel = .zero
        } else {
            let omega: CGFloat
            let zeta: CGFloat
            switch phase {
            case .tracking: omega = params.headFrequency; zeta = params.headDamping
            default: omega = committed ? 55 : 34; zeta = committed ? 0.7 : 0.38
            }
            let ax = omega * omega * (headTarget.x - head.x) - 2 * zeta * omega * headVel.x
            let ay = omega * omega * (headTarget.y - head.y) - 2 * zeta * omega * headVel.y
            headVel.x += ax * h
            headVel.y += ay * h
            head.x += headVel.x * h
            head.y += headVel.y * h
            headAccFrame.x += ax
            headAccFrame.y += ay
            headAccSamples += 1
        }

        // Neck: every interior particle chases its point on the pin→head line.
        spine[0] = pin
        spine[n - 1] = head
        for i in 1..<(n - 1) {
            let t = CGFloat(i) / CGFloat(n - 1)
            let tx = pin.x + (head.x - pin.x) * t
            let ty = pin.y + (head.y - pin.y) * t
            if reduce {
                spine[i] = CGPoint(x: tx, y: ty)
                spineVel[i] = .zero
                continue
            }
            let omega = params.neckFrequency * (1 - 0.4 * CGFloat(sin(Double(.pi * t))))
            let zeta = params.neckDamping
            var p = spine[i]
            var v = spineVel[i]
            let ax = omega * omega * (tx - p.x) - 2 * zeta * omega * v.x
            let ay = omega * omega * (ty - p.y) - 2 * zeta * omega * v.y
            v.x += ax * h; v.y += ay * h
            p.x += v.x * h; p.y += v.y * h
            spine[i] = p
            spineVel[i] = v
        }

        // Surface slosh: driven by head acceleration, rings briefly.
        if !reduce {
            let accX = headAccSamples > 0 ? headAccFrame.x / headAccSamples : 0
            let accY = headAccSamples > 0 ? headAccFrame.y / headAccSamples : 0
            let dx = head.x - pin.x, dy = head.y - pin.y
            let len = max(1, hypot(dx, dy))
            let tanA = (accX * dx + accY * dy) / len
            let latA = (-accX * dy + accY * dx) / len
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n - 1)
                let mid = CGFloat(sin(Double(.pi * t)))
                var drive = (-tanA * (t - 0.35) * 0.0016 + latA * mid * 0.0012) * params.slosh
                drive = max(-7, min(7, drive)) * params.mass.restRadius / 40
                let omega: CGFloat = 15, zeta: CGFloat = 0.2
                let a = omega * omega * (drive - slosh[i]) - 2 * zeta * omega * sloshVel[i]
                sloshVel[i] += a * h
                slosh[i] += sloshVel[i] * h
            }
        }

        stepLobes(h, reduce: reduce)
        stepDroplet(h)
    }

    private mutating func stepLobes(_ h: CGFloat, reduce: Bool) {
        let baseR = params.mass.restRadius * params.lobeRadiusFraction
        capturedGlow.step(to: (captured != nil && phase == .tracking) || committed ? 1 : 0, omega: 30, zeta: 1, h: h)
        let holdChosen = committed && releaseTime < 0.11
        for i in lobes.indices {
            let role = lobes[i].role
            let u = role.unit
            let base = CGPoint(x: pin.x + u.x * params.lobeDistance, y: pin.y + u.y * params.lobeDistance)
            let isCaptured = role == captured && phase == .tracking
            let isChosen = role == chosen && holdChosen
            let show = (bloomOn || isChosen) && emerge.x > 0.05

            var tx = pin.x, ty = pin.y, tr: CGFloat = 0, tg: CGFloat = 0
            if show {
                tx = base.x; ty = base.y
                tr = baseR
                if isCaptured {
                    // Magnet: the lobe leans toward the head as you approach it, and fuses into the head
                    // once you pull past it. No stray bead hanging off the neck.
                    let headDist = hypot(head.x - pin.x, head.y - pin.y)
                    let raw = max(0, min(1, (headDist - 0.35 * params.lobeDistance) / (0.65 * params.lobeDistance)))
                    let pull = raw * raw * (3 - 2 * raw)
                    tx = base.x + (head.x - base.x) * pull
                    ty = base.y + (head.y - base.y) * pull
                    tr = baseR * (1.0 + 0.28 * (1 - pull) + 0.1 * pull)
                    tg = 1
                } else if captured != nil, phase == .tracking {
                    tr = baseR * 0.78
                }
                if isChosen { tr = baseR * 1.45; tg = 1 }
            }
            if reduce {
                lobes[i].x.x = tx; lobes[i].y.x = ty; lobes[i].r.x = tr; lobes[i].glow.x = tg
                lobes[i].x.v = 0; lobes[i].y.v = 0; lobes[i].r.v = 0
            } else {
                lobes[i].x.step(to: tx, omega: 34, zeta: 0.55, h: h)
                lobes[i].y.step(to: ty, omega: 34, zeta: 0.55, h: h)
                lobes[i].r.step(to: tr, omega: 40, zeta: 0.5, h: h)
                lobes[i].glow.step(to: tg, omega: 26, zeta: 1, h: h)
            }
            lobes[i].r.x = max(0, lobes[i].r.x)
        }
    }

    private mutating func stepDroplet(_ h: CGFloat) {
        guard var d = droplet else { return }
        d.p.x += d.v.x * h
        d.p.y += d.v.y * h
        let drag = CGFloat(exp(Double(-2.6 * h)))
        d.v.x *= drag; d.v.y *= drag
        d.r *= CGFloat(exp(Double(-5.2 * h)))
        droplet = d.r < 0.7 ? nil : d
    }

    // MARK: Shape

    private mutating func refreshRadii() {
        let n = spine.count
        guard n >= 2 else { return }
        let e = max(0, min(1.12, emerge.x))
        if e < 0.004 {
            radii = Array(repeating: 0, count: n)
            return
        }

        var len: CGFloat = 0
        for i in 0..<(n - 1) {
            len += hypot(spine[i + 1].x - spine[i].x, spine[i + 1].y - spine[i].y)
        }

        var p = params.mass
        p.restRadius *= e
        p.minRadius *= e
        var base = BlobMass.radiusProfile(length: len, samples: n, params: p)

        let calm = params.reduceMotion ? 0 : max(0, 1 - hypot(headVel.x, headVel.y) / 240)
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            var r = base[i] + slosh[i] * e
            r *= 1 + 0.02 * calm * CGFloat(sin(Double(time * 5.2 + t * 3.1)))
            base[i] = max(p.minRadius * 0.7, r)
        }

        var out = BlobMass.rescaleToTotalArea(radii: base, length: max(len, 1), params: p)
        BlobMass.applyEndFloors(radii: &out, emerge: e, params: p)
        radii = out
    }

    /// Everything to draw, in draw order. The renderer smooth-unions these into one liquid.
    public func primitives() -> [BlobPrimitive] {
        var out: [BlobPrimitive] = []
        let n = spine.count
        if n >= 2, radii.count == n, emerge.x > 0.004 {
            let g = max(0, min(1, capturedGlow.x))
            for i in 0..<(n - 1) {
                let t = CGFloat(i + 1) / CGFloat(n - 1)
                out.append(BlobPrimitive(a: spine[i], b: spine[i + 1], ra: radii[i], rb: radii[i + 1], glow: g * t * t, isBody: true))
            }
        }
        for l in lobes where l.r.x > 0.4 {
            let c = CGPoint(x: l.x.x, y: l.y.x)
            out.append(BlobPrimitive(a: c, b: c, ra: l.r.x, rb: l.r.x, glow: max(0, min(1, l.glow.x))))
        }
        if let d = droplet {
            out.append(BlobPrimitive(a: d.p, b: d.p, ra: d.r, rb: d.r, glow: 0.6))
        }
        return out
    }

    public func lobeAnchors() -> [LobeAnchor] {
        let baseR = max(1, params.mass.restRadius * params.lobeRadiusFraction)
        return lobes.map { l in
            LobeAnchor(
                role: l.role,
                center: CGPoint(x: l.x.x, y: l.y.x),
                radius: l.r.x,
                presence: max(0, min(1, l.r.x / baseR)),
                glow: max(0, min(1, l.glow.x))
            )
        }
    }

    /// Conservative bounds of everything drawn, for sizing the render target.
    public func drawnBounds() -> CGRect? {
        let prims = primitives()
        guard var r = prims.first.map({ Self.bounds(of: $0) }) else { return nil }
        for p in prims.dropFirst() { r = r.union(Self.bounds(of: p)) }
        return r
    }

    private static func bounds(of p: BlobPrimitive) -> CGRect {
        let minX = min(p.a.x - p.ra, p.b.x - p.rb)
        let maxX = max(p.a.x + p.ra, p.b.x + p.rb)
        let minY = min(p.a.y - p.ra, p.b.y - p.rb)
        let maxY = max(p.a.y + p.ra, p.b.y + p.rb)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
