import AppKit
import TwangCore
import QuartzCore

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
