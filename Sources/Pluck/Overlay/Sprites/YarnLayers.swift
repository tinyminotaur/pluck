import AppKit
import PluckCore
import QuartzCore

private func wool(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor { Sprite.color(r, g, b, a) }

/// A ball of thread with a lasso loop on the end of the thread (see `YarnLassoSim`).
@MainActor
final class YarnLayers {
    let root = CALayer()
    private let ball = CAShapeLayer(), rim = CAShapeLayer(), highlight = CAShapeLayer()
    private let windA = lineLayer(wool(150, 92, 38, 0.9), 2), windB = lineLayer(wool(176, 38, 52, 0.85), 2)
    private let tail = lineLayer(wool(226, 178, 96), 2.6)
    private let threadShadow = lineLayer(wool(70, 40, 14, 0.5), 6), threadCore = lineLayer(wool(226, 178, 96), 3.6), threadTwist = lineLayer(wool(255, 240, 205, 0.85), 1.3)
    private let loopShadow = lineLayer(wool(70, 40, 14, 0.5), 6), loopCore = lineLayer(wool(226, 178, 96), 3.6), loopTwist = lineLayer(wool(255, 240, 205, 0.85), 1.3)
    private let knot = CAShapeLayer(), flash = CAShapeLayer()
    private lazy var sparks = DotPool(parent: root, image: softDot)

    init() {
        root.masksToBounds = false
        ball.fillColor = wool(226, 178, 96)
        rim.fillColor = nil; rim.strokeColor = wool(120, 74, 28, 0.9); rim.lineWidth = 2.2
        highlight.fillColor = wool(255, 250, 230, 0.28)
        knot.fillColor = wool(176, 38, 52); knot.strokeColor = wool(226, 178, 96); knot.lineWidth = 1.6
        flash.fillColor = wool(255, 255, 255, 0)
        for l in [threadTwist, loopTwist] { l.lineDashPattern = [2.5, 3.8] }
        for l in [tail, threadShadow, threadCore, threadTwist, loopShadow, loopCore, loopTwist, ball, windA, windB, rim, highlight, knot, flash] {
            root.addSublayer(l)
        }
    }

    func update(_ s: YarnScene) {
        root.opacity = Float(s.alpha)
        let c = s.ballCenter, R = s.ballRadius
        let circle = circlePath(c, R)
        ball.path = circle; rim.path = circle
        // Winding strokes: ellipses whose long axis is the ball's radius, so they always stay inside the ball.
        let a = CGMutablePath(), b = CGMutablePath()
        for k in 0..<6 {
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: s.ballSpin + CGFloat(k) * .pi / 6)
            let ry = R * (0.3 + 0.1 * CGFloat(k % 3))
            (k % 2 == 0 ? a : b).addEllipse(in: CGRect(x: -R * 0.96, y: -ry, width: R * 1.92, height: ry * 2), transform: t)
        }
        windA.path = a; windB.path = b
        windA.lineWidth = max(1.3, R * 0.07); windB.lineWidth = max(1.3, R * 0.07)
        highlight.path = circlePath(CGPoint(x: c.x - R * 0.35, y: c.y + R * 0.35), R * 0.28)

        let thread = polyline(s.thread)
        threadShadow.path = thread; threadCore.path = thread; threadTwist.path = thread
        threadTwist.lineDashPhase = -s.twist
        tail.path = polyline(s.tail)

        let loop = circlePath(s.loopCenter, s.loopRadius)
        loopShadow.path = loop; loopCore.path = loop; loopTwist.path = loop
        loopTwist.lineDashPhase = s.twist
        knot.path = circlePath(s.knot, 3.6)

        flash.path = circlePath(s.flashCenter, max(8, s.loopRadius * 2.4))
        flash.fillColor = wool(255, 255, 255, 0.4 * s.flash)
        for (i, sp) in s.sparks.enumerated() { sparks.place(i, at: sp.0, size: sp.2 * 2.6, alpha: sp.1) }
        sparks.hide(from: s.sparks.count)
    }
}
