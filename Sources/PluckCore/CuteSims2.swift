import CoreGraphics
import Foundation

private func sm(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { StyleHash.smoothstep(a, b, x) }

// MARK: - Tug of war

public struct TugScene: Sendable {
    public var rope: [CGPoint]
    public var flag: CGPoint
    public var flagAngle: CGFloat
    public var pin: CGPoint, head: CGPoint
    public var pinSize: CGFloat, headSize: CGFloat
    public var pinLean: CGFloat, headLean: CGFloat
    public var strain: CGFloat
    public var axis: CGFloat
    public var dust: [(CGPoint, CGFloat, CGFloat)]
    public var snapped: CGFloat
    public var alpha: CGFloat
}

/// Two critters in a tug of war. The rope's flag drifts toward whoever is heavier (the pin, by mass), both strain and
/// lean back, and dust puffs from their feet. Commit: the rope snaps and they tumble backward.
public struct TugOfWarSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.9 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> TugScene {
        let b = base, ax = b.axes, up = b.up()
        let e = max(0, min(1, emerge)), reach = sm(30, 130, ax.chord)
        let pm = b.rp * b.rp, hm = b.rh * b.rh
        let balance = (pm - hm) / (pm + hm)                       // + means the pin is winning
        let strain = 0.6 + 0.4 * CGFloat(sin(Double(b.time * 9)))
        let snapped: CGFloat = b.fired ? min(1, b.releaseT * 3) : 0
        var rope: [CGPoint] = []
        let L = 28
        for j in 0...L {
            let s = CGFloat(j) / CGFloat(L)
            let tremble = CGFloat(sin(Double(s * 40 - b.time * 30))) * 1.4 * strain * sin(.pi * s)
            let droop = -(1 - strain * 0.8) * min(14, ax.chord * 0.03) * 4 * s * (1 - s) - snapped * 60 * s * (1 - s)
            rope.append(CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s + up.x * (tremble + droop), y: b.pin.y + (b.head.y - b.pin.y) * s + up.y * (tremble + droop)))
        }
        let fs = max(0.12, min(0.88, 0.5 - 0.32 * balance + 0.012 * CGFloat(sin(Double(b.time * 7)))))
        let fi = min(L - 1, Int(fs * CGFloat(L)))
        let fp = rope[fi]
        let leanBase: CGFloat = 0.16 + 0.12 * strain
        var out: [(CGPoint, CGFloat, CGFloat)] = []
        for i in 0..<10 {
            let ph = (b.time * 1.7 + CGFloat(i) / 10).truncatingRemainder(dividingBy: 1)
            let (c, r, dir): (CGPoint, CGFloat, CGFloat) = i % 2 == 0 ? (b.pin, b.rp, -1) : (b.head, b.rh, 1)
            out.append((CGPoint(x: c.x - ax.a.x * dir * -1 * r * 0.4 + ax.a.x * dir * 0 + ax.a.x * (-dir) * (r * 0.5 + 18 * ph) * -1 * -1 + up.x * (-r * 0.9 + 14 * ph),
                                y: c.y + ax.a.y * (-dir) * (r * 0.5 + 18 * ph) * -1 * -1 * 0 + up.y * (-r * 0.9 + 14 * ph) - ax.a.y * dir * (r * 0.5 + 18 * ph) * -1),
                        e * reach * (1 - ph) * 0.6, 5 + 10 * ph))
        }
        return TugScene(rope: rope, flag: fp, flagAngle: atan2(up.y, up.x) - .pi / 2 + 0.2 * CGFloat(sin(Double(b.time * 5))), pin: b.pin, head: b.head,
                        pinSize: b.rp, headSize: b.rh * (1 + 0.1 * headGlow), pinLean: leanBase * (b.fired ? -3 * snapped : 1),
                        headLean: leanBase * (b.fired ? -3 * snapped : 1), strain: strain, axis: atan2(ax.a.y, ax.a.x), dust: out, snapped: snapped,
                        alpha: e * b.fade(1.0) * (reach > 0.02 ? 1 : 0.0001))
    }
}

// MARK: - Newton's cradle

public struct CradleScene: Sendable {
    public var barA: CGPoint, barB: CGPoint
    public var balls: [(CGPoint, CGFloat)]
    public var tops: [CGPoint]
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var clicks: [(CGPoint, CGFloat)]
    public var alpha: CGFloat
}

public struct NewtonsCradleSim: Sendable {
    public var base = SimBase()
    public var count = 5
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> CradleScene {
        let b = base, ax = b.axes, up = b.up()
        let e = max(0, min(1, emerge)), reach = sm(40, 160, ax.chord)
        let n = count
        let r = max(8, min(26, ax.chord / CGFloat(n) * 0.5 * 0.96))
        let span = r * 2 * CGFloat(n)
        let mid = CGPoint(x: (b.pin.x + b.head.x) / 2, y: (b.pin.y + b.head.y) / 2)
        let stringLen = max(60, min(170, ax.chord * 0.5 + 20))
        let hang = CGPoint(x: -up.x, y: -up.y)
        let H = stringLen * 0.55
        let top0 = CGPoint(x: mid.x + up.x * H, y: mid.y + up.y * H)
        let omega: CGFloat = 4.2
        let ph = b.time * omega
        let amp: CGFloat = 0.62
        let swingL = max(0, CGFloat(sin(Double(ph)))) * amp                    // first ball swings out then back
        let swingR = max(0, CGFloat(-sin(Double(ph)))) * amp
        var balls: [(CGPoint, CGFloat)] = [], tops: [CGPoint] = []
        for i in 0..<n {
            let x = (CGFloat(i) - CGFloat(n - 1) / 2) * r * 2
            let top = CGPoint(x: top0.x + ax.a.x * x, y: top0.y + ax.a.y * x)
            var th: CGFloat = 0
            if i == 0 { th = -swingL } else if i == n - 1 { th = swingR }
            // The ball hangs along `hang`, rotated by th about its top.
            let hx = hang.x * cos(th) - hang.y * sin(th), hy = hang.x * sin(th) + hang.y * cos(th)
            let c = CGPoint(x: top.x + hx * stringLen, y: top.y + hy * stringLen)
            balls.append((c, r)); tops.append(top)
        }
        var clicks: [(CGPoint, CGFloat)] = []
        let hit = max(0, 1 - abs(CGFloat(sin(Double(ph)))) / 0.08)
        if hit > 0.02, let c = balls.dropFirst(n / 2).first { clicks.append((c.0, e * hit)) }
        _ = span
        // The frame spans the two points: posts stand at the pin and head, and the bar runs between their tops.
        let barA = CGPoint(x: b.pin.x + up.x * H, y: b.pin.y + up.y * H)
        let barB = CGPoint(x: b.head.x + up.x * H, y: b.head.y + up.y * H)
        _ = span
        var shift = CGPoint.zero
        if b.fired { shift = CGPoint(x: b.releaseDir.x * 700 * b.releaseT, y: b.releaseDir.y * 700 * b.releaseT) }
        let sh: (CGPoint) -> CGPoint = { CGPoint(x: $0.x + shift.x, y: $0.y + shift.y) }
        return CradleScene(barA: sh(barA), barB: sh(barB), balls: balls.map { (sh($0.0), $0.1) }, tops: tops.map(sh), pin: b.pin, head: b.head,
                           pinRadius: b.rp, headRadius: b.rh * (1 + 0.1 * headGlow), clicks: clicks, alpha: e * b.fade(0.8) * (reach > 0.02 ? 1 : 0.0001))
    }
}

// MARK: - Rainbow

public struct RainbowScene: Sendable {
    public var bands: [[CGPoint]]
    public var bandWidth: CGFloat
    public var cloudPin: [(CGPoint, CGFloat)]
    public var cloudHead: [(CGPoint, CGFloat)]
    public var sparkles: [(CGPoint, CGFloat, CGFloat)]
    public var draw: CGFloat
    public var alpha: CGFloat
}

public struct RainbowSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.9 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> RainbowScene {
        let b = base, ax = b.axes, up = b.up()
        let e = max(0, min(1, emerge)), reach = sm(30, 140, ax.chord)
        let arch = min(200, 24 + ax.chord * 0.3)
        let w: CGFloat = max(5, min(12, 4 + ax.chord * 0.02))
        let draw = reach * (b.fired ? max(0, 1 - b.releaseT / 0.8) : 1)
        var bands: [[CGPoint]] = []
        for k in 0..<7 {
            let off = (CGFloat(k) - 3) * w * 0.95
            var pts: [CGPoint] = []
            let steps = 40
            let upto = Int(CGFloat(steps) * min(1, draw * 1.0))
            for j in 0...upto {
                let s = CGFloat(j) / CGFloat(steps)
                let h = arch * 4 * s * (1 - s) + off * (0.4 + 0.6 * sin(.pi * s)) + 2 * CGFloat(sin(Double(s * 12 - b.time * 2))) * sin(.pi * s)
                pts.append(CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s + up.x * h, y: b.pin.y + (b.head.y - b.pin.y) * s + up.y * h))
            }
            bands.append(pts)
        }
        func cloud(_ c: CGPoint, _ r: CGFloat) -> [(CGPoint, CGFloat)] {
            [(CGPoint(x: c.x, y: c.y), r * 0.9), (CGPoint(x: c.x - r * 0.9, y: c.y - r * 0.2), r * 0.62), (CGPoint(x: c.x + r * 0.9, y: c.y - r * 0.2), r * 0.66),
             (CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.45), r * 0.6), (CGPoint(x: c.x + r * 0.4, y: c.y + r * 0.4), r * 0.55)]
        }
        let bob = 2.5 * CGFloat(sin(Double(b.time * 1.4)))
        var sparkles: [(CGPoint, CGFloat, CGFloat)] = []
        for i in 0..<18 {
            let s = StyleHash.unit(i, 191)
            let h = arch * 4 * s * (1 - s) + (StyleHash.unit(i, 192) - 0.5) * 50
            let tw = 0.5 + 0.5 * CGFloat(sin(Double(b.time * (2 + 3 * StyleHash.unit(i, 193)) + CGFloat(i))))
            sparkles.append((CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s + up.x * h, y: b.pin.y + (b.head.y - b.pin.y) * s + up.y * h),
                             e * draw * (s < draw ? 1 : 0) * tw, 4 + 5 * StyleHash.unit(i, 194)))
        }
        return RainbowScene(bands: bands, bandWidth: w, cloudPin: cloud(CGPoint(x: b.pin.x, y: b.pin.y + bob), b.rp * 0.8),
                            cloudHead: cloud(CGPoint(x: b.head.x, y: b.head.y - bob), b.rh * 0.8 * (1 + 0.1 * headGlow)), sparkles: sparkles, draw: draw, alpha: e)
    }
}

// MARK: - Dandelion

public struct SeedState: Sendable { public var position: CGPoint; public var angle: CGFloat; public var size: CGFloat; public var alpha: CGFloat }

public struct DandelionScene: Sendable {
    public var ball: CGPoint, ballRadius: CGFloat
    public var seedAngles: [CGFloat]
    public var flying: [SeedState]
    public var sprout: CGPoint, sproutHeight: CGFloat, bloom: CGFloat, sproutRadius: CGFloat
    public var alpha: CGFloat
}

public struct DandelionSim: Sendable {
    public var base = SimBase()
    public var seeds = 28
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.9 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> DandelionScene {
        let b = base, ax = b.axes, up = b.up()
        let e = max(0, min(1, emerge)), reach = sm(30, 140, ax.chord)
        let restR = b.bodyRadius
        let frac = max(0.05, min(1, (b.mass.sol.pin / restR) * (b.mass.sol.pin / restR)))      // how much of the puffball is left
        let keep = max(0, Int((CGFloat(seeds) * min(1, frac * 1.15)).rounded()))
        var angles: [CGFloat] = []
        for i in 0..<keep { angles.append(6.2832 * (CGFloat(i) + 0.4 * StyleHash.unit(i, 201)) / CGFloat(seeds)) }
        var flying: [SeedState] = []
        let arch = min(120, 20 + ax.chord * 0.2) * reach
        for i in 0..<14 {
            let period = 4.5 + 2 * StyleHash.unit(i, 202)
            let p = (b.time / period + StyleHash.unit(i, 203)).truncatingRemainder(dividingBy: 1)
            let drift = 14 * CGFloat(sin(Double(p * 9 + CGFloat(i))))
            let h = arch * 4 * p * (1 - p) * (0.6 + 0.8 * StyleHash.unit(i, 204)) + drift
            var pos = CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * p + up.x * h, y: b.pin.y + (b.head.y - b.pin.y) * p + up.y * h)
            if b.fired { pos.x += b.releaseDir.x * 500 * b.releaseT; pos.y += b.releaseDir.y * 500 * b.releaseT + 80 * b.releaseT }
            let tilt = 0.5 * CGFloat(sin(Double(p * 7 + CGFloat(i)))) + (ax.a.y > 0 ? 0 : 0)
            flying.append(SeedState(position: pos, angle: tilt, size: max(10, b.bodyRadius * 0.55), alpha: e * reach * sin(.pi * p) * b.fade(0.9)))
        }
        let grown = max(0, min(1, 1 - frac)) * reach
        return DandelionScene(ball: b.pin, ballRadius: b.rp * (0.55 + 0.45 * min(1, frac * 1.2)), seedAngles: angles, flying: flying,
                              sprout: b.head, sproutHeight: b.rh * (0.8 + 2.2 * grown) * (1 + 0.08 * headGlow), bloom: grown, sproutRadius: b.rh,
                              alpha: e * (b.fired ? max(0.001, b.fade(1.0)) : 1))
    }
}

// MARK: - Cable car

public struct CableScene: Sendable {
    public var cableA: [CGPoint], cableB: [CGPoint]
    public var car: CGPoint, carAngle: CGFloat, carSwing: CGFloat, carSize: CGFloat
    public var pulley: CGPoint
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var upDir: CGPoint
    public var alpha: CGFloat
}

public struct CableCarSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.9 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> CableScene {
        let b = base, ax = b.axes, up = b.up()
        let e = max(0, min(1, emerge)), reach = sm(40, 160, ax.chord)
        let sag = min(40, ax.chord * 0.05) * reach
        func cable(_ s: CGFloat, _ off: CGFloat) -> CGPoint {
            let h = -sag * 4 * s * (1 - s) + off
            return CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s + up.x * h, y: b.pin.y + (b.head.y - b.pin.y) * s + up.y * h)
        }
        let topY = b.bodyRadius * 1.3
        let period: CGFloat = 9
        let cyc = (b.time / period).truncatingRemainder(dividingBy: 1)
        let w = cyc < 0.5 ? cyc * 2 : 2 - cyc * 2
        let ease = w * w * (3 - 2 * w)
        let s = 0.1 + 0.8 * ease
        let speed = abs(sin(.pi * 2 * cyc))                                    // 0 at the stations, fast in the middle
        let dirSign: CGFloat = cyc < 0.5 ? 1 : -1
        let swing = (-dirSign * 0.12 * speed + 0.05 * CGFloat(sin(Double(b.time * 2.2)))) * reach
        let p = cable(s, topY)
        let q = cable(min(1, s + 0.01), topY)
        let slope = atan2(q.y - p.y, q.x - p.x)
        var car = CGPoint(x: p.x - up.x * b.bodyRadius * 1.1 * cos(swing) + ax.a.x * sin(swing) * b.bodyRadius * 1.1,
                          y: p.y - up.y * b.bodyRadius * 1.1 * cos(swing) + ax.a.y * sin(swing) * b.bodyRadius * 1.1)
        if b.fired { car.x += b.releaseDir.x * 900 * b.releaseT; car.y += b.releaseDir.y * 900 * b.releaseT }
        let cA = (0...32).map { cable(CGFloat($0) / 32, topY) }, cB = (0...32).map { cable(CGFloat($0) / 32, topY - 3.5) }
        return CableScene(cableA: cA, cableB: cB, car: car, carAngle: atan2(up.y, up.x) - .pi / 2 + swing + slope * 0, carSwing: swing,
                          carSize: b.bodyRadius * 0.9, pulley: p, pin: b.pin, head: b.head, pinRadius: b.rp, headRadius: b.rh * (1 + 0.1 * headGlow),
                          upDir: up, alpha: e * b.fade(0.9) * (reach > 0.02 ? 1 : 0.0001))
    }
}

// MARK: - Signal

public struct SignalScene: Sendable {
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var waves: [(CGPoint, CGFloat, CGFloat, CGFloat)]        // centre, radius, alpha, facing angle
    public var packets: [(CGPoint, CGFloat, Int)]
    public var strength: CGFloat
    public var line: [CGPoint]
    public var alpha: CGFloat
}

public struct SignalSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> SignalScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge)), reach = sm(30, 130, ax.chord)
        var waves: [(CGPoint, CGFloat, CGFloat, CGFloat)] = []
        for k in 0..<4 {
            let ph = (b.time * 0.9 + CGFloat(k) / 4).truncatingRemainder(dividingBy: 1)
            waves.append((b.pin, b.rp * (0.8 + 2.6 * ph), e * (1 - ph) * 0.9, atan2(ax.a.y, ax.a.x)))
            let ph2 = (b.time * 0.9 + CGFloat(k) / 4 + 0.5).truncatingRemainder(dividingBy: 1)
            waves.append((b.head, b.rh * (0.8 + 2.6 * ph2), e * (1 - ph2) * 0.9, atan2(ax.a.y, ax.a.x) + .pi))
        }
        var packets: [(CGPoint, CGFloat, Int)] = []
        for i in 0..<9 {
            let dirSign: CGFloat = i % 2 == 0 ? 1 : -1
            let p = (b.time * (0.45 + 0.1 * StyleHash.unit(i, 211)) + StyleHash.unit(i, 212)).truncatingRemainder(dividingBy: 1)
            let s = dirSign > 0 ? p : 1 - p
            var pos = CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s + ax.n.x * dirSign * 5, y: b.pin.y + (b.head.y - b.pin.y) * s + ax.n.y * dirSign * 5)
            if b.fired { pos.x += b.releaseDir.x * 600 * b.releaseT; pos.y += b.releaseDir.y * 600 * b.releaseT }
            packets.append((pos, e * reach * sin(.pi * p) * b.fade(0.7), i % 3))
        }
        // The signal weakens with distance (and the pin's heavier "transmitter" holds it longer).
        let strength = max(0.15, 1 - ax.chord / 1500)
        return SignalScene(pin: b.pin, head: b.head, pinRadius: b.rp, headRadius: b.rh * (1 + 0.1 * headGlow), waves: waves, packets: packets,
                           strength: strength, line: [b.pin, b.head], alpha: e * b.fade(0.8))
    }
}
