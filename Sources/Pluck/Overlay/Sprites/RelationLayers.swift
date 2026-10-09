import AppKit
import PluckCore
import QuartzCore

// Sprite renderers for the "relationship" styles: lightning, magnet field, slinky, tin-can phone, red thread.

func glowSprite(_ inner: CGColor, _ outer: CGColor, size: CGFloat = 64, stop: CGFloat = 0.35, mid: CGColor? = nil) -> CGImage? {
    Sprite.image(CGSize(width: size, height: size), scale: 3) { c in
        let cols = [inner, mid ?? inner, outer] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cols, locations: [0, stop, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0,
                             endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size / 2, options: [])
    }
}

func glossySphere(_ light: CGColor, _ dark: CGColor, rim: CGColor) -> CGImage? {
    Sprite.image(CGSize(width: 100, height: 100), scale: 3) { c in
        let r: CGFloat = 46, ctr = CGPoint(x: 50, y: 50)
        c.saveGState()
        c.addEllipse(in: CGRect(x: ctr.x - r, y: ctr.y - r, width: r * 2, height: r * 2)); c.clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [light, dark] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: 36, y: 64), startRadius: 2, endCenter: ctr, endRadius: r * 1.15, options: [.drawsAfterEndLocation])
        c.restoreGState()
        c.setStrokeColor(rim); c.setLineWidth(3)
        c.strokeEllipse(in: CGRect(x: ctr.x - r, y: ctr.y - r, width: r * 2, height: r * 2))
        c.setFillColor(Sprite.color(255, 255, 255, 0.8))
        c.fillEllipse(in: CGRect(x: 28, y: 60, width: 18, height: 11))
    }
}

func heartPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: -1))
    p.addCurve(to: CGPoint(x: -1, y: 0.3), control1: CGPoint(x: -0.3, y: -0.75), control2: CGPoint(x: -1, y: -0.25))
    p.addCurve(to: CGPoint(x: 0, y: 0.42), control1: CGPoint(x: -1, y: 0.98), control2: CGPoint(x: -0.2, y: 1.0))
    p.addCurve(to: CGPoint(x: 1, y: 0.3), control1: CGPoint(x: 0.2, y: 1.0), control2: CGPoint(x: 1, y: 0.98))
    p.addCurve(to: CGPoint(x: 0, y: -1), control1: CGPoint(x: 1, y: -0.25), control2: CGPoint(x: 0.3, y: -0.75))
    p.closeSubpath()
    return p
}

// MARK: - Lightning

@MainActor
final class LightningLayers {
    let root = CALayer()
    private let wide = CAShapeLayer(), mid = CAShapeLayer(), core = CAShapeLayer()
    private let pinOrb = CALayer(), headOrb = CALayer(), pinHalo = CALayer(), headHalo = CALayer(), flashLayer = CALayer()
    private static let sphere = glossySphere(Sprite.color(232, 228, 255), Sprite.color(90, 80, 150), rim: Sprite.color(255, 255, 255, 0.9))
    private static let halo = glowSprite(Sprite.color(200, 170, 255, 0.7), Sprite.color(150, 110, 255, 0), mid: Sprite.color(170, 130, 255, 0.35))

    init() {
        root.masksToBounds = false
        for l in [wide, mid, core] { l.fillColor = nil; l.lineCap = .round; l.lineJoin = .round }
        wide.strokeColor = Sprite.color(140, 100, 255, 0.5)
        wide.shadowColor = Sprite.color(170, 130, 255); wide.shadowOpacity = 1; wide.shadowRadius = 14; wide.shadowOffset = .zero
        mid.strokeColor = Sprite.color(205, 190, 255)
        core.strokeColor = Sprite.color(255, 255, 255)
        core.shadowColor = Sprite.color(255, 255, 255); core.shadowOpacity = 1; core.shadowRadius = 4; core.shadowOffset = .zero
        for l in [pinHalo, headHalo] { l.contents = Self.halo }
        for l in [pinOrb, headOrb] { l.contents = Self.sphere }
        for l in [pinHalo, headHalo, wide, mid, core, pinOrb, headOrb] { root.addSublayer(l) }
    }

    func update(_ s: LightningScene) {
        root.opacity = Float(s.alpha)
        let wp = CGMutablePath(), mp = CGMutablePath(), cp = CGMutablePath()
        var wmax: CGFloat = 0
        // Weights are shared per bolt, so draw each bolt into the layer matching its weight band.
        for (i, bolt) in s.bolts.enumerated() {
            guard let f = bolt.first else { continue }
            let target = s.weights[i] > 0.8 ? 0 : 1
            _ = target
            for p in [wp, mp, cp] { p.move(to: f); for q in bolt.dropFirst() { p.addLine(to: q) } }
            wmax = max(wmax, s.weights[i])
        }
        wide.path = wp; mid.path = mp; core.path = cp
        let k = 0.8 + 1.0 * s.intensity
        wide.lineWidth = 16 * k; mid.lineWidth = 6 * k; core.lineWidth = max(1.8, 2.6 * k)
        let on = s.intensity > 0.02
        for l in [wide, mid, core] { l.isHidden = !on; l.opacity = Float(min(1, 0.6 + 0.5 * s.flash + 0.3 * s.intensity)) }
        for (orb, halo, p, r) in [(pinOrb, pinHalo, s.pin, s.pinRadius), (headOrb, headHalo, s.head, s.headRadius)] {
            orb.bounds = CGRect(x: 0, y: 0, width: r * 2.1, height: r * 2.1); orb.position = p
            halo.bounds = CGRect(x: 0, y: 0, width: r * 5, height: r * 5); halo.position = p
            halo.opacity = Float(0.35 + 0.65 * min(1, s.intensity + s.flash))
        }
    }
}

// MARK: - Magnet

@MainActor
final class MagnetLayers {
    let root = CALayer()
    private let flowLines = CAShapeLayer(), baseLines = CAShapeLayer()
    private let north = CALayer(), south = CALayer()
    private let nText = CATextLayer(), sText = CATextLayer()
    private static let red = glossySphere(Sprite.color(255, 150, 140), Sprite.color(190, 40, 50), rim: Sprite.color(255, 250, 238))
    private static let blue = glossySphere(Sprite.color(150, 200, 255), Sprite.color(40, 80, 190), rim: Sprite.color(255, 250, 238))

    init() {
        root.masksToBounds = false
        baseLines.fillColor = nil; baseLines.strokeColor = Sprite.color(190, 210, 255, 0.28); baseLines.lineWidth = 1.2
        flowLines.fillColor = nil; flowLines.strokeColor = Sprite.color(255, 255, 255, 0.85); flowLines.lineWidth = 2.2
        flowLines.lineCap = .round; flowLines.lineDashPattern = [3, 11]
        flowLines.shadowColor = Sprite.color(170, 200, 255); flowLines.shadowOpacity = 1; flowLines.shadowRadius = 3; flowLines.shadowOffset = .zero
        north.contents = Self.red; south.contents = Self.blue
        for t in [nText, sText] {
            t.alignmentMode = .center; t.foregroundColor = Sprite.color(255, 255, 255); t.contentsScale = 3
            t.font = NSFont.systemFont(ofSize: 20, weight: .heavy)
        }
        nText.string = "N"; sText.string = "S"
        for l in [baseLines, flowLines, north, south, nText, sText] { root.addSublayer(l) }
    }

    func update(_ s: MagnetScene) {
        root.opacity = Float(s.alpha)
        let p = CGMutablePath()
        for line in s.lines { if let f = line.first { p.move(to: f); for q in line.dropFirst() { p.addLine(to: q) } } }
        baseLines.path = p; flowLines.path = p
        flowLines.lineDashPhase = -s.phase * 40
        for (pole, text, pt, r) in [(north, nText, s.pin, s.pinRadius), (south, sText, s.head, s.headRadius)] {
            pole.bounds = CGRect(x: 0, y: 0, width: r * 2.2, height: r * 2.2); pole.position = pt
            text.fontSize = max(10, r * 1.05)
            text.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 1.4)
            text.position = CGPoint(x: pt.x, y: pt.y)
        }
    }
}

// MARK: - Slinky

@MainActor
final class SlinkyLayers {
    let root = CALayer()
    private let chunks = 13
    private var under: [CAShapeLayer] = [], over: [CAShapeLayer] = []
    private let knobA = CAShapeLayer(), knobB = CAShapeLayer()

    init() {
        root.masksToBounds = false
        for i in 0..<chunks {
            let u = CAShapeLayer(), o = CAShapeLayer()
            for l in [u, o] { l.fillColor = nil; l.lineCap = .round; l.lineJoin = .round }
            u.strokeColor = Sprite.color(255, 250, 238)
            PaperRopeLayers.paperShadow(u, depth: 1.6)
            let hue = CGFloat(i) / CGFloat(chunks) * 0.82
            let c = NSColor(hue: hue, saturation: 0.62, brightness: 1.0, alpha: 1).usingColorSpace(.sRGB)!
            o.strokeColor = CGColor(srgbRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: 1)
            root.addSublayer(u); root.addSublayer(o)
            under.append(u); over.append(o)
        }
        for k in [knobA, knobB] {
            k.fillColor = Sprite.color(255, 207, 86); k.strokeColor = Sprite.color(255, 250, 238); k.lineWidth = 2.4
            PaperRopeLayers.paperShadow(k, depth: 1.6)
            root.addSublayer(k)
        }
    }

    func update(_ s: SlinkyScene) {
        root.opacity = Float(s.alpha)
        let n = s.coil.count
        guard n > 2 else { return }
        for i in 0..<chunks {
            let a = i * (n - 1) / chunks, b = min(n - 1, (i + 1) * (n - 1) / chunks + 1)
            let p = CGMutablePath(); p.move(to: s.coil[a]); for j in (a + 1)...b { p.addLine(to: s.coil[j]) }
            under[i].path = p; over[i].path = p
            under[i].lineWidth = s.wire + 2.4; over[i].lineWidth = s.wire
        }
        knobA.path = CGPath(ellipseIn: CGRect(x: s.pin.x - s.pinRadius, y: s.pin.y - s.pinRadius, width: s.pinRadius * 2, height: s.pinRadius * 2), transform: nil)
        knobB.path = CGPath(ellipseIn: CGRect(x: s.head.x - s.headRadius, y: s.head.y - s.headRadius, width: s.headRadius * 2, height: s.headRadius * 2), transform: nil)
        knobA.zPosition = 2; knobB.zPosition = 2
    }
}

// MARK: - Tin-can phone

@MainActor
final class TinCanLayers {
    let root = CALayer()
    private let string = CAShapeLayer(), stringHi = CAShapeLayer()
    private let canA = CanLayer(), canB = CanLayer()
    private var notes: [CATextLayer] = []
    private static let glyphs = ["♪", "♫", "♬"]
    private static let colors = [Sprite.color(255, 128, 118), Sprite.color(255, 207, 86), Sprite.color(92, 196, 190)]

    init() {
        root.masksToBounds = false
        string.fillColor = nil; string.strokeColor = Sprite.color(255, 250, 238); string.lineWidth = 2.2; string.lineCap = .round
        PaperRopeLayers.paperShadow(string, depth: 1)
        stringHi.fillColor = nil; stringHi.strokeColor = Sprite.color(220, 190, 150); stringHi.lineWidth = 1; stringHi.lineCap = .round
        for l in [string, stringHi, canA.root, canB.root] { root.addSublayer(l) }
    }

    func update(_ s: TinCanScene) {
        root.opacity = Float(s.alpha)
        let p = CGMutablePath()
        if let f = s.string.first { p.move(to: f); for q in s.string.dropFirst() { p.addLine(to: q) } }
        string.path = p; stringHi.path = p
        canA.update(at: s.pin, radius: s.pinRadius, angle: s.angle, wiggle: s.pinWiggle)
        canB.update(at: s.head, radius: s.headRadius, angle: s.angle + .pi, wiggle: s.headWiggle)
        while notes.count < s.notes.count {
            let t = CATextLayer(); t.alignmentMode = .center; t.contentsScale = 3; t.fontSize = 34
            t.font = NSFont.systemFont(ofSize: 34, weight: .bold); t.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
            t.shadowColor = CGColor(gray: 0, alpha: 1); t.shadowOpacity = 0.3; t.shadowOffset = CGSize(width: 0, height: -1.5); t.shadowRadius = 1.5
            root.addSublayer(t); notes.append(t)
        }
        for (i, t) in notes.enumerated() {
            guard i < s.notes.count else { t.isHidden = true; continue }
            let n = s.notes[i]
            t.isHidden = n.alpha < 0.02
            t.string = Self.glyphs[n.glyph % 3]
            t.foregroundColor = Self.colors[(n.glyph + i) % 3]
            t.position = n.position; t.opacity = Float(n.alpha)
            t.transform = CATransform3DScale(CATransform3DMakeRotation(n.rotation, 0, 0, 1), n.scale, n.scale, 1)
        }
    }
}

@MainActor
final class CanLayer {
    let root = CALayer()
    private let body = CAShapeLayer(), ribs = CAShapeLayer(), mouth = CAShapeLayer(), inner = CAShapeLayer(), shine = CAShapeLayer()

    init() {
        PaperRopeLayers.paperShadow(body, depth: 2)
        body.fillColor = Sprite.color(200, 208, 222); body.strokeColor = Sprite.color(255, 250, 238); body.lineWidth = 2.6; body.lineJoin = .round
        ribs.fillColor = nil; ribs.strokeColor = Sprite.color(150, 160, 182, 0.9); ribs.lineWidth = 1.4
        mouth.fillColor = Sprite.color(176, 184, 202); mouth.strokeColor = Sprite.color(255, 250, 238); mouth.lineWidth = 2
        inner.fillColor = Sprite.color(70, 70, 92)
        shine.fillColor = nil; shine.strokeColor = Sprite.color(255, 255, 255, 0.7); shine.lineWidth = 2.4; shine.lineCap = .round
        for l in [body, ribs, mouth, inner, shine] { root.addSublayer(l) }
    }

    /// The can's closed bottom is at `at` facing the other can; its open mouth faces away.
    func update(at p: CGPoint, radius r: CGFloat, angle: CGFloat, wiggle: CGFloat) {
        let len = r * 2.0
        let hb = r * 0.62, hm = r * 0.95
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: hb)); path.addLine(to: CGPoint(x: -len, y: hm))
        path.addLine(to: CGPoint(x: -len, y: -hm)); path.addLine(to: CGPoint(x: 0, y: -hb)); path.closeSubpath()
        body.path = path
        let rp = CGMutablePath()
        for k in 1...3 { let x = -len * CGFloat(k) / 4; let h = hb + (hm - hb) * CGFloat(k) / 4; rp.move(to: CGPoint(x: x, y: h)); rp.addLine(to: CGPoint(x: x, y: -h)) }
        ribs.path = rp
        mouth.path = CGPath(ellipseIn: CGRect(x: -len - hm * 0.28, y: -hm, width: hm * 0.56, height: hm * 2), transform: nil)
        inner.path = CGPath(ellipseIn: CGRect(x: -len - hm * 0.2, y: -hm * 0.82, width: hm * 0.4, height: hm * 1.64), transform: nil)
        let sp = CGMutablePath(); sp.move(to: CGPoint(x: -len * 0.12, y: hb * 0.65)); sp.addLine(to: CGPoint(x: -len * 0.9, y: hm * 0.7))
        shine.path = sp
        root.position = p
        let shake = wiggle * 0.22 * CGFloat(sin(Double(CACurrentMediaTime() * 48)))
        root.transform = CATransform3DMakeRotation(angle + shake, 0, 0, 1)
    }
}

// MARK: - Red thread

@MainActor
final class ThreadLayers {
    let root = CALayer()
    private let shadowLine = CAShapeLayer(), line = CAShapeLayer(), shine = CAShapeLayer()
    private let pulse = CALayer()
    private let heartA = CAShapeLayer(), heartB = CAShapeLayer(), shineA = CAShapeLayer(), shineB = CAShapeLayer()
    private var floaters: [CAShapeLayer] = []
    private static let path = heartPath()
    private static let pulseImg = glowSprite(Sprite.color(255, 235, 200, 0.95), Sprite.color(255, 150, 140, 0), mid: Sprite.color(255, 150, 150, 0.4))

    init() {
        root.masksToBounds = false
        for l in [shadowLine, line, shine] { l.fillColor = nil; l.lineCap = .round; l.lineJoin = .round }
        shadowLine.strokeColor = Sprite.color(255, 250, 238); shadowLine.lineWidth = 8
        PaperRopeLayers.paperShadow(shadowLine, depth: 1.4)
        line.strokeColor = Sprite.color(226, 56, 80); line.lineWidth = 5
        shine.strokeColor = Sprite.color(255, 160, 160, 0.9); shine.lineWidth = 1.1; shine.lineDashPattern = [5, 9]
        pulse.contents = Self.pulseImg; pulse.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        for (h, sh, col) in [(heartA, shineA, Sprite.color(226, 56, 80)), (heartB, shineB, Sprite.color(255, 130, 160))] {
            h.path = Self.path; h.fillColor = col; h.strokeColor = Sprite.color(255, 250, 238); h.lineWidth = 0.13; h.lineJoin = .round
            PaperRopeLayers.paperShadow(h, depth: 1.6)
            sh.path = { let p = CGMutablePath(); p.addArc(center: CGPoint(x: -0.45, y: 0.32), radius: 0.3, startAngle: .pi * 0.55, endAngle: .pi * 0.95, clockwise: false); return p }()
            sh.fillColor = nil; sh.strokeColor = Sprite.color(255, 255, 255, 0.85); sh.lineWidth = 0.1; sh.lineCap = .round
        }
        for l in [shadowLine, line, shine, pulse, heartA, shineA, heartB, shineB] { root.addSublayer(l) }
    }

    private func place(_ layer: CAShapeLayer, _ sh: CAShapeLayer?, _ h: HeartState) {
        layer.isHidden = h.alpha < 0.02; sh?.isHidden = layer.isHidden
        layer.opacity = Float(h.alpha); sh?.opacity = Float(h.alpha)
        let t = CATransform3DScale(CATransform3DMakeRotation(h.rotation, 0, 0, 1), h.size, h.size, 1)
        let tr = CATransform3DConcat(t, CATransform3DMakeTranslation(h.position.x, h.position.y, 0))
        layer.transform = tr; sh?.transform = tr
    }

    func update(_ s: ThreadScene) {
        root.opacity = Float(s.alpha)
        let p = CGMutablePath()
        if let f = s.thread.first { p.move(to: f); for q in s.thread.dropFirst() { p.addLine(to: q) } }
        shadowLine.path = p; line.path = p; shine.path = p
        shine.lineDashPhase = -CACurrentMediaTime() * 18
        pulse.position = s.pulse; pulse.opacity = Float(s.pulseAlpha)
        place(heartA, shineA, s.pinHeart); place(heartB, shineB, s.headHeart)
        while floaters.count < s.hearts.count {
            let h = CAShapeLayer(); h.path = Self.path; h.strokeColor = Sprite.color(255, 250, 238); h.lineWidth = 0.18
            h.fillColor = [Sprite.color(255, 120, 150), Sprite.color(255, 170, 190), Sprite.color(240, 80, 110)][floaters.count % 3]
            root.addSublayer(h); floaters.append(h)
        }
        for (i, h) in floaters.enumerated() {
            guard i < s.hearts.count else { h.isHidden = true; continue }
            place(h, nil, s.hearts[i])
        }
    }
}
