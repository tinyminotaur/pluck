import CoreGraphics
import Foundation

private func sm(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { StyleHash.smoothstep(a, b, x) }

// MARK: - Lasso

public struct LassoScene: Sendable {
    public var rope: [CGPoint]
    public var loopCenter: CGPoint, rx: CGFloat, ry: CGFloat, angle: CGFloat
    public var cinch: CGFloat
    public var sparks: [(CGPoint, CGFloat, CGFloat)]
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var phase: CGFloat
    public var alpha: CGFloat
}

/// An abstract neon lasso: a rope of light leaves the pin, ripples across the screen and ends in a spinning loop that
/// settles around the target, its inside marked out with marching ants. Commit: the loop cinches shut with a snap and a
/// spray of sparks. Cancel: it unspools and fades.
public struct LassoSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.9 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> LassoScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge)), reach = sm(20, 130, ax.chord)
        let tt = b.fired ? b.releaseT : 0
        let commit = b.fired && !b.cancelled
        let cinch: CGFloat = commit ? (sm(0, 0.22, tt) - 0.08 * CGFloat(sin(Double(min(1, tt / 0.4) * .pi * 2))) * (tt < 0.4 ? 1 : 0)) : 0
        let R0 = max(30, b.rh * 2.1 + 10) * (1 - 0.88 * max(0, cinch)) * (b.fired && !commit ? max(0, 1 - tt / 0.6) : 1)
        // The loop spins about the rope's axis: it squashes and swells as it turns, settling around the target.
        let spin = b.time * 2.4
        let ry = R0 * (0.32 + 0.68 * abs(CGFloat(sin(Double(spin)))))
        let loopC = CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * reach, y: b.pin.y + (b.head.y - b.pin.y) * reach)
        let rx = R0 * (1 + 0.25 * (1 - reach)) * (1 + 0.5 * (1 - reach))
        let angle = atan2(ax.a.y, ax.a.x) + 0.35 * CGFloat(sin(Double(b.time * 1.1)))
        // Rope: from the pin to the loop's near edge, rippling with a travelling wave.
        let edge = CGPoint(x: loopC.x - ax.a.x * rx * 0.96, y: loopC.y - ax.a.y * rx * 0.96)
        let len = hypot(edge.x - b.pin.x, edge.y - b.pin.y)
        var rope: [CGPoint] = []
        for j in 0...34 {
            let s = CGFloat(j) / 34
            let amp = min(46, 8 + len * 0.1) * sin(.pi * s) * (b.fired ? max(0.2, 1 - tt * 1.5) : 1)
            let w = amp * CGFloat(sin(Double(s * 7 - b.time * 6))) * reach
            rope.append(CGPoint(x: b.pin.x + (edge.x - b.pin.x) * s + ax.n.x * w, y: b.pin.y + (edge.y - b.pin.y) * s + ax.n.y * w))
        }
        var sparks: [(CGPoint, CGFloat, CGFloat)] = []
        for i in 0..<22 {
            let ph = (b.time * 0.9 + CGFloat(i) / 22).truncatingRemainder(dividingBy: 1)
            let a = 6.28 * StyleHash.unit(i, 401) + b.time * (1 + StyleHash.unit(i, 402))
            let r = R0 * (1 + 0.4 * ph)
            var p = CGPoint(x: loopC.x + cos(a) * r, y: loopC.y + sin(a) * r * 0.7)
            var al = e * reach * (1 - ph) * 0.9
            if commit {
                let burst = sm(0.1, 0.2, tt) * (1 - sm(0.2, 0.8, tt))
                p = CGPoint(x: loopC.x + cos(a) * (30 + 220 * tt), y: loopC.y + sin(a) * (30 + 220 * tt))
                al = e * burst
            }
            sparks.append((p, al, 3 + 5 * StyleHash.unit(i, 403)))
        }
        return LassoScene(rope: rope, loopCenter: loopC, rx: rx, ry: ry, angle: angle, cinch: max(0, cinch), sparks: sparks, pin: b.pin, head: b.head,
                          pinRadius: b.rp, headRadius: b.rh * (1 + 0.1 * headGlow), phase: b.time,
                          alpha: e * (commit ? max(0.001, 1 - sm(0.5, 0.9, tt)) : b.fade(0.7)))
    }
}

// MARK: - Laser pointer

public struct LaserScene: Sendable {
    public var dot: CGPoint
    public var trail: [(CGPoint, CGFloat, CGFloat)]
    public var pen: CGPoint, penAngle: CGFloat, penLength: CGFloat
    public var beamAlpha: CGFloat
    public var sparkles: [(CGPoint, CGFloat, CGFloat)]
    public var ping: [(CGFloat, CGFloat)]
    public var dotSize: CGFloat
    public var phase: CGFloat
    public var alpha: CGFloat
}

public struct LaserPointerSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.7 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> LaserScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge))
        let tt = b.fired ? b.releaseT : 0
        let commit = b.fired && !b.cancelled
        // A hand-held pointer never sits quite still: a tiny tremor on the dot.
        let tremor = CGPoint(x: 1.1 * CGFloat(sin(Double(b.time * 37))), y: 1.1 * CGFloat(cos(Double(b.time * 31))))
        let dot = CGPoint(x: b.head.x + tremor.x, y: b.head.y + tremor.y)
        var trail: [(CGPoint, CGFloat, CGFloat)] = []
        let pts = b.trail.suffix(60)
        for (i, tp) in pts.enumerated() {
            let age = b.time - tp.t
            let a = max(0, 1 - age / 0.9)
            trail.append((tp.p, a * a * e, 3 + 6 * CGFloat(i) / CGFloat(max(1, pts.count))))
        }
        var sparkles: [(CGPoint, CGFloat, CGFloat)] = []
        for i in 0..<10 {
            let ph = (b.time * 1.6 + CGFloat(i) / 10).truncatingRemainder(dividingBy: 1)
            let a = 6.28 * StyleHash.unit(i + Int(b.time * 1.6 + CGFloat(i) / 10) * 5, 411)
            let d = 8 + 26 * ph
            sparkles.append((CGPoint(x: dot.x + cos(a) * d, y: dot.y + sin(a) * d), e * (1 - ph) * 0.85, 2 + 3 * StyleHash.unit(i, 412)))
        }
        var ping: [(CGFloat, CGFloat)] = []
        if commit { ping = [(14 + 120 * min(1, tt / 0.5), max(0, 1 - tt / 0.5)), (10 + 70 * min(1, tt / 0.5), max(0, 0.8 - tt / 0.5))] }
        let alpha = e * (b.fired ? (commit ? max(0.001, 1 - sm(0.45, 0.7, tt)) : b.fade(0.35)) : 1)
        return LaserScene(dot: dot, trail: trail, pen: b.pin, penAngle: atan2(dot.y - b.pin.y, dot.x - b.pin.x), penLength: max(34, b.rp * 2.4),
                          beamAlpha: e * sm(20, 100, ax.chord) * 0.5, sparkles: sparkles, ping: ping, dotSize: max(9, b.rh * 0.42) * (1 + 0.5 * (commit ? (1 - sm(0, 0.2, tt)) : 0) + 0.2 * headGlow),
                          phase: b.time, alpha: alpha)
    }
}

// MARK: - Highlighter

public struct MarkerScene: Sendable {
    public var segments: [(CGPoint, CGPoint, CGFloat, CGFloat)]     // from, to, alpha, hue
    public var width: CGFloat
    public var tip: CGPoint, tipAngle: CGFloat
    public var cap: CGPoint, capSize: CGFloat
    public var flash: CGFloat
    public var alpha: CGFloat
}

public struct HighlighterSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> MarkerScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge))
        let tt = b.fired ? b.releaseT : 0
        var segs: [(CGPoint, CGPoint, CGFloat, CGFloat)] = []
        // The stroke is the path the head has taken; the colour drifts along it and the old ink dries away.
        var path = b.trail
        if path.isEmpty { path = [TrailPoint(p: b.pin, t: b.time)] }
        if hypot(path[0].p.x - b.pin.x, hypot(0, 0) + path[0].p.y - b.pin.y) > 4 { path.insert(TrailPoint(p: b.pin, t: path[0].t - 0.05), at: 0) }
        for i in 1..<max(1, path.count) {
            let age = b.time - path[i].t
            let a = max(0, 1 - age / 2.4) * (b.fired ? max(0, 1 - tt / 0.6) : 1)
            segs.append((path[i - 1].p, path[i].p, a * 0.9 * e, (b.time * 0.08 + CGFloat(i) * 0.004).truncatingRemainder(dividingBy: 1)))
        }
        return MarkerScene(segments: segs, width: max(16, b.bodyRadius * 0.7), tip: b.head, tipAngle: atan2(b.head.y - b.pin.y, b.head.x - b.pin.x),
                           cap: b.pin, capSize: max(14, b.rp * 0.9), flash: b.fired && !b.cancelled ? max(0, 1 - tt / 0.3) : 0,
                           alpha: e * (b.fired ? max(0.001, 1 - sm(0.5, 0.8, tt)) : 1) * (ax.chord > 4 ? 1 : 0.6))
    }
}

// MARK: - Spotlight

public struct SpotlightScene: Sendable {
    public var lamp: CGPoint, target: CGPoint
    public var radius: CGFloat
    public var dim: CGFloat
    public var coneAlpha: CGFloat
    public var motes: [(CGPoint, CGFloat, CGFloat)]
    public var lampSize: CGFloat
    public var phase: CGFloat
    public var alpha: CGFloat
}

public struct SpotlightSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.7 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> SpotlightScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge)), reach = sm(20, 110, ax.chord)
        let tt = b.fired ? b.releaseT : 0
        // The pool of light is the head's mass; the further you pull, the tighter it focuses (a smaller, brighter spot).
        let r = max(46, b.rh * 4.2) * (1 + 0.35 * (1 - reach)) * (b.fired && !b.cancelled ? 1 + 0.9 * sm(0, 0.2, tt) : 1)
        var motes: [(CGPoint, CGFloat, CGFloat)] = []
        for i in 0..<26 {
            let s = (StyleHash.unit(i, 421) + b.time * 0.04 * (0.5 + StyleHash.unit(i, 422))).truncatingRemainder(dividingBy: 1)
            let w = (StyleHash.unit(i, 423) * 2 - 1) * r * 0.9 * s
            let p = CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s + ax.n.x * w, y: b.pin.y + (b.head.y - b.pin.y) * s + ax.n.y * w + 8 * CGFloat(sin(Double(b.time * 0.8 + CGFloat(i)))))
            motes.append((p, e * reach * (0.3 + 0.7 * CGFloat(sin(Double(b.time * 1.3 + CGFloat(i) * 2)))) * 0.5 * (b.fired ? 0.3 : 1), 1.5 + 2.5 * StyleHash.unit(i, 424)))
        }
        let fade = b.fired ? max(0, 1 - sm(0.25, 0.7, tt)) : 1
        return SpotlightScene(lamp: b.pin, target: b.head, radius: r, dim: 0.5 * reach * fade, coneAlpha: reach * fade, motes: motes,
                              lampSize: max(16, b.rp * 1.1), phase: b.time, alpha: e)
    }
}

// MARK: - Callout arrow

public struct CalloutScene: Sendable {
    public var arrow: [CGPoint]
    public var head1: [CGPoint], head2: [CGPoint]
    public var scribble: [CGPoint]
    public var badge: CGPoint, badgeSize: CGFloat
    public var drawn: CGFloat
    public var pop: CGFloat
    public var alpha: CGFloat
}

/// A hand-drawn call-out: a marker arrow that draws itself from the numbered badge at the pin to the target, with a
/// scribbled circle around it. Everything jitters in stop-motion at about 10 frames a second, like a flip-book.
public struct CalloutArrowSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> CalloutScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge)), reach = sm(20, 120, ax.chord)
        let tt = b.fired ? b.releaseT : 0
        let frame = Int(b.time * 10)                                          // stop-motion: new jitter ten times a second
        func jit(_ i: Int, _ k: Int) -> CGFloat { (StyleHash.unit(frame &* 31 &+ i, k) - 0.5) * 2 }
        let start = CGPoint(x: b.pin.x + ax.a.x * b.rp * 1.3, y: b.pin.y + ax.a.y * b.rp * 1.3)
        let end = CGPoint(x: b.head.x - ax.a.x * (b.rh + 26), y: b.head.y - ax.a.y * (b.rh + 26))
        let bow = min(60, ax.chord * 0.12) * 0.8
        var pts: [CGPoint] = []
        let steps = 30
        let upto = Int(CGFloat(steps) * reach * (b.fired && b.cancelled ? max(0, 1 - tt / 0.5) : 1))
        for j in 0...max(1, upto) {
            let s = CGFloat(j) / CGFloat(steps)
            let arch = bow * 4 * s * (1 - s)
            pts.append(CGPoint(x: start.x + (end.x - start.x) * s + ax.n.x * (arch + 1.6 * jit(j, 431)), y: start.y + (end.y - start.y) * s + ax.n.y * (arch + 1.6 * jit(j, 432))))
        }
        // The arrowhead: two strokes off the end, along the final direction.
        var h1: [CGPoint] = [], h2: [CGPoint] = []
        if pts.count > 3, reach > 0.6 {
            let a = pts[pts.count - 1], c = pts[max(0, pts.count - 4)]
            let ang = atan2(a.y - c.y, a.x - c.x)
            let L: CGFloat = 20
            h1 = [a, CGPoint(x: a.x - cos(ang - 0.5) * L + 1.5 * jit(1, 433), y: a.y - sin(ang - 0.5) * L + 1.5 * jit(2, 433))]
            h2 = [a, CGPoint(x: a.x - cos(ang + 0.5) * L + 1.5 * jit(3, 433), y: a.y - sin(ang + 0.5) * L + 1.5 * jit(4, 433))]
        }
        // A scribbled circle around the target: a loose spiral drawn on as the arrow lands.
        var scribble: [CGPoint] = []
        let circleDrawn = sm(0.7, 1.0, reach)
        let n = Int(60 * circleDrawn)
        for j in 0..<max(0, n) {
            let u = CGFloat(j) / 60
            let a = u * 2 * .pi * 1.18 + 0.6
            let r = (b.rh + 22 + 7 * u) * (1 + 0.05 * jit(j, 434))
            scribble.append(CGPoint(x: b.head.x + cos(a) * r, y: b.head.y + sin(a) * r * 0.9))
        }
        let pop = b.fired && !b.cancelled ? 1 + 0.25 * CGFloat(sin(Double(min(1, tt / 0.3) * .pi))) : 1
        return CalloutScene(arrow: pts, head1: h1, head2: h2, scribble: scribble, badge: CGPoint(x: b.pin.x, y: b.pin.y), badgeSize: max(14, b.rp * 0.9) * pop,
                            drawn: reach, pop: pop, alpha: e * (b.fired ? max(0.001, 1 - sm(0.4, 0.8, tt)) : 1))
    }
}

// MARK: - Target lock

public struct TargetLockScene: Sendable {
    public var target: CGPoint
    public var bracket: CGFloat
    public var lock: CGFloat
    public var ringRadius: CGFloat
    public var ticks: [(CGPoint, CGPoint)]
    public var pings: [(CGFloat, CGFloat)]
    public var origin: CGPoint
    public var readout: String
    public var readoutPos: CGPoint
    public var pin: CGPoint, pinRadius: CGFloat
    public var line: [CGPoint]
    public var phase: CGFloat
    public var alpha: CGFloat
}

public struct TargetLockSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.7 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> TargetLockScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge)), reach = sm(20, 110, ax.chord)
        let tt = b.fired ? b.releaseT : 0
        // The brackets close in on the target and lock: wide at first, then snapping tight with a little overshoot.
        let lockT = sm(0.0, 1.0, min(1, b.time * 1.4))
        let size = (b.rh * 1.2 + 26) * (1 + 1.4 * (1 - lockT) + 0.12 * CGFloat(sin(Double(b.time * 9))) * (1 - lockT)) * (b.fired && !b.cancelled ? 1 - 0.5 * sm(0, 0.18, tt) : 1)
        var ticks: [(CGPoint, CGPoint)] = []
        for i in 0..<24 {
            let a = CGFloat(i) / 24 * 2 * .pi + b.time * 0.5
            let r0 = size * 1.35, r1 = r0 + (i % 6 == 0 ? 12 : 6)
            ticks.append((CGPoint(x: b.head.x + cos(a) * r0, y: b.head.y + sin(a) * r0), CGPoint(x: b.head.x + cos(a) * r1, y: b.head.y + sin(a) * r1)))
        }
        let pings: [(CGFloat, CGFloat)] = (0..<3).map { k in
            let ph = (b.time * 0.8 + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
            return (b.rp * (0.8 + 2.2 * ph), e * (1 - ph) * 0.8)
        }
        let dist = Int(ax.chord.rounded())
        let deg = Int((atan2(ax.a.y, ax.a.x) * 180 / .pi).rounded())
        let text = "LOCK  \(dist) px  \(deg)\u{00B0}"
        return TargetLockScene(target: b.head, bracket: size, lock: lockT, ringRadius: size * 1.2, ticks: ticks, pings: pings, origin: b.pin,
                               readout: text, readoutPos: CGPoint(x: b.head.x + size + 14, y: b.head.y + size * 0.6), pin: b.pin, pinRadius: b.rp,
                               line: [b.pin, b.head], phase: b.time,
                               alpha: e * reach * (b.fired ? (b.cancelled ? b.fade(0.3) : max(0.001, 1 - sm(0.3, 0.6, tt))) : 1) + 0.0001)
    }
}

// MARK: - Marquee (rectangular selection)

public struct MarqueeScene: Sendable {
    public var rect: CGRect
    public var corner: CGFloat
    public var handles: [CGPoint]
    public var tag: String
    public var tagPos: CGPoint
    public var sparkles: [(CGPoint, CGFloat, CGFloat)]
    public var flash: CGFloat
    public var phase: CGFloat
    public var pin: CGPoint, head: CGPoint
    public var alpha: CGFloat
}

/// The rubber-band rectangle you drag on the desktop to select things, made lively: its edges follow your corners on
/// springs so it stretches and settles like jelly, the corners round off while it moves, ants march round it, a
/// shimmer sweeps its glassy inside, the corners pop, and a size tag rides along. Commit: it snaps tight with a flash.
public struct MarqueeSim: Sendable {
    public var base = SimBase()
    private var x0: CGFloat = 0, x1: CGFloat = 0, y0: CGFloat = 0, y1: CGFloat = 0
    private var v0: CGFloat = 0, v1: CGFloat = 0, w0: CGFloat = 0, w1: CGFloat = 0
    private var speed: CGFloat = 0
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.7 }
    public mutating func reset(pin: CGPoint) { base.start(pin); x0 = pin.x; x1 = pin.x; y0 = pin.y; y1 = pin.y; v0 = 0; v1 = 0; w0 = 0; w1 = 0; speed = 0 }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) {
        let prev = base.head
        base.advance(dt, pin, head)
        speed += (hypot(head.x - prev.x, head.y - prev.y) / max(dt, 1e-4) - speed) * min(1, 8 * dt)
        // Each edge is a spring toward the box the corners define: a lively overshoot that settles.
        let tx0 = min(pin.x, head.x), tx1 = max(pin.x, head.x), ty0 = min(pin.y, head.y), ty1 = max(pin.y, head.y)
        func spring(_ x: inout CGFloat, _ v: inout CGFloat, _ target: CGFloat) {
            let k: CGFloat = 520, c: CGFloat = 26
            v += (k * (target - x) - c * v) * dt; x += v * dt
        }
        spring(&x0, &v0, tx0); spring(&x1, &v1, tx1); spring(&y0, &w0, ty0); spring(&y1, &w1, ty1)
    }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> MarqueeScene {
        let b = base
        let e = max(0, min(1, emerge))
        let tt = b.fired ? b.releaseT : 0
        let commit = b.fired && !b.cancelled
        var r = CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
        if commit { let k = 0.04 * sm(0, 0.12, tt) * (1 - sm(0.12, 0.4, tt)); r = r.insetBy(dx: r.width * k, dy: r.height * k) }
        if b.fired && b.cancelled { let k = max(0, 1 - tt / 0.45); let c = CGPoint(x: b.pin.x, y: b.pin.y); r = CGRect(x: c.x + (r.minX - c.x) * k, y: c.y + (r.minY - c.y) * k, width: r.width * k, height: r.height * k) }
        let corner = max(2, min(28, 4 + speed * 0.025))
        let handles = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
                       CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
        var sparkles: [(CGPoint, CGFloat, CGFloat)] = []
        let per = 2 * (r.width + r.height)
        for i in 0..<18 where per > 40 {
            let s = ((b.time * 0.18 + CGFloat(i) / 18).truncatingRemainder(dividingBy: 1)) * per
            var p: CGPoint
            if s < r.width { p = CGPoint(x: r.minX + s, y: r.minY) }
            else if s < r.width + r.height { p = CGPoint(x: r.maxX, y: r.minY + (s - r.width)) }
            else if s < 2 * r.width + r.height { p = CGPoint(x: r.maxX - (s - r.width - r.height), y: r.maxY) }
            else { p = CGPoint(x: r.minX, y: r.maxY - (s - 2 * r.width - r.height)) }
            sparkles.append((p, e * (0.4 + 0.6 * CGFloat(sin(Double(b.time * 4 + CGFloat(i) * 2)))) * 0.8, 2 + 3 * StyleHash.unit(i, 441)))
        }
        let tag = "\(Int(r.width.rounded())) \u{00D7} \(Int(r.height.rounded()))"
        let flash = commit ? max(0, 1 - tt / 0.3) : 0
        let a = e * (b.fired ? max(0.001, 1 - sm(0.35, 0.7, tt)) : 1) * (r.width + r.height > 6 ? 1 : 0.0001)
        return MarqueeScene(rect: r, corner: corner, handles: handles, tag: tag, tagPos: CGPoint(x: r.maxX + 8, y: r.minY - 26), sparkles: sparkles,
                            flash: flash, phase: b.time, pin: b.pin, head: b.head, alpha: a)
    }
}

// MARK: - Jelly circle (organic selection)

public struct JellyScene: Sendable {
    public var outline: [CGPoint]
    public var center: CGPoint
    public var radius: CGFloat
    public var ripples: [(CGFloat, CGFloat)]
    public var sparkles: [(CGPoint, CGFloat, CGFloat)]
    public var pin: CGPoint, head: CGPoint
    public var wobble: CGFloat
    public var flash: CGFloat
    public var phase: CGFloat
    public var alpha: CGFloat
}

/// An organic selection bubble with real physics: a ring of masses on springs whose diameter runs between the two
/// points. It is surface-tension taut, so it jiggles and sloshes when you move or stop, never holding a perfect circle,
/// and a faint inner current keeps it alive when still. Commit: it contracts with a wobble and pops with ripples.
public struct JellySim: Sendable {
    public var base = SimBase()
    private static let n = 44
    private var r: [CGFloat] = []
    private var rv: [CGFloat] = []
    private var center = CGPoint.zero, cv = CGPoint.zero
    private var accel = CGPoint.zero
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) {
        base.start(pin)
        r = Array(repeating: 6, count: Self.n); rv = Array(repeating: 0, count: Self.n)
        center = pin; cv = .zero; accel = .zero
    }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) {
        guard dt > 0 else { return }
        base.advance(dt, pin, head)
        let mid = CGPoint(x: (pin.x + head.x) / 2, y: (pin.y + head.y) / 2)
        let target = max(18, hypot(head.x - pin.x, head.y - pin.y) / 2) * (base.fired ? (base.cancelled ? max(0, 1 - base.releaseT / 0.5) : 1 - 0.4 * sm(0, 0.18, base.releaseT)) : 1)
        // The centre follows the midpoint on a soft spring (so the bubble lags and sloshes).
        let ox = cv.x, oy = cv.y
        cv.x += (140 * (mid.x - center.x) - 14 * cv.x) * dt; cv.y += (140 * (mid.y - center.y) - 14 * cv.y) * dt
        center.x += cv.x * dt; center.y += cv.y * dt
        accel = CGPoint(x: (cv.x - ox) / dt, y: (cv.y - oy) / dt)
        let n = Self.n
        let aMag = hypot(accel.x, accel.y), aAng = atan2(accel.y, accel.x)
        for _ in 0..<2 {
            let h = dt / 2
            for i in 0..<n {
                let th = CGFloat(i) / CGFloat(n) * 2 * .pi
                let l = r[(i + n - 1) % n], rr = r[(i + 1) % n]
                // Spring to the rest radius, surface tension to the neighbours, and inertia from the centre's acceleration.
                var a = 150 * (target - r[i]) - 7 * rv[i] + 300 * ((l + rr) / 2 - r[i])
                a -= min(7000, aMag) * 0.11 * CGFloat(cos(Double(th - aAng)))
                // A slow internal current keeps it from ever sitting perfectly round.
                a += 40 * CGFloat(sin(Double(th * 3 + base.time * 2.1))) * (base.fired ? 0 : 1)
                rv[i] += a * h
            }
            for i in 0..<n { r[i] += rv[i] * h }
        }
    }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> JellyScene {
        let b = base
        let e = max(0, min(1, emerge))
        let tt = b.fired ? b.releaseT : 0
        let commit = b.fired && !b.cancelled
        var outline: [CGPoint] = []
        for i in 0..<Self.n {
            let th = CGFloat(i) / CGFloat(Self.n) * 2 * .pi
            let rr = max(2, r[i])
            outline.append(CGPoint(x: center.x + cos(th) * rr, y: center.y + sin(th) * rr))
        }
        var rip: [(CGFloat, CGFloat)] = []
        if commit { rip = [(max(20, r.reduce(0, +) / CGFloat(r.count)) * (1 + 1.4 * min(1, tt / 0.5)), max(0, 1 - tt / 0.5)), (max(20, r.reduce(0, +) / CGFloat(r.count)) * (1 + 0.8 * min(1, tt / 0.5)), max(0, 0.8 - tt / 0.5))] }
        let avg = r.reduce(0, +) / CGFloat(max(1, r.count))
        var sparkles: [(CGPoint, CGFloat, CGFloat)] = []
        for i in 0..<14 {
            let a = 6.28 * StyleHash.unit(i, 451) + b.time * (0.4 + 0.5 * StyleHash.unit(i, 452))
            let d = avg * (0.2 + 0.7 * StyleHash.unit(i, 453))
            sparkles.append((CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d), e * (0.3 + 0.7 * CGFloat(sin(Double(b.time * 2 + CGFloat(i))))) * 0.7, 2 + 2.5 * StyleHash.unit(i, 454)))
        }
        let wob = r.map { abs($0 - avg) }.reduce(0, +) / CGFloat(max(1, r.count))
        return JellyScene(outline: outline, center: center, radius: avg, ripples: rip, sparkles: sparkles, pin: b.pin, head: b.head, wobble: wob,
                          flash: commit ? max(0, 1 - tt / 0.3) : 0, phase: b.time, alpha: e * (b.fired ? max(0.001, 1 - sm(0.3, 0.7, tt)) : 1))
    }
}

// MARK: - Freehand lasso

public struct FreehandScene: Sendable {
    public var path: [CGPoint]
    public var closing: [CGPoint]
    public var pin: CGPoint, head: CGPoint
    public var closed: CGFloat
    public var sparkles: [(CGPoint, CGFloat, CGFloat)]
    public var flash: CGFloat
    public var phase: CGFloat
    public var alpha: CGFloat
}

/// The classic freehand selection lasso: it draws the path your cursor has taken, joins it back to where you started
/// with a dashed closing line that tightens as the loop completes, fills the enclosed region with a glowing wash, and
/// marches ants along the whole outline. Commit: the outline snaps shut and the area flashes.
public struct FreehandLassoSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> FreehandScene {
        let b = base
        let e = max(0, min(1, emerge))
        let tt = b.fired ? b.releaseT : 0
        let commit = b.fired && !b.cancelled
        // The path: from the start through everything you have drawn; thinned and lightly smoothed.
        var raw: [CGPoint] = [b.pin] + b.trail.map(\.p)
        if raw.count > 3 { raw = stride(from: 0, to: raw.count, by: max(1, raw.count / 140)).map { raw[$0] } + [raw[raw.count - 1]] }
        var smooth = raw
        if raw.count > 4 {
            for i in 1..<(raw.count - 1) { smooth[i] = CGPoint(x: (raw[i - 1].x + 2 * raw[i].x + raw[i + 1].x) / 4, y: (raw[i - 1].y + 2 * raw[i].y + raw[i + 1].y) / 4) }
        }
        let last = smooth.last ?? b.head
        let closed = commit ? sm(0, 0.25, tt) : 0
        var closing: [CGPoint] = []
        for j in 0...12 {
            let s = CGFloat(j) / 12
            let sag = (1 - closed) * 12 * CGFloat(sin(Double(.pi * s))) * CGFloat(sin(Double(b.time * 5 + s * 6)))
            closing.append(CGPoint(x: last.x + (b.pin.x - last.x) * s + sag, y: last.y + (b.pin.y - last.y) * s + sag * 0.6))
        }
        var sparkles: [(CGPoint, CGFloat, CGFloat)] = []
        for i in 0..<16 where smooth.count > 3 {
            let s = (b.time * 0.25 + CGFloat(i) / 16).truncatingRemainder(dividingBy: 1)
            let idx = min(smooth.count - 1, Int(s * CGFloat(smooth.count)))
            sparkles.append((smooth[idx], e * (0.35 + 0.65 * CGFloat(sin(Double(b.time * 5 + CGFloat(i) * 2)))) * 0.85, 2 + 3 * StyleHash.unit(i, 461)))
        }
        return FreehandScene(path: smooth, closing: closing, pin: b.pin, head: b.head, closed: closed, sparkles: sparkles,
                             flash: commit ? max(0, 1 - tt / 0.35) : 0, phase: b.time,
                             alpha: e * (b.fired ? max(0.001, 1 - sm(0.4, 0.8, tt)) : 1))
    }
}
