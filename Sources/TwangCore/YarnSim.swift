import CoreGraphics
import Foundation

private func sm(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { StyleHash.smoothstep(a, b, x) }

/// Everything the renderer needs to draw one frame of the ball of thread.
public struct YarnScene: Sendable {
    public var ballCenter: CGPoint, ballRadius: CGFloat, ballSpin: CGFloat
    /// The thread from the ball's surface to where it meets the lasso loop.
    public var thread: [CGPoint]
    /// The lasso loop that ends the thread, and the honda knot where the thread joins it.
    public var loopCenter: CGPoint, loopRadius: CGFloat, knot: CGPoint
    /// A loose end curling off the ball.
    public var tail: [CGPoint]
    /// Moves the twisted-fibre highlight along the thread.
    public var twist: CGFloat
    public var sparks: [(CGPoint, CGFloat, CGFloat)]
    public var flash: CGFloat, flashCenter: CGPoint
    public var alpha: CGFloat
}

/// A ball of thread sits at the pin. Stretch and the thread unspools toward the cursor, ending in a lasso loop; the
/// ball shrinks as thread is let out and rolls as it feeds. The thread sags when you move slowly and pulls taut and
/// whips sideways when you move fast. Commit: the loop is thrown along the pull, cinches shut with a flash, and the
/// thread winds back into the ball. Cancel: the thread simply rewinds.
public struct YarnLassoSim: Sendable {
    public var base = SimBase()
    var swing: CGFloat = 0, swingV: CGFloat = 0
    var spin: CGFloat = 0
    var fed: CGFloat = 0
    var vel = CGPoint.zero
    var last = CGPoint.zero
    public init() {}

    public var isFinished: Bool { base.releaseT > 1.0 }
    public mutating func reset(pin: CGPoint) {
        base.start(pin); swing = 0; swingV = 0; spin = 0; fed = 0; vel = .zero; last = pin
    }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    /// Where the loop is right now: at the cursor, thrown past it on a commit, then reeled back to the ball.
    func effectiveHead() -> CGPoint {
        var h = base.head
        let tt = base.releaseT
        guard base.fired else { return h }
        if !base.cancelled {
            let d = base.releaseDir
            let len = max(1e-4, hypot(d.x, d.y))
            let throwDist = 70 * sm(0, 0.18, tt)
            h = CGPoint(x: h.x + d.x / len * throwDist, y: h.y + d.y / len * throwDist)
        }
        let start: CGFloat = base.cancelled ? 0 : 0.36
        let rw = sm(start, start + 0.5, tt)
        return CGPoint(x: h.x + (base.pin.x - h.x) * rw, y: h.y + (base.pin.y - h.y) * rw)
    }

    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) {
        base.advance(dt, pin, head)
        let h = max(dt, 1.0 / 240)
        let raw = CGPoint(x: (head.x - last.x) / h, y: (head.y - last.y) / h)
        let k = 1 - CGFloat(pow(0.55, Double(dt * 60)))
        vel = CGPoint(x: vel.x + (raw.x - vel.x) * k, y: vel.y + (raw.y - vel.y) * k)
        last = head

        let eh = effectiveHead()
        let ax = Axes(pin: base.pin, head: eh)
        // Sideways motion pushes the middle of the thread to the other side, then it swings back.
        let lat = vel.x * ax.n.x + vel.y * ax.n.y
        let target = max(-70, min(70, -lat * 0.06))
        let sub = max(1, Int(ceil(dt / (1.0 / 240))))
        let hh = dt / CGFloat(sub)
        for _ in 0..<sub {
            let a = 140 * (target - swing) - 9 * swingV
            swingV += a * hh
            swing += swingV * hh
        }
        // Thread fed out follows the stretch; the ball rolls by exactly the length that passes.
        let before = fed
        fed += (ax.chord - fed) * min(1, dt * 16)
        let r = max(8, ballRadius())
        spin += (fed - before) / r
    }

    func ballRadius() -> CGFloat {
        let r0 = max(14, base.bodyRadius * 0.9)
        return r0 * (0.46 + 0.54 * CGFloat(sqrt(Double(max(0, 1 - sm(0, 900, fed))))))
    }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> YarnScene {
        let b = base
        let e = max(0, min(1, emerge))
        let tt = b.fired ? b.releaseT : 0
        let commit = b.fired && !b.cancelled
        let eh = effectiveHead()
        let ax = Axes(pin: b.pin, head: eh)
        let u = ax.a, n = ax.n
        let R = ballRadius() * (0.35 + 0.65 * e)

        // Loop radius: calm at rest, swelling as it is thrown, then cinching shut.
        var loopFactor: CGFloat = 1
        if commit { loopFactor = (1 + 0.8 * sm(0, 0.14, tt)) * (1 - 0.82 * sm(0.18, 0.32, tt)) }
        else if b.fired { loopFactor = 1 - 0.5 * sm(0, 0.5, tt) }
        let loopR = max(2, min(28, 13 + ax.chord * 0.03) * loopFactor * (1 + 0.1 * headGlow))

        let start = CGPoint(x: b.pin.x + u.x * R * 0.95, y: b.pin.y + u.y * R * 0.95)
        let entry = CGPoint(x: eh.x - u.x * loopR, y: eh.y - u.y * loopR)
        let span = hypot(entry.x - start.x, entry.y - start.y)
        let speed = hypot(vel.x, vel.y)
        let taut = b.fired ? 1 : sm(120, 900, speed)
        let sag = min(70, 0.16 * span) * (1 - 0.85 * taut) * (b.fired ? 1 - sm(0.36, 0.86, tt) : 1)
        let g = CGPoint(x: 0, y: -1)
        let d = CGPoint(x: entry.x - start.x, y: entry.y - start.y)
        let c1 = CGPoint(x: start.x + d.x * 0.33 + g.x * sag * 1.3 + n.x * swing,
                         y: start.y + d.y * 0.33 + g.y * sag * 1.3 + n.y * swing)
        let c2 = CGPoint(x: start.x + d.x * 0.66 + g.x * sag * 1.3 + n.x * swing * 0.8,
                         y: start.y + d.y * 0.66 + g.y * sag * 1.3 + n.y * swing * 0.8)
        var thread: [CGPoint] = []
        let steps = 30
        let rip = 0.7 + 3.2 * taut
        for i in 0...steps {
            let s = CGFloat(i) / CGFloat(steps), m = 1 - s
            let x = m * m * m * start.x + 3 * m * m * s * c1.x + 3 * m * s * s * c2.x + s * s * s * entry.x
            let y = m * m * m * start.y + 3 * m * m * s * c1.y + 3 * m * s * s * c2.y + s * s * s * entry.y
            let w = rip * CGFloat(sin(Double(.pi * s))) * CGFloat(sin(Double(b.time * 9 - s * 10)))
            thread.append(CGPoint(x: x + n.x * w, y: y + n.y * w))
        }

        // The loose end: a short curl hanging off the back of the ball.
        let th = atan2(-u.y, -u.x) + 0.8
        let t0 = CGPoint(x: b.pin.x + CGFloat(cos(Double(th))) * R, y: b.pin.y + CGFloat(sin(Double(th))) * R)
        var tail: [CGPoint] = []
        for i in 0..<9 {
            let f = CGFloat(i)
            let wave = CGFloat(sin(Double(b.time * 3 + f * 0.9))) * f * 0.7
            tail.append(CGPoint(x: t0.x + CGFloat(cos(Double(th))) * f * 4.2 - CGFloat(sin(Double(th))) * wave,
                                y: t0.y + CGFloat(sin(Double(th))) * f * 4.2 + CGFloat(cos(Double(th))) * wave - f * f * 0.35))
        }

        // Landing: a flash and a ring of sparks when the loop cinches.
        var sparks: [(CGPoint, CGFloat, CGFloat)] = []
        var flash: CGFloat = 0
        if commit && tt > 0.18 {
            let p = (tt - 0.2) / 0.5
            flash = max(0, 1 - p) * sm(0.18, 0.22, tt)
            if p < 1 {
                for i in 0..<10 {
                    let a = CGFloat(i) / 10 * 2 * .pi + StyleHash.unit(i, 811) * 0.5
                    let rr = 10 + 60 * max(0, p)
                    sparks.append((CGPoint(x: eh.x + CGFloat(cos(Double(a))) * rr, y: eh.y + CGFloat(sin(Double(a))) * rr),
                                   max(0, 1 - p) * 0.9, 2.5 + 2 * StyleHash.unit(i, 812)))
                }
            }
        }
        let fade = b.fired ? 1 - sm(0.8, 1.0, tt) : 1
        return YarnScene(ballCenter: b.pin, ballRadius: R, ballSpin: spin, thread: thread,
                         loopCenter: eh, loopRadius: loopR, knot: entry, tail: tail, twist: b.time * 22,
                         sparks: sparks, flash: flash, flashCenter: eh, alpha: e * fade)
    }
}
