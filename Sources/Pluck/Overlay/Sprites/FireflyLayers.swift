import AppKit
import PluckCore
import QuartzCore

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
