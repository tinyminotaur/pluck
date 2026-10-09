import AppKit
import PluckCore
import QuartzCore

private func neon(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor { Sprite.color(r, g, b, a) }

private func ellipsePath(center c: CGPoint, rx: CGFloat, ry: CGFloat, angle: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: &t)
}

// MARK: - Lasso

@MainActor
final class LassoLayers {
    let root = CALayer()
    private let ropeGlow = lineLayer(neon(255, 90, 210, 0.45), 14), ropeMid = lineLayer(neon(255, 140, 230), 6), ropeCore = lineLayer(neon(255, 255, 255), 2.2)
    private let fill = CAShapeLayer()
    private let loopGlow = lineLayer(neon(80, 220, 255, 0.55), 11), loopCore = lineLayer(neon(255, 255, 255), 2.6)
    private let ants = lineLayer(neon(255, 90, 210), 3.2), ants2 = lineLayer(neon(80, 230, 255), 2.4)
    private let pinRing = lineLayer(neon(255, 140, 230), 3), pinDot = CAShapeLayer(), headDot = CAShapeLayer()
    private lazy var sparks = DotPool(parent: root, image: softDot)

    init() {
        root.masksToBounds = false
        ropeGlow.shadowColor = neon(255, 90, 210); ropeGlow.shadowOpacity = 1; ropeGlow.shadowRadius = 10; ropeGlow.shadowOffset = .zero
        loopGlow.shadowColor = neon(80, 220, 255); loopGlow.shadowOpacity = 1; loopGlow.shadowRadius = 10; loopGlow.shadowOffset = .zero
        fill.fillColor = neon(120, 230, 255, 0.10)
        ants.lineDashPattern = [9, 9]; ants2.lineDashPattern = [4, 12]
        pinDot.fillColor = neon(255, 255, 255); headDot.fillColor = neon(255, 255, 255, 0.9)
        for l in [ropeGlow, ropeMid, ropeCore, fill, loopGlow, loopCore, ants, ants2, pinRing, pinDot, headDot] { root.addSublayer(l) }
    }

    func update(_ s: LassoScene) {
        root.opacity = Float(s.alpha)
        let rp = polyline(s.rope)
        ropeGlow.path = rp; ropeMid.path = rp; ropeCore.path = rp
        let ring = ellipsePath(center: s.loopCenter, rx: max(2, s.rx), ry: max(2, s.ry), angle: s.angle)
        fill.path = ring; loopGlow.path = ring; loopCore.path = ring; ants.path = ring
        ants2.path = ellipsePath(center: s.loopCenter, rx: max(2, s.rx * 0.82), ry: max(2, s.ry * 0.82), angle: s.angle)
        ants.lineDashPhase = -s.phase * 36; ants2.lineDashPhase = s.phase * 28
        pinRing.path = circlePath(s.pin, s.pinRadius * 0.7)
        pinDot.path = circlePath(s.pin, max(3, s.pinRadius * 0.2))
        headDot.path = circlePath(s.head, max(2.5, s.headRadius * 0.16))
        headDot.opacity = Float(max(0, 1 - s.cinch * 1.2))
        for (i, sp) in s.sparks.enumerated() { sparks.place(i, at: sp.0, size: sp.2 * 2.6, alpha: sp.1) }
        sparks.hide(from: s.sparks.count)
    }
}

// MARK: - Laser pointer

@MainActor
final class LaserLayers {
    let root = CALayer()
    private lazy var trail = DotPool(parent: root, image: Self.red)
    private lazy var sparkles = DotPool(parent: root, image: Self.hot)
    private let beam = lineLayer(neon(255, 40, 40, 0.35), 1.6)
    private let pen = paperShape(neon(46, 48, 60), border: 2.2, depth: 2), band = paperShape(neon(190, 196, 210), border: 1.4, depth: 0), button = paperShape(neon(255, 60, 60), border: 1.2, depth: 0)
    private let halo = CALayer(), core = CALayer(), flare = CAShapeLayer()
    private var pings: [CAShapeLayer] = []
    private static let red: CGImage? = Sprite.image(CGSize(width: 16, height: 16), scale: 3) { c in
        Sprite.radial(c, center: CGPoint(x: 8, y: 8), radius: 7.5, inner: Sprite.color(255, 90, 70, 0.95), outer: Sprite.color(255, 30, 30, 0))
    }
    private static let hot: CGImage? = Sprite.image(CGSize(width: 16, height: 16), scale: 3) { c in
        Sprite.radial(c, center: CGPoint(x: 8, y: 8), radius: 7.5, inner: Sprite.color(255, 240, 220), outer: Sprite.color(255, 90, 60, 0))
    }
    private static let halo: CGImage? = glowSprite(Sprite.color(255, 70, 60, 0.9), Sprite.color(255, 30, 30, 0), mid: Sprite.color(255, 50, 50, 0.45))
    private static let core: CGImage? = glowSprite(Sprite.color(255, 255, 255), Sprite.color(255, 120, 100, 0), stop: 0.5, mid: Sprite.color(255, 200, 190, 0.9))

    init() {
        root.masksToBounds = false
        halo.contents = Self.halo; core.contents = Self.core
        flare.fillColor = neon(255, 255, 255, 0.85)
        for l in [beam, pen, band, button, halo, core, flare] { root.addSublayer(l) }
    }

    func update(_ s: LaserScene) {
        root.opacity = Float(s.alpha)
        for (i, t) in s.trail.enumerated() { trail.place(i, at: t.0, size: t.2 * 2.4, alpha: t.1 * 0.9) }
        trail.hide(from: s.trail.count)
        for (i, sp) in s.sparkles.enumerated() { sparkles.place(i, at: sp.0, size: sp.2 * 2.2, alpha: sp.1) }
        sparkles.hide(from: s.sparkles.count)
        beam.path = polyline([CGPoint(x: s.pen.x + cos(s.penAngle) * s.penLength * 0.5, y: s.pen.y + sin(s.penAngle) * s.penLength * 0.5), s.dot]); beam.opacity = Float(s.beamAlpha)
        let L = s.penLength
        var t = CGAffineTransform(translationX: s.pen.x, y: s.pen.y).rotated(by: s.penAngle)
        pen.path = CGPath(roundedRect: CGRect(x: -L * 0.5, y: -L * 0.13, width: L, height: L * 0.26), cornerWidth: L * 0.12, cornerHeight: L * 0.12, transform: &t)
        var t2 = CGAffineTransform(translationX: s.pen.x, y: s.pen.y).rotated(by: s.penAngle)
        band.path = CGPath(rect: CGRect(x: L * 0.12, y: -L * 0.13, width: L * 0.1, height: L * 0.26), transform: &t2)
        var t3 = CGAffineTransform(translationX: s.pen.x, y: s.pen.y).rotated(by: s.penAngle)
        button.path = CGPath(ellipseIn: CGRect(x: -L * 0.34, y: -L * 0.06, width: L * 0.12, height: L * 0.12), transform: &t3)
        let d = s.dotSize
        halo.bounds = CGRect(x: 0, y: 0, width: d * 6, height: d * 6); halo.position = s.dot
        halo.opacity = Float(0.7 + 0.3 * CGFloat(sin(Double(s.phase * 14))))
        core.bounds = CGRect(x: 0, y: 0, width: d * 2.2, height: d * 2.2); core.position = s.dot
        // A four-point flare turning slowly over the dot.
        let fp = CGMutablePath()
        for k in 0..<8 {
            let a = s.phase * 1.5 + CGFloat(k) * .pi / 4, r = k % 2 == 0 ? d * 2.4 : d * 0.5
            let pt = CGPoint(x: s.dot.x + cos(a) * r, y: s.dot.y + sin(a) * r)
            k == 0 ? fp.move(to: pt) : fp.addLine(to: pt)
        }
        fp.closeSubpath(); flare.path = fp; flare.opacity = 0.5
        while pings.count < s.ping.count { let l = lineLayer(neon(255, 90, 70), 3); root.addSublayer(l); pings.append(l) }
        for (i, l) in pings.enumerated() {
            guard i < s.ping.count else { l.isHidden = true; continue }
            l.isHidden = false; l.path = circlePath(s.dot, s.ping[i].0); l.opacity = Float(s.ping[i].1)
        }
    }
}

// MARK: - Highlighter

@MainActor
final class MarkerLayers {
    let root = CALayer()
    private var chunks: [CAShapeLayer] = []
    private let body = paperShape(neon(255, 250, 238), border: 2.4, depth: 2.4), tipShape = CAShapeLayer(), capShape = paperShape(neon(255, 235, 60), border: 2.2, depth: 2)
    private let band = CAShapeLayer()

    init() {
        root.masksToBounds = false
        root.addSublayer(body); root.addSublayer(band); root.addSublayer(tipShape); root.addSublayer(capShape)
    }

    func update(_ s: MarkerScene) {
        root.opacity = Float(s.alpha)
        let n = s.segments.count
        let per = max(1, n / 14)
        var idx = 0, c = 0
        while idx < n {
            let end = min(n, idx + per)
            if chunks.count <= c {
                let l = lineLayer(neon(255, 240, 60), 22); l.lineCap = .butt; root.insertSublayer(l, at: 0); chunks.append(l)
            }
            let l = chunks[c]
            let p = CGMutablePath()
            p.move(to: s.segments[idx].0)
            for k in idx..<end { p.addLine(to: s.segments[k].1) }
            l.path = p
            l.lineWidth = s.width
            let hue = 0.16 + 0.55 * (s.segments[idx].3 * 3).truncatingRemainder(dividingBy: 1) * 0 + 0.0
            _ = hue
            let hh = (0.15 + s.segments[idx].3).truncatingRemainder(dividingBy: 1)
            let col = NSColor(hue: hh, saturation: 0.62, brightness: 1.0, alpha: 1).usingColorSpace(.sRGB)!
            l.strokeColor = CGColor(srgbRed: col.redComponent, green: col.greenComponent, blue: col.blueComponent, alpha: s.segments[idx].2)
            l.isHidden = false
            idx = end; c += 1
        }
        for k in c..<chunks.count { chunks[k].isHidden = true }
        // The pen: a chisel tip on the target and a barrel trailing up and away.
        let a: CGFloat = 0.9
        var t = CGAffineTransform(translationX: s.tip.x, y: s.tip.y).rotated(by: a)
        body.path = CGPath(roundedRect: CGRect(x: 10, y: -10, width: 74, height: 20), cornerWidth: 6, cornerHeight: 6, transform: &t)
        var t2 = CGAffineTransform(translationX: s.tip.x, y: s.tip.y).rotated(by: a)
        let tp = CGMutablePath(); tp.move(to: CGPoint(x: 0, y: -4)); tp.addLine(to: CGPoint(x: 11, y: -10)); tp.addLine(to: CGPoint(x: 11, y: 10)); tp.addLine(to: CGPoint(x: 0, y: 5)); tp.closeSubpath()
        tipShape.path = tp.copy(using: &t2); tipShape.fillColor = neon(255, 235, 60)
        var t3 = CGAffineTransform(translationX: s.tip.x, y: s.tip.y).rotated(by: a)
        band.path = CGPath(rect: CGRect(x: 14, y: -10, width: 14, height: 20), transform: &t3); band.fillColor = neon(255, 235, 60)
        capShape.path = CGPath(roundedRect: CGRect(x: s.cap.x - s.capSize * 1.2, y: s.cap.y - s.capSize * 0.5, width: s.capSize * 2.4, height: s.capSize), cornerWidth: s.capSize * 0.3, cornerHeight: s.capSize * 0.3, transform: nil)
        capShape.opacity = 0.9
    }
}

// MARK: - Spotlight

@MainActor
final class SpotlightLayers {
    let root = CALayer()
    private let dim = CAGradientLayer()
    private let coneOuter = CAShapeLayer(), coneInner = CAShapeLayer(), rim = lineLayer(neon(255, 245, 200, 0.5), 3)
    private let lampBody = paperShape(neon(70, 76, 98), border: 2.4, depth: 2.4), lens = CAShapeLayer(), stand = lineLayer(neon(70, 76, 98), 4)
    private lazy var motes = DotPool(parent: root, image: softDot)
    private let half: CGFloat = 4500

    init() {
        root.masksToBounds = false
        dim.type = .radial
        dim.startPoint = CGPoint(x: 0.5, y: 0.5); dim.endPoint = CGPoint(x: 1, y: 1)
        dim.bounds = CGRect(x: 0, y: 0, width: half * 2, height: half * 2)
        coneOuter.fillColor = neon(255, 244, 200, 0.12); coneInner.fillColor = neon(255, 250, 225, 0.14)
        coneOuter.shadowColor = neon(255, 240, 190); coneOuter.shadowOpacity = 0.9; coneOuter.shadowRadius = 18; coneOuter.shadowOffset = .zero
        lens.fillColor = neon(255, 247, 210)
        lens.shadowColor = neon(255, 240, 170); lens.shadowOpacity = 1; lens.shadowRadius = 12; lens.shadowOffset = .zero
        for l in [dim, coneOuter, coneInner, rim, stand, lampBody, lens] { root.addSublayer(l) }
    }

    func update(_ s: SpotlightScene) {
        root.opacity = Float(s.alpha)
        dim.position = s.target
        let r = max(10, s.radius) / half
        dim.colors = [neon(0, 0, 0, 0), neon(0, 0, 0, 0), neon(6, 8, 18, s.dim * 0.6), neon(6, 8, 18, s.dim)]
        dim.locations = [0, NSNumber(value: r * 0.7), NSNumber(value: r * 1.25), 1]
        // The beam from the lamp widens to the pool of light.
        let dx = s.target.x - s.lamp.x, dy = s.target.y - s.lamp.y, l = max(1, hypot(dx, dy))
        let nx = -dy / l, ny = dx / l
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: s.lamp.x + nx * 5, y: s.lamp.y + ny * 5))
        tri.addLine(to: CGPoint(x: s.target.x + nx * s.radius * 0.9, y: s.target.y + ny * s.radius * 0.9))
        tri.addLine(to: CGPoint(x: s.target.x - nx * s.radius * 0.9, y: s.target.y - ny * s.radius * 0.9))
        tri.addLine(to: CGPoint(x: s.lamp.x - nx * 5, y: s.lamp.y - ny * 5)); tri.closeSubpath()
        coneOuter.path = tri; coneOuter.opacity = Float(s.coneAlpha)
        let tri2 = CGMutablePath()
        tri2.move(to: s.lamp)
        tri2.addLine(to: CGPoint(x: s.target.x + nx * s.radius * 0.45, y: s.target.y + ny * s.radius * 0.45))
        tri2.addLine(to: CGPoint(x: s.target.x - nx * s.radius * 0.45, y: s.target.y - ny * s.radius * 0.45)); tri2.closeSubpath()
        coneInner.path = tri2; coneInner.opacity = Float(s.coneAlpha)
        rim.path = circlePath(s.target, s.radius * 0.95); rim.opacity = Float(s.coneAlpha * 0.8)
        // The lamp: a can light on a stand, aimed at the target.
        let ang = atan2(dy, dx)
        var t = CGAffineTransform(translationX: s.lamp.x, y: s.lamp.y).rotated(by: ang)
        lampBody.path = CGPath(roundedRect: CGRect(x: -s.lampSize * 0.8, y: -s.lampSize * 0.55, width: s.lampSize * 1.5, height: s.lampSize * 1.1), cornerWidth: s.lampSize * 0.2, cornerHeight: s.lampSize * 0.2, transform: &t)
        var t2 = CGAffineTransform(translationX: s.lamp.x, y: s.lamp.y).rotated(by: ang)
        lens.path = CGPath(ellipseIn: CGRect(x: s.lampSize * 0.55, y: -s.lampSize * 0.42, width: s.lampSize * 0.3, height: s.lampSize * 0.84), transform: &t2)
        stand.path = polyline([s.lamp, CGPoint(x: s.lamp.x, y: s.lamp.y - s.lampSize * 1.7)])
        for (i, m) in s.motes.enumerated() { motes.place(i, at: m.0, size: m.2 * 2.2, alpha: m.1) }
        motes.hide(from: s.motes.count)
    }
}

// MARK: - Callout arrow

@MainActor
final class CalloutLayers {
    let root = CALayer()
    private let arrowEdge = lineLayer(neon(255, 250, 238), 12), arrowInk = lineLayer(neon(255, 70, 70), 7)
    private let headEdge = lineLayer(neon(255, 250, 238), 12), headInk = lineLayer(neon(255, 70, 70), 7)
    private let scribEdge = lineLayer(neon(255, 250, 238), 9), scribInk = lineLayer(neon(255, 70, 70), 5)
    private let badge = paperShape(neon(255, 70, 70), border: 3, depth: 2.4), label = CATextLayer()

    init() {
        root.masksToBounds = false
        label.string = "1"; label.alignmentMode = .center; label.foregroundColor = neon(255, 255, 255); label.contentsScale = 3
        label.font = NSFont.systemFont(ofSize: 18, weight: .heavy)
        for l in [scribEdge, scribInk, arrowEdge, headEdge, arrowInk, headInk, badge, label] { root.addSublayer(l) }
    }

    func update(_ s: CalloutScene) {
        root.opacity = Float(s.alpha)
        arrowEdge.path = polyline(s.arrow); arrowInk.path = polyline(s.arrow)
        let hp = CGMutablePath()
        for h in [s.head1, s.head2] where h.count == 2 { hp.move(to: h[0]); hp.addLine(to: h[1]) }
        headEdge.path = hp; headInk.path = hp
        scribEdge.path = polyline(s.scribble); scribInk.path = polyline(s.scribble)
        badge.path = circlePath(s.badge, s.badgeSize)
        label.fontSize = max(12, s.badgeSize * 1.1)
        label.bounds = CGRect(x: 0, y: 0, width: s.badgeSize * 2, height: s.badgeSize * 1.6)
        label.position = s.badge
    }
}

// MARK: - Target lock

@MainActor
final class TargetLockLayers {
    let root = CALayer()
    private let brackets = lineLayer(neon(120, 255, 170), 3.4), bracketGlow = lineLayer(neon(120, 255, 170, 0.35), 9)
    private let ringDash = lineLayer(neon(120, 255, 170, 0.8), 1.8), tickLayer = lineLayer(neon(120, 255, 170, 0.7), 1.6)
    private let cross = lineLayer(neon(255, 255, 255, 0.9), 1.6)
    private let link = lineLayer(neon(120, 255, 170, 0.3), 1.4)
    private let tag = CAShapeLayer(), text = CATextLayer()
    private var pings: [CAShapeLayer] = []
    private let originRing = lineLayer(neon(120, 255, 170), 2.4)

    init() {
        root.masksToBounds = false
        ringDash.lineDashPattern = [7, 6]; link.lineDashPattern = [3, 8]
        bracketGlow.shadowColor = neon(120, 255, 170); bracketGlow.shadowOpacity = 1; bracketGlow.shadowRadius = 8; bracketGlow.shadowOffset = .zero
        tag.fillColor = neon(8, 22, 16, 0.78); tag.strokeColor = neon(120, 255, 170, 0.8); tag.lineWidth = 1.2
        text.contentsScale = 3; text.foregroundColor = neon(150, 255, 190); text.fontSize = 11; text.alignmentMode = .left
        text.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        for l in [link, ringDash, tickLayer, bracketGlow, brackets, cross, originRing, tag, text] { root.addSublayer(l) }
    }

    func update(_ s: TargetLockScene) {
        root.opacity = Float(min(1, s.alpha))
        let c = s.target, b = s.bracket, arm = b * 0.42
        let p = CGMutablePath()
        for (sx, sy) in [(CGFloat(-1), CGFloat(1)), (1, 1), (1, -1), (-1, -1)] {
            let corner = CGPoint(x: c.x + sx * b, y: c.y + sy * b)
            p.move(to: CGPoint(x: corner.x - sx * arm, y: corner.y)); p.addLine(to: corner); p.addLine(to: CGPoint(x: corner.x, y: corner.y - sy * arm))
        }
        brackets.path = p; bracketGlow.path = p
        ringDash.path = circlePath(c, s.ringRadius); ringDash.lineDashPhase = -s.phase * 40
        let tk = CGMutablePath(); for t in s.ticks { tk.move(to: t.0); tk.addLine(to: t.1) }
        tickLayer.path = tk
        let cp = CGMutablePath(); let g: CGFloat = 8, l: CGFloat = 16
        for (dx, dy) in [(CGFloat(1), CGFloat(0)), (-1, 0), (0, 1), (0, -1)] { cp.move(to: CGPoint(x: c.x + dx * g, y: c.y + dy * g)); cp.addLine(to: CGPoint(x: c.x + dx * (g + l), y: c.y + dy * (g + l))) }
        cross.path = cp
        link.path = polyline(s.line)
        originRing.path = circlePath(s.origin, s.pinRadius * 0.45)
        while pings.count < s.pings.count { let r = lineLayer(neon(120, 255, 170), 2); root.insertSublayer(r, at: 0); pings.append(r) }
        for (i, r) in pings.enumerated() { guard i < s.pings.count else { r.isHidden = true; continue }
            r.isHidden = false; r.path = circlePath(s.origin, s.pings[i].0); r.opacity = Float(s.pings[i].1) }
        text.string = s.readout
        let w: CGFloat = 138, h: CGFloat = 20
        tag.path = CGPath(roundedRect: CGRect(x: s.readoutPos.x, y: s.readoutPos.y, width: w, height: h), cornerWidth: 4, cornerHeight: 4, transform: nil)
        text.bounds = CGRect(x: 0, y: 0, width: w - 12, height: h - 4)
        text.position = CGPoint(x: s.readoutPos.x + 6 + (w - 12) / 2, y: s.readoutPos.y + h / 2 + 1)
    }
}

private func closedSmooth(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    guard pts.count > 3 else { return p }
    let n = pts.count
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    p.move(to: mid(pts[n - 1], pts[0]))
    for i in 0..<n { p.addQuadCurve(to: mid(pts[i], pts[(i + 1) % n]), control: pts[i]) }
    p.closeSubpath()
    return p
}

// MARK: - Marquee

@MainActor
final class MarqueeLayers {
    let root = CALayer()
    private let fill = CAShapeLayer(), hatch = CAShapeLayer(), hatchMask = CAShapeLayer()
    private let glow = CAShapeLayer(), edge = CAShapeLayer(), ants = CAShapeLayer()
    private var handles: [CAShapeLayer] = []
    private lazy var sparkles = DotPool(parent: root, image: softDot)
    private let tag = CAShapeLayer(), tagText = CATextLayer(), flash = CAShapeLayer()

    init() {
        root.masksToBounds = false
        fill.fillColor = neon(70, 150, 255, 0.13)
        hatch.fillColor = nil; hatch.strokeColor = neon(255, 255, 255, 0.16); hatch.lineWidth = 2
        hatchMask.fillColor = neon(0, 0, 0, 1); hatch.mask = hatchMask
        glow.fillColor = nil; glow.strokeColor = neon(70, 160, 255, 0.45); glow.lineWidth = 9
        glow.shadowColor = neon(70, 160, 255); glow.shadowOpacity = 1; glow.shadowRadius = 10; glow.shadowOffset = .zero
        edge.fillColor = nil; edge.strokeColor = neon(255, 255, 255, 0.9); edge.lineWidth = 1.6
        ants.fillColor = nil; ants.strokeColor = neon(60, 140, 255); ants.lineWidth = 3.2; ants.lineDashPattern = [10, 10]
        flash.fillColor = neon(255, 255, 255, 0)
        tag.fillColor = neon(10, 24, 48, 0.82); tag.strokeColor = neon(120, 180, 255, 0.9); tag.lineWidth = 1.2
        tagText.contentsScale = 3; tagText.foregroundColor = neon(210, 232, 255); tagText.fontSize = 12; tagText.alignmentMode = .center
        tagText.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        for l in [fill, hatch, glow, edge, ants, flash, tag, tagText] { root.addSublayer(l) }
    }

    func update(_ s: MarqueeScene) {
        root.opacity = Float(s.alpha)
        let r = s.rect
        let rr = CGPath(roundedRect: r, cornerWidth: min(s.corner, r.width / 2), cornerHeight: min(s.corner, r.height / 2), transform: nil)
        fill.path = rr; glow.path = rr; edge.path = rr; ants.path = rr; hatchMask.path = rr; flash.path = rr
        ants.lineDashPhase = -s.phase * 34
        flash.fillColor = neon(255, 255, 255, 0.5 * s.flash)
        // A diagonal shimmer sweeping through the glass.
        let hp = CGMutablePath()
        let gap: CGFloat = 16, off = (s.phase * 26).truncatingRemainder(dividingBy: gap)
        var x = r.minX - r.height + off
        while x < r.maxX { hp.move(to: CGPoint(x: x, y: r.minY)); hp.addLine(to: CGPoint(x: x + r.height, y: r.maxY)); x += gap }
        hatch.path = hp
        while handles.count < s.handles.count {
            let h = paperShape(neon(255, 255, 255), border: 0, depth: 0); h.strokeColor = neon(60, 140, 255); h.lineWidth = 2.4; root.addSublayer(h); handles.append(h)
        }
        for (i, h) in handles.enumerated() {
            let big = i < 4
            let pop = 1 + 0.18 * CGFloat(sin(Double(s.phase * 4 + CGFloat(i))))
            h.path = circlePath(s.handles[i], (big ? 6 : 4) * pop)
        }
        for (i, sp) in s.sparkles.enumerated() { sparkles.place(i, at: sp.0, size: sp.2 * 2.6, alpha: sp.1) }
        sparkles.hide(from: s.sparkles.count)
        let w: CGFloat = 92, h: CGFloat = 22
        tag.path = CGPath(roundedRect: CGRect(x: s.tagPos.x, y: s.tagPos.y, width: w, height: h), cornerWidth: 6, cornerHeight: 6, transform: nil)
        tagText.string = s.tag
        tagText.bounds = CGRect(x: 0, y: 0, width: w, height: h - 4); tagText.position = CGPoint(x: s.tagPos.x + w / 2, y: s.tagPos.y + h / 2 + 1)
    }
}

// MARK: - Jelly

@MainActor
final class JellyLayers {
    let root = CALayer()
    private let body = CAShapeLayer(), inner = CAShapeLayer(), glow = CAShapeLayer(), membrane = CAShapeLayer(), rim = CAShapeLayer()
    private var rings: [CAShapeLayer] = []
    private lazy var sparkles = DotPool(parent: root, image: softDot)
    private let pinDrop = CAShapeLayer(), headDrop = CAShapeLayer()

    init() {
        root.masksToBounds = false
        body.fillColor = neon(110, 255, 190, 0.20)
        inner.fillColor = neon(255, 255, 255, 0.12)
        glow.fillColor = nil; glow.strokeColor = neon(120, 255, 200, 0.5); glow.lineWidth = 11
        glow.shadowColor = neon(120, 255, 200); glow.shadowOpacity = 1; glow.shadowRadius = 12; glow.shadowOffset = .zero
        membrane.fillColor = nil; membrane.strokeColor = neon(200, 255, 235, 0.35); membrane.lineWidth = 3
        rim.fillColor = nil; rim.strokeColor = neon(255, 255, 255, 0.85); rim.lineWidth = 2
        for d in [pinDrop, headDrop] { d.fillColor = neon(255, 255, 255, 0.95); d.strokeColor = neon(120, 255, 200); d.lineWidth = 2 }
        for l in [body, inner, glow, membrane, rim, pinDrop, headDrop] { root.addSublayer(l) }
    }

    func update(_ s: JellyScene) {
        root.opacity = Float(s.alpha)
        let path = closedSmooth(s.outline)
        body.path = path; glow.path = path; rim.path = path
        // An inner highlight (smaller, shifted toward the light) and a looser outer membrane.
        func scaled(_ k: CGFloat, dx: CGFloat, dy: CGFloat) -> CGPath {
            closedSmooth(s.outline.map { CGPoint(x: s.center.x + ($0.x - s.center.x) * k + dx, y: s.center.y + ($0.y - s.center.y) * k + dy) })
        }
        inner.path = scaled(0.66, dx: -s.radius * 0.1, dy: s.radius * 0.12)
        membrane.path = scaled(1.07 + min(0.08, s.wobble * 0.004), dx: 0, dy: 0)
        for (i, sp) in s.sparkles.enumerated() { sparkles.place(i, at: sp.0, size: sp.2 * 2.4, alpha: sp.1) }
        sparkles.hide(from: s.sparkles.count)
        pinDrop.path = circlePath(s.pin, 5); headDrop.path = circlePath(s.head, 5)
        while rings.count < s.ripples.count { let l = lineLayer(neon(200, 255, 235), 3); root.addSublayer(l); rings.append(l) }
        for (i, l) in rings.enumerated() {
            guard i < s.ripples.count else { l.isHidden = true; continue }
            l.isHidden = false; l.path = circlePath(s.center, s.ripples[i].0); l.opacity = Float(s.ripples[i].1)
        }
    }
}

// MARK: - Freehand lasso

@MainActor
final class FreehandLayers {
    let root = CALayer()
    private let fill = CAShapeLayer()
    private let glow = lineLayer(neon(255, 150, 60, 0.45), 10), core = lineLayer(neon(255, 255, 255), 2.4), ants = lineLayer(neon(255, 70, 150), 3.2)
    private let closing = lineLayer(neon(255, 255, 255, 0.85), 2), flash = CAShapeLayer()
    private let tip = CAShapeLayer(), start = CAShapeLayer()
    private lazy var sparkles = DotPool(parent: root, image: softDot)

    init() {
        root.masksToBounds = false
        fill.fillColor = neon(255, 90, 170, 0.14)
        glow.shadowColor = neon(255, 150, 60); glow.shadowOpacity = 1; glow.shadowRadius = 10; glow.shadowOffset = .zero
        ants.lineDashPattern = [9, 9]; closing.lineDashPattern = [4, 7]
        flash.fillColor = neon(255, 255, 255, 0)
        tip.fillColor = neon(255, 255, 255); tip.strokeColor = neon(255, 90, 160); tip.lineWidth = 3
        start.fillColor = neon(255, 90, 160); start.strokeColor = neon(255, 255, 255); start.lineWidth = 2
        for l in [fill, flash, glow, core, ants, closing, start, tip] { root.addSublayer(l) }
    }

    func update(_ s: FreehandScene) {
        root.opacity = Float(s.alpha)
        let p = polyline(s.path)
        let region = CGMutablePath(); region.addPath(p); region.addLines(between: s.closing); region.closeSubpath()
        fill.path = region; flash.path = region
        flash.fillColor = neon(255, 255, 255, 0.5 * s.flash)
        glow.path = p; core.path = p; ants.path = p; ants.lineDashPhase = -s.phase * 30
        closing.path = polyline(s.closing); closing.lineDashPhase = s.phase * 20; closing.opacity = Float(1 - 0.6 * s.closed)
        start.path = circlePath(s.pin, 6); tip.path = circlePath(s.head, 7)
        for (i, sp) in s.sparkles.enumerated() { sparkles.place(i, at: sp.0, size: sp.2 * 2.6, alpha: sp.1) }
        sparkles.hide(from: s.sparkles.count)
    }
}
