import CoreGraphics
import Foundation

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// Shared mass flow: the pin and head sizes from `DumbbellMass`, eased so mass visibly drains and refills.
struct MassFlow: Sendable {
    var flow: DumbbellMass.Solution?
    var sol = DumbbellMass.Solution(pin: 1, head: 1, waist: 1)
    mutating func update(chord: CGFloat, dt: CGFloat, params: DumbbellMass.Params, bodyRadius: CGFloat) {
        let target = DumbbellMass.solve(params, length: chord)
        var f = flow ?? target
        let k = CGFloat(1 - exp(-Double(dt) / 0.05))
        f = .init(pin: f.pin + (target.pin - f.pin) * k, head: f.head + (target.head - f.head) * k, waist: target.waist)
        flow = f
        let rs = bodyRadius / params.restRadius
        sol = .init(pin: f.pin * rs, head: f.head * rs, waist: f.waist)
    }
}

// MARK: - Stars

public struct StarState: Equatable, Sendable {
    public var position: CGPoint
    public var size: CGFloat          // outer radius
    public var twinkle: CGFloat       // 0...1
    public var rotation: CGFloat
    public var tint: Int              // 0 gold, 1 white, 2 lavender, 3 pink
    public var alpha: CGFloat
}

public struct ShootingStar: Equatable, Sendable {
    public var head: CGPoint
    public var tail: CGPoint
    public var alpha: CGFloat
}

public struct StarScene: Equatable, Sendable {
    public var pin: StarState
    public var headStar: StarState
    public var stars: [StarState]
    public var lines: [(CGPoint, CGPoint, CGFloat)]
    public var dust: [(CGPoint, CGFloat)]
    public var shooting: [ShootingStar]
    public var alpha: CGFloat

    public static func == (a: StarScene, b: StarScene) -> Bool {
        a.pin == b.pin && a.headStar == b.headStar && a.stars == b.stars && a.shooting == b.shooting && a.alpha == b.alpha
    }
}

/// Stars: the pin is a bright guiding star and the head a smaller one; between them a constellation of twinkling
/// stars appears and draws itself with faint lines. Commit: a shooting star streaks along the pull and the
/// constellation scatters into dust.
public struct StarSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 30
        public var stars: Int = 11
        public var dust: Int = 36
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    public var params: Params
    private var mass = MassFlow()
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    private var releaseDir = CGPoint(x: 1, y: 0)
    private var drift: [CGPoint] = []
    private var driftV: [CGPoint] = []
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.9 }
    public var pinSize: CGFloat { mass.sol.pin }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; mass = MassFlow()
        mass.sol = DumbbellMass.solve(params.dumbbell, length: 0)
        drift = Array(repeating: .zero, count: params.stars)
        driftV = Array(repeating: .zero, count: params.stars)
    }

    private func axes() -> (along: CGPoint, nrm: CGPoint, chord: CGFloat) {
        let dx = head.x - pin.x, dy = head.y - pin.y
        let c = hypot(dx, dy)
        let a = c > 1 ? CGPoint(x: dx / c, y: dy / c) : CGPoint(x: 1, y: 0)
        return (a, CGPoint(x: -a.y, y: a.x), c)
    }

    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt; pin = newPin; head = newHead
        mass.update(chord: axes().chord, dt: dt, params: params.dumbbell, bodyRadius: params.bodyRadius)
        // Stars drift lazily in the sky (a soft spring to a slowly moving home).
        for i in drift.indices {
            let hx = 9 * CGFloat(sin(Double(time * 0.5 + CGFloat(i) * 1.9))), hy = 9 * CGFloat(cos(Double(time * 0.43 + CGFloat(i) * 2.3)))
            driftV[i].x += ((hx - drift[i].x) * 6 - driftV[i].x * 2.2) * dt
            driftV[i].y += ((hy - drift[i].y) * 6 - driftV[i].y * 2.2) * dt
            drift[i].x += driftV[i].x * dt; drift[i].y += driftV[i].y * dt
        }
        if releaseT >= 0 { releaseT += dt }
    }

    public mutating func release(commit direction: CGPoint?) {
        releaseT = 0
        releaseDir = direction ?? .zero
    }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> StarScene {
        let e = max(0, min(1, emerge))
        let fade = releaseT >= 0 ? max(0, 1 - releaseT / 0.7) : 1
        let ax = axes()
        let reach = StyleHash.smoothstep(30, 200, ax.chord)
        func twinkle(_ i: Int) -> CGFloat {
            let f = 0.5 + 0.5 * CGFloat(sin(Double(time * (1.4 + 1.8 * StyleHash.unit(i, 71)) + 6.28 * StyleHash.unit(i, 72))))
            return f * f
        }
        let rate: CGFloat = releaseT >= 0 ? releaseT : 0
        var stars: [StarState] = []
        let n = params.stars
        for i in 0..<n {
            let s = (CGFloat(i) + 0.5 + 0.4 * (StyleHash.unit(i, 73) - 0.5)) / CGFloat(n)
            let lane = (StyleHash.unit(i, 74) * 2 - 1)
            let band = min(80, 18 + ax.chord * 0.12) * (0.4 + 0.6 * sin(.pi * s))
            // Near the pin they start gathered around it; they spread out along the span as you pull.
            let gather = (1 - reach)
            let sx = pin.x + (head.x - pin.x) * s * reach + ax.nrm.x * lane * band * reach
            let sy = pin.y + (head.y - pin.y) * s * reach + ax.nrm.y * lane * band * reach
            let ang = 6.28 * StyleHash.unit(i, 75) + time * 0.4
            let ring = params.bodyRadius * (1.5 + 1.1 * StyleHash.unit(i, 76))
            var p = CGPoint(x: sx + drift[i].x + cos(ang) * ring * gather, y: sy + drift[i].y + sin(ang) * ring * gather)
            if releaseT >= 0 {
                let a2 = 6.28 * StyleHash.unit(i, 77)
                p.x += (cos(a2) * 120 + releaseDir.x * 200) * rate; p.y += (sin(a2) * 120 + releaseDir.y * 200) * rate
            }
            let size = params.bodyRadius * (0.20 + 0.20 * StyleHash.unit(i, 78)) * (0.5 + 0.5 * sin(.pi * s) + 0.35)
            stars.append(StarState(position: p, size: size, twinkle: twinkle(i), rotation: 0.5 * CGFloat(sin(Double(time * 0.6 + CGFloat(i)))),
                                   tint: [1, 1, 2, 3, 0][i % 5], alpha: e * fade * (0.35 + 0.65 * reach + 0.3 * gather)))
        }
        // Constellation lines: each star to the next along the span, with the two guide stars at the ends.
        let pinStar = StarState(position: pin, size: mass.sol.pin * 0.95, twinkle: 0.6 + 0.4 * twinkle(100), rotation: time * 0.15, tint: 0, alpha: e * (0.4 + 0.6 * fade))
        let headStar = StarState(position: head, size: max(mass.sol.head, 6) * 0.95 * (1 + 0.15 * headGlow), twinkle: 0.5 + 0.5 * twinkle(101) + headGlow,
                                 rotation: -time * 0.2, tint: headGlow > 0.3 ? 3 : 1, alpha: e * (0.4 + 0.6 * fade))
        var lines: [(CGPoint, CGPoint, CGFloat)] = []
        var chain = [pinStar.position] + stars.sorted { dot($0.position, ax.along) < dot($1.position, ax.along) }.map(\.position) + [headStar.position]
        if reach < 0.05 { chain = [] }
        for i in 0..<max(0, chain.count - 1) { lines.append((chain[i], chain[i + 1], e * fade * reach * 0.55)) }
        var dust: [(CGPoint, CGFloat)] = []
        for i in 0..<params.dust {
            let s = StyleHash.unit(i, 80)
            let off = (StyleHash.unit(i, 81) * 2 - 1) * (50 + ax.chord * 0.15)
            let p = CGPoint(x: pin.x + (head.x - pin.x) * s + ax.nrm.x * off, y: pin.y + (head.y - pin.y) * s + ax.nrm.y * off)
            dust.append((p, e * fade * twinkle(200 + i) * reach))
        }
        var shooting: [ShootingStar] = []
        if releaseT >= 0 {
            let t = min(1, releaseT / 0.6)
            let dist: CGFloat = 900
            let h = CGPoint(x: pin.x + releaseDir.x * dist * t, y: pin.y + releaseDir.y * dist * t)
            let tail = CGPoint(x: h.x - releaseDir.x * 220 * min(1, t * 3), y: h.y - releaseDir.y * 220 * min(1, t * 3))
            shooting.append(ShootingStar(head: h, tail: tail, alpha: e * (1 - t * t)))
        }
        return StarScene(pin: pinStar, headStar: headStar, stars: stars, lines: lines, dust: dust, shooting: shooting, alpha: e)
    }

    private func dot(_ p: CGPoint, _ d: CGPoint) -> CGFloat { p.x * d.x + p.y * d.y }
}

// MARK: - Kite

public struct KiteScene: Equatable, Sendable {
    public var string: [CGPoint]
    public var spool: CGPoint
    public var spoolSize: CGFloat
    public var kite: CGPoint
    public var kiteAngle: CGFloat
    public var kiteSize: CGFloat
    public var tail: [CGPoint]
    public var bows: [CGFloat]
    public var alpha: CGFloat
    public var armed: CGFloat
}

/// Kite: the pin is a reel and the head is a kite on a long string, bobbing in the wind with a ribbon tail. The
/// string sags and ripples, the kite tilts into the wind, the tail whips behind it. Commit: the kite is let go and
/// soars away along the pull.
public struct KiteSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 30
        public var tailLinks: Int = 9
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    public var params: Params
    private var mass = MassFlow()
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var time: CGFloat = 0
    private var tailPts: [CGPoint] = []
    private var tailVel: [CGPoint] = []
    private var tilt: CGFloat = 0, tiltV: CGFloat = 0
    private var releaseT: CGFloat = -1
    private var releaseDir = CGPoint(x: 1, y: 0)
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.9 }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; mass = MassFlow()
        mass.sol = DumbbellMass.solve(params.dumbbell, length: 0)
        tailPts = Array(repeating: pin, count: params.tailLinks)
        tailVel = Array(repeating: .zero, count: params.tailLinks)
        tilt = 0; tiltV = 0
    }

    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt
        let prevHead = head
        pin = newPin; head = newHead
        let chord = hypot(head.x - pin.x, head.y - pin.y)
        mass.update(chord: chord, dt: dt, params: params.dumbbell, bodyRadius: params.bodyRadius)
        // The kite leans into the way it is moving, with a springy wobble.
        let vx = (head.x - prevHead.x) / dt
        let target = max(-0.6, min(0.6, -vx * 0.0011)) + 0.12 * CGFloat(sin(Double(time * 1.7)))
        var d = CGPoint(x: tilt - target, y: 0), dv = CGPoint(x: tiltV, y: 0)
        RecoilSpring.step(x: &d, v: &dv, omega: 7, zeta: 0.3, h: dt)
        tilt = target + d.x; tiltV = dv.x
        // The tail: a ribbon chain hanging from the kite's lower tip, blown by a little wind, pulled out behind.
        let kiteSize = max(params.bodyRadius * 1.25, mass.sol.head * 2.2)
        let anchor = tailAnchor(kiteSize: kiteSize)
        let linkLen = kiteSize * 0.8
        let wind = CGPoint(x: 26 * CGFloat(sin(Double(time * 1.3))), y: 8 * CGFloat(cos(Double(time * 0.9))))
        for i in tailPts.indices {
            let prev = i == 0 ? anchor : tailPts[i - 1]
            tailVel[i].x += (wind.x - tailVel[i].x * 3.2) * dt
            tailVel[i].y += (-90 + wind.y - tailVel[i].y * 3.2) * dt
            tailPts[i].x += tailVel[i].x * dt; tailPts[i].y += tailVel[i].y * dt
            let dx = tailPts[i].x - prev.x, dy = tailPts[i].y - prev.y
            let l = max(0.001, hypot(dx, dy))
            tailPts[i] = CGPoint(x: prev.x + dx / l * linkLen, y: prev.y + dy / l * linkLen)
        }
        if releaseT >= 0 { releaseT += dt }
    }

    private func kiteAngle() -> CGFloat {
        let dx = pin.x - head.x, dy = pin.y - head.y
        // The kite's "down" points toward the reel; its tilt adds the wobble.
        return (hypot(dx, dy) > 1 ? atan2(dy, dx) + .pi / 2 : 0) + tilt
    }
    private func tailAnchor(kiteSize: CGFloat) -> CGPoint {
        let a = kiteAngle()
        // Down vector in kite space is (0, -1) rotated by a.
        return CGPoint(x: head.x + sin(a) * kiteSize * 1.02, y: head.y - cos(a) * kiteSize * 1.02)
    }

    public mutating func release(commit direction: CGPoint?) {
        releaseT = 0
        releaseDir = direction ?? .zero
    }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> KiteScene {
        let e = max(0, min(1, emerge))
        let fade = releaseT >= 0 ? max(0, 1 - releaseT / 0.8) : 1
        let chord = hypot(head.x - pin.x, head.y - pin.y)
        let reach = StyleHash.smoothstep(25, 160, chord)
        let kiteSize = max(params.bodyRadius * 1.25, mass.sol.head * 2.2) * (0.35 + 0.65 * reach)
        var kc = head
        if releaseT >= 0 { let t = releaseT; kc.x += releaseDir.x * 520 * t * t * 2; kc.y += releaseDir.y * 520 * t * t * 2 + 160 * t }
        let sag = min(60, chord * 0.1) * reach * (releaseT >= 0 ? 1 + releaseT * 3 : 1)
        var str: [CGPoint] = []
        let L = 24
        for j in 0...L {
            let s = CGFloat(j) / CGFloat(L)
            let wave = CGFloat(sin(Double(s * 9 - time * 3.2))) * 3.2 * sin(.pi * s)
            let nx = chord > 1 ? -(head.y - pin.y) / chord : 0, ny = chord > 1 ? (head.x - pin.x) / chord : 1
            let base = CGPoint(x: pin.x + (kc.x - pin.x) * s, y: pin.y + (kc.y - pin.y) * s - sag * 4 * s * (1 - s))
            str.append(CGPoint(x: base.x + nx * wave, y: base.y + ny * wave))
        }
        let bows = (0..<params.tailLinks).map { i in 1 - CGFloat(i) / CGFloat(params.tailLinks + 2) }
        var tail = tailPts
        if releaseT >= 0 { let dx = kc.x - head.x, dy = kc.y - head.y; tail = tail.map { CGPoint(x: $0.x + dx, y: $0.y + dy) } }
        return KiteScene(string: str, spool: pin, spoolSize: max(10, mass.sol.pin * 1.1), kite: kc, kiteAngle: kiteAngle(),
                         kiteSize: kiteSize, tail: tail, bows: bows, alpha: e * fade, armed: headGlow)
    }
}

// MARK: - Soap bubbles

public struct BubbleState: Equatable, Sendable {
    public var position: CGPoint
    public var radius: CGFloat
    public var wobble: CGFloat       // squash amount
    public var wobbleAngle: CGFloat
    public var alpha: CGFloat
    /// 0 intact ... 1 fully popped (expanding ring and droplets).
    public var pop: CGFloat
    public var hue: CGFloat
}

/// Soap bubbles: the pin and head are big iridescent bubbles, and a stream of smaller ones drifts between them,
/// rising a little, wobbling as they go. Pulled far enough the bubbles trail into a long chain. Commit: they pop.
public struct BubbleSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 32
        public var bubbles: Int = 16
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    private struct B { var p: CGPoint; var v: CGPoint; var s: CGFloat; var lane: CGFloat; var size: CGFloat; var phase: CGFloat }
    public var params: Params
    private var mass = MassFlow()
    private var bubbles: [B] = []
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.7 }
    public var count: Int { bubbles.count }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; mass = MassFlow()
        mass.sol = DumbbellMass.solve(params.dumbbell, length: 0)
        bubbles = (0..<params.bubbles).map { i in
            B(p: pin, v: .zero, s: (CGFloat(i) + 0.5) / CGFloat(params.bubbles), lane: StyleHash.unit(i, 91) * 2 - 1,
              size: 0.35 + 0.65 * StyleHash.unit(i, 92), phase: 6.28 * StyleHash.unit(i, 93))
        }
    }

    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt; pin = newPin; head = newHead
        let dx = head.x - pin.x, dy = head.y - pin.y
        let chord = hypot(dx, dy)
        mass.update(chord: chord, dt: dt, params: params.dumbbell, bodyRadius: params.bodyRadius)
        let a = chord > 1 ? CGPoint(x: dx / chord, y: dy / chord) : CGPoint(x: 1, y: 0)
        let n = CGPoint(x: -a.y, y: a.x)
        let reach = StyleHash.smoothstep(30, 200, chord)
        let hold: CGFloat = releaseT >= 0 ? 0 : 1
        for i in bubbles.indices {
            var b = bubbles[i]
            // Each bubble drifts toward its place in the stream, bobbing, with a gentle updraft.
            let bob = CGFloat(sin(Double(time * 1.1 + b.phase)))
            let lift: CGFloat = 14 * CGFloat(sin(Double(time * 0.6 + b.phase * 2)))
            let band = (22 + chord * 0.07) * b.lane * (0.5 + 0.5 * sin(.pi * b.s))
            let ring = params.bodyRadius * (1.5 + 1.3 * b.size)
            let ang = b.phase + time * (0.4 + 0.3 * b.size)
            let tx = pin.x + dx * b.s * reach + n.x * band * reach + cos(ang) * ring * (1 - reach) + n.x * bob * 8
            let ty = pin.y + dy * b.s * reach + n.y * band * reach + sin(ang) * ring * (1 - reach) + n.y * bob * 8 + lift
            let w: CGFloat = 4.2 + 2 * b.size
            b.v.x += ((tx - b.p.x) * w * w - 2 * 0.7 * w * b.v.x) * dt * hold
            b.v.y += ((ty - b.p.y) * w * w - 2 * 0.7 * w * b.v.y) * dt * hold
            b.p.x += b.v.x * dt; b.p.y += b.v.y * dt
            bubbles[i] = b
        }
        if releaseT >= 0 { releaseT += dt }
    }

    public mutating func release(commit direction: CGPoint?) { releaseT = 0 }

    public func bubbleStates(emerge: CGFloat, headGlow: CGFloat = 0) -> [BubbleState] {
        let e = max(0, min(1, emerge))
        func wob(_ phase: CGFloat, _ speed: CGFloat) -> (CGFloat, CGFloat) {
            (0.07 * CGFloat(sin(Double(time * 3.1 + phase))) + min(0.18, speed * 0.0004), time * 0.8 + phase)
        }
        var out: [BubbleState] = []
        func popOf(_ i: Int) -> CGFloat {
            guard releaseT >= 0 else { return 0 }
            let delay = 0.18 * StyleHash.unit(i, 95)
            return max(0, min(1, (releaseT - delay) / 0.22))
        }
        let (w1, a1) = wob(0.3, 0)
        out.append(BubbleState(position: pin, radius: mass.sol.pin, wobble: w1, wobbleAngle: a1, alpha: e, pop: popOf(900), hue: 0.0))
        let (w2, a2) = wob(1.9, 0)
        out.append(BubbleState(position: head, radius: max(mass.sol.head, 7) * (1 + 0.1 * headGlow), wobble: w2, wobbleAngle: a2, alpha: e,
                               pop: popOf(901), hue: 0.5))
        let chord = hypot(head.x - pin.x, head.y - pin.y)
        let reach = StyleHash.smoothstep(25, 140, chord)
        for (i, b) in bubbles.enumerated() {
            let sp = hypot(b.v.x, b.v.y)
            let (w, ang) = wob(b.phase, sp)
            out.append(BubbleState(position: b.p, radius: params.bodyRadius * (0.16 + 0.28 * b.size) * (0.4 + 0.6 * max(reach, 0.35)),
                                   wobble: w, wobbleAngle: ang, alpha: e * (0.5 + 0.5 * max(reach, 0.4)), pop: popOf(i), hue: CGFloat(i % 6) / 6))
        }
        return out
    }
}
