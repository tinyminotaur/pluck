import AppKit
import TwangCore
import QuartzCore

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
