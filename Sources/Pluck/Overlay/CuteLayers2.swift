import AppKit
import PluckCore
import QuartzCore

private func hsv(_ h: CGFloat, _ s: CGFloat, _ v: CGFloat, _ a: CGFloat = 1) -> CGColor {
    let c = NSColor(hue: h.truncatingRemainder(dividingBy: 1), saturation: s, brightness: v, alpha: a).usingColorSpace(.sRGB)!
    return CGColor(srgbRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: a)
}

// MARK: - Tug of war

@MainActor
final class TugLayers {
    let root = CALayer()
    private let ropeShadow = lineLayer(paperWhite, 8, depth: 1.4), rope = lineLayer(Sprite.color(206, 160, 100), 5), twist = lineLayer(Sprite.color(150, 106, 64), 5)
    private let pole = lineLayer(Sprite.color(150, 106, 64), 2.4), flagShape = paperShape(Sprite.color(235, 80, 90), border: 1.8, depth: 1.2)
    private let fighterA = Fighter(bear: true), fighterB = Fighter(bear: false)
    private lazy var dust = DotPool(parent: root, image: softDot)

    init() {
        root.masksToBounds = false
        twist.lineDashPattern = [3, 8]
        for l in [ropeShadow, rope, twist, pole, flagShape, fighterA.root, fighterB.root] { root.addSublayer(l) }
    }

    func update(_ s: TugScene) {
        root.opacity = Float(s.alpha)
        let p = polyline(s.rope)
        ropeShadow.path = p; rope.path = p; twist.path = p
        // Fighters always stand upright; they only mirror to face their opponent and lift their arms toward the rope.
        let toHead = CGPoint(x: cos(s.axis), y: sin(s.axis))
        fighterA.update(at: s.pin, size: s.pinSize, toward: toHead, lean: s.pinLean, strain: s.strain)
        fighterB.update(at: s.head, size: s.headSize, toward: CGPoint(x: -toHead.x, y: -toHead.y), lean: s.headLean, strain: s.strain)
        // The flag on the rope.
        let f = s.flag, a = s.flagAngle
        let up = CGPoint(x: -sin(a), y: cos(a))
        pole.path = polyline([f, CGPoint(x: f.x + up.x * 26, y: f.y + up.y * 26)])
        let top = CGPoint(x: f.x + up.x * 26, y: f.y + up.y * 26), mid = CGPoint(x: f.x + up.x * 17, y: f.y + up.y * 17)
        let side = CGPoint(x: cos(a) * 15, y: sin(a) * 15)
        let fp = CGMutablePath(); fp.move(to: top); fp.addLine(to: CGPoint(x: top.x + side.x, y: top.y + side.y - 2)); fp.addLine(to: mid); fp.closeSubpath()
        flagShape.path = fp
        for (i, d) in s.dust.enumerated() { dust.place(i, at: d.0, size: d.2 * 1.6, alpha: d.1) }
    }

    @MainActor final class Fighter {
        let root = CALayer()
        private let earA: CAShapeLayer, earB: CAShapeLayer, body: CAShapeLayer
        private let belly = CAShapeLayer(), eyeA = lineLayer(Sprite.color(66, 48, 48), 2.4), eyeB = lineLayer(Sprite.color(66, 48, 48), 2.4)
        private let mouth = lineLayer(Sprite.color(66, 48, 48), 2), cheek = CAShapeLayer(), arm = paperShape(nil, border: 1.8, depth: 1.2)
        private let footA: CAShapeLayer, footB: CAShapeLayer
        private let bear: Bool
        init(bear: Bool) {
            self.bear = bear
            let fur = bear ? Sprite.color(176, 124, 84) : Sprite.color(255, 243, 222)
            let dark = bear ? Sprite.color(146, 100, 66) : Sprite.color(255, 214, 170)
            body = paperShape(fur, border: 2.4, depth: 2)
            earA = paperShape(dark, border: 2, depth: 0); earB = paperShape(dark, border: 2, depth: 0)
            footA = paperShape(dark, border: 1.8, depth: 0); footB = paperShape(dark, border: 1.8, depth: 0)
            arm.fillColor = dark
            belly.fillColor = bear ? Sprite.color(222, 190, 150) : Sprite.color(255, 252, 244)
            cheek.fillColor = Sprite.color(255, 143, 163, 0.85)
            for l in [earA, earB, footA, footB, body, belly, cheek, eyeA, eyeB, mouth, arm] { root.addSublayer(l) }
        }
        func update(at p: CGPoint, size R: CGFloat, toward: CGPoint, lean: CGFloat, strain: CGFloat) {
            root.position = p
            // Face the opponent by mirroring (never by rotating), then lean back about the feet.
            let facing: CGFloat = toward.x >= 0 ? 1 : -1
            var local = CATransform3DMakeTranslation(0, -R, 0)
            local = CATransform3DRotate(local, lean, 0, 0, 1)
            local = CATransform3DTranslate(local, 0, R, 0)
            root.transform = CATransform3DConcat(local, CATransform3DMakeScale(facing, 1, 1))
            // Arms reach along the line to the opponent (in the mirrored frame), within a comfortable range.
            let armAngle = max(-0.9, min(0.9, atan2(toward.y, abs(toward.x))))
            let shoulder = CGPoint(x: R * 0.55, y: -R * 0.05)
            var at = CATransform3DMakeTranslation(shoulder.x, shoulder.y, 0)
            at = CATransform3DRotate(at, armAngle, 0, 0, 1)
            arm.transform = CATransform3DTranslate(at, -shoulder.x, -shoulder.y, 0)
            body.path = CGPath(ellipseIn: CGRect(x: -R, y: -R * 0.95, width: R * 2, height: R * 1.9), transform: nil)
            belly.path = CGPath(ellipseIn: CGRect(x: -R * 0.5, y: -R * 0.9, width: R, height: R * 0.8), transform: nil)
            if bear {
                earA.path = circlePath(CGPoint(x: -R * 0.6, y: R * 0.95), R * 0.32); earB.path = circlePath(CGPoint(x: R * 0.6, y: R * 0.95), R * 0.32)
            } else {
                earA.path = CGPath(roundedRect: CGRect(x: -R * 0.62, y: R * 0.6, width: R * 0.36, height: R * 1.1), cornerWidth: R * 0.18, cornerHeight: R * 0.18, transform: nil)
                earB.path = CGPath(roundedRect: CGRect(x: R * 0.26, y: R * 0.6, width: R * 0.36, height: R * 1.1), cornerWidth: R * 0.18, cornerHeight: R * 0.18, transform: nil)
            }
            footA.path = CGPath(ellipseIn: CGRect(x: -R * 0.7, y: -R * 1.12, width: R * 0.6, height: R * 0.36), transform: nil)
            footB.path = CGPath(ellipseIn: CGRect(x: R * 0.1, y: -R * 1.12, width: R * 0.6, height: R * 0.36), transform: nil)
            // Eyes squeezed shut with effort: > <
            let e = R * 0.13
            for (eye, cx) in [(eyeA, R * 0.12), (eyeB, R * 0.6)] {
                let ep = CGMutablePath(); ep.move(to: CGPoint(x: cx - e, y: R * 0.32)); ep.addLine(to: CGPoint(x: cx + e, y: R * 0.18)); ep.addLine(to: CGPoint(x: cx - e, y: R * 0.04))
                eye.path = ep
            }
            cheek.path = circlePath(CGPoint(x: R * 0.42, y: -R * 0.2), R * 0.17)
            let mp = CGMutablePath(); mp.addRoundedRect(in: CGRect(x: R * 0.2, y: -R * 0.42, width: R * 0.46, height: R * 0.18 * (0.6 + 0.4 * strain)), cornerWidth: 2, cornerHeight: 2)
            mouth.path = mp
            // Both arms reach out to the rope.
            arm.path = CGPath(roundedRect: CGRect(x: R * 0.55, y: -R * 0.22, width: R * 1.0, height: R * 0.34), cornerWidth: R * 0.17, cornerHeight: R * 0.17, transform: nil)
        }
    }
}

// MARK: - Newton's cradle

@MainActor
final class CradleLayers {
    let root = CALayer()
    private let legA = lineLayer(Sprite.color(176, 124, 84), 5, depth: 1.4), legB = lineLayer(Sprite.color(176, 124, 84), 5, depth: 1.4)
    private let bar = lineLayer(Sprite.color(206, 156, 112), 8, depth: 1.6)
    private let strings = lineLayer(Sprite.color(255, 250, 238, 0.9), 1.4)
    private var balls: [CALayer] = []
    private let footA = PaperDisc(Sprite.color(255, 128, 118)), footB = PaperDisc(Sprite.color(92, 196, 190))
    private lazy var clicks = DotPool(parent: root, image: softDot)
    private static let steel = glossySphere(Sprite.color(255, 255, 255), Sprite.color(130, 140, 165), rim: Sprite.color(255, 250, 238))

    init() { root.masksToBounds = false; for l in [footA.root, footB.root, legA, legB, bar, strings] { root.addSublayer(l) } }

    func update(_ s: CradleScene) {
        root.opacity = Float(s.alpha)
        footA.update(at: s.pin, r: s.pinRadius * 0.8); footB.update(at: s.head, r: s.headRadius * 0.8)
        let pinIsLeft = s.pin.x <= s.head.x
        legA.path = polyline([s.pin, pinIsLeft ? s.barA : s.barB]); legB.path = polyline([s.head, pinIsLeft ? s.barB : s.barA]); bar.path = polyline([s.barA, s.barB])
        let sp = CGMutablePath()
        for (i, b) in s.balls.enumerated() { sp.move(to: s.tops[i]); sp.addLine(to: b.0) }
        strings.path = sp
        while balls.count < s.balls.count { let l = CALayer(); l.contents = Self.steel; root.addSublayer(l); balls.append(l) }
        for (i, b) in s.balls.enumerated() {
            balls[i].bounds = CGRect(x: 0, y: 0, width: b.1 * 2.2, height: b.1 * 2.2); balls[i].position = b.0
        }
        for (i, c) in s.clicks.enumerated() { clicks.place(i, at: c.0, size: 46, alpha: c.1) }
        clicks.hide(from: s.clicks.count)
    }
}

// MARK: - Rainbow

@MainActor
final class RainbowLayers {
    let root = CALayer()
    private let glow = lineLayer(Sprite.color(255, 255, 255, 0.16), 20)
    private var bands: [CAShapeLayer] = []
    private var cloudsA: [CAShapeLayer] = [], cloudsB: [CAShapeLayer] = []
    private lazy var sparkles = DotPool(parent: root, image: softDot)

    init() {
        root.masksToBounds = false
        glow.shadowColor = Sprite.color(255, 255, 255); glow.shadowOpacity = 0.5; glow.shadowRadius = 8; glow.shadowOffset = .zero
        root.addSublayer(glow)
        for k in 0..<7 {
            let l = lineLayer(hsv(0.0 + CGFloat(k) * 0.13, 0.62, 1), 8); l.lineCap = .butt
            root.addSublayer(l); bands.append(l)
        }
    }

    private func clouds(_ pool: inout [CAShapeLayer], _ puffs: [(CGPoint, CGFloat)]) {
        while pool.count < puffs.count {
            let l = paperShape(Sprite.color(255, 255, 255), border: 2.4, depth: 2); root.addSublayer(l); pool.append(l)
        }
        for (i, l) in pool.enumerated() where i < puffs.count { l.path = circlePath(puffs[i].0, puffs[i].1) }
    }

    func update(_ s: RainbowScene) {
        root.opacity = Float(s.alpha)
        for (i, b) in bands.enumerated() { b.path = polyline(s.bands[i]); b.lineWidth = s.bandWidth }
        glow.path = polyline(s.bands[3]); glow.lineWidth = s.bandWidth * 7.0
        clouds(&cloudsA, s.cloudPin); clouds(&cloudsB, s.cloudHead)
        for (i, sp) in s.sparkles.enumerated() { sparkles.place(i, at: sp.0, size: sp.2 * 2.4, alpha: sp.1) }
        sparkles.hide(from: s.sparkles.count)
        for l in cloudsA + cloudsB { l.zPosition = 2 }
    }
}

// MARK: - Dandelion

@MainActor
final class DandelionLayers {
    let root = CALayer()
    private let core = paperShape(Sprite.color(236, 226, 206), border: 1.6, depth: 0)
    private let seeds = lineLayer(Sprite.color(255, 255, 255, 0.95), 1.3), tufts = lineLayer(Sprite.color(255, 255, 255, 0.9), 1)
    private let stem = lineLayer(Sprite.color(112, 190, 112), 5, depth: 1.4), mound = paperShape(Sprite.color(156, 112, 76), border: 1.8, depth: 1)
    private let leafA = paperShape(Sprite.color(112, 190, 112), border: 1.6, depth: 0), leafB = paperShape(Sprite.color(112, 190, 112), border: 1.6, depth: 0)
    private var petals: [CAShapeLayer] = []
    private let heart = paperShape(Sprite.color(255, 207, 86), border: 1.6, depth: 0)
    private var flyers: [(CALayer, CAShapeLayer, CAShapeLayer)] = []

    init() {
        root.masksToBounds = false
        for l in [mound, stem, leafA, leafB] { root.addSublayer(l) }
        for i in 0..<9 { let p = paperShape(Sprite.color(255, 226, 120), border: 1.4, depth: 0); root.addSublayer(p); petals.append(p); _ = i }
        for l in [heart, core, seeds, tufts] { root.addSublayer(l) }
    }

    private func seedPath(_ p: CGMutablePath, from a: CGPoint, to b: CGPoint, tuft: CGMutablePath, R: CGFloat) {
        p.move(to: a); p.addLine(to: b)
        for k in 0..<8 {
            let ang = CGFloat(k) / 8 * 2 * .pi
            tuft.move(to: b); tuft.addLine(to: CGPoint(x: b.x + cos(ang) * R * 0.2, y: b.y + sin(ang) * R * 0.2))
        }
    }

    func update(_ s: DandelionScene) {
        root.opacity = Float(s.alpha)
        let R = s.ballRadius
        core.path = circlePath(s.ball, max(3, R * 0.2))
        let sp = CGMutablePath(), tp = CGMutablePath()
        for a in s.seedAngles {
            seedPath(sp, from: CGPoint(x: s.ball.x + cos(a) * R * 0.2, y: s.ball.y + sin(a) * R * 0.2),
                     to: CGPoint(x: s.ball.x + cos(a) * R * 0.82, y: s.ball.y + sin(a) * R * 0.82), tuft: tp, R: R)
        }
        seeds.path = sp; tufts.path = tp
        // Sprout at the head.
        let h = s.sproutHeight, hp = s.sprout
        mound.path = CGPath(ellipseIn: CGRect(x: hp.x - s.sproutRadius * 0.9, y: hp.y - s.sproutRadius * 0.55, width: s.sproutRadius * 1.8, height: s.sproutRadius * 0.7), transform: nil)
        let top = CGPoint(x: hp.x + 4 * CGFloat(sin(Double(s.bloom * 6))), y: hp.y + h)
        let st = CGMutablePath(); st.move(to: CGPoint(x: hp.x, y: hp.y - s.sproutRadius * 0.15)); st.addQuadCurve(to: top, control: CGPoint(x: hp.x - 8, y: hp.y + h * 0.5))
        stem.path = st
        let lw = s.sproutRadius * 0.9
        leafA.path = CGPath(ellipseIn: CGRect(x: hp.x - lw * 1.4, y: hp.y + h * 0.28, width: lw * 1.3, height: lw * 0.6), transform: nil)
        leafB.path = CGPath(ellipseIn: CGRect(x: hp.x + lw * 0.1, y: hp.y + h * 0.42, width: lw * 1.3, height: lw * 0.6), transform: nil)
        let pr = s.sproutRadius * 0.5 * s.bloom
        for (i, p) in petals.enumerated() {
            let a = CGFloat(i) / CGFloat(petals.count) * 2 * .pi
            p.isHidden = pr < 1
            p.path = circlePath(CGPoint(x: top.x + cos(a) * pr * 1.1, y: top.y + sin(a) * pr * 1.1), pr * 0.62)
        }
        heart.path = circlePath(top, max(2, pr * 0.75)); heart.isHidden = pr < 1
        // Drifting seeds with their little parachutes.
        while flyers.count < s.flying.count {
            let box = CALayer(), a = lineLayer(Sprite.color(255, 255, 255, 0.95), 1.4), b = lineLayer(Sprite.color(255, 255, 255, 0.95), 1)
            box.addSublayer(a); box.addSublayer(b); root.addSublayer(box); flyers.append((box, a, b))
        }
        for (i, f) in flyers.enumerated() {
            guard i < s.flying.count else { f.0.isHidden = true; continue }
            let sd = s.flying[i]
            f.0.isHidden = sd.alpha < 0.02; f.0.opacity = Float(sd.alpha)
            f.0.position = sd.position; f.0.transform = CATransform3DMakeRotation(sd.angle, 0, 0, 1)
            let z = sd.size
            let stemP = CGMutablePath(); stemP.move(to: CGPoint(x: 0, y: -z * 0.45)); stemP.addLine(to: CGPoint(x: 0, y: z * 0.1))
            f.1.path = stemP
            let fl = CGMutablePath()
            for k in 0..<9 { let a = .pi / 2 + (CGFloat(k) - 4) * 0.28; fl.move(to: CGPoint(x: 0, y: z * 0.1)); fl.addLine(to: CGPoint(x: cos(a) * z * 0.5, y: z * 0.1 + sin(a) * z * 0.5)) }
            f.2.path = fl
        }
    }
}

// MARK: - Cable car

@MainActor
final class CableCarLayers {
    let root = CALayer()
    private let cableA = lineLayer(Sprite.color(90, 98, 120), 2.4, depth: 1), cableB = lineLayer(Sprite.color(90, 98, 120), 2.4)
    private let towerA = paperShape(Sprite.color(255, 128, 118), border: 2.4, depth: 2), towerB = paperShape(Sprite.color(92, 196, 190), border: 2.4, depth: 2)
    private let hanger = lineLayer(Sprite.color(70, 76, 96), 2.4), wheel = paperShape(Sprite.color(150, 160, 178), border: 1.6, depth: 0)
    private let cabin = paperShape(Sprite.color(235, 80, 90), border: 2.4, depth: 2), roofC = paperShape(Sprite.color(255, 207, 86), border: 2, depth: 0)
    private var windows: [CAShapeLayer] = []
    private let face = paperShape(Sprite.color(255, 243, 222), border: 1.4, depth: 0), earL = CAShapeLayer(), earR = CAShapeLayer()

    init() {
        root.masksToBounds = false
        for l in [cableB, cableA, towerA, towerB, hanger, wheel, cabin, roofC] { root.addSublayer(l) }
        for _ in 0..<3 { let w = paperShape(Sprite.color(190, 228, 255), border: 1.4, depth: 0); root.addSublayer(w); windows.append(w) }
        earL.fillColor = Sprite.color(255, 214, 170); earR.fillColor = Sprite.color(255, 214, 170)
        for l in [earL, earR, face] { root.addSublayer(l) }
    }

    func update(_ s: CableScene) {
        root.opacity = Float(s.alpha)
        cableA.path = polyline(s.cableA); cableB.path = polyline(s.cableB)
        for (t, p, r) in [(towerA, s.pin, s.pinRadius), (towerB, s.head, s.headRadius)] {
            let h = r * 2.6
            let path = CGMutablePath()
            path.move(to: CGPoint(x: p.x - r * 0.7, y: p.y - r * 0.9)); path.addLine(to: CGPoint(x: p.x - r * 0.18, y: p.y - r * 0.9 + h))
            path.addLine(to: CGPoint(x: p.x + r * 0.18, y: p.y - r * 0.9 + h)); path.addLine(to: CGPoint(x: p.x + r * 0.7, y: p.y - r * 0.9)); path.closeSubpath()
            t.path = path
        }
        hanger.path = polyline([s.pulley, s.car])
        wheel.path = circlePath(s.pulley, 5)
        let R = s.carSize
        let tr = CGAffineTransform(translationX: s.car.x, y: s.car.y).rotated(by: s.carAngle)
        var t1 = tr
        cabin.path = CGPath(roundedRect: CGRect(x: -R * 0.9, y: -R * 0.7, width: R * 1.8, height: R * 1.3), cornerWidth: R * 0.28, cornerHeight: R * 0.28, transform: &t1)
        var t2 = tr
        roofC.path = CGPath(roundedRect: CGRect(x: -R * 1.0, y: R * 0.5, width: R * 2.0, height: R * 0.28), cornerWidth: R * 0.14, cornerHeight: R * 0.14, transform: &t2)
        for (i, w) in windows.enumerated() {
            var t3 = tr
            let x = -R * 0.72 + CGFloat(i) * R * 0.52
            w.path = CGPath(roundedRect: CGRect(x: x, y: -R * 0.35, width: R * 0.42, height: R * 0.56), cornerWidth: R * 0.1, cornerHeight: R * 0.1, transform: &t3)
        }
        // A little passenger waves from the middle window.
        var t4 = tr; var t5 = tr; var t6 = tr
        face.path = circlePath(.zero, 0).copy(using: &t4)
        let fc = CGPoint(x: -R * 0.72 + R * 0.52 + R * 0.21, y: -R * 0.05)
        face.path = CGPath(ellipseIn: CGRect(x: fc.x - R * 0.17, y: fc.y - R * 0.17, width: R * 0.34, height: R * 0.34), transform: &t6)
        earL.path = CGPath(ellipseIn: CGRect(x: fc.x - R * 0.17, y: fc.y + R * 0.1, width: R * 0.1, height: R * 0.3), transform: &t4)
        earR.path = CGPath(ellipseIn: CGRect(x: fc.x + R * 0.07, y: fc.y + R * 0.1, width: R * 0.1, height: R * 0.3), transform: &t5)
    }
}

// MARK: - Signal

@MainActor
final class SignalLayers {
    let root = CALayer()
    private let link = lineLayer(Sprite.color(255, 255, 255, 0.25), 1.6)
    private let discA = PaperDisc(Sprite.color(255, 128, 118)), discB = PaperDisc(Sprite.color(92, 196, 190))
    private let glyphA = lineLayer(paperWhite, 2.6), glyphB = lineLayer(paperWhite, 2.6)
    private var arcs: [CAShapeLayer] = []
    private var packets: [CAShapeLayer] = []
    private static let cols = [Sprite.color(255, 207, 86), Sprite.color(255, 128, 118), Sprite.color(92, 196, 190)]

    init() {
        root.masksToBounds = false
        link.lineDashPattern = [4, 8]
        for l in [link, discA.root, discB.root, glyphA, glyphB] { root.addSublayer(l) }
    }

    private func glyph(_ layer: CAShapeLayer, at c: CGPoint, r: CGFloat, level: CGFloat) {
        let p = CGMutablePath()
        for k in 1...3 {
            let rad = r * 0.2 * CGFloat(k) * 1.15
            p.addArc(center: CGPoint(x: c.x, y: c.y - r * 0.28), radius: rad, startAngle: .pi * 0.3, endAngle: .pi * 0.7, clockwise: false)
            p.move(to: CGPoint(x: c.x + cos(.pi * 0.3) * rad * 0 + 0, y: c.y))
        }
        p.addEllipse(in: CGRect(x: c.x - 1.8, y: c.y - r * 0.3 - 1.8, width: 3.6, height: 3.6))
        layer.path = p
        layer.opacity = Float(0.5 + 0.5 * level)
    }

    func update(_ s: SignalScene) {
        root.opacity = Float(s.alpha)
        link.path = polyline(s.line)
        discA.update(at: s.pin, r: s.pinRadius); discB.update(at: s.head, r: s.headRadius)
        glyph(glyphA, at: s.pin, r: s.pinRadius, level: 1); glyph(glyphB, at: s.head, r: s.headRadius, level: s.strength)
        while arcs.count < s.waves.count {
            let l = lineLayer(Sprite.color(255, 255, 255), 3); l.lineCap = .round; root.addSublayer(l); arcs.append(l)
        }
        for (i, w) in s.waves.enumerated() {
            let p = CGMutablePath()
            p.addArc(center: w.0, radius: w.1, startAngle: w.3 - 0.9, endAngle: w.3 + 0.9, clockwise: false)
            arcs[i].path = p; arcs[i].opacity = Float(w.2)
            arcs[i].strokeColor = i % 2 == 0 ? Sprite.color(255, 160, 140) : Sprite.color(120, 220, 215)
        }
        while packets.count < s.packets.count {
            let l = paperShape(Self.cols[packets.count % 3], border: 1.4, depth: 1); root.addSublayer(l); packets.append(l)
        }
        for (i, pk) in s.packets.enumerated() {
            packets[i].path = CGPath(roundedRect: CGRect(x: pk.0.x - 5, y: pk.0.y - 3.5, width: 10, height: 7), cornerWidth: 2, cornerHeight: 2, transform: nil)
            packets[i].fillColor = Self.cols[pk.2]
            packets[i].opacity = Float(pk.1)
        }
    }
}
