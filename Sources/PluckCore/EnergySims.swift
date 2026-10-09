import CoreGraphics
import Foundation

/// The anime energy attacks: one engine, many very different looks. Each variant has its own palette, beam profile,
/// extra strands, particles and impact, and the whole set can run either "held" (the attack streams while you hold
/// the pull) or "charge, then fire" (hold to charge, aim with the head, release to shoot).
public enum EnergyVariant: String, CaseIterable, Codable, Sendable {
    case kamehameha, spiritGun, finalFlash, drillBeam, getsuga, rasengan, cero, fireRoar, moonPrism, spiritBomb

    public var name: String {
        switch self {
        case .kamehameha: return "Wave-Motion Beam"
        case .spiritGun: return "Spirit Gun"
        case .finalFlash: return "Final Flash"
        case .drillBeam: return "Drill Beam"
        case .getsuga: return "Crescent Slash"
        case .rasengan: return "Spiral Sphere"
        case .cero: return "Hollow Blast"
        case .fireRoar: return "Fire Roar"
        case .moonPrism: return "Moon Prism"
        case .spiritBomb: return "Spirit Bomb"
        }
    }

    public var tagline: String {
        switch self {
        case .kamehameha: return "The classic: a blue wave of energy with a white-hot core"
        case .spiritGun: return "A needle of pale light with shock rings racing down it"
        case .finalFlash: return "A broad, jagged golden beam with speed lines and lightning"
        case .drillBeam: return "A violet needle with golden helices drilling around it"
        case .getsuga: return "Black-and-red crescent slashes tear across the screen"
        case .rasengan: return "A spinning spiral sphere, charged in the palm and thrown"
        case .cero: return "A widening crimson cone ringed with black lightning"
        case .fireRoar: return "A roaring stream of tumbling flames"
        case .moonPrism: return "A pink stream of hearts, stars and ribbons"
        case .spiritBomb: return "A huge orb gathers light, then is hurled"
        }
    }

    /// Glow, body, core, accent (0...255).
    public var palette: [[CGFloat]] {
        switch self {
        case .kamehameha: return [[70, 185, 255], [150, 232, 255], [255, 255, 255], [190, 245, 255]]
        case .spiritGun: return [[120, 210, 255], [200, 242, 255], [255, 255, 255], [90, 190, 255]]
        case .finalFlash: return [[255, 190, 40], [255, 226, 110], [255, 255, 235], [255, 245, 150]]
        case .drillBeam: return [[150, 80, 230], [196, 140, 255], [255, 245, 255], [255, 206, 90]]
        case .getsuga: return [[255, 60, 70], [30, 24, 40], [255, 238, 238], [255, 90, 100]]
        case .rasengan: return [[90, 170, 255], [170, 220, 255], [255, 255, 255], [60, 130, 240]]
        case .cero: return [[200, 20, 40], [255, 70, 90], [255, 226, 230], [24, 8, 16]]
        case .fireRoar: return [[200, 40, 20], [255, 140, 30], [255, 232, 120], [60, 30, 28]]
        case .moonPrism: return [[255, 130, 200], [255, 182, 226], [255, 255, 255], [255, 222, 120]]
        case .spiritBomb: return [[90, 190, 255], [190, 232, 255], [255, 255, 255], [255, 255, 200]]
        }
    }

    public var isProjectile: Bool { self == .getsuga || self == .rasengan || self == .spiritBomb }
}

public struct EnergyRibbon: Sendable {
    public var centerline: [CGPoint]
    public var halfWidth: [CGFloat]
    public var role: Int            // palette index
    public var alpha: CGFloat
}

public struct EnergyParticle: Sendable {
    public var position: CGPoint
    public var size: CGFloat
    public var alpha: CGFloat
    public var color: Int           // palette index, or 4 for black smoke
    public var shape: Int           // 0 dot, 1 heart, 2 star, 3 flame, 4 ring
    public var angle: CGFloat
}

public struct EnergyProjectile: Sendable {
    public var position: CGPoint
    public var angle: CGFloat
    public var size: CGFloat
    public var kind: Int            // 0 spiral sphere, 1 crescent, 2 great orb
    public var alpha: CGFloat
    public var trail: [CGPoint]
}

public struct EnergyScene: Sendable {
    public var variant: EnergyVariant
    public var orb: CGPoint
    public var orbRadius: CGFloat
    public var charge: CGFloat
    public var spin: CGFloat
    public var motes: [(CGPoint, CGFloat, CGFloat)]
    public var arcs: [[CGPoint]]
    public var ribbons: [EnergyRibbon]
    public var strands: [[CGPoint]]
    public var strandRole: Int
    public var particles: [EnergyParticle]
    public var projectiles: [EnergyProjectile]
    public var speedLines: [(CGPoint, CGPoint, CGFloat)]
    public var impact: CGPoint
    public var impactRadius: CGFloat
    public var impactAmount: CGFloat
    public var rings: [(CGFloat, CGFloat)]
    public var aimLine: [CGPoint]
    public var reticle: CGFloat
    public var flash: CGFloat
    public var phase: CGFloat
    public var alpha: CGFloat
}

public struct EnergySim: Sendable {
    public var base = SimBase()
    public var variant: EnergyVariant = .kamehameha
    /// False: the attack streams while you hold the pull. True: hold to charge, aim with the head, release to fire.
    public var chargeThenFire = false
    public init() {}

    private var fireDuration: CGFloat { variant.isProjectile ? 1.25 : 1.1 }
    public var isFinished: Bool { base.releaseT > (chargeThenFire ? fireDuration : 0.9) }
    public mutating func reset(pin: CGPoint) { base.start(pin) }
    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { base.advance(dt, pin, head) }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    private func sm(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { StyleHash.smoothstep(a, b, x) }

    public func scene(emerge: CGFloat, headGlow: CGFloat = 0) -> EnergyScene {
        let b = base, ax = b.axes
        let e = max(0, min(1, emerge))
        let dir = ax.a, nrm = ax.n
        let chord = ax.chord
        let fired = b.fired
        let tt = fired ? b.releaseT : 0
        let holdCharge = sm(0, 1.7, b.time)                                   // grows the longer you hold
        let pull = sm(40, 150, chord)
        let charge = chargeThenFire ? (0.2 + 0.8 * holdCharge) : min(1, 0.25 + chord / 260)
        // How much attack is out: held mode streams with the pull; charge mode fires only after release.
        var amount: CGFloat
        var surge: CGFloat = 1
        var fadeAll: CGFloat = 1
        if chargeThenFire {
            amount = fired ? sm(0, 0.07, tt) * (1 - sm(0.5, fireDuration - 0.1, tt)) : 0
            surge = fired ? 1 + 0.9 * (1 - sm(0, 0.35, tt)) : 1
            fadeAll = fired ? max(0, 1 - sm(fireDuration - 0.2, fireDuration, tt)) : 1
        } else {
            amount = pull * (fired ? max(0, 1 - tt / 0.75) : 1)
            surge = fired ? (1 + 1.6 * CGFloat(sin(Double(min(1, tt / 0.2) * .pi / 2)))) * max(0, 1 - tt / 0.7) : 1
            fadeAll = fired ? max(0, 1 - tt / 0.8) : 1
        }
        let flash = fired ? max(0, 1 - tt / 0.35) : 0
        let R = max(10, b.rp * 0.95)
        var orbR = R * (chargeThenFire && !fired ? 0.55 + 0.6 * charge : 1.0)
        if variant == .spiritBomb { orbR = R * (chargeThenFire ? (fired ? 1.0 + 1.6 * (1 - sm(0, 0.3, tt)) : 0.8 + 1.7 * holdCharge) : 0.9 + 1.4 * pull) }
        if fired, chargeThenFire, variant != .spiritBomb { orbR *= 1 + 0.35 * flash }
        let t = b.time

        // Charge motes spiral into the orb; lightning crackles around it.
        var motes: [(CGPoint, CGFloat, CGFloat)] = []
        for i in 0..<14 {
            let period = 0.7 + 0.5 * StyleHash.unit(i, 121)
            let age = (t / period + StyleHash.unit(i, 122)).truncatingRemainder(dividingBy: 1)
            let r = orbR * (3.2 - 2.7 * age)
            let ang = 6.28 * StyleHash.unit(i, 123) + age * 5.5 * (i % 2 == 0 ? 1 : -1)
            motes.append((CGPoint(x: b.pin.x + cos(ang) * r, y: b.pin.y + sin(ang) * r), e * fadeAll * sin(.pi * age) * (0.4 + 0.6 * charge) * (fired && chargeThenFire ? max(0, 1 - tt / 0.2) : 1),
                          1.6 + 2.2 * StyleHash.unit(i, 124)))
        }
        let bucket = Int(t * 20)
        var arcs: [[CGPoint]] = []
        let arcCount = (variant == .finalFlash || variant == .cero || variant == .kamehameha || variant == .drillBeam) ? 5 : 3
        for k in 0..<arcCount {
            let a0 = 6.28 * StyleHash.unit(k + bucket * 7, 125)
            var pts: [CGPoint] = []
            for j in 0...5 {
                let r = orbR * (0.9 + 0.55 * CGFloat(j) / 5) + (StyleHash.unit(k * 11 + j + bucket * 13, 126) - 0.5) * orbR * 0.3
                let a = a0 + (StyleHash.unit(k * 5 + j + bucket * 3, 127) - 0.5) * 0.9
                pts.append(CGPoint(x: b.pin.x + cos(a) * r, y: b.pin.y + sin(a) * r))
            }
            arcs.append(pts)
        }

        // ----- beam geometry
        var ribbons: [EnergyRibbon] = []
        var strands: [[CGPoint]] = []
        var particles: [EnergyParticle] = []
        var speedLines: [(CGPoint, CGPoint, CGFloat)] = []
        var projectiles: [EnergyProjectile] = []
        let n = 40
        let startOffset = orbR * 0.6
        let len = max(1, chord - startOffset)
        func point(_ s: CGFloat, _ off: CGFloat = 0) -> CGPoint {
            CGPoint(x: b.pin.x + dir.x * (startOffset + len * s) + nrm.x * off, y: b.pin.y + dir.y * (startOffset + len * s) + nrm.y * off)
        }
        func ribbon(role: Int, scale: CGFloat, base w: CGFloat, alpha: CGFloat, width: (CGFloat) -> CGFloat, sway: (CGFloat) -> CGFloat = { _ in 0 }) -> EnergyRibbon {
            var c: [CGPoint] = [], hw: [CGFloat] = []
            for j in 0...n {
                let s = CGFloat(j) / CGFloat(n)
                c.append(point(s, sway(s)))
                hw.append(max(0, w * scale * width(s) * amount))
            }
            return EnergyRibbon(centerline: c, halfWidth: hw, role: role, alpha: alpha)
        }
        func env(_ s: CGFloat) -> CGFloat { sm(0, 0.07, s) * (0.8 + 0.2 * CGFloat(sin(Double(.pi * s)))) * (1 + 0.3 * sm(0.85, 1, s)) }
        let wob = { (s: CGFloat, f: CGFloat, a: CGFloat) -> CGFloat in 1 + a * CGFloat(sin(Double(s * f - t * 32))) + 0.4 * a * CGFloat(sin(Double(s * f * 2.3 - t * 51))) }
        var strandRole = 3

        if amount > 0.01 || (chargeThenFire && fired) {
            switch variant {
            case .kamehameha:
                let w = (b.rp * 0.55 + 4) * surge
                for (role, sc, al) in [(0, 2.1, 0.55), (1, 1.25, 1.0), (2, 0.62, 1.0)] as [(Int, CGFloat, CGFloat)] {
                    ribbons.append(ribbon(role: role, scale: sc, base: w, alpha: al, width: { env($0) * wob($0, 14, 0.12) }, sway: { 2.2 * $0 * CGFloat(sin(Double($0 * 6 - t * 9))) * (fired ? 2 : 1) }))
                }
            case .spiritGun:
                let w = (3.4 + b.rp * 0.1) * surge
                for (role, sc, al) in [(0, 3.4, 0.4), (1, 1.5, 1.0), (2, 0.7, 1.0)] as [(Int, CGFloat, CGFloat)] {
                    ribbons.append(ribbon(role: role, scale: sc, base: w, alpha: al, width: { env($0) * (0.7 + 0.3 * $0) * wob($0, 20, 0.05) }))
                }
                for i in 0..<5 {                                                    // shock rings racing down the needle
                    let s = ((t * 1.1 + CGFloat(i) / 5).truncatingRemainder(dividingBy: 1))
                    particles.append(EnergyParticle(position: point(s), size: 9 + 6 * (1 - s), alpha: e * amount * sin(.pi * s) * fadeAll, color: 3, shape: 4, angle: atan2(dir.y, dir.x)))
                }
            case .finalFlash:
                let w = (b.rp * 0.95 + 8) * surge
                for (role, sc, al) in [(0, 1.9, 0.5), (1, 1.15, 1.0), (2, 0.7, 1.0)] as [(Int, CGFloat, CGFloat)] {
                    ribbons.append(ribbon(role: role, scale: sc, base: w, alpha: al, width: { env($0) * wob($0, 22, 0.28) }))
                }
                for i in 0..<16 {
                    let s = StyleHash.unit(i + bucket / 2 * 3, 301)
                    let side: CGFloat = i % 2 == 0 ? 1 : -1
                    let p0 = point(s, side * w * 1.4), p1 = point(max(0, s - 0.12 - 0.1 * StyleHash.unit(i, 302)), side * w * (2.2 + StyleHash.unit(i, 303)))
                    speedLines.append((p0, p1, e * amount * fadeAll * 0.8))
                }
            case .drillBeam:
                let w = (b.rp * 0.3 + 4) * surge
                for (role, sc, al) in [(0, 2.4, 0.5), (1, 1.2, 1.0), (2, 0.55, 1.0)] as [(Int, CGFloat, CGFloat)] {
                    ribbons.append(ribbon(role: role, scale: sc, base: w, alpha: al, width: { env($0) * (0.55 + 0.45 * (1 - $0 * 0.5)) }))
                }
                for k in 0..<2 {
                    var pts: [CGPoint] = []
                    for j in 0...(n * 2) {
                        let s = CGFloat(j) / CGFloat(n * 2)
                        let th = s * 18 + t * 14 + CGFloat(k) * .pi
                        pts.append(point(s, w * 2.4 * amount * env(s) * CGFloat(sin(Double(th)))))
                    }
                    strands.append(pts)
                }
                strandRole = 3
            case .cero:
                let w = (b.rp * 0.8 + 6) * surge
                ribbons.append(ribbon(role: 3, scale: 1.35, base: w, alpha: 0.9, width: { (0.18 + 1.3 * $0) * env($0) }))
                ribbons.append(ribbon(role: 0, scale: 1.1, base: w, alpha: 1.0, width: { (0.15 + 1.2 * $0) * env($0) * wob($0, 10, 0.08) }))
                ribbons.append(ribbon(role: 1, scale: 0.75, base: w, alpha: 1.0, width: { (0.12 + 0.95 * $0) * env($0) }))
                ribbons.append(ribbon(role: 2, scale: 0.34, base: w, alpha: 1.0, width: { (0.1 + 0.8 * $0) * env($0) }))
            case .fireRoar:
                let w = (b.rp * 0.7 + 6) * surge
                for (role, sc, al) in [(0, 1.7, 0.4), (1, 1.0, 0.95), (2, 0.5, 1.0)] as [(Int, CGFloat, CGFloat)] {
                    ribbons.append(ribbon(role: role, scale: sc, base: w, alpha: al, width: { env($0) * wob($0, 9, 0.22) * (0.5 + 0.8 * $0) }, sway: { 6 * CGFloat(sin(Double($0 * 7 - t * 11))) * $0 }))
                }
                for i in 0..<44 {
                    let age = (t * 1.3 + CGFloat(i) / 44).truncatingRemainder(dividingBy: 1)
                    let off = (StyleHash.unit(i + Int(t * 1.3 + CGFloat(i) / 44) * 17, 311) - 0.5) * w * 1.6 * (0.3 + age)
                    let color = age < 0.25 ? 2 : (age < 0.55 ? 1 : (age < 0.85 ? 0 : 4))
                    particles.append(EnergyParticle(position: point(age, off + 5 * CGFloat(sin(Double(age * 20 + CGFloat(i))))), size: (7 + 14 * age) * (0.6 + 0.6 * StyleHash.unit(i, 312)),
                                                    alpha: e * amount * (1 - age * age) * fadeAll * (color == 4 ? 0.4 : 0.9), color: color, shape: 3, angle: atan2(dir.y, dir.x)))
                }
            case .moonPrism:
                let w = (b.rp * 0.45 + 5) * surge
                for (role, sc, al) in [(0, 2.0, 0.45), (1, 1.2, 0.95), (2, 0.55, 1.0)] as [(Int, CGFloat, CGFloat)] {
                    ribbons.append(ribbon(role: role, scale: sc, base: w, alpha: al, width: { env($0) * wob($0, 12, 0.1) }))
                }
                for k in 0..<2 {                                                     // two ribbons weave through the beam
                    var pts: [CGPoint] = []
                    for j in 0...(n * 2) {
                        let s = CGFloat(j) / CGFloat(n * 2)
                        pts.append(point(s, w * 2.6 * amount * env(s) * CGFloat(sin(Double(s * 11 - t * 7 + CGFloat(k) * .pi)))))
                    }
                    strands.append(pts)
                }
                strandRole = 3
                for i in 0..<26 {
                    let s = (t * 0.7 + CGFloat(i) / 26).truncatingRemainder(dividingBy: 1)
                    let off = (StyleHash.unit(i, 321) - 0.5) * w * 3.2 * sin(.pi * s)
                    particles.append(EnergyParticle(position: point(s, off), size: 6 + 7 * StyleHash.unit(i, 322), alpha: e * amount * sin(.pi * s) * fadeAll,
                                                    color: i % 3 == 0 ? 3 : (i % 3 == 1 ? 1 : 2), shape: i % 2 == 0 ? 1 : 2, angle: 0.5 * CGFloat(sin(Double(t * 3 + CGFloat(i))))))
                }
            default:
                break
            }
        }

        // ----- projectiles (crescent slashes, spiral sphere, great orb)
        if variant.isProjectile {
            var shots: [(CGFloat, CGFloat)] = []                                      // (progress 0...1, fade)
            if chargeThenFire {
                if fired { let p = min(1, tt / 0.5); shots.append((p, 1)) }
            } else if pull > 0.05 || fired {
                let period: CGFloat = variant == .getsuga ? 0.5 : 0.9
                for k in 0..<3 {
                    let p = ((t / period) + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
                    shots.append((p, pull * fadeAll))
                }
            }
            let kindIndex = variant == .getsuga ? 1 : (variant == .rasengan ? 0 : 2)
            for (p, f) in shots {
                let s = p * p * (3 - 2 * p) * 0.2 + p * 0.8
                let pos = point(s * 0.98, 0)
                var trail: [CGPoint] = []
                for k in 1...8 { let sp = max(0, s - CGFloat(k) * 0.025); trail.append(point(sp * 0.98)) }
                let size: CGFloat
                switch variant {
                case .getsuga: size = b.bodyRadius * (0.9 + 0.5 * p)
                case .rasengan: size = b.bodyRadius * 0.85
                default: size = b.bodyRadius * 1.9
                }
                projectiles.append(EnergyProjectile(position: pos, angle: atan2(dir.y, dir.x), size: size, kind: kindIndex, alpha: e * f * (p < 0.96 ? 1 : 0), trail: trail))
            }
        }

        // ----- impact and rings
        let impactAmount: CGFloat
        if chargeThenFire {
            if variant.isProjectile { impactAmount = fired ? sm(0.45, 0.6, tt) * (1 - sm(0.7, fireDuration, tt)) : 0 }
            else { impactAmount = amount }
        } else {
            impactAmount = variant.isProjectile ? pull * fadeAll * 0.6 : amount
        }
        var rings: [(CGFloat, CGFloat)] = []
        if fired {
            let k = chargeThenFire && variant.isProjectile ? max(0, tt - 0.5) : tt
            rings = [(b.rh * 1.5 + 420 * min(1, k / 0.6), max(0, 1 - k / 0.6)), (b.rh + 260 * min(1, k / 0.6), max(0, 0.7 - k / 0.7))]
            if chargeThenFire && variant.isProjectile && tt < 0.5 { rings = [] }
        }
        let impactR = max(b.rh * 1.2, 12) * (1 + 0.15 * headGlow) * (0.7 + 0.5 * impactAmount) * (fired ? 1 + flash : 1)

        // ----- aim: while charging, the head is the target
        var aim: [CGPoint] = []
        var reticle: CGFloat = 0
        if chargeThenFire, !fired {
            aim = [b.pin, b.head]
            reticle = e * (0.4 + 0.6 * holdCharge)
        }
        let alpha = e * (fired && !chargeThenFire ? max(0.001, fadeAll) : 1)
        return EnergyScene(variant: variant, orb: b.pin, orbRadius: orbR * (1 + 0.06 * CGFloat(sin(Double(t * 11))) * charge), charge: charge, spin: t * 2.2,
                           motes: motes, arcs: arcs, ribbons: ribbons, strands: strands, strandRole: strandRole, particles: particles, projectiles: projectiles,
                           speedLines: speedLines, impact: b.head, impactRadius: impactR, impactAmount: impactAmount, rings: rings, aimLine: aim, reticle: reticle,
                           flash: flash, phase: t, alpha: alpha)
    }
}
