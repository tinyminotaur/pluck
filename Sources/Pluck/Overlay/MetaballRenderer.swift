import AppKit
import Foundation
import PluckCore
import QuartzCore
import simd

/// Liquid tether + optical draw.
///
/// COORDINATE LOCK:
/// - `lockedPin` is captured when the gesture starts and never moves.
/// - `head` tracks the live pointer 1:1 in the same view space.
/// - Metal circles use AppKit bbox-local coords (y-up). No Y-flip.
final class MetaballView: NSView {
    var pin: CGPoint = .zero {
        didSet {
            // Only adopt pin before lock; after startPhysics, pin is frozen.
            if !pinLocked { lockedPin = pin }
        }
    }
    var head: CGPoint = .zero
    var emerge: CGFloat = 0
    var bloom: CGFloat = 0
    var captured: CompassRole?
    var items: [CompassItem] = []
    var tintColor: NSColor = NSColor(calibratedRed: 0.05, green: 0.055, blue: 0.07, alpha: 1)
    var reducedMotion = false

    /// Frozen anchor — LOCKED for the gesture lifetime.
    private var lockedPin: CGPoint = .zero
    private var pinLocked = false

    private var spine: [CGPoint] = []
    private var prevSpine: [CGPoint] = []
    private var radii: [CGFloat] = []
    private var slosh: [CGFloat] = []
    private var prevSlosh: [CGFloat] = []

    private var displayLink: CVDisplayLink?
    private var fallbackTimer: Timer?
    private var lastTick: CFTimeInterval = 0
    private var physicsRunning = false
    private var prevHead: CGPoint = .zero
    private var headVel: CGPoint = .zero
    private var smoothLight = CGPoint(x: -0.4, y: 0.75)
    private var time: CGFloat = 0

    private let metal = ObsidianBlobMetal.shared

    private var cfg: FeelLabConfig { FeelLabConfig.shared }
    private var mass: BlobMassParams { cfg.massParams }
    private var particleCount: Int { cfg.resolvedParticleCount }

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    deinit { stopPhysics() }

    func startPhysics() {
        // LOCK pin to wherever the gesture began.
        lockedPin = pin
        pinLocked = true
        head = pin

        guard !reducedMotion else {
            resetSpineStraight()
            needsDisplay = true
            return
        }
        resetSpineStraight()
        prevHead = head
        headVel = .zero
        guard !physicsRunning else { return }
        physicsRunning = true
        lastTick = CACurrentMediaTime()

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else {
            fallbackTimer?.invalidate()
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 90.0, repeats: true) { [weak self] t in
                guard let self, self.physicsRunning else { t.invalidate(); return }
                Task { @MainActor in self.tick() }
            }
            if let fallbackTimer { RunLoop.main.add(fallbackTimer, forMode: .common) }
            return
        }
        displayLink = link
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context -> CVReturn in
            guard let context else { return kCVReturnSuccess }
            let view = Unmanaged<MetaballView>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { view.tick() }
            return kCVReturnSuccess
        }
        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
    }

    func stopPhysics() {
        physicsRunning = false
        pinLocked = false
        if let displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func tick() {
        guard physicsRunning || emerge > 0.01 else { return }
        // Keep system cursor suppressed for the whole gesture.
        NSCursor.hide()

        let now = CACurrentMediaTime()
        var dt = now - lastTick
        lastTick = now
        dt = min(1.0 / 30.0, max(1.0 / 240.0, dt))
        time += CGFloat(dt)
        tintColor = cfg.tintColor
        stepPhysics(dt: CGFloat(dt))
        needsDisplay = true
    }

    private func resetSpineStraight() {
        let n = particleCount
        let anchor = lockedPin
        spine = (0..<n).map { i in lerp(anchor, head, CGFloat(i) / CGFloat(max(1, n - 1))) }
        prevSpine = spine
        radii = BlobMass.radiusProfile(
            length: hypot(head.x - anchor.x, head.y - anchor.y),
            samples: n,
            params: mass
        )
        slosh = Array(repeating: 0, count: n)
        prevSlosh = slosh
    }

    private func stepPhysics(dt: CGFloat) {
        let n = particleCount
        let params = mass
        let anchor = lockedPin
        if spine.count != n { resetSpineStraight(); return }

        let rawVel = CGPoint(
            x: (head.x - prevHead.x) / max(dt, 1.0 / 240.0),
            y: (head.y - prevHead.y) / max(dt, 1.0 / 240.0)
        )
        let velAlpha = GestureMath.smoothingAlpha(retain: 0.55, dt: dt)
        headVel = CGPoint(
            x: headVel.x + (rawVel.x - headVel.x) * velAlpha,
            y: headVel.y + (rawVel.y - headVel.y) * velAlpha
        )
        prevHead = head

        let speed = hypot(headVel.x, headVel.y)
        if speed > 8 {
            let target = CGPoint(x: -headVel.x / speed, y: headVel.y / speed * 0.35 + 0.65)
            smoothLight.x += (target.x - smoothLight.x) * min(1, dt * 6)
            smoothLight.y += (target.y - smoothLight.y) * min(1, dt * 6)
        } else {
            smoothLight.x += (-0.4 - smoothLight.x) * min(1, dt * 2)
            smoothLight.y += (0.75 - smoothLight.y) * min(1, dt * 2)
        }

        let dx = head.x - anchor.x
        let dy = head.y - anchor.y
        let chord = hypot(dx, dy)
        let tx: CGFloat = chord > 0.5 ? dx / chord : 1
        let ty: CGFloat = chord > 0.5 ? dy / chord : 0
        let nx = -ty
        let ny = tx
        let latSpeed = headVel.x * nx + headVel.y * ny
        let tanSpeed = headVel.x * tx + headVel.y * ty

        var baseRadii = BlobMass.radiusProfile(length: chord, samples: n, params: params)
        let emergeScale = max(0.08, emerge)

        // LOCKED anchors.
        spine[0] = anchor
        spine[n - 1] = head

        let damping = GestureMath.damping(cfg.dampingConstant, dt: dt)
        // Accelerations are tuned at 60 fps; dt² * 60 keeps the same feel at any refresh rate.
        let step = dt * dt * 60
        let spring = cfg.springConstant
        let whip = CGFloat(cfg.whipResponse)
        let sloshAmp = CGFloat(cfg.sloshAmount)
        let ideal = max(0.5, chord / CGFloat(n - 1))

        for i in 1..<(n - 1) {
            let cur = spine[i]
            let prv = prevSpine[i]
            var vel = CGPoint(x: (cur.x - prv.x) * damping, y: (cur.y - prv.y) * damping)
            let t = CGFloat(i) / CGFloat(n - 1)
            let mid = sin(.pi * t)
            let target = lerp(anchor, head, t)
            let k = spring * (0.4 + 0.6 * (1 - mid)) * step
            vel.x += (target.x - cur.x) * k
            vel.y += (target.y - cur.y) * k
            let impulse = latSpeed * mid * 0.05 * whip
            vel.x += nx * impulse * step * 60
            vel.y += ny * impulse * step * 60
            prevSpine[i] = cur
            spine[i] = CGPoint(x: cur.x + vel.x, y: cur.y + vel.y)
        }

        if slosh.count != n {
            slosh = Array(repeating: 0, count: n)
            prevSlosh = slosh
        }
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            let mid = sin(.pi * t)
            let drive = (-tanSpeed * 0.0045 * (t - 0.3) + latSpeed * 0.004 * mid) * sloshAmp
                + sin(time * 8.5 + t * 5.5) * min(1, hypot(headVel.x, headVel.y) / 700) * 2.8 * mid * sloshAmp
            let prev = slosh[i]
            let prv = prevSlosh[i]
            var v = (prev - prv) * GestureMath.damping(0.9, dt: dt)
            v += (drive - prev) * 16 * step
            prevSlosh[i] = prev
            slosh[i] = prev + v
            baseRadii[i] = max(params.minRadius, baseRadii[i] + slosh[i])
        }

        radii = BlobMass.rescaleToTotalArea(radii: baseRadii, length: max(chord, 1), params: params)
            .map { $0 * emergeScale }
        BlobMass.applyEndFloors(radii: &radii, emerge: emergeScale, params: params)

        for _ in 0..<5 {
            spine[0] = anchor
            spine[n - 1] = head
            for i in 0..<(n - 1) {
                var a = spine[i]
                var b = spine[i + 1]
                let segDx = b.x - a.x
                let segDy = b.y - a.y
                let d = hypot(segDx, segDy)
                guard d > 0.001 else { continue }
                let diff = (d - ideal) / d
                let ox = segDx * 0.5 * diff
                let oy = segDy * 0.5 * diff
                if i == 0 {
                    b.x -= ox * 2; b.y -= oy * 2; spine[i + 1] = b
                } else if i + 1 == n - 1 {
                    a.x += ox * 2; a.y += oy * 2; spine[i] = a
                } else {
                    a.x += ox; a.y += oy; b.x -= ox; b.y -= oy
                    spine[i] = a; spine[i + 1] = b
                }
            }
        }
        spine[0] = anchor
        spine[n - 1] = head
        prevSpine[0] = anchor
        prevSpine[n - 1] = head
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        guard emerge > 0.01 else { return }

        tintColor = cfg.tintColor
        if spine.count != particleCount || radii.count != particleCount {
            resetSpineStraight()
        }

        if reducedMotion || metal == nil {
            drawFallbackFlat(ctx)
            return
        }
        _ = drawOptical(ctx)
    }

    @discardableResult
    private func drawOptical(_ ctx: CGContext) -> Bool {
        guard let metal, let bbox = massBounds() else { return false }

        let scale = min(2.0, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        let anchor = lockedPin

        // LOCKED mapping: AppKit world → bbox-local (y-up). No inversion.
        func local(_ p: CGPoint) -> SIMD2<Float> {
            SIMD2(Float(p.x - bbox.minX), Float(p.y - bbox.minY))
        }

        var circles: [ObsidianBlobMetal.Circle] = []
        circles.reserveCapacity(spine.count + 2)
        for i in spine.indices {
            circles.append(.init(center: local(spine[i]), radius: Float(radii[i])))
        }
        let params = mass
        let pinR = max(radii.first ?? 20, params.restRadius * params.pinMinFraction * 0.75 * emerge)
        let headR = max(radii.last ?? 14, params.restRadius * params.headMinFraction * 0.85 * emerge)
        circles.append(.init(center: local(anchor), radius: Float(pinR)))
        circles.append(.init(center: local(head), radius: Float(headR)))

        let c = (tintColor.usingColorSpace(.deviceRGB) ?? tintColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)

        let cool = CGFloat(cfg.coolTint)
        let glow = SIMD3<Float>(
            Float(0.55 + 0.2 * (1 - cool)),
            Float(0.65 + 0.15 * cool),
            Float(0.85 + 0.15 * cool)
        )
        let absorb = SIMD3<Float>(
            Float(0.9 + cfg.absorption * 0.7),
            Float(0.7 + cfg.absorption * 0.55),
            Float(0.45 + cfg.absorption * 0.35)
        )

        let look = ObsidianBlobMetal.Look(
            lightDir: SIMD2(Float(smoothLight.x), Float(smoothLight.y)),
            time: Float(time),
            shininess: Float(max(0.55, cfg.shininess)),
            fresnel: Float(max(0.5, cfg.fresnel)),
            transmission: Float(max(0.45, cfg.transmission)),
            opacity: Float(cfg.glassOpacity),
            edgeSoft: Float(0.08 + (1 - cfg.gooThreshold) * 0.1),
            baseColor: SIMD3(Float(max(r, 0.04)), Float(max(g, 0.045)), Float(max(b, 0.06))),
            absorb: absorb,
            glow: glow,
            facet: Float(cfg.facetAmount),
            facetSize: Float(cfg.facetSize)
        )

        guard let image = metal.render(
            size: bbox.size,
            scale: scale,
            circles: circles,
            spineCount: spine.count,
            fillet: params.restRadius * 0.22,
            look: look
        ) else {
            return false
        }
        // Only composite the blob image; empty texels were scrubbed to alpha 0.
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.draw(image, in: bbox)
        ctx.restoreGState()
        return true
    }

    private func massBounds() -> CGRect? {
        guard !spine.isEmpty, spine.count == radii.count else { return nil }
        let pad: CGFloat = 32
        let anchor = lockedPin
        var minX = min(anchor.x, head.x)
        var maxX = max(anchor.x, head.x)
        var minY = min(anchor.y, head.y)
        var maxY = max(anchor.y, head.y)
        for i in spine.indices {
            let r = radii[i]
            let p = spine[i]
            minX = min(minX, p.x - r)
            maxX = max(maxX, p.x + r)
            minY = min(minY, p.y - r)
            maxY = max(maxY, p.y + r)
        }
        let rect = CGRect(x: minX - pad, y: minY - pad, width: (maxX - minX) + pad * 2, height: (maxY - minY) + pad * 2)
        return rect.intersection(bounds.insetBy(dx: -pad, dy: -pad))
    }

    private func drawFallbackFlat(_ ctx: CGContext) {
        ctx.setFillColor(tintColor.withAlphaComponent(0.92).cgColor)
        for i in spine.indices {
            let r = radii[i]
            let p = spine[i]
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
