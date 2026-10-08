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
    /// Up to ~67 ms of physics per frame, so a slow frame never runs the liquid in slow motion.
    private static let maxSubsteps = 16
    /// Soft ceiling (px/s) on the pointer speed fed into whip / slosh / lighting.
    private static let maxDriveSpeed: CGFloat = 3500
    private var accumulator: CGFloat = 0
    private var frameStartHead: CGPoint = .zero
    private var frameStartTarget: CGPoint = .zero
    private var magVel: CGPoint = .zero
    // Organic mass: lopsided lump clusters at the pin and head, seeded per gesture, that jiggle with
    // inertia and gravity. Plus slow swelling along the tether. Nothing is ever a perfect disc.
    private var pinLumps: [BlobLumpSpec] = []
    private var headLumps: [BlobLumpSpec] = []
    private var pinJig: [CGPoint] = []
    private var pinJigVel: [CGPoint] = []
    private var headJig: [CGPoint] = []
    private var headJigVel: [CGPoint] = []
    private var swellPhase: [CGFloat] = []
    private var prevVelForAcc: CGPoint = .zero
    private var headAcc: CGPoint = .zero

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

    func startPhysics(driveManually: Bool = false) {
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
        seedOrganicShape()
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
        if driveManually { return }   // headless report: the caller steps the simulation

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

    /// Headless stepping for `Pluck --sim-report`: one display frame of the real simulation.
    func debugAdvance(dt: CGFloat) {
        time += dt
        tickFixed(frameDt: dt)
        updateCompassUI(dt: dt)
    }

    /// Times one real optical draw (Metal render + CPU readback + composite) in milliseconds, for `--sim-report`.
    func debugRenderMillis(into ctx: CGContext) -> Double {
        let t0 = CACurrentMediaTime()
        _ = drawOptical(ctx)
        return (CACurrentMediaTime() - t0) * 1000
    }

    /// Poses the view for `--render-compass`: runs the real physics until it settles with the pointer pulled to
    /// `pointer`, optionally with a direction armed, so the integrated labels can be rendered headlessly.
    func debugPose(pin: CGPoint, pointer: CGPoint, armed: CompassRole?, items: [CompassItem], seconds: CGFloat) {
        self.pin = pin
        head = pin
        pointerTarget = pin
        emerge = 1
        bloom = 1
        self.items = items
        startPhysics(driveManually: true)
        var t: CGFloat = 0
        let dt: CGFloat = 1.0 / 120
        while t < seconds {
            let k = min(1, t / 0.3)
            pointerTarget = CGPoint(x: pin.x + (pointer.x - pin.x) * k, y: pin.y + (pointer.y - pin.y) * k)
            if t > 0.4 { captured = armed }
            emerge = 1
            bloom = 1
            debugAdvance(dt: dt)
            t += dt
        }
    }

    /// Read-only view of the simulation for `--sim-report`.
    var debugState: (head: CGPoint, spine: [CGPoint], radii: [CGFloat]) { (head, spine, radii) }

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
                stepJiggle(h)
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
            stepJiggle(h)
        }
        frameStartTarget = endTarget
        frameStartHead = head
    }

    /// New random shape for each gesture, and a random start in the time-driven noise so no two
    /// gestures look alike.
    private func seedOrganicShape() {
        let seed = UInt64.random(in: 0...UInt64.max)
        pinLumps = BlobLumps.specs(seed: seed, count: 4)
        headLumps = BlobLumps.specs(seed: seed ^ 0xA5A5_5A5A_1234_4321, count: 2)
        pinJig = Array(repeating: .zero, count: pinLumps.count)
        pinJigVel = pinJig
        headJig = Array(repeating: .zero, count: headLumps.count)
        headJigVel = headJig
        swellPhase = (0..<32).map { _ in CGFloat.random(in: 0..<(2 * .pi)) }
        headAcc = .zero
        prevVelForAcc = .zero
        time = CGFloat.random(in: 0..<200)
    }

    /// Each lump is a little spring-mass: it lurches against head acceleration (inertia) and sinks under
    /// gravity, then wobbles back at its own pace. Different lumps wobble differently, so the mass
    /// moves like jelly instead of rotating rigidly.
    private func stepJiggle(_ h: CGFloat) {
        let g = CGFloat(cfg.gravity)
        let drive = CGPoint(
            x: max(-9, min(9, -headAcc.x * 0.0035)),
            y: max(-9, min(9, -headAcc.y * 0.0035)) - 2.5 * g
        )
        func advance(_ specs: [BlobLumpSpec], _ off: inout [CGPoint], _ vel: inout [CGPoint]) {
            for i in specs.indices {
                var x = CGPoint(x: off[i].x - drive.x * specs[i].size, y: off[i].y - drive.y * specs[i].size)
                var v = vel[i]
                RecoilSpring.step(x: &x, v: &v, omega: specs[i].omega, zeta: specs[i].zeta, h: h)
                vel[i] = v
                off[i] = CGPoint(x: x.x + drive.x * specs[i].size, y: x.y + drive.y * specs[i].size)
            }
        }
        advance(pinLumps, &pinJig, &pinJigVel)
        advance(headLumps, &headJig, &headJigVel)
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

        // Smoothed head acceleration: the lumps lurch against it like jelly.
        let dtA = max(dt, 1.0 / 240.0)
        let rawAcc = CGPoint(x: (headVel.x - prevVelForAcc.x) / dtA, y: (headVel.y - prevVelForAcc.y) / dtA)
        let accAlpha = GestureMath.smoothingAlpha(retain: 0.7, dt: dt)
        headAcc = CGPoint(
            x: max(-20000, min(20000, headAcc.x + (rawAcc.x - headAcc.x) * accAlpha)),
            y: max(-20000, min(20000, headAcc.y + (rawAcc.y - headAcc.y) * accAlpha))
        )
        prevVelForAcc = headVel

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
            // Natural meander: a slow lateral S-curve that never stops, so the strand is a flowing thread, not a
            // ruled line. Zero at both ends, scaled to the length.
            let ph0 = swellPhase.count > 30 ? swellPhase[30] : 0
            let ph1 = swellPhase.count > 31 ? swellPhase[31] : 0
            let swayAmp = min(9, 0.02 * chord + 1.5)
            let sway = (0.6 * sin(time * 0.9 + t * 4.1 + ph0) + 0.4 * sin(time * 1.7 + t * 7.3 + ph1)) * swayAmp * mid
            let target = CGPoint(x: lerp(anchor, head, t).x + nx * sway, y: lerp(anchor, head, t).y + ny * sway)
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
            // Slow, out-of-step swelling so the thickness is never even along the tether.
            let ph = i < swellPhase.count ? swellPhase[i] : 0
            let swell = 1 + 0.10 * sin(time * 0.55 + ph) + 0.06 * sin(time * 1.05 + ph * 1.9)
            baseRadii[i] = max(params.minRadius, (baseRadii[i] + slosh[i] + pool) * swell)
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
    /// The armed action: the head of the liquid swells into a bud that carries the label.
    private struct Bud {
        var item: CompassItem
        var center: CGPoint
        var radius: CGFloat
        var pop: CGFloat
        var armed: Bool
        var glow: CGFloat
    }

    private static let budBaseRadius: CGFloat = 30

    /// Nothing shows at rest. Once you move into a direction and it latches, that one action grows out of the
    /// head of the liquid (glyph and name inside it, lit by the theme). It stays quiet during very fast flicks,
    /// so expert marking never sees labels, and on commit the chosen one swells like a confirmation.
    private func budGeometry(pinR: CGFloat) -> [Bud] {
        let committing = recoiling && commitRole != nil
        let role: CompassRole? = committing ? commitRole : captured
        guard let role, let item = items.first(where: { $0.role == role }) else { return [] }
        var pop = reducedMotion ? 1 : (armedPos[role] ?? 0)
        if committing { pop = 1 + 1.3 * (1 - commitFlash) }
        let speed = hypot(headVel.x, headVel.y)
        let gate = committing ? 1 : 1 - smoothstep01((speed - 1300) / 900)
        let appear = min(1, max(0, pop)) * gate
        guard appear > 0.02 else { return [] }
        let base = Self.budBaseRadius * (cfg.meetingMode ? 0.8 : 1)
        let ease = appear * appear * (3 - 2 * appear)
        let r = base * ease * (1 + 0.18 * max(0, pop - 1))
        let glow = committing ? 1 : 0.35 + 0.65 * appear
        return [Bud(item: item, center: head, radius: r, pop: pop, armed: true, glow: glow)]
    }

    /// The cancel ring (only while a direction is armed), then the armed action's label drawn inside the head.
    /// Text is composited with a screen blend, tinted by the theme, over a faint dark inset, so it reads as light
    /// held inside the glass rather than a sticker.
    private func drawCompass(_ ctx: CGContext) {
        let committing = recoiling && commitRole != nil
        guard !items.isEmpty, captured != nil || committing else { return }
        let theme = cfg.theme
        let tint = NSColor(calibratedRed: CGFloat(theme.a.r), green: CGFloat(theme.a.g), blue: CGFloat(theme.a.b), alpha: 1)

        if !committing {
            let c = lockedPin
            let ringR = GestureMath.deadZone
            let ring = NSBezierPath(ovalIn: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2))
            ring.lineWidth = 1
            ring.setLineDash([3, 4], count: 2, phase: 0)
            tint.blended(withFraction: 0.5, of: .white)?.withAlphaComponent(0.16).setStroke()
            ring.stroke()
        }

        let pinR = max(radii.first ?? 20, mass.restRadius * mass.pinMinFraction * 0.75 * emerge)
        for bud in budGeometry(pinR: pinR) {
            let fit = bud.radius / (Self.budBaseRadius * (cfg.meetingMode ? 0.8 : 1))
            let textFade = smoothstep01((fit - 0.4) / 0.5)   // text appears once the bud is big enough to hold it
            guard textFade > 0.01 else { continue }
            let light = NSColor.white
            let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            let attrs: (NSColor) -> [NSAttributedString.Key: Any] = { [.font: titleFont, .foregroundColor: $0] }
            let title = NSAttributedString(string: bud.item.title, attributes: attrs(light))
            let shadow = NSAttributedString(string: bud.item.title, attributes: attrs(NSColor(calibratedWhite: 0, alpha: 0.55)))
            let tSize = title.size()
            let glyph = Self.glyph(for: bud.item.role, color: light)

            ctx.saveGState()
            ctx.translateBy(x: bud.center.x, y: bud.center.y)
            let s = min(1.25, max(0.5, fit))
            ctx.scaleBy(x: s, y: s)
            let hasGlyph = glyph != nil
            let top = ((hasGlyph ? 15 : 0) + tSize.height) / 2
            // Faint inset shadow first (normal blend), then the light itself (screen blend).
            ctx.setAlpha(textFade * 0.9)
            shadow.draw(at: CGPoint(x: -tSize.width / 2, y: top - (hasGlyph ? 15 : 0) - tSize.height - 0.8))
            ctx.setBlendMode(.screen)
            ctx.setAlpha(textFade)
            if let glyph { glyph.draw(in: CGRect(x: -7, y: top - 14, width: 14, height: 14)) }
            title.draw(at: CGPoint(x: -tSize.width / 2, y: top - (hasGlyph ? 15 : 0) - tSize.height))
            ctx.restoreGState()
        }
    }

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
        // Smooth, natural strand: a spline through the physics particles with a softened taper, instead of
        // straight tapered segments joined at angles.
        let sub = spine.count <= 20 ? 3 : 2
        let strand = StrandSmoothing.resample(
            points: spine,
            radii: StrandSmoothing.smoothRadii(radii, passes: 2),
            subdivisions: sub
        )
        for i in strand.points.indices {
            circles.append(.init(center: local(strand.points[i]), radius: Float(strand.radii[i])))
        }
        let strandCount = strand.points.count
        let params = mass
        let pinR = max(radii.first ?? 20, params.restRadius * params.pinMinFraction * 0.75 * emerge)
        let headR = max(radii.last ?? 14, params.restRadius * params.headMinFraction * 0.85 * emerge)
            * (1 + 0.22 * latchPulse)
        // Lopsided lump clusters (before pin/head so the last two circles stay pin and head).
        if circles.count + pinLumps.count + headLumps.count + 2 <= ObsidianBlobMetal.maxCircles {
            for (i, s) in pinLumps.enumerated() {
                let l = BlobLumps.place(s, center: anchor, baseRadius: pinR, time: time, jiggle: pinJig[i])
                circles.append(.init(center: local(l.center), radius: Float(l.radius)))
            }
            for (i, s) in headLumps.enumerated() {
                let l = BlobLumps.place(s, center: head, baseRadius: headR, time: time, jiggle: headJig[i])
                circles.append(.init(center: local(l.center), radius: Float(l.radius)))
            }
        }
        // Action buds: each direction is a liquid bud on the pin, big enough to hold its label.
        for bud in budGeometry(pinR: pinR) where circles.count < ObsidianBlobMetal.maxCircles - 2 {
            circles.append(.init(center: local(bud.center), radius: Float(bud.radius), emphasis: Float(bud.glow)))
        }
        circles.append(.init(center: local(anchor), radius: Float(pinR)))
        circles.append(.init(center: local(head), radius: Float(headR)))

        let theme = cfg.theme
        let absorb = SIMD3<Float>(theme.absorb.r, theme.absorb.g, theme.absorb.b) * Float(cfg.absorption / 0.75)

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
            shininess: Float(max(0.3, cfg.shininess)),
            fresnel: Float(max(0.3, cfg.fresnel)),
            transmission: Float(max(0.1, cfg.transmission)),
            opacity: Float(cfg.glassOpacity * (cfg.meetingMode ? 0.8 : 1)),
            edgeSoft: Float(0.08 + (1 - cfg.gooThreshold) * 0.1),
            baseColor: SIMD3(theme.body.r, theme.body.g, theme.body.b),
            absorb: absorb,
            glow: SIMD3(theme.a.r, theme.a.g, theme.a.b),
            facet: cfg.facetsEnabled ? Float(min(1, facetEff)) : 0,
            facetSize: Float(cfg.facetSize),
            ember: Float(Double(theme.ember) * cfg.ember * (cfg.meetingMode ? 0.5 : 1)),
            themeA: SIMD4(theme.a.r, theme.a.g, theme.a.b, theme.sheen),
            themeB: SIMD4(theme.b.r, theme.b.g, theme.b.b, theme.rim),
            themeC: SIMD4(theme.c.r, theme.c.g, theme.c.b, 0),
            gradient: SIMD3(theme.gradientScale, theme.gradientSpeed, theme.iridescence),
            fill: theme.fill,
            chrome: theme.chrome
        )

        guard let image = metal.render(
            size: bbox.size,
            scale: scale,
            circles: circles,
            spineCount: strandCount,
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
        // The pin lobes and the action buds bulge past the strand: include them or they render cut off.
        let pinR = max(radii.first ?? 20, mass.restRadius * mass.pinMinFraction * 0.75 * emerge)
        let pinReach = max(pinR, radii.first ?? 0) * 1.35
        minX = min(minX, anchor.x - pinReach); maxX = max(maxX, anchor.x + pinReach)
        minY = min(minY, anchor.y - pinReach); maxY = max(maxY, anchor.y + pinReach)
        for bud in budGeometry(pinR: pinR) {
            minX = min(minX, bud.center.x - bud.radius); maxX = max(maxX, bud.center.x + bud.radius)
            minY = min(minY, bud.center.y - bud.radius); maxY = max(maxY, bud.center.y + bud.radius)
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
