import CoreGraphics
import Foundation

private func sm(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { StyleHash.smoothstep(a, b, x) }

// MARK: - Tug of war

public struct TugScene: Sendable {
    public var rope: [CGPoint]
    public var flag: CGPoint
    public var flagAngle: CGFloat
    public var pin: CGPoint, head: CGPoint
    public var pinOffset: CGPoint, headOffset: CGPoint
    public var pinSize: CGFloat, headSize: CGFloat
    public var pinLean: CGFloat, headLean: CGFloat
    public var pinBob: CGFloat, headBob: CGFloat
    public var strain: CGFloat
    /// -1...1: negative when you push toward the pin (the rope goes slack), positive as you pull away (it goes taut).
    public var tension: CGFloat
    public var axis: CGFloat
    public var dust: [(CGPoint, CGFloat, CGFloat)]
    public var sweat: [(CGPoint, CGFloat, CGFloat)]
    public var snapped: CGFloat
    public var alpha: CGFloat
}

/// Two critters in a tug of war, with a feel of push and pull. The rope's tension follows how fast you pull away from
/// or push toward the pin: pull and the pin fighter is yanked forward (stumbling, then digging in) while the cursor's
/// fighter leans back harder; push and the rope goes slack, the pin fighter rocks back and the other lurches forward.
/// Both are on springs, so they overshoot and settle. When you are still they keep heaving in turn, and sweat flies
/// off them, more the harder the effort. The flag drifts toward the heavier end. Commit: the rope snaps and they tumble.
public struct TugOfWarSim: Sendable {
    public var base = SimBase()
    private var tension: CGFloat = 0
    private var prevChord: CGFloat = 0
    private var speedSmooth: CGFloat = 0
    private var slideA: CGFloat = 0, slideAV: CGFloat = 0
    private var slideB: CGFloat = 0, slideBV: CGFloat = 0
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.9 }
    public mutating func reset(pin: CGPoint) { base.start(pin); tension = 0; prevChord = 0; speedSmooth = 0; slideA = 0; slideAV = 0; slideB = 0; slideBV = 0 }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }
    /// The current effort, 0...1 (drives sweat and breathing).
    public var effort: CGFloat { min(1, 0.28 + abs(tension) / 520 + speedSmooth / 1600) }

    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) {
        guard dt > 0 else { return }
        let prevHead = base.head
        base.advance(dt, pin, head)
        let chord = hypot(head.x - pin.x, head.y - pin.y)
        let rate = prevChord > 0 || base.time > 0.05 ? (chord - prevChord) / dt : 0
        prevChord = chord
        tension += (max(-900, min(900, rate)) - tension) * min(1, 11 * dt)
        speedSmooth += (hypot(head.x - prevHead.x, head.y - prevHead.y) / dt - speedSmooth) * min(1, 8 * dt)
        // Springy stumbles. Pulling away drags the pin fighter toward the cursor and shoves the other back; pushing in
        // does the opposite. Underdamped on purpose, so they overshoot and settle.
        func spring(_ x: inout CGFloat, _ v: inout CGFloat, _ target: CGFloat) {
            let w: CGFloat = 15, z: CGFloat = 0.3
            v += (w * w * (target - x) - 2 * z * w * v) * dt; x += v * dt
        }
        spring(&slideA, &slideAV, max(-26, min(26, tension * 0.05)))
        spring(&slideB, &slideBV, max(-16, min(16, tension * 0.028)))
    }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> TugScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge)), reach = sm(30, 130, ax.chord)
        let tt = b.fired ? b.releaseT : 0
        let snapped: CGFloat = b.fired ? min(1, tt * 3) : 0
        let pm = b.rp * b.rp, hm = b.rh * b.rh
        let balance = (pm - hm) / (pm + hm)
        let T = max(-1, min(1, tension / 500))
        let effort = self.effort
        // A shared heave-ho rhythm that quickens with effort: the two fighters take turns hauling.
        let beat = b.time * (4.6 + 2.4 * effort)
        let heaveA = CGFloat(sin(Double(beat))), heaveB = CGFloat(sin(Double(beat + .pi)))
        let facing: CGFloat = ax.a.x >= 0 ? 1 : -1
        let up = CGPoint(x: 0, y: 1)
        // Offsets along the span (screen x/y), plus a small bounce on each heave.
        let offA = CGPoint(x: ax.a.x * slideA, y: ax.a.y * slideA)
        let offB = CGPoint(x: ax.a.x * slideB, y: ax.a.y * slideB)
        let bobA = 3.5 * max(0, heaveA) * (0.5 + effort), bobB = 3.5 * max(0, heaveB) * (0.5 + effort)
        let pinC = CGPoint(x: b.pin.x + offA.x, y: b.pin.y + offA.y + bobA)
        let headC = CGPoint(x: b.head.x + offB.x, y: b.head.y + offB.y + bobB)

        // The rope runs hand to hand. Taut when pulled, drooping when slack, always trembling a little.
        let handA = CGPoint(x: pinC.x + ax.a.x * b.rp * 1.35, y: pinC.y + ax.a.y * b.rp * 1.35)
        let handB = CGPoint(x: headC.x - ax.a.x * b.rh * 1.35, y: headC.y - ax.a.y * b.rh * 1.35)
        let slack = max(0, -T) * 0.9 + (1 - effort) * 0.12
        var rope: [CGPoint] = []
        let L = 30
        for j in 0...L {
            let s = CGFloat(j) / CGFloat(L)
            let tremble = CGFloat(sin(Double(s * 42 - b.time * 32))) * (0.8 + 2.2 * max(0, T)) * sin(.pi * s)
            let droop = -(slack * min(60, ax.chord * 0.16 + 14)) * 4 * s * (1 - s) - snapped * 70 * s * (1 - s)
            rope.append(CGPoint(x: handA.x + (handB.x - handA.x) * s, y: handA.y + (handB.y - handA.y) * s + droop + tremble * up.y))
        }
        let fs = max(0.12, min(0.88, 0.5 - 0.32 * balance - 0.16 * T + 0.012 * CGFloat(sin(Double(b.time * 7)))))
        let fi = min(L - 1, Int(fs * CGFloat(L)))
        let fp = rope[fi]

        // Lean: leaning back to resist. A hard pull yanks the pin fighter forward (the lean flips), a push rocks it back.
        var leanA = 0.2 - 0.34 * T + 0.07 * heaveA * (0.5 + effort)
        var leanB = 0.2 + 0.30 * T + 0.07 * heaveB * (0.5 + effort)
        leanA = max(-0.32, min(0.6, leanA)); leanB = max(-0.32, min(0.6, leanB))
        if b.fired { leanA = -0.7 * snapped; leanB = -0.7 * snapped }

        // Sweat: drops fly off each fighter's brow, more of them (and farther) the harder the effort.
        var sweat: [(CGPoint, CGFloat, CGFloat)] = []
        for who in 0..<2 {
            let c = who == 0 ? pinC : headC
            let R = who == 0 ? b.rp : b.rh
            let away: CGFloat = who == 0 ? -facing : facing                   // flung away from the opponent
            for j in 0..<9 {
                let seed = who * 31 + j
                let period = 0.55 + 0.5 * StyleHash.unit(seed, 601)
                let cyc = (b.time / period + StyleHash.unit(seed, 602))
                let age = cyc - floor(cyc)
                let cycleIndex = Int(floor(cyc))
                if StyleHash.unit(seed &* 13 &+ cycleIndex, 603) > effort * 0.95 + 0.1 { continue }      // fewer drops when relaxed
                let tau = age * period
                let kick = 1 + abs(T) * 0.9
                let vx = away * (30 + 60 * StyleHash.unit(seed &+ cycleIndex, 604)) * kick
                let vy = 70 + 90 * StyleHash.unit(seed &+ cycleIndex, 605)
                let x0 = c.x + away * R * 0.35 + (StyleHash.unit(seed, 606) - 0.5) * R * 0.6
                let y0 = c.y + R * 0.78
                let p = CGPoint(x: x0 + vx * tau, y: y0 + vy * tau - 0.5 * 520 * tau * tau)
                sweat.append((p, e * reach * pow(1 - age, 0.7) * (0.5 + 0.5 * effort), 2.6 + 2.4 * StyleHash.unit(seed, 607)))
            }
        }
        // Dust kicked up at the feet when they scramble.
        var dust: [(CGPoint, CGFloat, CGFloat)] = []
        for i in 0..<10 {
            let who = i % 2
            let c = who == 0 ? pinC : headC
            let R = who == 0 ? b.rp : b.rh
            let ph = (b.time * (1.2 + effort) + CGFloat(i) / 10).truncatingRemainder(dividingBy: 1)
            let away: CGFloat = who == 0 ? -facing : facing
            let strength = min(1, abs(T) * 1.3 + 0.15)
            dust.append((CGPoint(x: c.x + away * (R * 0.5 + 24 * ph), y: c.y - R * 1.0 + 12 * ph), e * reach * (1 - ph) * 0.5 * strength, 5 + 11 * ph))
        }
        return TugScene(rope: rope, flag: fp, flagAngle: 0.25 * CGFloat(sin(Double(b.time * 5))) + 0.5 * T, pin: b.pin, head: b.head, pinOffset: CGPoint(x: offA.x, y: offA.y + bobA),
                        headOffset: CGPoint(x: offB.x, y: offB.y + bobB), pinSize: b.rp, headSize: b.rh * (1 + 0.1 * headGlow), pinLean: leanA, headLean: leanB,
                        pinBob: bobA, headBob: bobB, strain: effort, tension: T, axis: atan2(ax.a.y, ax.a.x), dust: dust, sweat: sweat, snapped: snapped,
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
        let hang = CGPoint(x: 0, y: -1)                       // balls always hang straight down
        let H = stringLen * 0.55
        let top0 = CGPoint(x: mid.x, y: mid.y + H)
        let omega: CGFloat = 4.2
        let ph = b.time * omega
        let amp: CGFloat = 0.62
        let swingL = max(0, CGFloat(sin(Double(ph)))) * amp                    // first ball swings out then back
        let swingR = max(0, CGFloat(-sin(Double(ph)))) * amp
        var balls: [(CGPoint, CGFloat)] = [], tops: [CGPoint] = []
        for i in 0..<n {
            let x = (CGFloat(i) - CGFloat(n - 1) / 2) * r * 2
            let top = CGPoint(x: top0.x + x, y: top0.y)
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
        let left = min(b.pin.x, b.head.x), right = max(b.pin.x, b.head.x)
        let barHalf = max((right - left) / 2, span / 2 + 14)
        let barA = CGPoint(x: top0.x - barHalf, y: top0.y)
        let barB = CGPoint(x: top0.x + barHalf, y: top0.y)
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
        // The gondola always hangs straight down from its pulley (gravity), swinging a little.
        let hangLen = b.bodyRadius * 1.1
        var car = CGPoint(x: p.x + sin(swing) * hangLen, y: p.y - cos(swing) * hangLen)
        if b.fired { car.x += b.releaseDir.x * 900 * b.releaseT; car.y += b.releaseDir.y * 900 * b.releaseT }
        let cA = (0...32).map { cable(CGFloat($0) / 32, topY) }, cB = (0...32).map { cable(CGFloat($0) / 32, topY - 3.5) }
        return CableScene(cableA: cA, cableB: cB, car: car, carAngle: swing + slope * 0, carSwing: swing,
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
