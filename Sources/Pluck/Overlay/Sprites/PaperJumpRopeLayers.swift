import AppKit
import PluckCore
import QuartzCore

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
