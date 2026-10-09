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
    private let stars = StarLayers()
    private let kite = KiteLayers()
    private let bubbles = BubbleLayers()
    private let lightning = LightningLayers()
    private let magnet = MagnetLayers()
    private let slinky = SlinkyLayers()
    private let tincan = TinCanLayers()
    private let thread = ThreadLayers()

    init() {
        root.masksToBounds = false
        root.isHidden = true
        root.addSublayer(fireflies.root)
        root.addSublayer(paper.root)
        root.addSublayer(stars.root)
        root.addSublayer(kite.root)
        root.addSublayer(bubbles.root)
        for l in [lightning.root, magnet.root, slinky.root, tincan.root, thread.root] { root.addSublayer(l) }
    }

    private func only(_ l: CALayer) {
        for x in root.sublayers ?? [] { x.isHidden = x !== l }
    }

    private var runnerLayer: CALayer?

    /// A soft scale-in about the pin as the gesture emerges (and out as it leaves), shared by every sprite style.
    func entrance(pin: CGPoint, amount: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let t = max(0, min(1, amount))
        let ease = t * t * (3 - 2 * t)
        let k = 0.8 + 0.2 * ease
        var tr = CATransform3DMakeTranslation(pin.x, pin.y, 0)
        tr = CATransform3DScale(tr, k, k, 1)
        tr = CATransform3DTranslate(tr, -pin.x, -pin.y, 0)
        root.transform = tr
    }

    /// For offscreen previews: drop the layers of styles that are not showing, so only the active one is rendered.
    func pruneHidden() { for l in root.sublayers ?? [] where l.isHidden { l.removeFromSuperlayer() } }

    /// A runner-based style: its layer replaces the previous runner's.
    func attach(_ layer: CALayer) {
        runnerLayer?.removeFromSuperlayer()
        layer.isHidden = true
        root.addSublayer(layer)
        runnerLayer = layer
    }

    func present(_ runner: VectorRunner, emerge: CGFloat, glow: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.isHidden = emerge < 0.01
        only(runner.layer)
        runner.present(emerge: emerge, glow: glow)
    }

    func hide() {
        root.isHidden = true
    }

    func updateFireflies(_ flies: [FireflyState], pin: (center: CGPoint, radius: CGFloat), head: (center: CGPoint, radius: CGFloat),
                         alpha: CGFloat, headGlow: CGFloat, time: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.isHidden = alpha < 0.01
        only(fireflies.root)
        fireflies.update(flies, pin: pin, head: head, alpha: alpha, headGlow: headGlow, time: time)
    }

    func updatePaper(_ scene: PaperRopeScene) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.isHidden = scene.alpha < 0.01
        only(paper.root)
        paper.update(scene)
    }

    func updateStars(_ scene: StarScene) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.isHidden = scene.alpha < 0.01
        only(stars.root)
        stars.update(scene)
    }

    func updateKite(_ scene: KiteScene) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.isHidden = scene.alpha < 0.01
        only(kite.root)
        kite.update(scene)
    }

    func updateLightning(_ s: LightningScene) { run(s.alpha, lightning.root) { lightning.update(s) } }
    func updateMagnet(_ s: MagnetScene) { run(s.alpha, magnet.root) { magnet.update(s) } }
    func updateSlinky(_ s: SlinkyScene) { run(s.alpha, slinky.root) { slinky.update(s) } }
    func updateTinCan(_ s: TinCanScene) { run(s.alpha, tincan.root) { tincan.update(s) } }
    func updateThread(_ s: ThreadScene) { run(s.alpha, thread.root) { thread.update(s) } }

    private func run(_ alpha: CGFloat, _ layer: CALayer, _ body: () -> Void) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.isHidden = alpha < 0.01
        only(layer)
        body()
    }

    func updateBubbles(_ states: [BubbleState], alpha: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.isHidden = alpha < 0.01
        only(bubbles.root)
        bubbles.update(states)
    }
}

// MARK: - Sprite drawing helpers

enum Sprite {
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

// MARK: - Fireflies (soft glow wisps)

@MainActor
final class FireflyLayers {
    let root = CALayer()

    private struct Wisp {
        let box = CALayer()
        let tail = CALayer()
        let halo = CALayer()
        let core = CALayer()
        let sparkle = CALayer()
    }
    private var wisps: [Wisp] = []

    private static let tints: [(core: CGColor, halo: CGColor, mid: CGColor)] = [
        (Sprite.color(255, 251, 220), Sprite.color(255, 226, 120, 0.55), Sprite.color(255, 214, 90)),
        (Sprite.color(236, 255, 240), Sprite.color(150, 255, 200, 0.5), Sprite.color(120, 235, 175)),
        (Sprite.color(255, 240, 232), Sprite.color(255, 176, 150, 0.5), Sprite.color(255, 160, 130)),
    ]

    private static func haloImage(_ i: Int) -> CGImage? {
        Sprite.image(CGSize(width: 64, height: 64), scale: 2) { c in
            Sprite.radial(c, center: CGPoint(x: 32, y: 32), radius: 32, inner: tints[i].halo, outer: Sprite.color(255, 255, 255, 0))
        }
    }

    private static func coreImage(_ i: Int) -> CGImage? {
        Sprite.image(CGSize(width: 32, height: 32), scale: 4) { c in
            Sprite.radial(c, center: CGPoint(x: 16, y: 16), radius: 8, inner: Sprite.color(255, 255, 255), outer: tints[i].mid)
            // A soft edge so the core never looks hard.
            c.setStrokeColor(tints[i].halo); c.setLineWidth(1.4)
            c.strokeEllipse(in: CGRect(x: 8, y: 8, width: 16, height: 16))
        }
    }

    private static let sparkleImage: CGImage? = Sprite.image(CGSize(width: 64, height: 64), scale: 3) { c in
        // A four-point twinkle with long soft arms and a short diagonal pair.
        func arm(_ len: CGFloat, _ w: CGFloat, _ angle: CGFloat, _ alpha: CGFloat) {
            c.saveGState()
            c.translateBy(x: 32, y: 32); c.rotate(by: angle)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -len, y: 0)); p.addQuadCurve(to: CGPoint(x: 0, y: w), control: CGPoint(x: -len * 0.12, y: w * 0.2))
            p.addQuadCurve(to: CGPoint(x: len, y: 0), control: CGPoint(x: len * 0.12, y: w * 0.2))
            p.addQuadCurve(to: CGPoint(x: 0, y: -w), control: CGPoint(x: len * 0.12, y: -w * 0.2))
            p.addQuadCurve(to: CGPoint(x: -len, y: 0), control: CGPoint(x: -len * 0.12, y: -w * 0.2))
            c.addPath(p); c.setFillColor(Sprite.color(255, 255, 255, alpha)); c.fillPath()
            c.restoreGState()
        }
        arm(30, 2.6, 0, 0.9); arm(30, 2.6, .pi / 2, 0.9)
        arm(14, 1.6, .pi / 4, 0.55); arm(14, 1.6, -.pi / 4, 0.55)
    }

    private static let tailImage: CGImage? = Sprite.image(CGSize(width: 96, height: 24), scale: 2) { c in
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [Sprite.color(255, 255, 255, 0.0), Sprite.color(255, 245, 190, 0.5)] as CFArray, locations: [0, 1])!
        c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 6, width: 96, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil)); c.clip()
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: 12), end: CGPoint(x: 96, y: 12), options: [])
    }

    init() { root.masksToBounds = false }

    private func make(_ tint: Int) -> Wisp {
        let w = Wisp()
        w.tail.contents = Self.tailImage
        w.tail.bounds = CGRect(x: 0, y: 0, width: 96, height: 24)
        w.tail.anchorPoint = CGPoint(x: 1, y: 0.5)
        w.tail.position = CGPoint.zero
        w.halo.contents = Self.haloImage(tint)
        w.halo.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        w.core.contents = Self.coreImage(tint)
        w.core.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        w.sparkle.contents = Self.sparkleImage
        w.sparkle.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        for l in [w.tail, w.halo, w.core, w.sparkle] { w.box.addSublayer(l) }
        w.box.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        root.addSublayer(w.box)
        return w
    }

    func update(_ states: [FireflyState], pin: (center: CGPoint, radius: CGFloat), head: (center: CGPoint, radius: CGFloat),
                alpha: CGFloat, headGlow: CGFloat, time: CGFloat) {
        // The pin and head are big soft wisps too (the pin warm and steady, the head cooler and brighter when armed).
        var all: [FireflyState] = []
        all.append(FireflyState(position: pin.center, heading: 0, length: pin.radius * 1.7, glow: 0.72 + 0.12 * CGFloat(sin(Double(time * 1.4))),
                                wingPhase: time * 0.6, alpha: alpha, speed: 0, tint: 0))
        all.append(FireflyState(position: head.center, heading: 0, length: max(12, head.radius * 1.7), glow: 0.55 + 0.45 * headGlow + 0.1 * CGFloat(sin(Double(time * 1.9))),
                                wingPhase: time * 0.7 + 1, alpha: alpha, speed: 0, tint: 2))
        all += states
        while wisps.count < all.count { wisps.append(make(wisps.count < 2 ? [0, 2][wisps.count] : all[wisps.count].tint)) }
        for (i, w) in wisps.enumerated() {
            guard i < all.count else { w.box.isHidden = true; continue }
            let s = all[i]
            w.box.isHidden = s.alpha < 0.02
            w.box.opacity = Float(s.alpha)
            w.box.position = s.position
            let sc = s.length / 16
            w.box.transform = CATransform3DMakeScale(sc, sc, 1)
            let big = i < 2
            // Halo breathes with the glow; the core brightens with it.
            let hs = 0.55 + 0.7 * s.glow
            w.halo.transform = CATransform3DMakeScale(hs, hs, 1)
            w.halo.opacity = Float(0.35 + 0.65 * s.glow)
            let cs = 0.75 + 0.35 * s.glow
            w.core.transform = CATransform3DMakeScale(cs, cs, 1)
            w.core.opacity = Float(0.55 + 0.45 * s.glow)
            // The sparkle twinkles: it swells and turns when the light peaks.
            let ss = (big ? 0.55 : 0.45) * (0.2 + 1.1 * s.glow * s.glow)
            w.sparkle.transform = CATransform3DScale(CATransform3DMakeRotation(s.wingPhase * 0.05 + s.glow * 0.6, 0, 0, 1), ss, ss, 1)
            w.sparkle.opacity = Float(min(1, s.glow * 1.25))
            // A short comet tail behind a moving wisp.
            let len = min(1.6, s.speed / 260)
            w.tail.isHidden = len < 0.08 || big
            w.tail.transform = CATransform3DScale(CATransform3DMakeRotation(s.heading, 0, 0, 1), len * 0.5, 0.35, 1)
            w.tail.opacity = Float(min(1, len) * s.glow * 0.9)
        }
    }
}

// MARK: - Stars

@MainActor
final class StarLayers {
    let root = CALayer()
    private struct Star { let box = CALayer(); let halo = CALayer(); let flare = CALayer(); let star = CALayer() }
    private var pool: [Star] = []
    private let lines = CAShapeLayer()
    private var dust: [CALayer] = []
    private var shoot: [CAShapeLayer] = []

    private static let tints: [(fill: CGColor, rim: CGColor, halo: CGColor)] = [
        (Sprite.color(255, 226, 122), Sprite.color(255, 188, 70), Sprite.color(255, 214, 110, 0.55)),
        (Sprite.color(255, 255, 255), Sprite.color(206, 226, 255), Sprite.color(200, 225, 255, 0.5)),
        (Sprite.color(226, 208, 255), Sprite.color(170, 140, 240), Sprite.color(190, 165, 255, 0.5)),
        (Sprite.color(255, 208, 226), Sprite.color(255, 150, 190), Sprite.color(255, 175, 210, 0.5)),
    ]

    private static func starImage(_ t: Int) -> CGImage? {
        Sprite.image(CGSize(width: 64, height: 64), scale: 3) { c in
            let path = CGMutablePath()
            for i in 0..<10 {
                let r: CGFloat = i % 2 == 0 ? 24 : 11.5
                let a = .pi / 2 + CGFloat(i) * .pi / 5
                let p = CGPoint(x: 32 + cos(a) * r, y: 32 + sin(a) * r - 1)
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.closeSubpath()
            c.setLineJoin(.round); c.setLineWidth(7)
            c.setStrokeColor(tints[t].fill); c.setFillColor(tints[t].fill)
            c.addPath(path); c.drawPath(using: .fillStroke)             // rounded points
            c.saveGState(); c.addPath(path); c.setLineWidth(7); c.replacePathWithStrokedPath(); c.clip()
            Sprite.radial(c, center: CGPoint(x: 28, y: 36), radius: 30, inner: Sprite.color(255, 255, 255), outer: tints[t].rim)
            c.restoreGState()
            c.setFillColor(Sprite.color(255, 255, 255, 0.85))
            c.fillEllipse(in: CGRect(x: 25, y: 38, width: 5, height: 5))                       // a bright shine
        }
    }

    private static func haloImage(_ t: Int) -> CGImage? {
        Sprite.image(CGSize(width: 64, height: 64), scale: 2) { c in
            Sprite.radial(c, center: CGPoint(x: 32, y: 32), radius: 32, inner: tints[t].halo, outer: Sprite.color(255, 255, 255, 0))
        }
    }

    private static let flareImage: CGImage? = Sprite.image(CGSize(width: 96, height: 96), scale: 2) { c in
        for ang in [CGFloat(0), .pi / 2] {
            c.saveGState(); c.translateBy(x: 48, y: 48); c.rotate(by: ang)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -46, y: 0)); p.addQuadCurve(to: CGPoint(x: 46, y: 0), control: CGPoint(x: 0, y: 3.4))
            p.addQuadCurve(to: CGPoint(x: -46, y: 0), control: CGPoint(x: 0, y: -3.4))
            c.addPath(p); c.setFillColor(Sprite.color(255, 255, 255, 0.85)); c.fillPath(); c.restoreGState()
        }
    }

    private static let dustImage: CGImage? = Sprite.image(CGSize(width: 16, height: 16), scale: 3) { c in
        Sprite.radial(c, center: CGPoint(x: 8, y: 8), radius: 5, inner: Sprite.color(255, 255, 255), outer: Sprite.color(255, 255, 255, 0))
    }

    init() {
        root.masksToBounds = false
        lines.fillColor = nil
        lines.strokeColor = Sprite.color(215, 228, 255, 0.55)
        lines.lineWidth = 1.2; lines.lineDashPattern = [2, 5]; lines.lineCap = .round
        root.addSublayer(lines)
    }

    private func make(_ tint: Int) -> Star {
        let s = Star()
        s.halo.contents = Self.haloImage(tint); s.halo.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        s.flare.contents = Self.flareImage; s.flare.bounds = CGRect(x: 0, y: 0, width: 96, height: 96)
        s.star.contents = Self.starImage(tint); s.star.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        for l in [s.halo, s.flare, s.star] { s.box.addSublayer(l) }
        s.box.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        root.addSublayer(s.box)
        return s
    }

    func update(_ sc: StarScene) {
        root.opacity = Float(sc.alpha)
        let all = [sc.pin, sc.headStar] + sc.stars
        while pool.count < all.count { pool.append(make(all[pool.count].tint)) }
        for (i, st) in pool.enumerated() {
            guard i < all.count else { st.box.isHidden = true; continue }
            let s = all[i]
            st.box.isHidden = s.alpha < 0.02
            st.box.opacity = Float(s.alpha)
            st.box.position = s.position
            let k = max(0.05, s.size / 22)
            st.box.transform = CATransform3DMakeScale(k, k, 1)
            st.star.transform = CATransform3DMakeRotation(s.rotation, 0, 0, 1)
            let pulse = 0.92 + 0.14 * s.twinkle
            st.star.transform = CATransform3DScale(st.star.transform, pulse, pulse, 1)
            st.halo.opacity = Float(0.3 + 0.7 * s.twinkle)
            let hs = 1.0 + 0.8 * s.twinkle
            st.halo.transform = CATransform3DMakeScale(hs, hs, 1)
            st.flare.opacity = Float(max(0, s.twinkle * s.twinkle * 1.1 - 0.1))
            let fs = 0.4 + 0.9 * s.twinkle
            st.flare.transform = CATransform3DScale(CATransform3DMakeRotation(s.rotation * 0.5, 0, 0, 1), fs, fs, 1)
        }
        // Constellation lines.
        let p = CGMutablePath()
        for (a, b, _) in sc.lines { p.move(to: a); p.addLine(to: b) }
        lines.path = p
        lines.opacity = Float(sc.lines.map { $0.2 }.max() ?? 0)
        // Dust: tiny twinkles.
        while dust.count < sc.dust.count {
            let l = CALayer(); l.contents = Self.dustImage; l.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
            root.addSublayer(l); dust.append(l)
        }
        for (i, l) in dust.enumerated() {
            guard i < sc.dust.count else { l.isHidden = true; continue }
            l.isHidden = sc.dust[i].1 < 0.03
            l.position = sc.dust[i].0
            l.opacity = Float(sc.dust[i].1)
        }
        // Shooting star: a bright head with a fading streak.
        while shoot.count < max(1, sc.shooting.count) * 3 {
            let l = CAShapeLayer(); l.fillColor = nil; l.lineCap = .round
            root.addSublayer(l); shoot.append(l)
        }
        for l in shoot { l.isHidden = true }
        for (i, sh) in sc.shooting.enumerated() {
            for j in 0..<3 {
                let l = shoot[i * 3 + j]
                let f = [0.0, 0.45, 0.8][j]
                let a = CGPoint(x: sh.tail.x + (sh.head.x - sh.tail.x) * f, y: sh.tail.y + (sh.head.y - sh.tail.y) * f)
                let path = CGMutablePath(); path.move(to: a); path.addLine(to: sh.head)
                l.path = path
                l.strokeColor = Sprite.color(255, 250, 225, 0.35 + 0.3 * CGFloat(j))
                l.lineWidth = [7, 4.5, 2.6][j]
                l.opacity = Float(sh.alpha)
                l.isHidden = false
            }
        }
    }
}

// MARK: - Kite

@MainActor
final class KiteLayers {
    let root = CALayer()
    private let string = CAShapeLayer()
    private let tail = CAShapeLayer()
    private let spool = CAShapeLayer(), spoolInner = CAShapeLayer(), spoolHub = CAShapeLayer(), spoolWind = CAShapeLayer()
    private let kite = CALayer()
    private let panels = (0..<4).map { _ in CAShapeLayer() }
    private let outline = CAShapeLayer(), spars = CAShapeLayer()
    private var bows: [(CAShapeLayer, CAShapeLayer)] = []
    private let ref: CGFloat = 40
    private static let panelColors = [Sprite.color(255, 128, 118), Sprite.color(255, 207, 86), Sprite.color(92, 196, 190), Sprite.color(255, 160, 196)]
    private static let bowColors = [Sprite.color(255, 128, 118), Sprite.color(255, 207, 86), Sprite.color(92, 196, 190)]

    init() {
        root.masksToBounds = false
        string.fillColor = nil; string.strokeColor = Sprite.color(255, 250, 238, 0.95); string.lineWidth = 1.6; string.lineCap = .round
        PaperRopeLayers.paperShadow(string, depth: 1)
        tail.fillColor = nil; tail.strokeColor = Sprite.color(255, 250, 238, 0.9); tail.lineWidth = 1.6; tail.lineCap = .round
        for l in [string, tail] { root.addSublayer(l) }
        for l in [spool, spoolInner, spoolHub, spoolWind] { root.addSublayer(l) }
        PaperRopeLayers.paperShadow(spool, depth: 2)
        spool.fillColor = Sprite.color(222, 168, 108); spool.strokeColor = Sprite.color(255, 250, 238); spool.lineWidth = 2.6
        spoolInner.fillColor = Sprite.color(246, 214, 168)
        spoolHub.fillColor = Sprite.color(110, 78, 56)
        spoolWind.fillColor = nil; spoolWind.strokeColor = Sprite.color(255, 250, 238, 0.85); spoolWind.lineWidth = 1.3
        root.addSublayer(kite)
        let r = ref
        let top = CGPoint(x: 0, y: r * 1.25), right = CGPoint(x: r * 0.8, y: r * 0.15), bottom = CGPoint(x: 0, y: -r * 1.0)
        let left = CGPoint(x: -r * 0.8, y: r * 0.15), ctr = CGPoint(x: 0, y: r * 0.15)
        let tris: [[CGPoint]] = [[top, right, ctr], [right, bottom, ctr], [bottom, left, ctr], [left, top, ctr]]
        for (i, p) in panels.enumerated() {
            let path = CGMutablePath(); path.move(to: tris[i][0]); path.addLine(to: tris[i][1]); path.addLine(to: tris[i][2]); path.closeSubpath()
            p.path = path; p.fillColor = Self.panelColors[i]
            kite.addSublayer(p)
        }
        let o = CGMutablePath(); o.move(to: top); o.addLine(to: right); o.addLine(to: bottom); o.addLine(to: left); o.closeSubpath()
        outline.path = o; outline.fillColor = nil; outline.strokeColor = Sprite.color(255, 250, 238); outline.lineWidth = 3.2; outline.lineJoin = .round
        PaperRopeLayers.paperShadow(outline, depth: 2.4)
        let sp = CGMutablePath(); sp.move(to: top); sp.addLine(to: bottom); sp.move(to: left); sp.addLine(to: right)
        spars.path = sp; spars.fillColor = nil; spars.strokeColor = Sprite.color(255, 250, 238, 0.9); spars.lineWidth = 1.6
        kite.addSublayer(spars); kite.addSublayer(outline)
    }

    func update(_ s: KiteScene) {
        root.opacity = Float(s.alpha)
        let sp = CGMutablePath()
        if let f = s.string.first {
            sp.move(to: f)
            for q in s.string.dropFirst() { sp.addLine(to: q) }
        }
        string.path = sp
        // Reel: a wooden spool seen front-on.
        let R = s.spoolSize
        let c = s.spool
        spool.path = CGPath(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2), transform: nil)
        spoolInner.path = CGPath(ellipseIn: CGRect(x: c.x - R * 0.68, y: c.y - R * 0.68, width: R * 1.36, height: R * 1.36), transform: nil)
        spoolHub.path = CGPath(ellipseIn: CGRect(x: c.x - R * 0.2, y: c.y - R * 0.2, width: R * 0.4, height: R * 0.4), transform: nil)
        let w = CGMutablePath()
        for k in 0..<3 { let rr = R * (0.32 + 0.13 * CGFloat(k)); w.addEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)) }
        spoolWind.path = w
        // Kite.
        let k = max(0.02, s.kiteSize / (ref * 1.1))
        kite.position = s.kite
        kite.transform = CATransform3DScale(CATransform3DMakeRotation(s.kiteAngle, 0, 0, 1), k, k, 1)
        // Tail ribbon and bows.
        let tp = CGMutablePath()
        let anchor = CGPoint(x: s.kite.x + sin(s.kiteAngle) * s.kiteSize * 1.02, y: s.kite.y - cos(s.kiteAngle) * s.kiteSize * 1.02)
        tp.move(to: anchor)
        for q in s.tail { tp.addLine(to: q) }
        tail.path = tp
        while bows.count < s.tail.count {
            let a = CAShapeLayer(), b = CAShapeLayer()
            for l in [a, b] { l.strokeColor = Sprite.color(255, 250, 238); l.lineWidth = 1.6; l.lineJoin = .round; root.addSublayer(l) }
            let col = Self.bowColors[bows.count % Self.bowColors.count]
            a.fillColor = col; b.fillColor = col
            bows.append((a, b))
        }
        for (i, pair) in bows.enumerated() {
            guard i < s.tail.count else { pair.0.isHidden = true; pair.1.isHidden = true; continue }
            let p = s.tail[i]
            let prev = i == 0 ? anchor : s.tail[i - 1]
            let ang = atan2(p.y - prev.y, p.x - prev.x)
            let sz = max(3.5, s.kiteSize * 0.27 * s.bows[i])
            for (j, l) in [pair.0, pair.1].enumerated() {
                let sgn: CGFloat = j == 0 ? 1 : -1
                let path = CGMutablePath()
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: sgn * sz * 1.5, y: sz)); path.addLine(to: CGPoint(x: sgn * sz * 1.5, y: -sz)); path.closeSubpath()
                var t = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: ang + .pi / 2)
                l.path = path.copy(using: &t)
                l.isHidden = false
            }
        }
    }
}

// MARK: - Soap bubbles

@MainActor
final class BubbleLayers {
    let root = CALayer()
    private struct Bub { let box = CALayer(); let img = CALayer(); let ring = CAShapeLayer(); let drops = (0..<6).map { _ in CALayer() } }
    private var pool: [Bub] = []

    private static func hsv(_ h: CGFloat, _ s: CGFloat, _ v: CGFloat, _ a: CGFloat) -> CGColor {
        let c = NSColor(hue: h.truncatingRemainder(dividingBy: 1), saturation: s, brightness: v, alpha: a).usingColorSpace(.sRGB)!
        return CGColor(srgbRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: a)
    }

    private static func bubbleImage(_ variant: Int) -> CGImage? {
        Sprite.image(CGSize(width: 128, height: 128), scale: 2) { c in
            let ctr = CGPoint(x: 64, y: 64), r: CGFloat = 58
            let rect = CGRect(x: ctr.x - r, y: ctr.y - r, width: r * 2, height: r * 2)
            c.saveGState(); c.addEllipse(in: rect); c.clip()
            // A film that is nearly clear in the middle and tinted toward the rim.
            Sprite.radial(c, center: ctr, radius: r, inner: Sprite.color(255, 255, 255, 0.02), outer: Sprite.color(255, 255, 255, 0.24))
            c.restoreGState()
            // Iridescent rim: segments around the circle cycle through hues, twice (outer and a fainter inner band).
            let n = 72
            for band in 0..<2 {
                let rr = r - 1.5 - CGFloat(band) * 6.5
                for i in 0..<n {
                    let a0 = CGFloat(i) / CGFloat(n) * 2 * .pi, a1 = CGFloat(i + 1) / CGFloat(n) * 2 * .pi + 0.02
                    let hue = CGFloat(i) / CGFloat(n) * (band == 0 ? 1.0 : 1.4) + CGFloat(variant) * 0.17 + CGFloat(band) * 0.3
                    c.setStrokeColor(hsv(hue, 0.55, 1.0, band == 0 ? 0.62 : 0.28))
                    c.setLineWidth(band == 0 ? 4.2 : 3)
                    c.addArc(center: ctr, radius: rr, startAngle: a0, endAngle: a1, clockwise: false); c.strokePath()
                }
            }
            c.setStrokeColor(Sprite.color(255, 255, 255, 0.5)); c.setLineWidth(1.0); c.strokeEllipse(in: rect)
            // Highlights: a bright curved window reflection and a small dot opposite.
            c.setLineCap(.round)
            c.setStrokeColor(Sprite.color(255, 255, 255, 0.92)); c.setLineWidth(5.5)
            c.addArc(center: ctr, radius: r - 13, startAngle: .pi * 0.62, endAngle: .pi * 0.86, clockwise: false); c.strokePath()
            c.setLineWidth(3)
            c.addArc(center: ctr, radius: r - 13, startAngle: .pi * 0.9, endAngle: .pi * 0.95, clockwise: false); c.strokePath()
            c.setFillColor(Sprite.color(255, 255, 255, 0.6))
            c.fillEllipse(in: CGRect(x: ctr.x + 24, y: ctr.y - 34, width: 8, height: 5))
        }
    }

    private static let variants: [CGImage?] = (0..<3).map { bubbleImage($0) }
    private static let dropImage: CGImage? = Sprite.image(CGSize(width: 12, height: 12), scale: 3) { c in
        Sprite.radial(c, center: CGPoint(x: 6, y: 6), radius: 5, inner: Sprite.color(255, 255, 255, 0.95), outer: Sprite.color(190, 230, 255, 0))
    }

    init() { root.masksToBounds = false }

    private func make(_ i: Int) -> Bub {
        let b = Bub()
        b.img.contents = Self.variants[i % 3]
        b.img.bounds = CGRect(x: 0, y: 0, width: 128, height: 128)
        b.ring.fillColor = nil; b.ring.strokeColor = Sprite.color(255, 255, 255, 0.8); b.ring.lineWidth = 2
        for d in b.drops { d.contents = Self.dropImage; d.bounds = CGRect(x: 0, y: 0, width: 8, height: 8); b.box.addSublayer(d) }
        b.box.addSublayer(b.img); b.box.addSublayer(b.ring)
        b.box.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        root.addSublayer(b.box)
        return b
    }

    func update(_ states: [BubbleState]) {
        while pool.count < states.count { pool.append(make(pool.count)) }
        for (i, b) in pool.enumerated() {
            guard i < states.count else { b.box.isHidden = true; continue }
            let s = states[i]
            b.box.isHidden = s.alpha < 0.02
            b.box.position = s.position
            let k = max(0.02, s.radius / 58)
            let popScale = 1 + 0.35 * s.pop
            var t = CATransform3DMakeRotation(s.wobbleAngle, 0, 0, 1)
            t = CATransform3DScale(t, (1 + s.wobble) * k * popScale, (1 - s.wobble) * k * popScale, 1)
            b.img.transform = CATransform3DRotate(t, -s.wobbleAngle, 0, 0, 1)
            b.img.opacity = Float(s.alpha * max(0, 1 - s.pop * 1.4))
            // A thin shimmering ring flies outward as it pops, with a few droplets.
            let popping = s.pop > 0.001
            b.ring.isHidden = !popping
            if popping {
                let rr = s.radius * (1 + 0.8 * s.pop)
                b.ring.path = CGPath(ellipseIn: CGRect(x: -rr, y: -rr, width: rr * 2, height: rr * 2), transform: nil)
                b.ring.opacity = Float(s.alpha * (1 - s.pop))
            }
            for (j, d) in b.drops.enumerated() {
                d.isHidden = !popping
                guard popping else { continue }
                let a = CGFloat(j) / 6 * 2 * .pi + 0.4
                let rr = s.radius * (0.9 + 1.5 * s.pop)
                d.position = CGPoint(x: cos(a) * rr, y: sin(a) * rr - 14 * s.pop * s.pop)
                d.opacity = Float(s.alpha * (1 - s.pop))
            }
        }
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
