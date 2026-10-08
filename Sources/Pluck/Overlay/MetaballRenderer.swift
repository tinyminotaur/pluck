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
    /// Smoothed head: the liquid's leading edge. It is pulled toward `pointerTarget` like iron toward a
    /// magnet (see `stepMagnet`), so it trails fast moves and sloshes into place. Set by the overlay's
    /// `head` only while reduced motion is on (no physics).
    var head: CGPoint = .zero
    /// The raw cursor position the head is attracted to.
    var pointerTarget: CGPoint = .zero
    var emerge: CGFloat = 0
    var bloom: CGFloat = 0
    var captured: CompassRole? {
        didSet {
            guard captured != oldValue, captured != nil else { return }
            latchPulse = 1   // little "click" when a direction latches
        }
    }
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

    private static let fixedStep: CGFloat = 1.0 / 240.0
    private static let maxSubsteps = 4
    /// Soft ceiling (px/s) on the pointer speed fed into whip / slosh / lighting.
    private static let maxDriveSpeed: CGFloat = 3500
    private var accumulator: CGFloat = 0
    private var frameStartHead: CGPoint = .zero
    private var frameStartTarget: CGPoint = .zero
    private var magVel: CGPoint = .zero

    private var recoiling = false
    private var recoilSettled = false
    private var recoilElapsed: CGFloat = 0
    private var recoilVel: CGPoint = .zero
    private var recoilPulse: CGFloat = 0
    private var recoilDone: (() -> Void)?

    // Direction UI
    private var gestureTime: CGFloat = 0
    private var labelAlpha: CGFloat = 0
    private var latchPulse: CGFloat = 0
    private var armedPos: [CompassRole: CGFloat] = [:]
    private var armedVel: [CompassRole: CGFloat] = [:]
    /// 0…1 "stir" energy: builds while the pointer circles the pin, decays slowly after.
    private var stir: CGFloat = 0
    private var commitRole: CompassRole?
    private var commitFlash: CGFloat = 0

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
        frameStartHead = head
        pointerTarget = head
        frameStartTarget = head
        magVel = .zero
        accumulator = 0
        recoiling = false
        recoilDone = nil
        recoilPulse = 0
        gestureTime = 0
        labelAlpha = 0
        latchPulse = 0
        armedPos = [:]
        armedVel = [:]
        commitRole = nil
        commitFlash = 0
        stir = 0
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
        recoiling = false
        recoilDone = nil
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
        CursorGuard.shared.checkIn()
        let now = CACurrentMediaTime()
        var dt = now - lastTick
        lastTick = now
        dt = min(1.0 / 30.0, max(1.0 / 240.0, dt))
        time += CGFloat(dt)
        tintColor = cfg.tintColor
        tickFixed(frameDt: CGFloat(dt))
        updateCompassUI(dt: CGFloat(dt))
        needsDisplay = true
    }

    /// Label visibility gate + per-label "pop" springs. Labels stay out of the way of fast
    /// flicks (experts mark ahead without ever seeing them) and fade in once you linger.
    private func updateCompassUI(dt: CGFloat) {
        gestureTime += dt
        latchPulse = max(0, latchPulse - dt / 0.35)
        commitFlash = max(0, commitFlash - dt / 0.32)

        let speed = hypot(headVel.x, headVel.y)
        let lingering = gestureTime > 0.22 || (gestureTime > 0.10 && speed < 150)
        var target: CGFloat = (bloom > 0.05 && lingering && !recoiling) ? 1 : 0
        if speed > 1600 { target *= 0.25 }
        labelAlpha += (target - labelAlpha) * GestureMath.smoothingAlpha(retain: 0.78, dt: dt)

        // Armed label: springy overshoot toward 1, others relax to 0.
        let omega = RecoilSpring.omega(period: 0.20)
        let zeta: CGFloat = 0.42
        for role in CompassRole.allCases {
            let goal: CGFloat = (captured == role) ? 1 : 0
            var x = CGPoint(x: (armedPos[role] ?? 0) - goal, y: 0)
            var v = CGPoint(x: armedVel[role] ?? 0, y: 0)
            var left = dt
            while left > 0 {
                let h = min(left, Self.fixedStep)
                RecoilSpring.step(x: &x, v: &v, omega: omega, zeta: zeta, h: h)
                left -= h
            }
            armedPos[role] = goal + x.x
            armedVel[role] = v.x
        }
    }

    /// Fixed-timestep accumulator: physics always advances in fixed (`fixedStep`) so damping,
    /// spring feel and whip are identical on 60 Hz, 120 Hz and jittery frame pacing.
    private func tickFixed(frameDt: CGFloat) {
        let h = Self.fixedStep
        updateHeadMotion(dt: frameDt)

        accumulator += frameDt
        var steps = Int(accumulator / h)
        if steps > Self.maxSubsteps {
            steps = Self.maxSubsteps
            accumulator = 0
        } else {
            accumulator -= CGFloat(steps) * h
        }
        guard steps > 0 else { return }

        if recoiling {
            integrateRecoil(steps: steps, h: h, frameDt: frameDt)
            // Recoil drives the head directly; keep the magnet state continuous for the next grab.
            let start = frameStartHead
            let end = head
            for k in 1...steps {
                let t = CGFloat(k) / CGFloat(steps)
                stepPhysics(dt: h, head: lerp(start, end, t))
            }
            frameStartHead = end
            frameStartTarget = pointerTarget
            magVel = recoilVel
            finishRecoilIfSettled(frameDt: frameDt)
            return
        }
        let startTarget = frameStartTarget
        let endTarget = pointerTarget
        for k in 1...steps {
            let t = CGFloat(k) / CGFloat(steps)
            stepMagnet(target: lerp(startTarget, endTarget, t), h: h)
            stepPhysics(dt: h, head: head)
        }
        frameStartTarget = endTarget
        frameStartHead = head
    }

    /// The head is a heavy liquid mass attracted to the cursor like iron to a magnet: pulled by a spring
    /// that gets stiffer as the gap closes (`MagnetPull`), so it trails fast moves and sloshes into place.
    /// A faint wander keeps it from ever being perfectly still, as water never is.
    private func stepMagnet(target: CGPoint, h: CGFloat) {
        let idle = CGFloat(cfg.idleLife)
        let wander = CGPoint(
            x: 1.3 * idle * sin(time * 1.17 + 0.6),
            y: 1.3 * idle * cos(time * 0.93)
        )
        let tgt = CGPoint(x: target.x + wander.x, y: target.y + wander.y)
        var x = CGPoint(x: head.x - tgt.x, y: head.y - tgt.y)
        let omega = MagnetPull.omega(
            distance: hypot(x.x, x.y),
            base: CGFloat(cfg.magnetPull),
            stick: CGFloat(cfg.magnetStick)
        )
        var v = magVel
        RecoilSpring.step(x: &x, v: &v, omega: omega, zeta: CGFloat(cfg.magnetWeight), h: h)
        magVel = v
        head = CGPoint(x: tgt.x + x.x, y: tgt.y + x.y)
    }

    // MARK: Recoil (the satisfying snap-back on release)

    /// Release: the head springs back to the pin with overshoot while the body sloshes, then
    /// the blob melts away. `done` fires once, after the blob has settled.
    func beginRecoil(role: CompassRole? = nil, done: @escaping () -> Void) {
        guard !reducedMotion, physicsRunning, !recoiling else { done(); return }
        commitRole = role
        commitFlash = role == nil ? 0 : 1
        recoiling = true
        recoilElapsed = 0
        recoilSettled = false
        recoilDone = done
        // Keep a fraction of the release momentum so a flick overshoots past the pin.
        let fling = CGFloat(cfg.flingMomentum)
        recoilVel = CGPoint(x: headVel.x * fling, y: headVel.y * fling)
        recoilPulse = 1
    }

    private func integrateRecoil(steps: Int, h: CGFloat, frameDt: CGFloat) {
        // Underdamped spring toward the pin. Bounce knob: 0 = tight, 1 = very wobbly.
        let bounce = CGFloat(cfg.recoilBounce)
        let zeta = RecoilSpring.zeta(bounce: bounce)
        let omega = RecoilSpring.omega(period: 0.30)
        var x = CGPoint(x: head.x - lockedPin.x, y: head.y - lockedPin.y)
        var v = recoilVel
        for _ in 0..<steps {
            RecoilSpring.step(x: &x, v: &v, omega: omega, zeta: zeta, h: h)
        }
        recoilVel = v
        head = CGPoint(x: lockedPin.x + x.x, y: lockedPin.y + x.y)
        recoilElapsed += frameDt
        recoilPulse = max(0, recoilPulse - frameDt / 0.45)
        let off = hypot(x.x, x.y)
        let speed = hypot(v.x, v.y)
        if recoilElapsed > 0.22, off < 2, speed < 40 { recoilSettled = true }
        if recoilElapsed > 0.8 { recoilSettled = true }
    }

    private func finishRecoilIfSettled(frameDt: CGFloat) {
        guard recoilSettled else { return }
        emerge = max(0, emerge - frameDt / 0.14)
        if emerge <= 0.001 {
            emerge = 0
            recoiling = false
            let done = recoilDone
            recoilDone = nil
            done?()
        }
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

    /// Once per display frame: head velocity (soft-clamped) and the light that follows motion.
    private func updateHeadMotion(dt: CGFloat) {
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

        // Soft-limit the speed that drives whip and slosh so one coalesced mouse event
        // (or a 5000 px/s flick) can't blow the chain up.
        let rawSpeed = hypot(headVel.x, headVel.y)
        if rawSpeed > 1 {
            let limited = Self.maxDriveSpeed * tanh(rawSpeed / Self.maxDriveSpeed)
            headVel = CGPoint(x: headVel.x * limited / rawSpeed, y: headVel.y * limited / rawSpeed)
        }

        // Stir: angular speed of the head around the pin. Circling builds energy that outlasts
        // the motion, so the liquid keeps sloshing after you stop.
        let rx = head.x - lockedPin.x
        let ry = head.y - lockedPin.y
        let r2 = rx * rx + ry * ry
        var stirTarget: CGFloat = 0
        if r2 > 1600 {
            let omega = (rx * headVel.y - ry * headVel.x) / r2   // rad/s
            stirTarget = min(1, abs(omega) / 7)
        }
        let stirRetain: CGFloat = stirTarget > stir ? 0.90 : 0.985
        stir += (stirTarget - stir) * GestureMath.smoothingAlpha(retain: stirRetain, dt: dt)

        // One fixed environment: the light does not swing with the cursor. Only the liquid's own
        // surface changes what it reflects.
        smoothLight = CGPoint(x: -0.4, y: 0.75)
    }

    /// One fixed physics step. `head` is the (possibly interpolated) head position for this step.
    private func stepPhysics(dt: CGFloat, head: CGPoint) {
        let n = particleCount
        let params = mass
        let anchor = lockedPin
        if spine.count != n { resetSpineStraight(); return }

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
        let sloshAmp = CGFloat(cfg.sloshAmount) * (1 + 1.1 * stir)
        // A little slack lets the liquid bow, sag and whip instead of staying a rigid line.
        let speedNow = hypot(headVel.x, headVel.y)
        let slack = 1 + 0.03 + 0.09 * min(1, speedNow / 900) * min(1.2, whip)
        let ideal = max(0.5, chord / CGFloat(n - 1) * slack)
        let idle = CGFloat(cfg.idleLife)
        let curSpeed = speedNow
        let gravityK = CGFloat(cfg.gravity)
        let gravityAccel = 90 * gravityK
        let yMean = spine.reduce(0) { $0 + $1.y } / CGFloat(max(1, n))

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
            // Gravity: the liquid hangs under its own weight (view space is y-up, so down is -y). The
            // neck spring balances it, which gives a soft catenary sag that is deepest mid-span.
            vel.y -= gravityAccel * step
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
            // Breathing while held still, so the blob always feels alive under your fingers.
            let stillness: CGFloat = 1 - min(1, curSpeed / 500)
            let breathing: CGFloat = sin(time * 2.3 + t * 4.0) * 1.1 * idle * (0.35 + 0.65 * mid) * stillness
            let drive = (-tanSpeed * 0.0045 * (t - 0.3) + latSpeed * 0.004 * mid) * sloshAmp
                + sin(time * 8.5 + t * 5.5) * min(1, hypot(headVel.x, headVel.y) / 700) * 2.8 * mid * sloshAmp
                + breathing
            let prev = slosh[i]
            let prv = prevSlosh[i]
            var v = (prev - prv) * GestureMath.damping(0.9, dt: dt)
            v += (drive - prev) * 16 * step
            prevSlosh[i] = prev
            slosh[i] = prev + v
            // Mass pools toward the lowest part of the tether (a drip forming under gravity).
            let pool = max(-3.5, min(3.5, (yMean - spine[i].y) * 0.05)) * gravityK * (0.4 + 0.6 * mid)
            baseRadii[i] = max(params.minRadius, baseRadii[i] + slosh[i] + pool)
        }

        radii = BlobMass.rescaleToTotalArea(radii: baseRadii, length: max(chord, 1), params: params)
            .map { $0 * emergeScale }
        BlobMass.applyEndFloors(radii: &radii, emerge: emergeScale, params: params)

        for _ in 0..<3 {
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
            drawCompass(ctx)
            return
        }
        _ = drawOptical(ctx)
        drawCompass(ctx)
    }

    // MARK: Direction labels

    /// Cancel ring + one pill per available role. Slices are fixed (see `GestureMath`); only the
    /// labels move, to stay on screen near display edges.
    private func drawCompass(_ ctx: CGContext) {
        let committing = recoiling && commitRole != nil
        let alpha = committing ? commitFlash : (reducedMotion ? bloom : labelAlpha)
        guard alpha > 0.01, !items.isEmpty else { return }
        let c = lockedPin

        // Selected direction: a soft arc sweeping the armed slice.
        if !committing, let role = captured, !reducedMotion {
            let pop = max(0, min(1.2, armedPos[role] ?? 0))
            let d = LabelLayout.direction(of: role)
            let mid = atan2(d.y, d.x) * 180 / .pi
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: GestureMath.deadZone + 26, startAngle: mid - 38, endAngle: mid + 38)
            arc.lineWidth = 3
            arc.lineCapStyle = .round
            NSColor(calibratedRed: 0.8, green: 0.9, blue: 1.0, alpha: 0.5 * alpha * pop).setStroke()
            arc.stroke()
        }

        // Cancel zone: release inside the ring cancels.
        let ringR = GestureMath.deadZone
        let ring = NSBezierPath(ovalIn: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2))
        ring.lineWidth = 1
        ring.setLineDash([3, 4], count: 2, phase: 0)
        let inside = captured == nil
        NSColor.white.withAlphaComponent(alpha * (inside ? 0.30 : 0.10)).setStroke()
        ring.stroke()

        let anyArmed = captured != nil
        for item in items {
            // On commit only the chosen label stays: it swells and fades like a confirmation.
            if committing, item.role != commitRole { continue }
            let armed = committing || captured == item.role
            var pop = reducedMotion ? (armed ? 1 : 0) : (armedPos[item.role] ?? 0)
            if committing { pop = 1 + 1.3 * (1 - commitFlash) }
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: armed ? NSColor(calibratedWhite: 0.06, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1),
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: armed ? NSColor(calibratedWhite: 0.2, alpha: 1) : NSColor(calibratedWhite: 0.75, alpha: 1),
            ]
            let title = NSAttributedString(string: item.title, attributes: titleAttrs)
            let sub = item.subtitle.map { NSAttributedString(string: $0, attributes: subAttrs) }
            let tSize = title.size()
            let sSize = sub?.size() ?? .zero
            let glyphColor = armed ? NSColor(calibratedWhite: 0.08, alpha: 1) : NSColor(calibratedWhite: 0.95, alpha: 1)
            let glyph = Self.glyph(for: item.role, color: glyphColor)
            let glyphW: CGFloat = glyph == nil ? 0 : 20
            let size = CGSize(
                width: max(tSize.width, sSize.width) + 26 + glyphW,
                height: sub == nil ? 28 : 28 + sSize.height + 2
            )
            let textShift = glyphW / 2

            let scale = 1 + 0.16 * pop
            let dist = LabelLayout.distance + 7 * max(0, pop)
            let raw = LabelLayout.center(pin: c, role: item.role, distance: dist)
            let scaled = CGSize(width: size.width * scale, height: size.height * scale)
            let center = LabelLayout.clamped(center: raw, size: scaled, in: bounds)

            ctx.saveGState()
            ctx.setAlpha(alpha * ((anyArmed && !armed && !committing) ? 0.55 : 1))
            ctx.translateBy(x: center.x, y: center.y)
            ctx.scaleBy(x: scale, y: scale)

            let pill = NSBezierPath(
                roundedRect: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
                xRadius: size.height / 2, yRadius: size.height / 2
            )
            (armed ? NSColor(calibratedRed: 0.86, green: 0.92, blue: 1.0, alpha: 0.96)
                   : NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 0.78)).setFill()
            pill.fill()
            NSColor.white.withAlphaComponent(armed ? 0.0 : 0.20).setStroke()
            pill.lineWidth = 1
            pill.stroke()

            if let glyph {
                glyph.draw(in: CGRect(x: -size.width / 2 + 12, y: -7, width: 14, height: 14))
            }
            if let sub {
                title.draw(at: CGPoint(x: textShift - tSize.width / 2, y: -tSize.height / 2 + sSize.height / 2 + 1))
                sub.draw(at: CGPoint(x: textShift - sSize.width / 2, y: -sSize.height / 2 - tSize.height / 2 + 2))
            } else {
                title.draw(at: CGPoint(x: textShift - tSize.width / 2, y: -tSize.height / 2))
            }
            ctx.restoreGState()
        }
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
            * (1 + 0.22 * latchPulse)
        circles.append(.init(center: local(anchor), radius: Float(pinR)))
        circles.append(.init(center: local(head), radius: Float(headR)))

        let c = (tintColor.usingColorSpace(.deviceRGB) ?? tintColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)

        let glow = ObsidianPalette.glow(warmth: Float(cfg.coolTint))
        let absorb = ObsidianPalette.absorb(depth: Float(cfg.absorption))

        // Liquid at rest, obsidian under tension: facets sharpen as the tether stretches and
        // flash on release (recoil pulse).
        let chordNow = hypot(head.x - anchor.x, head.y - anchor.y)
        let stretchT = smoothstep01((chordNow - 40) / 200)
        let cry = CGFloat(cfg.crystallize)
        let tension: CGFloat = (1 - cry) + cry * (0.3 + 0.9 * stretchT)
        var facetEff: CGFloat = CGFloat(cfg.facetAmount) * tension
        facetEff += 0.35 * recoilPulse
        facetEff += 0.25 * latchPulse
        facetEff += 0.15 * stir

        let look = ObsidianBlobMetal.Look(
            lightDir: SIMD2(Float(smoothLight.x), Float(smoothLight.y)),
            time: Float(time),
            shininess: Float(max(0.55, cfg.shininess)),
            fresnel: Float(max(0.5, cfg.fresnel)),
            transmission: Float(max(0.45, cfg.transmission)),
            opacity: Float(cfg.glassOpacity * (cfg.meetingMode ? 0.8 : 1)),
            edgeSoft: Float(0.08 + (1 - cfg.gooThreshold) * 0.1),
            baseColor: SIMD3(Float(max(r, 0.04)), Float(max(g, 0.045)), Float(max(b, 0.06))),
            absorb: absorb,
            glow: glow,
            facet: Float(min(1, facetEff)),
            facetSize: Float(cfg.facetSize),
            ember: Float(cfg.ember * (cfg.meetingMode ? 0.5 : 1))
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

    /// SF Symbol per role, tinted with a palette colour. Nil if the symbol is unavailable.
    private static func glyph(for role: CompassRole, color: NSColor) -> NSImage? {
        let name: String
        switch role {
        case .north: name = "arrow.down.to.line"      // keep / save
        case .east: name = "arrow.right"              // go
        case .south: name = "square.and.arrow.up"     // give / share
        case .west: name = "questionmark"             // ask
        }
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: role.accessibilityLabel)?
            .withSymbolConfiguration(config)
    }

    private func smoothstep01(_ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
