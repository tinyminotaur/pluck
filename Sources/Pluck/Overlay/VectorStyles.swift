import AppKit
import PluckCore
import QuartzCore

/// Hand-drawn vector sprites for the styles that are not made of glass: real fireflies and a papercraft jump rope.
/// Everything is a small Core Animation layer (sprites rendered once, then moved per frame), so it stays cheap at
/// 120 Hz, and it can also be rendered offscreen with `CALayer.render(in:)` for previews.
@MainActor
final class VectorStyleHost {
    let root = CALayer()
    private let fireflies = FireflyLayers()
    private let paper = PaperRopeLayers()

    init() {
        root.masksToBounds = false
        root.isHidden = true
        root.addSublayer(fireflies.root)
        root.addSublayer(paper.root)
    }

    func hide() {
        root.isHidden = true
    }

    func updateFireflies(_ flies: [FireflyState], pin: (center: CGPoint, radius: CGFloat), head: (center: CGPoint, radius: CGFloat),
                         alpha: CGFloat, headGlow: CGFloat, time: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.isHidden = alpha < 0.01
        fireflies.root.isHidden = false
        paper.root.isHidden = true
        fireflies.update(flies, pin: pin, head: head, alpha: alpha, headGlow: headGlow, time: time)
    }

    func updatePaper(_ scene: PaperRopeScene) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.isHidden = scene.alpha < 0.01
        fireflies.root.isHidden = true
        paper.root.isHidden = false
        paper.update(scene)
    }
}

// MARK: - Sprite drawing helpers

private enum Sprite {
    static func color(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    static func image(_ size: CGSize, scale: CGFloat = 3, _ draw: (CGContext) -> Void) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAllowsAntialiasing(true)
        draw(ctx)
        return ctx.makeImage()
    }

    static func radial(_ ctx: CGContext, center: CGPoint, radius: CGFloat, inner: CGColor, outer: CGColor) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [inner, outer] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
}

// MARK: - Fireflies

@MainActor
final class FireflyLayers {
    let root = CALayer()

    private struct Fly {
        let box = CALayer()
        let halo = CALayer()
        let wingA = CALayer()
        let wingB = CALayer()
        let body = CALayer()
        let lamp = CALayer()
    }
    private var flies: [Fly] = []
    private let pinLantern = LanternLayers()
    private let headLantern = LanternLayers()

    private static let canvas = CGSize(width: 44, height: 26)
    private static let lampCenter = CGPoint(x: -9.5, y: 0)      // relative to the canvas centre, body facing +x

    private static let bodyImage: CGImage? = Sprite.image(canvas) { c in
        c.translateBy(x: canvas.width / 2, y: canvas.height / 2)
        // Legs.
        c.setStrokeColor(Sprite.color(36, 26, 18, 0.9)); c.setLineWidth(0.8); c.setLineCap(.round)
        for (x, dx) in [(CGFloat(6), CGFloat(2.4)), (3, 0.4), (0.5, -1.8)] {
            for sgn in [CGFloat(1), -1] {
                c.move(to: CGPoint(x: x, y: sgn * 2.6)); c.addLine(to: CGPoint(x: x + dx, y: sgn * 6.6)); c.strokePath()
            }
        }
        // Antennae.
        c.setLineWidth(0.75)
        for sgn in [CGFloat(1), -1] {
            c.move(to: CGPoint(x: 12.2, y: sgn * 1.0))
            c.addQuadCurve(to: CGPoint(x: 18.6, y: sgn * 4.8), control: CGPoint(x: 16, y: sgn * 1.6)); c.strokePath()
        }
        // Abdomen (the lamp sits on its tip), thorax shield, head.
        c.setFillColor(Sprite.color(46, 32, 22))
        c.fillEllipse(in: CGRect(x: -15.5, y: -4.6, width: 19, height: 9.2))
        c.setStrokeColor(Sprite.color(78, 56, 38, 0.8)); c.setLineWidth(0.6)
        for x in stride(from: CGFloat(-9), through: 1, by: 3.4) {
            c.move(to: CGPoint(x: x, y: -4.1)); c.addQuadCurve(to: CGPoint(x: x, y: 4.1), control: CGPoint(x: x + 1.1, y: 0)); c.strokePath()
        }
        c.setFillColor(Sprite.color(226, 108, 58))                                   // the orange shield behind the head
        c.fillEllipse(in: CGRect(x: 1.2, y: -4.5, width: 9, height: 9))
        c.setFillColor(Sprite.color(60, 30, 20, 0.85))
        c.fill(CGRect(x: 4.2, y: -1.0, width: 4, height: 2))
        c.setFillColor(Sprite.color(34, 24, 16))
        c.fillEllipse(in: CGRect(x: 8.6, y: -2.6, width: 5.4, height: 5.2))
        c.setFillColor(Sprite.color(255, 255, 255, 0.55))
        c.fillEllipse(in: CGRect(x: 12.0, y: 0.6, width: 1.0, height: 1.0))
        c.fillEllipse(in: CGRect(x: 12.0, y: -1.6, width: 1.0, height: 1.0))
    }

    private static let lampImage: CGImage? = Sprite.image(canvas) { c in
        c.translateBy(x: canvas.width / 2, y: canvas.height / 2)
        let rect = CGRect(x: -15.4, y: -4.1, width: 12.2, height: 8.2)
        c.saveGState()
        c.addEllipse(in: rect); c.clip()
        Sprite.radial(c, center: CGPoint(x: rect.midX + 1, y: 0), radius: 7.5,
                      inner: Sprite.color(246, 255, 170), outer: Sprite.color(150, 224, 40))
        c.restoreGState()
    }

    private static let haloImage: CGImage? = Sprite.image(CGSize(width: 64, height: 64), scale: 2) { c in
        Sprite.radial(c, center: CGPoint(x: 32, y: 32), radius: 32, inner: Sprite.color(205, 255, 110, 0.62), outer: Sprite.color(190, 255, 80, 0))
    }

    private static let wingImage: CGImage? = Sprite.image(CGSize(width: 30, height: 16)) { c in
        let r = CGRect(x: 2, y: 3.2, width: 27, height: 9.6)
        c.setFillColor(Sprite.color(235, 245, 255, 0.34)); c.fillEllipse(in: r)
        c.setStrokeColor(Sprite.color(255, 255, 255, 0.62)); c.setLineWidth(0.7); c.strokeEllipse(in: r)
        c.setStrokeColor(Sprite.color(255, 255, 255, 0.4)); c.setLineWidth(0.5)
        c.move(to: CGPoint(x: 2, y: 8)); c.addLine(to: CGPoint(x: 25, y: 8)); c.strokePath()
    }

    init() {
        root.masksToBounds = false
        root.addSublayer(pinLantern.root)
        root.addSublayer(headLantern.root)
    }

    private func make() -> Fly {
        let f = Fly()
        let c = Self.canvas
        f.box.bounds = CGRect(origin: .zero, size: c)
        f.halo.contents = Self.haloImage
        f.halo.bounds = CGRect(x: 0, y: 0, width: 130, height: 130)
        f.halo.position = CGPoint(x: c.width / 2 + Self.lampCenter.x, y: c.height / 2)
        for l in [f.body, f.lamp] { l.contents = Self.bodyImage; l.frame = f.box.bounds }
        f.lamp.contents = Self.lampImage
        for w in [f.wingA, f.wingB] {
            w.contents = Self.wingImage
            w.bounds = CGRect(x: 0, y: 0, width: 30, height: 16)
            w.anchorPoint = CGPoint(x: 2.0 / 30, y: 0.5)
        }
        f.wingA.position = CGPoint(x: c.width / 2 + 3, y: c.height / 2 + 2.2)
        f.wingB.position = CGPoint(x: c.width / 2 + 3, y: c.height / 2 - 2.2)
        // Draw order: halo, wings (behind), body, lamp on top.
        for l in [f.halo, f.wingA, f.wingB, f.body, f.lamp] { f.box.addSublayer(l) }
        root.addSublayer(f.box)
        return f
    }

    func update(_ states: [FireflyState], pin: (center: CGPoint, radius: CGFloat), head: (center: CGPoint, radius: CGFloat),
                alpha: CGFloat, headGlow: CGFloat, time: CGFloat) {
        while flies.count < states.count { flies.append(make()) }
        pinLantern.update(center: pin.center, radius: pin.radius, alpha: alpha, glow: 0.55 + 0.1 * CGFloat(sin(Double(time * 1.3))), time: time)
        headLantern.update(center: head.center, radius: max(10, head.radius), alpha: alpha, glow: 0.5 + 0.5 * headGlow, time: time + 1.7)
        for (i, f) in flies.enumerated() {
            guard i < states.count else { f.box.isHidden = true; continue }
            let s = states[i]
            f.box.isHidden = s.alpha < 0.02
            f.box.opacity = Float(s.alpha)
            f.box.position = s.position
            let sc = s.length / 22
            f.box.transform = CATransform3DScale(CATransform3DMakeRotation(s.heading, 0, 0, 1), sc, sc, 1)
            f.lamp.opacity = Float(s.glow)
            f.halo.opacity = Float(s.glow * 0.95)
            let hs = 0.7 + 0.5 * s.glow
            f.halo.transform = CATransform3DMakeScale(hs, hs, 1)
            // Wings buzz: a fast flap that holds steady while the lantern is bright (a lazy hover).
            let flap = abs(CGFloat(sin(Double(s.wingPhase)))) * (0.75 - 0.35 * s.glow)
            f.wingA.transform = CATransform3DMakeRotation(.pi - 0.35 - flap, 0, 0, 1)
            f.wingB.transform = CATransform3DMakeRotation(.pi + 0.35 + flap, 0, 0, 1)
        }
    }
}

/// A little glass lantern with a warm light: the pin and head of the firefly scene.
@MainActor
final class LanternLayers {
    let root = CALayer()
    private let halo = CALayer()
    private let jar = CALayer()

    private static let jarImage: CGImage? = Sprite.image(CGSize(width: 100, height: 116), scale: 3) { c in
        let ctr = CGPoint(x: 50, y: 52), r: CGFloat = 38
        // Handle ring and cap.
        c.setStrokeColor(Sprite.color(70, 52, 40)); c.setLineWidth(3); c.setLineCap(.round)
        c.addArc(center: CGPoint(x: 50, y: 104), radius: 9, startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: false); c.strokePath()
        c.setFillColor(Sprite.color(78, 58, 44))
        c.addPath(CGPath(roundedRect: CGRect(x: 34, y: 88, width: 32, height: 11), cornerWidth: 4, cornerHeight: 4, transform: nil)); c.fillPath()
        // Glass globe with warm light.
        c.saveGState()
        c.addEllipse(in: CGRect(x: ctr.x - r, y: ctr.y - r, width: r * 2, height: r * 2)); c.clip()
        Sprite.radial(c, center: CGPoint(x: ctr.x - 6, y: ctr.y + 6), radius: r * 1.15,
                      inner: Sprite.color(255, 240, 170, 0.98), outer: Sprite.color(255, 164, 60, 0.62))
        c.restoreGState()
        c.setStrokeColor(Sprite.color(255, 255, 255, 0.85)); c.setLineWidth(2.4)
        c.strokeEllipse(in: CGRect(x: ctr.x - r, y: ctr.y - r, width: r * 2, height: r * 2))
        c.setStrokeColor(Sprite.color(255, 255, 255, 0.8)); c.setLineWidth(3.2)
        c.addArc(center: ctr, radius: r - 7, startAngle: .pi * 0.62, endAngle: .pi * 0.9, clockwise: false); c.strokePath()
    }

    private static let haloImage: CGImage? = Sprite.image(CGSize(width: 64, height: 64), scale: 2) { c in
        Sprite.radial(c, center: CGPoint(x: 32, y: 32), radius: 32, inner: Sprite.color(255, 196, 96, 0.55), outer: Sprite.color(255, 170, 70, 0))
    }

    init() {
        halo.contents = Self.haloImage
        jar.contents = Self.jarImage
        root.addSublayer(halo); root.addSublayer(jar)
    }

    func update(center: CGPoint, radius: CGFloat, alpha: CGFloat, glow: CGFloat, time: CGFloat) {
        root.isHidden = alpha < 0.02
        root.opacity = Float(alpha)
        let r = max(6, radius)
        let k = r / 38
        jar.bounds = CGRect(x: 0, y: 0, width: 100 * k, height: 116 * k)
        jar.position = CGPoint(x: center.x, y: center.y + (116 / 2 - 52) * k)
        let flick = 1 + 0.05 * CGFloat(sin(Double(time * 9))) * glow
        halo.bounds = CGRect(x: 0, y: 0, width: r * 6, height: r * 6)
        halo.position = center
        halo.opacity = Float(min(1, 0.35 + glow * 0.7))
        halo.transform = CATransform3DMakeScale(flick, flick, 1)
    }
}

// MARK: - Papercraft jump rope

@MainActor
final class PaperRopeLayers {
    let root = CALayer()

    private let ground = CAShapeLayer(), groundStitch = CAShapeLayer()
    private let ropeBase = CAShapeLayer(), ropeStripe = CAShapeLayer()
    private let handleA = PaperHandle(), handleB = PaperHandle()
    private let critter = Critter()

    private static let paper = Sprite.color(255, 250, 238)

    init() {
        root.masksToBounds = false
        for l in [ground, groundStitch, ropeBase, ropeStripe] { root.addSublayer(l) }
        root.addSublayer(handleA.root); root.addSublayer(handleB.root); root.addSublayer(critter.root)
        PaperRopeLayers.paperShadow(ground, depth: 1.5)
        ground.fillColor = Sprite.color(128, 200, 130)
        ground.strokeColor = Self.paper; ground.lineWidth = 3
        groundStitch.fillColor = nil
        groundStitch.strokeColor = Sprite.color(255, 255, 255, 0.85)
        groundStitch.lineWidth = 1.6; groundStitch.lineDashPattern = [4, 4]; groundStitch.lineCap = .round
        PaperRopeLayers.paperShadow(ropeBase, depth: 2.5)
        ropeBase.fillColor = nil; ropeBase.strokeColor = Sprite.color(232, 80, 91)
        ropeBase.lineCap = .round; ropeBase.lineJoin = .round
        ropeStripe.fillColor = nil; ropeStripe.strokeColor = Self.paper
        ropeStripe.lineCap = .butt; ropeStripe.lineJoin = .round
    }

    static func paperShadow(_ l: CALayer, depth: CGFloat) {
        l.shadowColor = CGColor(gray: 0, alpha: 1)
        l.shadowOpacity = 0.26
        l.shadowOffset = CGSize(width: depth * 0.5, height: -depth * 1.6)
        l.shadowRadius = depth * 1.3
    }

    private func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        guard pts.count > 2 else { return p }
        p.move(to: pts[0])
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i])
        }
        p.addLine(to: pts[pts.count - 1])
        return p
    }

    func update(_ s: PaperRopeScene) {
        root.opacity = Float(s.alpha)
        // Ground tab: a strip of green card the critter stands on, stitched.
        let gw = max(20, s.groundWidth), gh: CGFloat = 12
        let gRect = CGRect(x: -gw / 2, y: -gh / 2 - 1, width: gw, height: gh)
        var gt = CGAffineTransform(translationX: s.groundCenter.x, y: s.groundCenter.y).rotated(by: s.groundAngle)
        ground.path = CGPath(roundedRect: gRect, cornerWidth: 5, cornerHeight: 5, transform: &gt)
        groundStitch.path = CGPath(roundedRect: gRect.insetBy(dx: 4, dy: 3.4), cornerWidth: 3, cornerHeight: 3, transform: &gt)

        // Rope: a red paper ribbon with white twist stripes. It passes in front of the critter on its way down.
        let path = smoothPath(s.rope)
        ropeBase.path = path; ropeStripe.path = path
        ropeBase.lineWidth = s.ropeWidth
        ropeStripe.lineWidth = s.ropeWidth - 0.5
        ropeStripe.lineDashPattern = [NSNumber(value: Double(s.ropeWidth * 0.9)), NSNumber(value: Double(s.ropeWidth * 1.7))]
        ropeStripe.strokeColor = Self.paper
        let z: CGFloat = s.ropeInFront ? 3 : 0
        ropeBase.zPosition = z; ropeStripe.zPosition = z + 0.01

        handleA.update(center: s.handlePin, size: s.handlePinSize, tint: 0, lit: 0)
        handleB.update(center: s.handleHead, size: s.handleHeadSize, tint: 1, lit: s.armed)
        critter.update(s)
    }
}

/// A rope handle cut from teal card with a darker cap and a stripe.
@MainActor
final class PaperHandle {
    let root = CALayer()
    private let grip = CAShapeLayer(), band = CAShapeLayer(), cap = CAShapeLayer(), glow = CAShapeLayer()

    init() {
        for l in [glow, grip, band, cap] { root.addSublayer(l) }
        PaperRopeLayers.paperShadow(grip, depth: 2)
        grip.strokeColor = Sprite.color(255, 250, 238); grip.lineWidth = 2.6
        cap.strokeColor = Sprite.color(255, 250, 238); cap.lineWidth = 2
        band.fillColor = Sprite.color(255, 207, 86)
        glow.fillColor = Sprite.color(255, 207, 86, 0.0)
    }

    func update(center: CGPoint, size: CGFloat, tint: Int, lit: CGFloat) {
        let w = size * 0.62, h = size * 1.7
        root.position = center
        let body = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        grip.path = CGPath(roundedRect: body, cornerWidth: w * 0.42, cornerHeight: w * 0.42, transform: nil)
        grip.fillColor = tint == 0 ? Sprite.color(63, 167, 160) : Sprite.color(255, 143, 100)
        band.path = CGPath(rect: CGRect(x: -w / 2 + 1.2, y: -h * 0.06, width: w - 2.4, height: h * 0.16), transform: nil)
        cap.path = CGPath(roundedRect: CGRect(x: -w * 0.34, y: h / 2 - w * 0.2, width: w * 0.68, height: w * 0.5),
                          cornerWidth: w * 0.2, cornerHeight: w * 0.2, transform: nil)
        cap.fillColor = tint == 0 ? Sprite.color(44, 122, 117) : Sprite.color(214, 98, 62)
        let g = CGPath(ellipseIn: body.insetBy(dx: -w * 0.6, dy: -w * 0.6), transform: nil)
        glow.path = g
        glow.fillColor = Sprite.color(255, 220, 120, 0.35 * lit)
    }
}

/// The critter: a paper bunny with pink ears, rosy cheeks, a bow and a cotton tail. Hops over the rope.
@MainActor
final class Critter {
    let root = CALayer()
    private let body = CAShapeLayer(), belly = CAShapeLayer(), tail = CAShapeLayer()
    private let earL = CALayer(), earR = CALayer()
    private let earLOuter = CAShapeLayer(), earROuter = CAShapeLayer(), earLInner = CAShapeLayer(), earRInner = CAShapeLayer()
    private let footL = CAShapeLayer(), footR = CAShapeLayer()
    private let eyeL = CAShapeLayer(), eyeR = CAShapeLayer(), shineL = CAShapeLayer(), shineR = CAShapeLayer()
    private let cheekL = CAShapeLayer(), cheekR = CAShapeLayer(), nose = CAShapeLayer(), mouth = CAShapeLayer()
    private let bowL = CAShapeLayer(), bowR = CAShapeLayer(), bowKnot = CAShapeLayer()
    private let shadow = CAShapeLayer()

    private static let ref: CGFloat = 40
    private let cream = Sprite.color(255, 243, 222), edge = Sprite.color(255, 250, 238)
    private let ink = Sprite.color(66, 48, 48), pink = Sprite.color(255, 150, 170)

    private func shape(_ l: CAShapeLayer, _ path: CGPath, fill: CGColor?, edgeWidth: CGFloat = 2.4, shadow: CGFloat = 0) {
        l.path = path
        l.fillColor = fill
        if edgeWidth > 0 { l.strokeColor = edge; l.lineWidth = edgeWidth; l.lineJoin = .round }
        if shadow > 0 { PaperRopeLayers.paperShadow(l, depth: shadow) }
    }

    init() {
        let r = Self.ref
        // Ground shadow, ears (pivot at base), feet, tail, body, belly, face, bow.
        shadow.fillColor = CGColor(gray: 0, alpha: 0.18)
        shadow.path = CGPath(ellipseIn: CGRect(x: -r * 0.9, y: -r * 1.12, width: r * 1.8, height: r * 0.26), transform: nil)
        root.addSublayer(shadow)

        for (ear, outer, inner, sgn) in [(earL, earLOuter, earLInner, CGFloat(-1)), (earR, earROuter, earRInner, 1)] {
            ear.position = CGPoint(x: sgn * r * 0.36, y: r * 0.62)
            ear.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            ear.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            shape(outer, CGPath(roundedRect: CGRect(x: -r * 0.27, y: -r * 0.12, width: r * 0.54, height: r * 1.28), cornerWidth: r * 0.27, cornerHeight: r * 0.27, transform: nil),
                  fill: Sprite.color(255, 214, 170), shadow: 1.6)
            shape(inner, CGPath(roundedRect: CGRect(x: -r * 0.14, y: r * 0.06, width: r * 0.28, height: r * 0.86), cornerWidth: r * 0.14, cornerHeight: r * 0.14, transform: nil),
                  fill: pink, edgeWidth: 0)
            ear.addSublayer(outer); ear.addSublayer(inner)
            root.addSublayer(ear)
        }
        for (foot, sgn) in [(footL, CGFloat(-1)), (footR, 1)] {
            shape(foot, CGPath(ellipseIn: CGRect(x: sgn * r * 0.38 - r * 0.28, y: -r * 1.04, width: r * 0.56, height: r * 0.4), transform: nil),
                  fill: Sprite.color(255, 214, 170), shadow: 1.4)
            root.addSublayer(foot)
        }
        shape(tail, CGPath(ellipseIn: CGRect(x: -r * 1.2, y: -r * 0.42, width: r * 0.44, height: r * 0.44), transform: nil), fill: edge, edgeWidth: 0, shadow: 1.4)
        root.addSublayer(tail)
        shape(body, CGPath(ellipseIn: CGRect(x: -r * 0.98, y: -r * 0.94, width: r * 1.96, height: r * 1.84), transform: nil), fill: cream, shadow: 2.4)
        root.addSublayer(body)
        shape(belly, CGPath(ellipseIn: CGRect(x: -r * 0.52, y: -r * 0.86, width: r * 1.04, height: r * 0.8), transform: nil),
              fill: Sprite.color(255, 252, 244), edgeWidth: 0)
        root.addSublayer(belly)
        for (cheek, sgn) in [(cheekL, CGFloat(-1)), (cheekR, 1)] {
            shape(cheek, CGPath(ellipseIn: CGRect(x: sgn * r * 0.55 - r * 0.17, y: -r * 0.2, width: r * 0.34, height: r * 0.24), transform: nil),
                  fill: Sprite.color(255, 143, 163, 0.85), edgeWidth: 0)
            root.addSublayer(cheek)
        }
        for (eye, shine, sgn) in [(eyeL, shineL, CGFloat(-1)), (eyeR, shineR, 1)] {
            let box = CGRect(x: sgn * r * 0.34 - r * 0.1, y: r * 0.02, width: r * 0.2, height: r * 0.26)
            shape(eye, CGPath(ellipseIn: box, transform: nil), fill: ink, edgeWidth: 0)
            shape(shine, CGPath(ellipseIn: CGRect(x: box.minX + r * 0.02, y: box.maxY - r * 0.11, width: r * 0.08, height: r * 0.08), transform: nil),
                  fill: CGColor(gray: 1, alpha: 0.95), edgeWidth: 0)
            root.addSublayer(eye); root.addSublayer(shine)
        }
        shape(nose, CGPath(ellipseIn: CGRect(x: -r * 0.07, y: -r * 0.1, width: r * 0.14, height: r * 0.1), transform: nil), fill: pink, edgeWidth: 0)
        root.addSublayer(nose)
        mouth.fillColor = nil; mouth.strokeColor = ink; mouth.lineWidth = 1.5; mouth.lineCap = .round
        root.addSublayer(mouth)
        // A little yellow bow under the chin.
        let bowCol = Sprite.color(255, 207, 86)
        shape(bowL, { let p = CGMutablePath(); p.move(to: CGPoint(x: 0, y: -r * 0.58)); p.addLine(to: CGPoint(x: -r * 0.34, y: -r * 0.42))
                      p.addLine(to: CGPoint(x: -r * 0.34, y: -r * 0.76)); p.closeSubpath(); return p }(), fill: bowCol, edgeWidth: 1.6, shadow: 1)
        shape(bowR, { let p = CGMutablePath(); p.move(to: CGPoint(x: 0, y: -r * 0.58)); p.addLine(to: CGPoint(x: r * 0.34, y: -r * 0.42))
                      p.addLine(to: CGPoint(x: r * 0.34, y: -r * 0.76)); p.closeSubpath(); return p }(), fill: bowCol, edgeWidth: 1.6, shadow: 1)
        shape(bowKnot, CGPath(ellipseIn: CGRect(x: -r * 0.09, y: -r * 0.67, width: r * 0.18, height: r * 0.18), transform: nil),
              fill: Sprite.color(255, 176, 60), edgeWidth: 0)
        for l in [bowL, bowR, bowKnot] { root.addSublayer(l) }
    }

    func update(_ s: PaperRopeScene) {
        root.zPosition = 1.5
        let k = max(0.001, s.critterSize / Self.ref)
        let sx = 1 + 0.22 * s.squash, sy = 1 - 0.22 * s.squash
        root.position = s.critterCenter
        root.transform = CATransform3DScale(CATransform3DMakeRotation(s.critterAngle, 0, 0, 1), k * sx, k * sy, 1)
        // Ears flop against the motion.
        earL.transform = CATransform3DMakeRotation(0.16 + s.earFlop, 0, 0, 1)
        earR.transform = CATransform3DMakeRotation(-0.16 - s.earFlop, 0, 0, 1)
        // Feet tuck up when airborne.
        let tuck: CGFloat = s.hopping ? Self.ref * 0.16 : 0
        footL.transform = CATransform3DMakeTranslation(0, tuck, 0)
        footR.transform = CATransform3DMakeTranslation(0, tuck, 0)
        // Blink, and an open "o" mouth while airborne.
        let eyeScale = max(0.08, 1 - s.blink)
        for l in [eyeL, eyeR] {
            let c = CGPoint(x: l.path?.boundingBox.midX ?? 0, y: l.path?.boundingBox.midY ?? 0)
            var t = CATransform3DMakeTranslation(c.x, c.y, 0)
            t = CATransform3DScale(t, 1, eyeScale, 1)
            l.transform = CATransform3DTranslate(t, -c.x, -c.y, 0)
        }
        for l in [shineL, shineR] { l.opacity = Float(eyeScale > 0.5 ? 1 : 0) }
        let r = Self.ref
        let m = CGMutablePath()
        if s.hopping {
            m.addEllipse(in: CGRect(x: -r * 0.09, y: -r * 0.34, width: r * 0.18, height: r * 0.2))
            mouth.fillColor = Sprite.color(190, 80, 100)
        } else {
            m.move(to: CGPoint(x: -r * 0.16, y: -r * 0.2))
            m.addQuadCurve(to: CGPoint(x: 0, y: -r * 0.2), control: CGPoint(x: -r * 0.08, y: -r * 0.32))
            m.addQuadCurve(to: CGPoint(x: r * 0.16, y: -r * 0.2), control: CGPoint(x: r * 0.08, y: -r * 0.32))
            mouth.fillColor = nil
        }
        mouth.path = m
        shadow.opacity = Float(max(0, 1 - s.lift / (Self.ref * 1.6)))
    }
}
