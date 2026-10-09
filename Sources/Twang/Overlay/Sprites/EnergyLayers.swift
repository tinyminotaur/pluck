import AppKit
import TwangCore
import QuartzCore

/// Draws any `EnergyScene`: ribbons, strands, particles, projectiles, impact and aim, coloured by the variant's palette.
@MainActor
final class EnergyLayers {
    let root = CALayer()
    private var ribbonLayers: [CAShapeLayer] = []
    private var strandLayers: [CAShapeLayer] = []
    private let speed = lineLayer(Sprite.color(255, 255, 255), 2.2)
    private let arcs = lineLayer(Sprite.color(255, 255, 255), 1.8)
    private let orbHalo = CALayer(), orbBody = CALayer(), orbRing = lineLayer(Sprite.color(255, 255, 255, 0.8), 2.2)
    private let impactHalo = CALayer(), impactCore = CALayer(), burst = CAShapeLayer()
    private let aim = lineLayer(Sprite.color(255, 255, 255, 0.5), 1.8), reticle = lineLayer(Sprite.color(255, 255, 255, 0.8), 2.4), reticle2 = lineLayer(Sprite.color(255, 255, 255, 0.8), 2)
    private var motes: [CALayer] = []
    private var particles: [CAShapeLayer] = []
    private var rings: [CAShapeLayer] = []
    private var shots: [Shot] = []
    private var lastVariant: EnergyVariant?
    private var haloImg: CGImage?, coreImg: CGImage?, moteImg: CGImage?

    private struct Shot {
        let box = CALayer()
        let body = CAShapeLayer()
        let arm: [CAShapeLayer] = (0..<3).map { _ in CAShapeLayer() }
        let trail = CAShapeLayer()
    }

    private static let heart: CGPath = heartPath()
    private static let star: CGPath = {
        let p = CGMutablePath()
        for i in 0..<10 {
            let r: CGFloat = i % 2 == 0 ? 1 : 0.45, a = .pi / 2 + CGFloat(i) * .pi / 5
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath(); return p
    }()
    private static let flame: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 1, y: 0))                                             // tip points along +x (the way it flies)
        p.addCurve(to: CGPoint(x: -0.9, y: 0.55), control1: CGPoint(x: 0.4, y: 0.5), control2: CGPoint(x: -0.4, y: 0.75))
        p.addCurve(to: CGPoint(x: -0.9, y: -0.55), control1: CGPoint(x: -1.2, y: 0.2), control2: CGPoint(x: -1.2, y: -0.2))
        p.addCurve(to: CGPoint(x: 1, y: 0), control1: CGPoint(x: -0.4, y: -0.75), control2: CGPoint(x: 0.4, y: -0.5))
        p.closeSubpath(); return p
    }()
    private static let ring: CGPath = CGPath(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2), transform: nil)
    private static let dot: CGPath = CGPath(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2), transform: nil)

    init() {
        root.masksToBounds = false
        for l in [speed, arcs, orbRing, aim, reticle, reticle2] { l.fillColor = nil }
        speed.lineCap = .round
        arcs.lineJoin = .round
        orbRing.lineDashPattern = [12, 7]
        aim.lineDashPattern = [5, 7]; reticle2.lineDashPattern = [6, 5]
        burst.shadowOpacity = 1; burst.shadowRadius = 8; burst.shadowOffset = .zero
        for l in [impactHalo, burst, impactCore, orbHalo, orbBody, orbRing, arcs, speed, aim, reticle, reticle2] { root.addSublayer(l) }
    }

    private func col(_ v: EnergyVariant, _ i: Int, _ a: CGFloat = 1) -> CGColor {
        if i >= v.palette.count { return Sprite.color(40, 30, 36, a) }
        let c = v.palette[i]
        return Sprite.color(Int(c[0]), Int(c[1]), Int(c[2]), a)
    }

    private func retint(_ v: EnergyVariant) {
        guard lastVariant != v else { return }
        lastVariant = v
        let g = col(v, 0), body = col(v, 1), core = col(v, 2)
        func glow(_ inner: CGColor, _ mid: CGColor) -> CGImage? { glowSprite(inner, g.copy(alpha: 0)!, mid: mid) }
        if v == .voidBeam {
            // A black hole: a violet-white glow around a hard black disc.
            haloImg = glow(col(v, 3, 0.55), col(v, 0, 0.35))
            coreImg = Sprite.image(CGSize(width: 64, height: 64), scale: 3) { c in
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                   colors: [Sprite.color(0, 0, 0), Sprite.color(0, 0, 0), Sprite.color(10, 6, 20), self.col(v, 3, 0.95), self.col(v, 0, 0.0)] as CFArray,
                                   locations: [0, 0.5, 0.64, 0.7, 1])!
                c.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
            }
        } else {
            haloImg = glow(col(v, 1, 0.85), col(v, 0, 0.45))
            coreImg = glow(core, col(v, 1, 0.95))
        }
        moteImg = Sprite.image(CGSize(width: 12, height: 12), scale: 3) { c in
            Sprite.radial(c, center: CGPoint(x: 6, y: 6), radius: 5.5, inner: core, outer: self.col(v, 0, 0))
        }
        orbHalo.contents = haloImg; orbBody.contents = coreImg; impactHalo.contents = haloImg; impactCore.contents = coreImg
        for m in motes { m.contents = moteImg }
        arcs.strokeColor = col(v, v == .cero || v == .getsuga ? 3 : 2)
        arcs.shadowColor = col(v, 0); arcs.shadowOpacity = 1; arcs.shadowRadius = 5; arcs.shadowOffset = .zero
        speed.strokeColor = col(v, 2, 0.9)
        orbRing.strokeColor = col(v, 1, 0.8)
        aim.strokeColor = col(v, 1, 0.6); reticle.strokeColor = col(v, 2, 0.9); reticle2.strokeColor = col(v, 1, 0.9)
        burst.fillColor = col(v, 2, 0.95); burst.shadowColor = col(v, v == .voidBeam ? 3 : 1)
        for r in ribbonLayers { r.shadowOpacity = 0 }
    }

    private func ribbonPath(_ pts: [CGPoint], _ hw: [CGFloat]) -> CGPath {
        let path = CGMutablePath()
        guard pts.count > 1 else { return path }
        var top: [CGPoint] = [], bot: [CGPoint] = []
        for i in pts.indices {
            let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)]
            let dx = b.x - a.x, dy = b.y - a.y, l = max(0.001, hypot(dx, dy))
            let nx = -dy / l, ny = dx / l
            top.append(CGPoint(x: pts[i].x + nx * hw[i], y: pts[i].y + ny * hw[i]))
            bot.append(CGPoint(x: pts[i].x - nx * hw[i], y: pts[i].y - ny * hw[i]))
        }
        path.move(to: top[0]); for p in top.dropFirst() { path.addLine(to: p) }
        for p in bot.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    func update(_ s: EnergyScene) {
        retint(s.variant)
        let v = s.variant
        root.opacity = Float(s.alpha)
        // Ribbons.
        while ribbonLayers.count < 5 { let l = CAShapeLayer(); l.shadowOffset = .zero; l.zPosition = CGFloat(ribbonLayers.count) - 20; root.addSublayer(l); ribbonLayers.append(l) }
        for (i, l) in ribbonLayers.enumerated() {
            guard i < s.ribbons.count else { l.isHidden = true; continue }
            let r = s.ribbons[i]
            l.isHidden = false
            l.path = ribbonPath(r.centerline, r.halfWidth)
            l.fillColor = col(v, r.role, r.alpha)
            l.shadowColor = col(v, r.role == 3 ? 0 : r.role); l.shadowOpacity = r.role == 0 ? 1 : 0; l.shadowRadius = 14
        }
        // Strands (helices, weaving ribbons).
        while strandLayers.count < s.strands.count {
            let l = lineLayer(Sprite.color(255, 255, 255), 3); root.insertSublayer(l, below: speed); strandLayers.append(l)
        }
        for (i, l) in strandLayers.enumerated() {
            guard i < s.strands.count else { l.isHidden = true; continue }
            l.isHidden = false
            l.path = polyline(s.strands[i])
            l.strokeColor = col(v, s.strandRole, 0.95); l.lineWidth = v == .moonPrism ? 4 : 3
            l.shadowColor = col(v, s.strandRole); l.shadowOpacity = 0.9; l.shadowRadius = 4; l.shadowOffset = .zero
        }
        // Speed lines and lightning.
        let sp = CGMutablePath()
        for l in s.speedLines { sp.move(to: l.0); sp.addLine(to: l.1) }
        speed.path = sp; speed.opacity = Float(s.speedLines.first?.2 ?? 0)
        let ap = CGMutablePath()
        for arc in s.arcs { if let f = arc.first { ap.move(to: f); for q in arc.dropFirst() { ap.addLine(to: q) } } }
        arcs.path = ap; arcs.opacity = Float(0.4 + 0.6 * s.charge)
        // The charging orb.
        let R = s.orbRadius
        orbHalo.bounds = CGRect(x: 0, y: 0, width: R * 5.4, height: R * 5.4); orbHalo.position = s.orb
        orbHalo.opacity = Float(0.5 + 0.5 * s.charge)
        orbBody.bounds = CGRect(x: 0, y: 0, width: R * 2.5, height: R * 2.5); orbBody.position = s.orb
        orbBody.opacity = Float(min(1, 0.8 + s.flash))
        orbRing.path = circlePath(s.orb, R * 1.25); orbRing.lineDashPhase = -s.phase * 60; orbRing.opacity = Float(0.4 + 0.5 * s.charge)
        for (i, m) in s.motes.enumerated() {
            while motes.count <= i { let l = CALayer(); l.contents = moteImg; root.addSublayer(l); motes.append(l) }
            motes[i].position = m.0; motes[i].opacity = Float(m.1); motes[i].bounds = CGRect(x: 0, y: 0, width: m.2 * 2.6, height: m.2 * 2.6)
        }
        // Impact.
        let showImpact = s.impactAmount > 0.08 || s.flash > 0
        impactHalo.isHidden = !showImpact; burst.isHidden = !showImpact; impactCore.isHidden = !showImpact
        if showImpact {
            let r = s.impactRadius
            impactHalo.bounds = CGRect(x: 0, y: 0, width: r * 5, height: r * 5); impactHalo.position = s.impact
            impactCore.bounds = CGRect(x: 0, y: 0, width: r * 2.2, height: r * 2.2); impactCore.position = s.impact
            let bp = CGMutablePath()
            let spikes = v == .finalFlash ? 14 : (v == .getsuga ? 4 : 8)
            for i in 0..<(spikes * 2) {
                let a = s.spin + CGFloat(i) * .pi / CGFloat(spikes)
                let rr = i % 2 == 0 ? r * (1.7 + 0.35 * CGFloat(sin(Double(s.phase * 17 + CGFloat(i))))) : r * 0.55
                let pt = CGPoint(x: s.impact.x + cos(a) * rr, y: s.impact.y + sin(a) * rr)
                i == 0 ? bp.move(to: pt) : bp.addLine(to: pt)
            }
            bp.closeSubpath(); burst.path = bp
            burst.opacity = Float(min(1, 0.4 + 0.6 * s.impactAmount))
        }
        // Particles of any shape.
        while particles.count < s.particles.count { let l = CAShapeLayer(); root.addSublayer(l); particles.append(l) }
        for (i, l) in particles.enumerated() {
            guard i < s.particles.count else { l.isHidden = true; continue }
            let p = s.particles[i]
            l.isHidden = p.alpha < 0.02
            switch p.shape {
            case 1: l.path = Self.heart
            case 2: l.path = Self.star
            case 3: l.path = Self.flame
            case 4: l.path = Self.ring
            default: l.path = Self.dot
            }
            l.fillColor = p.shape == 4 ? nil : col(v, p.color)
            l.strokeColor = p.shape == 4 ? col(v, p.color) : nil
            l.lineWidth = p.shape == 4 ? 0.14 : 0
            l.opacity = Float(p.alpha)
            l.transform = CATransform3DScale(CATransform3DMakeRotation(p.angle, 0, 0, 1), p.size, p.size, 1)
            l.position = p.position
        }
        // Rings and the aim reticle.
        while rings.count < s.rings.count { let l = lineLayer(Sprite.color(255, 255, 255), 3); l.shadowOpacity = 1; l.shadowRadius = 6; l.shadowOffset = .zero; root.addSublayer(l); rings.append(l) }
        for (i, l) in rings.enumerated() {
            guard i < s.rings.count else { l.isHidden = true; continue }
            l.isHidden = false; l.path = circlePath(s.impact, s.rings[i].0); l.opacity = Float(s.rings[i].1)
            l.strokeColor = col(v, 2); l.shadowColor = col(v, 0)
        }
        aim.isHidden = s.aimLine.isEmpty; reticle.isHidden = s.aimLine.isEmpty; reticle2.isHidden = s.aimLine.isEmpty
        if !s.aimLine.isEmpty {
            aim.path = polyline(s.aimLine); aim.lineDashPhase = -s.phase * 30; aim.opacity = Float(s.reticle)
            reticle.path = circlePath(s.impact, 16 + 3 * CGFloat(sin(Double(s.phase * 6)))); reticle.opacity = Float(s.reticle)
            reticle2.path = circlePath(s.impact, 26); reticle2.lineDashPhase = s.phase * 40; reticle2.opacity = Float(s.reticle)
        }
        // Projectiles.
        while shots.count < s.projectiles.count {
            let sh = Shot()
            for l in [sh.trail, sh.body] + sh.arm { sh.box.addSublayer(l) }
            root.addSublayer(sh.box); shots.append(sh)
        }
        for (i, sh) in shots.enumerated() {
            guard i < s.projectiles.count else { sh.box.isHidden = true; continue }
            let p = s.projectiles[i]
            sh.box.isHidden = p.alpha < 0.02; sh.box.opacity = Float(p.alpha)
            sh.box.position = p.position
            sh.box.transform = CATransform3DMakeRotation(p.angle, 0, 0, 1)
            let z = p.size
            // The trail, in the shot's local frame (it streams backward).
            let tp = CGMutablePath()
            for (k, q) in p.trail.enumerated() {
                let loc = CGPoint(x: (q.x - p.position.x) * cos(p.angle) + (q.y - p.position.y) * sin(p.angle), y: -(q.x - p.position.x) * sin(p.angle) + (q.y - p.position.y) * cos(p.angle))
                k == 0 ? tp.move(to: loc) : tp.addLine(to: loc)
            }
            sh.trail.path = tp; sh.trail.fillColor = nil; sh.trail.strokeColor = col(v, 0, 0.7); sh.trail.lineWidth = p.kind == 1 ? z * 0.16 : z * 0.5; sh.trail.lineCap = .round
            sh.trail.shadowColor = col(v, 0); sh.trail.shadowOpacity = 1; sh.trail.shadowRadius = 8; sh.trail.shadowOffset = .zero
            switch p.kind {
            case 1:                                                                  // crescent slash
                let cp = CGMutablePath()
                let big = z * 1.9
                cp.addArc(center: CGPoint(x: -big * 0.35, y: 0), radius: big, startAngle: -.pi * 0.46, endAngle: .pi * 0.46, clockwise: false)
                cp.addArc(center: CGPoint(x: -big * 0.95, y: 0), radius: big * 1.28, startAngle: .pi * 0.36, endAngle: -.pi * 0.36, clockwise: true)
                cp.closeSubpath()
                sh.body.path = cp; sh.body.fillColor = col(v, 1); sh.body.strokeColor = col(v, 2); sh.body.lineWidth = 4
                sh.body.shadowColor = col(v, 0); sh.body.shadowOpacity = 1; sh.body.shadowRadius = 10; sh.body.shadowOffset = .zero
                for a in sh.arm { a.isHidden = true }
            case 0:                                                                  // spiral sphere
                sh.body.path = circlePath(.zero, z); sh.body.fillColor = col(v, 1, 0.9); sh.body.strokeColor = col(v, 2); sh.body.lineWidth = 2
                sh.body.shadowColor = col(v, 0); sh.body.shadowOpacity = 1; sh.body.shadowRadius = 12; sh.body.shadowOffset = .zero
                for (k, a) in sh.arm.enumerated() {
                    a.isHidden = false
                    let sp = CGMutablePath()
                    let ph = s.phase * 9 + CGFloat(k) * 2.094
                    for j in 0...16 {
                        let u = CGFloat(j) / 16, r = z * (0.1 + 0.85 * u), th = ph + u * 4.2
                        let pt = CGPoint(x: cos(th) * r, y: sin(th) * r)
                        j == 0 ? sp.move(to: pt) : sp.addLine(to: pt)
                    }
                    a.path = sp; a.fillColor = nil; a.strokeColor = col(v, k == 0 ? 2 : 3); a.lineWidth = 3; a.lineCap = .round
                }
            default:                                                                 // great orb
                sh.body.path = circlePath(.zero, z); sh.body.fillColor = col(v, 2, 0.95); sh.body.strokeColor = col(v, 1); sh.body.lineWidth = 4
                sh.body.shadowColor = col(v, 0); sh.body.shadowOpacity = 1; sh.body.shadowRadius = 22; sh.body.shadowOffset = .zero
                for (k, a) in sh.arm.enumerated() {
                    a.isHidden = false
                    let sp = CGMutablePath()
                    let ph = -s.phase * 3 + CGFloat(k) * 2.094
                    for j in 0...14 {
                        let u = CGFloat(j) / 14, r = z * (0.15 + 0.8 * u), th = ph + u * 3
                        let pt = CGPoint(x: cos(th) * r, y: sin(th) * r)
                        j == 0 ? sp.move(to: pt) : sp.addLine(to: pt)
                    }
                    a.path = sp; a.fillColor = nil; a.strokeColor = col(v, 1, 0.7); a.lineWidth = 4; a.lineCap = .round
                }
            }
        }
    }
}
