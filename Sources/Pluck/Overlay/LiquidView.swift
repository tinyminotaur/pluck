import AppKit
import Foundation
import Metal
import PluckCore
import QuartzCore
import simd

/// Hosts the liquid: a bbox-sized `CAMetalLayer` presented straight from the GPU, label layers on top,
/// and the display link that drives the simulation. Everything is y-up AppKit view space.
@MainActor
final class LiquidView: NSView {
    /// Called once per display frame before the simulation steps. The session samples the pointer here.
    var onFrame: ((CGFloat) -> Void)?
    /// Called once when the release animation has fully played out.
    var onFinished: (() -> Void)?

    private(set) var tether = LiquidTether()
    private let renderer = BlobRenderer()
    private let metalLayer = CAMetalLayer()
    private var labels: [CompassRole: CATextLayer] = [:]
    private var labelSizes: [CompassRole: CGSize] = [:]
    private var items: [CompassItem] = []
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var time: Float = 0
    private var light = SIMD2<Float>(-0.45, 0.8)
    private var reduceMotion = false
    private var finishedFired = false
    private var drawableSize: CGSize = .zero

    private var cfg: FeelLabConfig { FeelLabConfig.shared }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false

        metalLayer.device = renderer?.device
        metalLayer.pixelFormat = BlobRenderer.pixelFormat
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.backgroundColor = nil
        // Layer frame and drawable must change atomically as the blob grows and moves.
        metalLayer.presentsWithTransaction = true
        metalLayer.isHidden = true
        layer?.addSublayer(metalLayer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit { displayLink?.invalidate() }

    // MARK: Control

    func begin(pin: CGPoint, items: [CompassItem], reduceMotion: Bool, startDisplayLink: Bool = true) {
        self.reduceMotion = reduceMotion
        finishedFired = false
        time = 0
        lastTimestamp = 0
        light = SIMD2(-0.45, 0.8)
        setItems(items)
        tether = LiquidTether(params: cfg.tetherParams(reduceMotion: reduceMotion))
        tether.begin(pin: pin, roles: items.map(\.role))
        if startDisplayLink { startLink() }
    }

    func setTarget(_ p: CGPoint) { tether.setTarget(p) }
    func setCaptured(_ r: CompassRole?) { tether.setCaptured(r) }
    func setBloom(_ on: Bool) { tether.setBloom(on) }

    func setItems(_ new: [CompassItem]) {
        items = new
        tether.setRoles(new.map(\.role))
        rebuildLabels()
    }

    func release(commit direction: CGPoint?, role: CompassRole?) {
        tether.release(commit: direction, role: role)
    }

    /// Offscreen stepping for snapshots: advances the simulation and lays out labels, without a display link.
    func advanceManually(dt: CGFloat) {
        tether.params = cfg.tetherParams(reduceMotion: reduceMotion)
        tether.advance(dt: dt)
        updateLabels()
    }

    /// Renders just the label layers (the Metal layer is not captured) for snapshot compositing.
    func renderLabels(into ctx: CGContext) {
        layer?.render(in: ctx)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        metalLayer.isHidden = true
        for l in labels.values { l.removeFromSuperlayer() }
        labels.removeAll()
    }

    // MARK: Display link

    private func startLink() {
        displayLink?.invalidate()
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let ts = link.timestamp
        var dt = lastTimestamp == 0 ? 1.0 / 60 : ts - lastTimestamp
        lastTimestamp = ts
        dt = min(0.05, max(1.0 / 480, dt))

        CursorGuard.shared.checkIn()
        onFrame?(CGFloat(dt))

        tether.params = cfg.tetherParams(reduceMotion: reduceMotion)
        tether.advance(dt: CGFloat(dt))
        time += Float(dt)
        updateLight(dt: Float(dt))
        render()
        updateLabels()

        if tether.isFinished, !finishedFired {
            finishedFired = true
            metalLayer.isHidden = true
            onFinished?()
        }
    }

    private func updateLight(dt: Float) {
        let v = tether.headVelocity
        let speed = Float(hypot(v.x, v.y))
        var target = SIMD2<Float>(-0.45, 0.8)
        if speed > 60 {
            // The highlight swings opposite to motion: the surface catches light as it drags.
            let dir = SIMD2<Float>(Float(-v.x), Float(-v.y)) / speed
            let k = min(1, (speed - 60) / 700)
            target = simd_normalize(SIMD2<Float>(-0.45, 0.8) * (1 - k) + (dir * 0.8 + SIMD2(0, 0.45)) * k)
        }
        light += (target - light) * min(1, dt * 5)
    }

    // MARK: Rendering

    private func render() {
        guard let renderer, metalLayer.device != nil else { return }
        guard let bounds = tether.drawnBounds() else {
            metalLayer.isHidden = true
            return
        }
        let blend = CGFloat(cfg.blend)
        let pad = blend * 1.2 + 40
        var rect = bounds.insetBy(dx: -pad, dy: -pad)
        // Quantize so the drawable only reallocates when the blob has really grown.
        let q: CGFloat = 32
        let x0 = floor(rect.minX / q) * q, y0 = floor(rect.minY / q) * q
        rect = CGRect(x: x0, y: y0,
                      width: ceil((rect.maxX - x0) / (q * 2)) * q * 2,
                      height: ceil((rect.maxY - y0) / (q * 2)) * q * 2)
        rect = rect.intersection(self.bounds.insetBy(dx: -pad, dy: -pad))
        guard rect.width >= 2, rect.height >= 2 else {
            metalLayer.isHidden = true
            return
        }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let px = CGSize(width: ceil(rect.width * scale), height: ceil(rect.height * scale))
        guard px.width < 8192, px.height < 8192 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = rect
        metalLayer.contentsScale = scale
        if drawableSize != px {
            metalLayer.drawableSize = px
            drawableSize = px
        }
        metalLayer.isHidden = false
        CATransaction.commit()

        guard let drawable = metalLayer.nextDrawable(),
              let cmd = renderer.makeCommandBuffer() else { return }
        let look = cfg.look(time: time, light: light)
        renderer.encode(
            into: drawable.texture,
            commandBuffer: cmd,
            origin: rect.origin,
            scale: scale,
            primitives: tether.primitives(),
            look: look
        )
        cmd.commit()
        cmd.waitUntilScheduled()
        drawable.present()
    }

    // MARK: Labels

    private func rebuildLabels() {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let keep = Set(items.map(\.role))
        for (role, layer) in labels where !keep.contains(role) {
            layer.removeFromSuperlayer()
            labels[role] = nil
            labelSizes[role] = nil
        }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for item in items {
            let text = item.title
            let attr = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
            ])
            let size = attr.size()
            let layer = labels[item.role] ?? CATextLayer()
            layer.string = attr
            layer.alignmentMode = .center
            layer.contentsScale = scale
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.8
            layer.shadowRadius = 3
            layer.shadowOffset = .zero
            layer.opacity = 0
            labelSizes[item.role] = CGSize(width: ceil(size.width) + 4, height: ceil(size.height) + 2)
            if layer.superlayer == nil { self.layer?.addSublayer(layer) }
            labels[item.role] = layer
        }
    }

    private func updateLabels() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let anchors = tether.lobeAnchors()
        for a in anchors {
            guard let layer = labels[a.role], let size = labelSizes[a.role] else { continue }
            let presence = a.presence
            let gap: CGFloat = 9
            var origin = CGPoint.zero
            switch a.role {
            case .east: origin = CGPoint(x: a.center.x + a.radius + gap, y: a.center.y - size.height / 2)
            case .west: origin = CGPoint(x: a.center.x - a.radius - gap - size.width, y: a.center.y - size.height / 2)
            case .north: origin = CGPoint(x: a.center.x - size.width / 2, y: a.center.y + a.radius + gap)
            case .south: origin = CGPoint(x: a.center.x - size.width / 2, y: a.center.y - a.radius - gap - size.height)
            }
            layer.frame = CGRect(origin: origin, size: size)
            let emphasis = 0.62 + 0.38 * a.glow
            layer.opacity = Float(max(0, min(1, (presence - 0.25) / 0.75)) * emphasis * min(1, tether.emergence))
        }
    }
}
