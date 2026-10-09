import CoreGraphics
import Foundation

private func sm(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { StyleHash.smoothstep(a, b, x) }
private func tri(_ x: CGFloat) -> CGFloat { let f = x - floor(x); return f < 0.5 ? f * 2 : 2 - f * 2 }

/// Common plumbing for the sprite styles: positions, mass flow, clock, release.
public struct TrailPoint: Sendable { public var p: CGPoint; public var t: CGFloat }

public struct SimBase: Sendable {
    /// Recent head positions (about the last three seconds), for the styles that draw where you have been.
    public var trail: [TrailPoint] = []
    public var pin = CGPoint.zero, head = CGPoint.zero
    var mass = MassFlow()
    public var time: CGFloat = 0
    public var releaseT: CGFloat = -1
    public var releaseDir = CGPoint(x: 1, y: 0)
    public var bodyRadius: CGFloat = 30
    public var dumbbell = DumbbellMass.Params()

    mutating func start(_ p: CGPoint) {
        pin = p; head = p; time = 0; releaseT = -1; mass = MassFlow(); trail = []
        mass.sol = DumbbellMass.solve(dumbbell, length: 0)
    }
    mutating func advance(_ dt: CGFloat, _ newPin: CGPoint, _ newHead: CGPoint) {
        time += dt; pin = newPin; head = newHead
        if trail.last.map({ hypot($0.p.x - newHead.x, $0.p.y - newHead.y) > 1.2 }) ?? true { trail.append(TrailPoint(p: newHead, t: time)) }
        while let f = trail.first, time - f.t > 3 { trail.removeFirst() }
        mass.update(chord: hypot(head.x - pin.x, head.y - pin.y), dt: dt, params: dumbbell, bodyRadius: bodyRadius)
        if releaseT >= 0 { releaseT += dt }
    }
    /// A commit carries the pull direction; a cancel has none, so things dissolve or settle in place instead of flying off.
    mutating func fire(_ d: CGPoint?) { releaseT = 0; releaseDir = d ?? .zero; cancelled = d == nil }
    public var cancelled = false
    var axes: Axes { Axes(pin: pin, head: head) }
    var rp: CGFloat { max(9, mass.sol.pin) }
    var rh: CGFloat { max(7, mass.sol.head) }
    var fired: Bool { releaseT >= 0 }
    func fade(_ dur: CGFloat) -> CGFloat { releaseT >= 0 ? max(0, 1 - releaseT / dur) : 1 }
    func up() -> CGPoint {
        let a = axes
        var u = a.n
        if u.y < 0 || (abs(u.y) < 1e-6 && u.x < 0) { u = CGPoint(x: -u.x, y: -u.y) }
        return u
    }
}

// MARK: - Ping-pong

public struct PingPongScene: Equatable, Sendable {
    public var ball: CGPoint, ballRadius: CGFloat
    public var trail: [(CGPoint, CGFloat)]
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var paddleAngle: CGFloat
    public var pinKick: CGFloat, headKick: CGFloat
    public var sparks: [(CGPoint, CGFloat)]
    public var alpha: CGFloat
    public static func == (a: PingPongScene, b: PingPongScene) -> Bool { a.ball == b.ball && a.alpha == b.alpha }
}

public struct PingPongSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.7 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> PingPongScene {
        let b = base, ax = b.axes, up = b.up()
        let e = max(0, min(1, emerge)), reach = sm(30, 130, ax.chord)
        let period: CGFloat = 1.15
        func pos(_ t: CGFloat) -> CGPoint {
            let u = tri(t / period)                                  // 0 at the pin, 1 at the head, back
            let arch = min(70, 14 + ax.chord * 0.14) * 4 * u * (1 - u) * (u < 0.5 ? 1 : 1)
            let bounceDip = -abs(CGFloat(sin(Double(u * .pi * 3)))) * 0   // keep it clean
            let s = (b.rp * 0.9) / max(1, ax.chord)
            let uu = s + (1 - 2 * s) * u
            return CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * uu + up.x * (arch + bounceDip),
                           y: b.pin.y + (b.head.y - b.pin.y) * uu + up.y * (arch + bounceDip))
        }
        var t = b.time
        var ballPos = pos(t)
        var fadeBall: CGFloat = 1
        if b.fired {
            // Smash: the ball is hit off along the pull.
            let r = b.releaseT
            let base = pos(period * 0.5 * 1)
            ballPos = CGPoint(x: base.x + b.releaseDir.x * 1400 * r, y: base.y + b.releaseDir.y * 1400 * r)
            t = b.time
            fadeBall = max(0, 1 - r / 0.6)
        }
        var trail: [(CGPoint, CGFloat)] = []
        for k in 1...16 {
            let tt = t - CGFloat(k) * 0.022
            let p = b.fired ? CGPoint(x: ballPos.x - b.releaseDir.x * 40 * CGFloat(k), y: ballPos.y - b.releaseDir.y * 40 * CGFloat(k)) : pos(tt)
            trail.append((p, e * reach * fadeBall * (1 - CGFloat(k) / 17) * 0.8))
        }
        let phase = (b.time / period).truncatingRemainder(dividingBy: 1)
        func hit(_ x: CGFloat) -> CGFloat { max(0, 1 - abs(x) / 0.09) }
        let pinHit = max(hit(phase), hit(phase - 1)), headHit = hit(phase - 0.5)
        var sparks: [(CGPoint, CGFloat)] = []
        for (c, h, dir) in [(b.pin, pinHit, CGFloat(1)), (b.head, headHit, CGFloat(-1))] where h > 0.02 {
            for i in 0..<6 {
                let a = atan2(ax.a.y, ax.a.x) + (dir > 0 ? 0 : .pi) + (CGFloat(i) - 2.5) * 0.4
                let d = 14 + 30 * (1 - h)
                sparks.append((CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d), e * h))
            }
        }
        return PingPongScene(ball: ballPos, ballRadius: max(8, b.bodyRadius * 0.34), trail: trail, pin: b.pin, head: b.head,
                             pinRadius: b.rp, headRadius: b.rh * (1 + 0.1 * headGlow), paddleAngle: atan2(ax.a.y, ax.a.x),
                             pinKick: pinHit, headKick: headHit, sparks: sparks, alpha: e)
    }
}

// MARK: - Rope bridge

public struct PlankState: Equatable, Sendable { public var position: CGPoint; public var angle: CGFloat; public var width: CGFloat }

public struct BridgeScene: Equatable, Sendable {
    public var planks: [PlankState]
    public var railA: [CGPoint], railB: [CGPoint]
    public var walker: CGPoint, walkerAngle: CGFloat, walkerFacing: CGFloat, walkerBob: CGFloat, walkerStep: CGFloat
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var alpha: CGFloat
}

public struct BridgeSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> BridgeScene {
        let b = base, ax = b.axes, up = b.up()
        let e = max(0, min(1, emerge)), reach = sm(30, 130, ax.chord)
        let sag = (min(70, 16 + ax.chord * 0.1) * (1 - 0.7 * sm(300, 1100, ax.chord))) * reach * (b.fired ? 1 + b.releaseT * 4 : 1)
        func deck(_ s: CGFloat, wave: CGFloat = 0) -> CGPoint {
            let drop = -sag * 4 * s * (1 - s) + wave
            return CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s + up.x * drop, y: b.pin.y + (b.head.y - b.pin.y) * s + up.y * drop)
        }
        // The walker paces end to end, pausing and turning at each.
        let period: CGFloat = 7
        let cyc = (b.time / period).truncatingRemainder(dividingBy: 1)
        let w = cyc < 0.5 ? cyc * 2 : 2 - cyc * 2                  // 0...1...0
        let ws = 0.1 + 0.8 * (w * w * (3 - 2 * w))
        let facing: CGFloat = cyc < 0.5 ? 1 : -1
        let bobT = b.time * 9
        var planks: [PlankState] = []
        let n = 18
        for i in 0...n {
            let s = CGFloat(i) / CGFloat(n)
            let dip = -3 * exp(-pow((s - ws) / 0.07, 2)) * reach          // the deck sags under the walker
            let p = deck(s, wave: dip + 1.5 * CGFloat(sin(Double(s * 9 - b.time * 2))) * reach * 0.6)
            let q = deck(min(1, s + 0.01), wave: dip)
            planks.append(PlankState(position: p, angle: atan2(q.y - p.y, q.x - p.x), width: max(8, ax.chord / CGFloat(n) * 0.9)))
        }
        func rail(_ off: CGFloat) -> [CGPoint] {
            (0...24).map { j in
                let s = CGFloat(j) / 24
                let p = deck(s)
                return CGPoint(x: p.x + up.x * off, y: p.y + up.y * off)
            }
        }
        let wp = deck(ws, wave: -3 * reach)
        var wpos = CGPoint(x: wp.x + up.x * (b.bodyRadius * 0.42 + 2.5 * abs(CGFloat(sin(Double(bobT))))), y: wp.y + up.y * (b.bodyRadius * 0.42 + 2.5 * abs(CGFloat(sin(Double(bobT))))))
        if b.fired { wpos.x += b.releaseDir.x * 300 * b.releaseT; wpos.y += b.releaseDir.y * 300 * b.releaseT + 120 * b.releaseT }
        let q = deck(min(1, ws + 0.01))
        // The walker is always upright: a deck running leftward mirrors it instead of turning it over.
        var slope = atan2(q.y - wp.y, q.x - wp.x), flip: CGFloat = 1
        if cos(slope) < 0 { slope -= .pi; flip = -1 }
        return BridgeScene(planks: planks, railA: rail(b.bodyRadius * 0.55), railB: rail(b.bodyRadius * 0.9), walker: wpos,
                           walkerAngle: slope, walkerFacing: facing * flip, walkerBob: abs(CGFloat(sin(Double(bobT)))),
                           walkerStep: CGFloat(sin(Double(bobT))), pin: b.pin, head: b.head, pinRadius: b.rp, headRadius: b.rh * (1 + 0.1 * headGlow),
                           alpha: e * (b.fired ? max(0.001, b.fade(0.9)) : 1) * (reach > 0.02 ? 1 : 0.0001))
    }
}

// MARK: - Paper planes

public struct PlaneState: Equatable, Sendable {
    public var position: CGPoint, angle: CGFloat, size: CGFloat, alpha: CGFloat, roll: CGFloat, tint: Int
    public var trail: [(CGPoint, CGFloat)]
    public static func == (a: PlaneState, b: PlaneState) -> Bool { a.position == b.position && a.angle == b.angle && a.alpha == b.alpha }
}

public struct PlanesScene: Equatable, Sendable {
    public var planes: [PlaneState]
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var alpha: CGFloat
}

public struct PaperPlanesSim: Sendable {
    public var base = SimBase()
    public var planes = 5
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> PlanesScene {
        let b = base, ax = b.axes, up = b.up()
        let e = max(0, min(1, emerge)), reach = sm(30, 130, ax.chord)
        var out: [PlaneState] = []
        for i in 0..<planes {
            let dirSign: CGFloat = i % 2 == 0 ? 1 : -1
            let period = 3.0 + 0.9 * StyleHash.unit(i, 161)
            let off = StyleHash.unit(i, 162)
            func place(_ t: CGFloat) -> (CGPoint, CGFloat, CGFloat) {
                let p = (t / period + off).truncatingRemainder(dividingBy: 1)
                let s = dirSign > 0 ? p : 1 - p
                let lane = (StyleHash.unit(i, 163) * 2 - 1) * 22
                let loop = StyleHash.unit(i, 164) > 0.55 ? CGFloat(1) : 0
                let arc = (30 + 40 * StyleHash.unit(i, 165)) * sin(.pi * p) * (StyleHash.unit(i, 166) > 0.5 ? 1 : -1)
                var x = b.pin.x + (b.head.x - b.pin.x) * s + ax.n.x * (lane + arc)
                var y = b.pin.y + (b.head.y - b.pin.y) * s + ax.n.y * (lane + arc)
                // A loop-the-loop in the middle of the flight for some of them.
                let lp = sm(0.4, 0.5, p) * (1 - sm(0.62, 0.72, p)) * loop
                let la = (p - 0.45) / 0.2 * 2 * .pi
                x += (cos(la) - 1) * 24 * lp * up.x * 0 + ax.a.x * dirSign * sin(la) * 26 * lp - ax.n.x * 0
                y += ax.a.y * dirSign * sin(la) * 26 * lp
                x += up.x * (1 - cos(la)) * 26 * lp; y += up.y * (1 - cos(la)) * 26 * lp
                return (CGPoint(x: x, y: y), p, lp)
            }
            let (pos0, p, lp) = place(b.time)
            let (pos1, _, _) = place(b.time + 0.03)
            var pos = pos0
            var ang = atan2(pos1.y - pos0.y, pos1.x - pos0.x)
            if b.fired { pos.x += b.releaseDir.x * 900 * b.releaseT * (0.5 + 0.5 * StyleHash.unit(i, 167)); pos.y += b.releaseDir.y * 900 * b.releaseT * (0.5 + 0.5 * StyleHash.unit(i, 167)); ang = atan2(b.releaseDir.y, b.releaseDir.x) }
            var trail: [(CGPoint, CGFloat)] = []
            for k in 1...14 {
                let q = place(b.time - CGFloat(k) * 0.07).0
                trail.append((q, e * reach * (1 - CGFloat(k) / 15) * 0.9 * (k % 2 == 0 ? 1 : 0.0)))
            }
            let fadeIn = e * reach * sin(.pi * p) * b.fade(0.8)
            out.append(PlaneState(position: pos, angle: ang, size: b.bodyRadius * (0.55 + 0.25 * StyleHash.unit(i, 168)), alpha: max(fadeIn, b.fired ? e * b.fade(0.8) : 0),
                                  roll: 0.6 * CGFloat(sin(Double(b.time * 2 + CGFloat(i)))) + lp * 2, tint: i % 4, trail: trail))
        }
        return PlanesScene(planes: out, pin: b.pin, head: b.head, pinRadius: b.rp, headRadius: b.rh * (1 + 0.1 * headGlow), alpha: e)
    }
}

// MARK: - Water arc

public struct WaterScene: Equatable, Sendable {
    public var arc: [CGPoint]
    public var drops: [(CGPoint, CGFloat, CGFloat)]
    public var tank: CGPoint, tankRadius: CGFloat, tankLevel: CGFloat
    public var cup: CGPoint, cupRadius: CGFloat, cupLevel: CGFloat
    public var rings: [(CGFloat, CGFloat)]
    public var splash: [(CGPoint, CGFloat)]
    public var flow: CGFloat
    public var time: CGFloat
    public var alpha: CGFloat
    public static func == (a: WaterScene, b: WaterScene) -> Bool { a.tank == b.tank && a.cup == b.cup && a.alpha == b.alpha }
}

public struct WaterArcSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> WaterScene {
        let b = base, ax = b.axes, up = b.up()
        let e = max(0, min(1, emerge)), reach = sm(30, 140, ax.chord)
        let restR = b.dumbbell.restRadius * (b.bodyRadius / b.dumbbell.restRadius)
        // Water moves from the tank to the cup as you pull: the levels are the masses.
        let tankLevel = max(0.06, min(1, (b.mass.sol.pin / restR) * (b.mass.sol.pin / restR) * 1.15))
        let cupLevel = min(1, max(0.08, 1 - tankLevel * 0.9))
        let arch = min(150, 20 + ax.chord * 0.2) * reach
        let flow = reach * (b.fired ? max(0, 1 - b.releaseT / 0.4) : 1)
        func p(_ u: CGFloat) -> CGPoint {
            let h = arch * 4 * u * (1 - u)
            return CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * u + up.x * h, y: b.pin.y + (b.head.y - b.pin.y) * u + up.y * h)
        }
        let arc = (0...28).map { p(CGFloat($0) / 28) }
        var drops: [(CGPoint, CGFloat, CGFloat)] = []
        for i in 0..<60 {
            let u = ((b.time * 0.85 + CGFloat(i) / 60) + 0.015 * StyleHash.unit(i, 171)).truncatingRemainder(dividingBy: 1)
            let jitter = (StyleHash.unit(i, 172) - 0.5) * 7
            let q = p(u)
            drops.append((CGPoint(x: q.x + ax.n.x * jitter, y: q.y + ax.n.y * jitter), e * flow * sin(.pi * min(1, u * 1.1)), 1.6 + 2.2 * StyleHash.unit(i, 173)))
        }
        var rings: [(CGFloat, CGFloat)] = []
        for k in 0..<3 {
            let ph = (b.time * 1.2 + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
            rings.append((b.rh * (0.6 + 0.9 * ph), e * flow * (1 - ph) * 0.7))
        }
        var splash: [(CGPoint, CGFloat)] = []
        for i in 0..<10 {
            let ph = (b.time * 2.2 + CGFloat(i) / 10).truncatingRemainder(dividingBy: 1)
            let a = .pi / 2 + (StyleHash.unit(i, 174) - 0.5) * 1.8
            let cupTop = CGPoint(x: b.head.x + up.x * b.rh, y: b.head.y + up.y * b.rh)
            let d = 38 * ph
            splash.append((CGPoint(x: cupTop.x + cos(a) * d * 0.8, y: cupTop.y + sin(a) * d - 22 * ph * ph), e * flow * (1 - ph)))
        }
        return WaterScene(arc: arc, drops: drops, tank: b.pin, tankRadius: b.rp, tankLevel: tankLevel, cup: b.head, cupRadius: b.rh * (1 + 0.1 * headGlow),
                          cupLevel: cupLevel, rings: rings, splash: splash, flow: flow, time: b.time, alpha: e)
    }
}

// MARK: - Toy train

public struct TrainCar: Equatable, Sendable { public var position: CGPoint; public var angle: CGFloat; public var kind: Int; public var facing: CGFloat = 1 }

public struct TrainScene: Equatable, Sendable {
    public var track: [CGPoint]
    public var ties: [PlankState]
    public var cars: [TrainCar]
    public var smoke: [(CGPoint, CGFloat, CGFloat)]
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var alpha: CGFloat
    public static func == (a: TrainScene, b: TrainScene) -> Bool { a.cars == b.cars && a.alpha == b.alpha }
}

public struct ToyTrainSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.9 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> TrainScene {
        let b = base, ax = b.axes, up = b.up()
        let e = max(0, min(1, emerge)), reach = sm(40, 160, ax.chord)
        let rise = min(60, ax.chord * 0.1) * reach
        func p(_ s: CGFloat) -> CGPoint {
            let h = rise * CGFloat(sin(Double(s * 2 * .pi))) * 0.6                   // a gentle S-curve of track
            return CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s + up.x * h, y: b.pin.y + (b.head.y - b.pin.y) * s + up.y * h)
        }
        let track = (0...40).map { p(CGFloat($0) / 40) }
        var ties: [PlankState] = []
        let nTies = max(6, Int(ax.chord / 18))
        for i in 0...nTies {
            let s = CGFloat(i) / CGFloat(nTies)
            let q = p(s), r = p(min(1, s + 0.01))
            ties.append(PlankState(position: q, angle: atan2(r.y - q.y, r.x - q.x) + .pi / 2, width: 14))
        }
        // The train shuttles end to end with an ease at each station.
        let period: CGFloat = 8
        let cyc = (b.time / period).truncatingRemainder(dividingBy: 1)
        let w = cyc < 0.5 ? cyc * 2 : 2 - cyc * 2
        let head0 = 0.16 + 0.82 * (w * w * (3 - 2 * w))
        let dirSign: CGFloat = cyc < 0.5 ? 1 : -1
        let spacing = min(0.12, 46 / max(1, ax.chord))
        var cars: [TrainCar] = []
        for k in 0..<4 {
            let s = max(0, min(1, head0 - dirSign * CGFloat(k) * spacing))
            let q = p(s), r = p(min(1, s + 0.01))
            var ang = atan2(r.y - q.y, r.x - q.x)
            if dirSign < 0 { ang += .pi }
            var pos = CGPoint(x: q.x + up.x * 8, y: q.y + up.y * 8)
            if b.fired { pos.x += b.releaseDir.x * 600 * b.releaseT * (1 + CGFloat(k) * 0.1); pos.y += b.releaseDir.y * 600 * b.releaseT }
            cars.append(TrainCar(position: pos, angle: dirSign < 0 ? ang - .pi : ang, kind: k == 0 ? 0 : (k == 3 ? 2 : 1), facing: dirSign))
        }
        var smoke: [(CGPoint, CGFloat, CGFloat)] = []
        if let eng = cars.first {
            for i in 0..<8 {
                let ph = (b.time * 0.9 + CGFloat(i) / 8).truncatingRemainder(dividingBy: 1)
                let drift = -dirSign * 36 * ph
                smoke.append((CGPoint(x: eng.position.x + drift + up.x * (22 + 34 * ph), y: eng.position.y + up.y * (22 + 34 * ph) + 0), e * reach * (1 - ph) * 0.8, 5 + 12 * ph))
            }
        }
        return TrainScene(track: track, ties: ties, cars: cars, smoke: smoke, pin: b.pin, head: b.head, pinRadius: b.rp, headRadius: b.rh * (1 + 0.1 * headGlow),
                          alpha: e * b.fade(0.9) * (reach > 0.02 ? 1 : 0.0001))
    }
}

// MARK: - Equalizer

public struct EqBar: Equatable, Sendable { public var base: CGPoint; public var height: CGFloat; public var peak: CGFloat; public var hue: CGFloat }

public struct EqualizerScene: Sendable {
    public var bars: [EqBar]
    public var barWidth: CGFloat
    public var axis: CGFloat
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var pinPulse: CGFloat, headPulse: CGFloat
    public var rings: [(CGFloat, CGFloat)]
    public var alpha: CGFloat
}

public struct EqualizerSim: Sendable {
    public var base = SimBase()
    public var barsCount = 24
    /// Live audio bands (0...1, bass first), when the app is capturing system audio; nil means animate on its own.
    public var spectrum: [CGFloat]?
    public var isLive: Bool { spectrum != nil }
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> EqualizerScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge)), reach = sm(40, 160, ax.chord)
        var beat = max(0, CGFloat(sin(Double(b.time * 7.2)))) * max(0, CGFloat(sin(Double(b.time * 2.4 + 0.4))) * 0.5 + 0.6)
        if let sp = spectrum, !sp.isEmpty { beat = min(1, sp.prefix(max(1, sp.count / 6)).reduce(0, +) / CGFloat(max(1, sp.count / 6)) * 1.4) }
        var bars: [EqBar] = []
        let n = barsCount
        for i in 0..<n {
            let s = (CGFloat(i) + 0.5) / CGFloat(n)
            let bass = (1 - s)                                                     // bass lives at the heavy pin
            let t = b.time
            let v = 0.35 + 0.35 * CGFloat(sin(Double(t * (3 + 7 * s) + CGFloat(i) * 1.7))) * CGFloat(sin(Double(t * 1.3 + CGFloat(i))))
            let kick = beat * bass * bass * 0.9
            let massK = (b.mass.sol.pin * (1 - s) + b.mass.sol.head * s) / max(1, b.bodyRadius)
            var h = (max(0.05, v) + kick) * (24 + 46 * massK) * reach
            if let sp = spectrum, !sp.isEmpty {
                let idx = min(sp.count - 1, Int(CGFloat(sp.count) * s))
                // The real spectrum drives the bar; bass sits at the heavy pin. Mass sets how tall each end can grow.
                h = max(0.04, sp[idx]) * (30 + 78 * massK) * reach
            }
            if b.fired { h *= 1 + 2.5 * max(0, 1 - b.releaseT / 0.3) * StyleHash.unit(i, 181) }
            let base = CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s, y: b.pin.y + (b.head.y - b.pin.y) * s)
            let peak = h * (1.1 + 0.25 * CGFloat(sin(Double(t * 2.1 + CGFloat(i)))))
            bars.append(EqBar(base: base, height: h, peak: peak, hue: s))
        }
        let rings: [(CGFloat, CGFloat)] = (0..<2).map { k in
            let ph = (b.time * 1.1 + CGFloat(k) / 2).truncatingRemainder(dividingBy: 1)
            return (b.rp * (1 + 1.2 * ph), e * (1 - ph) * 0.5 * (0.4 + beat))
        }
        return EqualizerScene(bars: bars, barWidth: max(4, min(18, ax.chord / CGFloat(n) * 0.62)), axis: atan2(ax.a.y, ax.a.x),
                              pin: b.pin, head: b.head, pinRadius: b.rp, headRadius: b.rh * (1 + 0.1 * headGlow),
                              pinPulse: beat, headPulse: max(0, CGFloat(sin(Double(b.time * 10.5)))) * 0.6, rings: rings,
                              alpha: e * b.fade(0.8))
    }
}

// MARK: - DNA

public struct DNARung: Equatable, Sendable { public var a: CGPoint; public var b: CGPoint; public var depth: CGFloat; public var pair: Int }

public struct DNAScene: Equatable, Sendable {
    public var strandA: [(CGPoint, CGFloat)]
    public var strandB: [(CGPoint, CGFloat)]
    public var rungs: [DNARung]
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var alpha: CGFloat
    public static func == (a: DNAScene, b: DNAScene) -> Bool { a.rungs == b.rungs && a.alpha == b.alpha }
}

public struct DNASim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.8 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> DNAScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge)), reach = sm(30, 130, ax.chord)
        let turns = max(1.2, ax.chord / 85)
        let n = 90
        var A: [(CGPoint, CGFloat)] = [], B: [(CGPoint, CGFloat)] = []
        var rungs: [DNARung] = []
        let unwind: CGFloat = b.fired ? b.releaseT * 8 : 0
        for i in 0...n {
            let s = CGFloat(i) / CGFloat(n)
            let R = (b.mass.sol.pin * (1 - s) + b.mass.sol.head * s) * 1.15 * reach * (0.6 + 0.4 * sin(.pi * min(1, s * 1.2 + 0.0)))
            let th = s * turns * 2 * .pi + b.time * 1.8 + unwind * s
            let c = CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s, y: b.pin.y + (b.head.y - b.pin.y) * s)
            let sa = CGFloat(sin(Double(th))), sb = CGFloat(sin(Double(th + .pi)))
            let pa = CGPoint(x: c.x + ax.n.x * R * sa, y: c.y + ax.n.y * R * sa)
            let pb = CGPoint(x: c.x + ax.n.x * R * sb, y: c.y + ax.n.y * R * sb)
            A.append((pa, CGFloat(cos(Double(th))))); B.append((pb, CGFloat(cos(Double(th + .pi)))))
            if i % 4 == 2, s > 0.04, s < 0.96 {
                rungs.append(DNARung(a: pa, b: pb, depth: CGFloat(cos(Double(th))), pair: (i / 4) % 4))
            }
        }
        return DNAScene(strandA: A, strandB: B, rungs: rungs, pin: b.pin, head: b.head, pinRadius: b.rp * 0.8,
                        headRadius: b.rh * 0.8 * (1 + 0.1 * headGlow), alpha: e * b.fade(0.8))
    }
}

// MARK: - Fishing

public struct FishingScene: Equatable, Sendable {
    public var rodBase: CGPoint, rodTip: CGPoint
    public var line: [CGPoint]
    public var bobber: CGPoint, bobberDip: CGFloat
    public var ripples: [(CGFloat, CGFloat)]
    public var fish: CGPoint, fishAngle: CGFloat, fishAlpha: CGFloat
    public var splash: [(CGPoint, CGFloat)]
    public var pinRadius: CGFloat, headRadius: CGFloat
    public var alpha: CGFloat
    public static func == (a: FishingScene, b: FishingScene) -> Bool { a.bobber == b.bobber && a.fish == b.fish && a.alpha == b.alpha }
}

public struct FishingSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.9 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> FishingScene {
        let b = base, ax = b.axes
        let up = CGPoint(x: 0, y: 1)                                  // the rod and float always follow gravity
        let e = max(0, min(1, emerge)), reach = sm(30, 130, ax.chord)
        let rodLen = b.rp * 5.2
        // The rod leans back from the water, tip over the line.
        let lean = CGPoint(x: -ax.a.x * 0.5 + up.x * 0.85, y: -ax.a.y * 0.5 + up.y * 0.85)
        let l = max(1, hypot(lean.x, lean.y))
        let tip = CGPoint(x: b.pin.x + lean.x / l * rodLen, y: b.pin.y + lean.y / l * rodLen)
        // A nibble every ~6 seconds: the bobber dips, then a fish leaps.
        let period: CGFloat = 6
        let c = b.time.truncatingRemainder(dividingBy: period)
        let nibble = c > 2.2 && c < 3.1 ? CGFloat(sin(Double((c - 2.2) / 0.9 * .pi * 3))) * 0.5 + 0.5 : 0
        let leap = (c - 3.1) / 1.1
        let bob = CGFloat(sin(Double(b.time * 2.6))) * 2.2 - nibble * 7
        let bobber = CGPoint(x: b.head.x + up.x * bob, y: b.head.y + up.y * bob)
        let sag = min(60, ax.chord * 0.12) * reach
        var line: [CGPoint] = []
        for j in 0...26 {
            let s = CGFloat(j) / 26
            let p = CGPoint(x: tip.x + (bobber.x - tip.x) * s, y: tip.y + (bobber.y - tip.y) * s)
            let d = -sag * 4 * s * (1 - s) * (1 - nibble * 0.5)
            line.append(CGPoint(x: p.x + up.x * d, y: p.y + up.y * d))
        }
        var fish = b.head, fa: CGFloat = 0, fAlpha: CGFloat = 0
        var splash: [(CGPoint, CGFloat)] = []
        if leap > 0, leap < 1 {
            let h = 70 * 4 * leap * (1 - leap)
            let dx = (leap - 0.5) * 60
            fish = CGPoint(x: b.head.x + ax.a.x * dx * -1 + up.x * h, y: b.head.y + ax.a.y * dx * -1 + up.y * h)
            fa = atan2(up.y * (1 - 2 * leap) + ax.a.y * -0.5, up.x * (1 - 2 * leap) - ax.a.x * 0.5)
            fAlpha = e * reach
            for i in 0..<8 {
                let ph = leap < 0.15 ? leap / 0.15 : (leap > 0.85 ? (leap - 0.85) / 0.15 : 0)
                if ph > 0 { splash.append((CGPoint(x: b.head.x + cos(CGFloat(i) * 0.8) * 20 * ph, y: b.head.y + 20 * ph * CGFloat(sin(Double(.pi * ph))) + sin(CGFloat(i)) * 6), e * (1 - ph))) }
            }
        }
        let ripples: [(CGFloat, CGFloat)] = (0..<3).map { k in
            let ph = (b.time * 0.5 + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
            return (b.rh * (0.8 + 1.8 * ph), e * reach * (1 - ph) * 0.8)
        }
        var rb = b.pin, rt = tip
        if b.fired { let f = min(1, b.releaseT * 4); rt = CGPoint(x: tip.x + ax.a.x * 40 * f, y: tip.y - 30 * f) }
        _ = rb; rb = b.pin
        return FishingScene(rodBase: rb, rodTip: rt, line: line, bobber: bobber, bobberDip: nibble, ripples: ripples, fish: fish, fishAngle: fa,
                            fishAlpha: fAlpha * b.fade(0.9), splash: splash, pinRadius: b.rp, headRadius: b.rh * (1 + 0.1 * headGlow), alpha: e * b.fade(0.9))
    }
}

// MARK: - Ribbon dance

public struct RibbonScene: Equatable, Sendable {
    public var spine: [CGPoint]
    public var width: [CGFloat]
    public var twist: [CGFloat]
    public var pin: CGPoint, head: CGPoint, pinRadius: CGFloat, headRadius: CGFloat
    public var alpha: CGFloat
}

public struct RibbonSim: Sendable {
    public var base = SimBase()
    public init() {}
    public var isFinished: Bool { base.releaseT > 0.9 }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> RibbonScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge)), reach = sm(20, 110, ax.chord)
        let n = 70
        var spine: [CGPoint] = [], width: [CGFloat] = [], twist: [CGFloat] = []
        // A rhythmic-gymnastics ribbon: a travelling wave with curls, anchored at both ends.
        let amp = min(110, 24 + ax.chord * 0.14) * reach * (b.fired ? 1 + b.releaseT * 3 : 1)
        let curls = max(1.5, ax.chord / 140)
        for i in 0...n {
            let s = CGFloat(i) / CGFloat(n)
            let env = sin(.pi * s)
            let ph = s * curls * 2 * .pi - b.time * 4.2
            let off = amp * env * (CGFloat(sin(Double(ph))) + 0.35 * CGFloat(sin(Double(ph * 2.3 + b.time))))
            let al = amp * 0.35 * env * CGFloat(cos(Double(ph)))
            spine.append(CGPoint(x: b.pin.x + (b.head.x - b.pin.x) * s + ax.n.x * off + ax.a.x * al,
                                 y: b.pin.y + (b.head.y - b.pin.y) * s + ax.n.y * off + ax.a.y * al))
            width.append((10 + 8 * env) * (0.4 + 0.6 * reach))
            twist.append(CGFloat(cos(Double(ph * 0.9 + 1))))
        }
        return RibbonScene(spine: spine, width: width, twist: twist, pin: b.pin, head: b.head, pinRadius: b.rp * 0.8,
                           headRadius: b.rh * 0.8 * (1 + 0.1 * headGlow), alpha: e * b.fade(0.9))
    }
}
