import CoreGraphics
import Foundation

/// Styles whose whole point is the relationship between the two points: a current, a field, a spring, a
/// conversation, a thread. Each gets its end sizes from `DumbbellMass` (the pin is the heavy one), so the mass
/// relationship is visible in the shapes themselves.

private func smooth(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { StyleHash.smoothstep(a, b, x) }

struct Axes {
    var a: CGPoint, n: CGPoint, chord: CGFloat
    init(pin: CGPoint, head: CGPoint) {
        let dx = head.x - pin.x, dy = head.y - pin.y
        chord = hypot(dx, dy)
        a = chord > 1 ? CGPoint(x: dx / chord, y: dy / chord) : CGPoint(x: 1, y: 0)
        n = CGPoint(x: -a.y, y: a.x)
    }
}

// MARK: - Lightning

public struct LightningScene: Equatable, Sendable {
    public var pin: CGPoint, head: CGPoint
    public var pinRadius: CGFloat, headRadius: CGFloat
    public var bolts: [[CGPoint]]
    public var weights: [CGFloat]
    public var flash: CGFloat
    public var intensity: CGFloat
    public var alpha: CGFloat
}

/// A Tesla arc: two terminals and a bolt of electricity that jumps between them, re-rolled many times a second,
/// forking as it goes and cracking brighter now and then. The more you pull, the more it has to stretch for. Commit:
/// one huge discharge.
public struct LightningSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 28
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    public var params: Params
    private var mass = MassFlow()
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.7 }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; mass = MassFlow()
        mass.sol = DumbbellMass.solve(params.dumbbell, length: 0)
    }
    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt; pin = newPin; head = newHead
        mass.update(chord: hypot(head.x - pin.x, head.y - pin.y), dt: dt, params: params.dumbbell, bodyRadius: params.bodyRadius)
        if releaseT >= 0 { releaseT += dt }
    }
    public mutating func release(commit direction: CGPoint?) { releaseT = 0 }

    private func jag(_ a: CGPoint, _ b: CGPoint, depth: Int, seed: Int, amp: CGFloat) -> [CGPoint] {
        guard depth > 0 else { return [a, b] }
        let dx = b.x - a.x, dy = b.y - a.y
        let l = max(0.001, hypot(dx, dy))
        let off = (StyleHash.unit(seed, 141) - 0.5) * 2 * amp
        let m = CGPoint(x: (a.x + b.x) / 2 - dy / l * off, y: (a.y + b.y) / 2 + dx / l * off)
        let left = jag(a, m, depth: depth - 1, seed: seed &* 2 &+ 1, amp: amp * 0.56)
        let right = jag(m, b, depth: depth - 1, seed: seed &* 2 &+ 2, amp: amp * 0.56)
        return left + right.dropFirst()
    }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> LightningScene {
        let e = max(0, min(1, emerge))
        let ax = Axes(pin: pin, head: head)
        let fired = releaseT >= 0
        let fade = fired ? max(0, 1 - releaseT / 0.6) : 1
        let on = smooth(30, 110, ax.chord) * fade
        let bucket = Int(time * 26) &+ (fired ? 9000 : 0)
        let strike = StyleHash.unit(bucket / 5, 142) < 0.3 || fired
        let amp = min(70, 12 + ax.chord * 0.1) * (strike ? 1.25 : 0.9)
        var bolts: [[CGPoint]] = [], weights: [CGFloat] = []
        let r1 = max(8, mass.sol.pin * 0.7), r2 = max(6, mass.sol.head * 0.7)
        if on > 0.02 {
            let a = CGPoint(x: pin.x + ax.a.x * r1, y: pin.y + ax.a.y * r1)
            let b = CGPoint(x: head.x - ax.a.x * r2, y: head.y - ax.a.y * r2)
            let main = jag(a, b, depth: 6, seed: bucket &* 3, amp: amp)
            bolts.append(main); weights.append(1)
            // Forks leave the main bolt and wander off.
            let forks = strike ? 4 : 2
            for k in 0..<forks {
                let idx = Int(CGFloat(main.count - 1) * (0.12 + 0.76 * StyleHash.unit(bucket &* 7 &+ k, 143)))
                let from = main[idx]
                let side: CGFloat = StyleHash.unit(bucket &* 11 &+ k, 144) > 0.5 ? 1 : -1
                let ang = atan2(ax.a.y, ax.a.x) + side * (0.5 + 0.7 * StyleHash.unit(bucket &* 13 &+ k, 145))
                let len = min(150, ax.chord * (0.12 + 0.18 * StyleHash.unit(bucket &* 17 &+ k, 146)))
                let to = CGPoint(x: from.x + cos(ang) * len, y: from.y + sin(ang) * len)
                bolts.append(jag(from, to, depth: 4, seed: bucket &* 19 &+ k, amp: amp * 0.35)); weights.append(0.45)
            }
        }
        return LightningScene(pin: pin, head: head, pinRadius: max(8, mass.sol.pin), headRadius: max(6, mass.sol.head) * (1 + 0.12 * headGlow),
                              bolts: bolts, weights: weights, flash: fired ? max(0, 1 - releaseT / 0.3) : (strike ? 0.25 : 0),
                              intensity: on * (strike ? 1 : 0.75) * (fired ? 1.5 : 1), alpha: e)
    }
}

// MARK: - Magnet field

public struct MagnetScene: Equatable, Sendable {
    public var pin: CGPoint, head: CGPoint
    public var pinRadius: CGFloat, headRadius: CGFloat
    public var lines: [[CGPoint]]
    public var phase: CGFloat
    /// Fraction of the field lines that start at the pin but never reach the head (the imbalance of the two masses).
    public var escaping: CGFloat
    public var alpha: CGFloat
}

/// A magnet: the pin is the north pole and the head the south pole, with iron-filing field lines streaming between
/// them. The poles' strengths are their masses, so the heavy pin throws out more lines than the light head can
/// catch, and the surplus bows away into space. Commit: the field collapses.
public struct MagnetSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 28
        public var lines: Int = 22
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    public var params: Params
    private var mass = MassFlow()
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.6 }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; mass = MassFlow()
        mass.sol = DumbbellMass.solve(params.dumbbell, length: 0)
    }
    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt; pin = newPin; head = newHead
        mass.update(chord: hypot(head.x - pin.x, head.y - pin.y), dt: dt, params: params.dumbbell, bodyRadius: params.bodyRadius)
        if releaseT >= 0 { releaseT += dt }
    }
    public mutating func release(commit direction: CGPoint?) { releaseT = 0 }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> MagnetScene {
        let e = max(0, min(1, emerge))
        let ax = Axes(pin: pin, head: head)
        let fade = releaseT >= 0 ? max(0, 1 - releaseT / 0.5) : 1
        let rp = max(8, mass.sol.pin), rh = max(6, mass.sol.head)
        let qp = rp * rp, qh = rh * rh
        let limit = ax.chord * 0.7 + 110
        var lines: [[CGPoint]] = []
        var escaped = 0
        if ax.chord > 30 {
            let n = params.lines
            for k in 0..<n {
                // Start around the north pole; lines bunch toward the axis like a real dipole's.
                let u = (CGFloat(k) + 0.5) / CGFloat(n)
                let th = atan2(ax.a.y, ax.a.x) + (u * 2 - 1) * .pi
                var p = CGPoint(x: pin.x + cos(th) * rp * 1.04, y: pin.y + sin(th) * rp * 1.04)
                var pts = [p]
                var reached = false
                for _ in 0..<320 {
                    var ex: CGFloat = 0, ey: CGFloat = 0
                    for (c, q) in [(pin, qp), (head, -qh)] {
                        let dx = p.x - c.x, dy = p.y - c.y
                        let r2 = max(25, dx * dx + dy * dy), r = r2.squareRoot()
                        ex += q * dx / (r2 * r); ey += q * dy / (r2 * r)
                    }
                    let m = max(1e-9, hypot(ex, ey))
                    let step: CGFloat = 7
                    p = CGPoint(x: p.x + ex / m * step, y: p.y + ey / m * step)
                    pts.append(p)
                    if hypot(p.x - head.x, p.y - head.y) < rh * 1.05 { reached = true; break }
                    if hypot(p.x - pin.x, p.y - pin.y) > limit { break }
                }
                if !reached { escaped += 1 }
                lines.append(pts)
            }
            if releaseT >= 0 { lines = lines.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) }
        }
        let denom = max(1, lines.count)
        return MagnetScene(pin: pin, head: head, pinRadius: rp, headRadius: rh * (1 + 0.1 * headGlow), lines: lines, phase: time,
                           escaping: CGFloat(escaped) / CGFloat(denom), alpha: e * fade)
    }
}

// MARK: - Slinky

public struct SlinkyScene: Equatable, Sendable {
    public var coil: [CGPoint]
    public var pin: CGPoint, head: CGPoint
    public var pinRadius: CGFloat, headRadius: CGFloat
    public var wire: CGFloat
    public var alpha: CGFloat
}

/// A rainbow slinky stretched between the two points. It is a tapered coil (wide at the heavy pin, narrow at the
/// light head); pulling thins and straightens it, and a compression wave runs along its length. Commit: it springs
/// back into a tight coil and bounces.
public struct SlinkySim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 30
        public var loops: Int = 26
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    public var params: Params
    private var mass = MassFlow()
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    private var wave: CGFloat = 0, waveV: CGFloat = 0
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.9 }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; mass = MassFlow(); wave = 0; waveV = 0
        mass.sol = DumbbellMass.solve(params.dumbbell, length: 0)
    }
    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt
        let prev = hypot(head.x - pin.x, head.y - pin.y)
        pin = newPin; head = newHead
        let chord = hypot(head.x - pin.x, head.y - pin.y)
        mass.update(chord: chord, dt: dt, params: params.dumbbell, bodyRadius: params.bodyRadius)
        // Stretching or letting go rings the spring: a damped oscillation of the wave amplitude.
        waveV += ((chord - prev) / max(dt, 1e-4) * 0.0007) * (1 / 60) * 60
        var d = CGPoint(x: wave, y: 0), v = CGPoint(x: waveV, y: 0)
        RecoilSpring.step(x: &d, v: &v, omega: 9, zeta: 0.12, h: dt)
        wave = max(-1.5, min(1.5, d.x)); waveV = v.x
        if releaseT >= 0 { releaseT += dt }
    }
    public mutating func release(commit direction: CGPoint?) { releaseT = 0; waveV += 12 }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> SlinkyScene {
        let e = max(0, min(1, emerge))
        let ax = Axes(pin: pin, head: head)
        let fade = releaseT >= 0 ? max(0, 1 - max(0, releaseT - 0.3) / 0.6) : 1
        let rp = max(8, mass.sol.pin), rh = max(6, mass.sol.head)
        let reach = smooth(20, 120, ax.chord)
        let loops = params.loops
        let perLoop = 26
        let total = loops * perLoop
        var pts: [CGPoint] = []
        pts.reserveCapacity(total + 1)
        // The coil's wire thins as it stretches (a fixed wire, a longer spring).
        let thin = 1 / (1 + ax.chord / 500)
        let tight: CGFloat = releaseT >= 0 ? min(1, releaseT * 2.2) : 0     // after release it recoils into a tight coil
        for i in 0...total {
            let s = CGFloat(i) / CGFloat(total)
            let th = CGFloat(i) / CGFloat(perLoop) * 2 * .pi
            let sw = s + 0.012 * wave * CGFloat(sin(Double(s * 18 - time * 14)))      // compression wave along the length
            let R = (rp * (1 - s) + rh * s) * 1.15 * (0.55 + 0.45 * thin) * (0.5 + 0.5 * reach) * (1 + 0.5 * tight)
            let centre = CGPoint(x: pin.x + (head.x - pin.x) * sw, y: pin.y + (head.y - pin.y) * sw)
            let along = R * 0.34 * CGFloat(cos(Double(th)))                      // the slight lean that makes it look like a coil
            pts.append(CGPoint(x: centre.x + ax.a.x * along + ax.n.x * R * CGFloat(sin(Double(th))),
                               y: centre.y + ax.a.y * along + ax.n.y * R * CGFloat(sin(Double(th)))))
        }
        return SlinkyScene(coil: pts, pin: pin, head: head, pinRadius: rp * 0.5, headRadius: rh * 0.5 * (1 + 0.1 * headGlow),
                           wire: max(2.4, 4.4 * (0.5 + 0.5 * thin)), alpha: e * fade)
    }
}

// MARK: - Tin-can phone

public struct NoteState: Equatable, Sendable {
    public var position: CGPoint
    public var alpha: CGFloat
    public var glyph: Int
    public var scale: CGFloat
    public var rotation: CGFloat
}

public struct TinCanScene: Equatable, Sendable {
    public var pin: CGPoint, head: CGPoint
    public var pinRadius: CGFloat, headRadius: CGFloat
    public var angle: CGFloat
    public var string: [CGPoint]
    public var notes: [NoteState]
    public var pinWiggle: CGFloat, headWiggle: CGFloat
    public var alpha: CGFloat
}

/// Two tin cans and a taut string, taking turns to talk: notes float from the speaking can along the string, the
/// string ripples with each word, and the listening can shivers as they arrive. Commit: they shout, and the cans
/// rattle away.
public struct TinCanSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 28
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    public var params: Params
    private var mass = MassFlow()
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.7 }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; mass = MassFlow()
        mass.sol = DumbbellMass.solve(params.dumbbell, length: 0)
    }
    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt; pin = newPin; head = newHead
        mass.update(chord: hypot(head.x - pin.x, head.y - pin.y), dt: dt, params: params.dumbbell, bodyRadius: params.bodyRadius)
        if releaseT >= 0 { releaseT += dt }
    }
    public mutating func release(commit direction: CGPoint?) { releaseT = 0 }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> TinCanScene {
        let e = max(0, min(1, emerge))
        let ax = Axes(pin: pin, head: head)
        let fade = releaseT >= 0 ? max(0, 1 - max(0, releaseT - 0.2) / 0.5) : 1
        let rp = max(10, mass.sol.pin), rh = max(8, mass.sol.head) * (1 + 0.1 * headGlow)
        let reach = smooth(20, 110, ax.chord)
        // Conversation clock: the pin talks for ~1.8 s, then the head answers.
        let period: CGFloat = 4.2
        let cycle = time.truncatingRemainder(dividingBy: period)
        let pinTalks = cycle < period / 2
        let phaseT = cycle.truncatingRemainder(dividingBy: period / 2)
        let travel: CGFloat = 1.1
        var notes: [NoteState] = []
        var arrive: CGFloat = 0, speak: CGFloat = 0
        let wordCount = 4
        for w in 0..<wordCount {
            let t0 = CGFloat(w) * 0.32
            let p = (phaseT - t0) / travel
            guard p > 0, p < 1 else { continue }
            let s = pinTalks ? p : 1 - p
            let hop = 14 * CGFloat(sin(Double(p * .pi))) + 4 * CGFloat(sin(Double(p * 14 + CGFloat(w))))
            let pos = CGPoint(x: pin.x + (head.x - pin.x) * s + ax.n.x * hop, y: pin.y + (head.y - pin.y) * s + ax.n.y * hop + 6)
            notes.append(NoteState(position: pos, alpha: e * reach * sin(.pi * p) * fade, glyph: (w + (pinTalks ? 0 : 2)) % 3,
                                   scale: 0.75 + 0.5 * sin(.pi * p), rotation: 0.3 * CGFloat(sin(Double(p * 9 + CGFloat(w))))))
            if p > 0.86 { arrive = max(arrive, (p - 0.86) / 0.14) }
        }
        speak = phaseT < 1.4 ? 1 - phaseT / 1.4 : 0
        let (pw, hw) = pinTalks ? (speak, arrive) : (arrive, speak)
        // The string ripples with each word travelling along it.
        var str: [CGPoint] = []
        let L = 30
        let amp: CGFloat = (4 + 5 * max(speak, arrive)) * reach
        for j in 0...L {
            let s = CGFloat(j) / CGFloat(L)
            let dirSign: CGFloat = pinTalks ? 1 : -1
            let w = CGFloat(sin(Double((s * 7 - dirSign * time * 4.5) * .pi))) * amp * sin(.pi * s)
            str.append(CGPoint(x: pin.x + (head.x - pin.x) * s + ax.n.x * w, y: pin.y + (head.y - pin.y) * s + ax.n.y * w))
        }
        return TinCanScene(pin: pin, head: head, pinRadius: rp, headRadius: rh, angle: atan2(ax.a.y, ax.a.x), string: str, notes: notes,
                           pinWiggle: pw, headWiggle: hw, alpha: e * fade)
    }
}

// MARK: - Red thread

public struct HeartState: Equatable, Sendable {
    public var position: CGPoint
    public var size: CGFloat
    public var alpha: CGFloat
    public var rotation: CGFloat
}

public struct ThreadScene: Equatable, Sendable {
    public var pin: CGPoint, head: CGPoint
    public var pinHeart: HeartState, headHeart: HeartState
    public var thread: [CGPoint]
    public var hearts: [HeartState]
    public var pulse: CGPoint
    public var pulseAlpha: CGFloat
    public var alpha: CGFloat
}

/// The red thread of fate: a thread between two hearts, one big and one small, each beating. A glow pulses along
/// the thread and little hearts float along it in both directions. Pull hard and the thread tightens; commit and it
/// untangles into a burst of hearts.
public struct ThreadSim: Sendable {
    public struct Params: Equatable, Sendable {
        public var bodyRadius: CGFloat = 28
        public var hearts: Int = 7
        public var dumbbell = DumbbellMass.Params()
        public init() {}
    }
    public var params: Params
    private var mass = MassFlow()
    private var pin = CGPoint.zero, head = CGPoint.zero
    private var time: CGFloat = 0
    private var releaseT: CGFloat = -1
    private var releaseDir = CGPoint(x: 1, y: 0)
    public init(params: Params = Params()) { self.params = params }
    public var isFinished: Bool { releaseT > 0.8 }

    public mutating func reset(pin: CGPoint) {
        self.pin = pin; head = pin; time = 0; releaseT = -1; mass = MassFlow()
        mass.sol = DumbbellMass.solve(params.dumbbell, length: 0)
    }
    public mutating func step(dt: CGFloat, pin newPin: CGPoint, head newHead: CGPoint) {
        guard dt > 0 else { return }
        time += dt; pin = newPin; head = newHead
        mass.update(chord: hypot(head.x - pin.x, head.y - pin.y), dt: dt, params: params.dumbbell, bodyRadius: params.bodyRadius)
        if releaseT >= 0 { releaseT += dt }
    }
    public mutating func release(commit direction: CGPoint?) {
        releaseT = 0
        releaseDir = direction ?? .zero
    }

    private func beat(_ t: CGFloat) -> CGFloat {
        // A lub-dub: two quick swells per second.
        let c = t.truncatingRemainder(dividingBy: 0.95) / 0.95
        func bump(_ x: CGFloat, _ w: CGFloat) -> CGFloat { max(0, 1 - abs(x) / w) }
        return max(bump(c - 0.08, 0.1), 0.7 * bump(c - 0.26, 0.1))
    }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> ThreadScene {
        let e = max(0, min(1, emerge))
        let ax = Axes(pin: pin, head: head)
        let fired = releaseT >= 0
        let fade = fired ? max(0, 1 - releaseT / 0.7) : 1
        let reach = smooth(20, 110, ax.chord)
        let rp = max(10, mass.sol.pin), rh = max(8, mass.sol.head) * (1 + 0.1 * headGlow)
        let b1 = beat(time), b2 = beat(time - 0.12)
        let sag = (min(50, 10 + ax.chord * 0.07) * (1 - 0.8 * smooth(200, 900, ax.chord))) * reach * (fired ? 1 + releaseT * 3 : 1)
        let sway = CGFloat(sin(Double(time * 1.3))) * 3 * reach
        var thread: [CGPoint] = []
        let L = 34
        for j in 0...L {
            let s = CGFloat(j) / CGFloat(L)
            let drop = -sag * 4 * s * (1 - s)
            let w = sway * sin(.pi * s) + 2 * CGFloat(sin(Double(s * 12 - time * 3))) * sin(.pi * s) * reach
            thread.append(CGPoint(x: pin.x + (head.x - pin.x) * s + ax.n.x * w, y: pin.y + (head.y - pin.y) * s + ax.n.y * w + drop))
        }
        func at(_ s: CGFloat) -> CGPoint {
            let f = s * CGFloat(L), i = min(L - 1, Int(f)), u = f - CGFloat(i)
            return CGPoint(x: thread[i].x + (thread[i + 1].x - thread[i].x) * u, y: thread[i].y + (thread[i + 1].y - thread[i].y) * u)
        }
        var hearts: [HeartState] = []
        for i in 0..<params.hearts {
            let dirSign = i % 2 == 0 ? 1 : -1
            let period = 3.4 + 1.6 * StyleHash.unit(i, 151)
            let p = (time / period + StyleHash.unit(i, 152)).truncatingRemainder(dividingBy: 1)
            let s = dirSign > 0 ? p : 1 - p
            var pos = at(s)
            pos.y += 14 * CGFloat(sin(Double(p * .pi))) + 4 * CGFloat(sin(Double(p * 18 + CGFloat(i))))
            var a = e * reach * sin(.pi * p) * fade
            var sz = max(7, rp * (0.3 + 0.2 * StyleHash.unit(i, 153)))
            if fired {
                let t = releaseT
                let ang = 6.28 * StyleHash.unit(i, 154)
                pos.x += (cos(ang) * 130 + releaseDir.x * 160) * t; pos.y += (sin(ang) * 130 + releaseDir.y * 160) * t + 70 * t
                a = e * fade; sz *= 1 + t
            }
            hearts.append(HeartState(position: pos, size: sz, alpha: a, rotation: 0.35 * CGFloat(sin(Double(p * 8 + CGFloat(i))))))
        }
        let pulseP = (time / 1.6).truncatingRemainder(dividingBy: 1)
        return ThreadScene(pin: pin, head: head,
                           pinHeart: HeartState(position: pin, size: rp * (1 + 0.14 * b1), alpha: e * (fired ? max(0.3, fade) : 1), rotation: 0),
                           headHeart: HeartState(position: head, size: rh * (1 + 0.14 * b2), alpha: e * (fired ? max(0.3, fade) : 1), rotation: 0),
                           thread: thread, hearts: hearts, pulse: at(pulseP), pulseAlpha: e * reach * sin(.pi * pulseP) * fade, alpha: e)
    }
}
