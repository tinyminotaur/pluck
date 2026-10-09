import AppKit
import PluckCore
import QuartzCore

/// Holds the sprite layers on screen: shows the active style's layer, hides the rest, and gives every sprite style the
/// same soft scale-in. Everything is a small Core Animation layer (sprites rendered once, then moved per frame), so it
/// stays cheap at 120 Hz, and it can also be rendered offscreen with `CALayer.render(in:)` for previews.
@MainActor
final class VectorStyleHost {
    let root = CALayer()
    private var runnerLayer: CALayer?

    init() {
        root.masksToBounds = false
        root.isHidden = true
    }

    /// The active runner's layer replaces the previous one.
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
        for x in root.sublayers ?? [] { x.isHidden = x !== runner.layer }
        runner.present(emerge: emerge, glow: glow)
    }

    /// A soft scale-in about the pin as the gesture emerges (and out as it leaves).
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

    func hide() { root.isHidden = true }
}
