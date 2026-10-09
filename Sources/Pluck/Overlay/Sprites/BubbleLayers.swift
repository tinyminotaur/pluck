import AppKit
import PluckCore
import QuartzCore

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
