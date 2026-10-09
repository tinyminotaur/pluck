import AppKit
import Foundation
import PluckCore

/// Owns one active Pluck gesture: context, overlay, and commit/cancel.
@MainActor
final class PluckSession: ObservableObject {
    let engine = ChordEngine()
    let overlay = OverlayController()
    let clipboardHistory = ClipboardHistory.shared

    @Published private(set) var isActive = false
    @Published private(set) var context: GrabContext?
    @Published private(set) var capturedRole: CompassRole?
    /// Presenter mode: the armed direction, and whether the visual has been brought to life by dragging further.
    private var presenterMode = false
    private var presenterIndex: Int?
    private var presenterEngaged = false
    @Published private(set) var pin: CGPoint = .zero
    @Published private(set) var pointer: CGPoint = .zero
    @Published private(set) var emergeProgress: CGFloat = 0
    @Published private(set) var bloomProgress: CGFloat = 0

    private var animTimer: Timer?
    private var openedAt: CFTimeInterval = 0
    private var cursorHidden = false
    private var finishing = false
    private var animStart: Date?
    private var lastRing = 0

    private var reducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init() {
        engine.session = self
    }

    /// `NSEvent.mouseLocation` is AppKit space (y up); `GestureMath` / `CompassRole` use screen
    /// space (y down, north = up on screen). Flip once, here, so North really is up.
    private static func screenSpace(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: -p.y)
    }

    func startListening() {
        engine.start()
        if !FeelLab.enabled {
            clipboardHistory.start()
        }
    }

    func stopListening() {
        if isActive { cancel() }
        engine.stop()
        showCursor()
        CursorGuard.forceVisible()
        clipboardHistory.stop()
    }

    /// If the grab is near a screen edge, move the pin (and the real cursor) inward so every direction
    /// stays reachable. Warping the cursor is not an input event; Pluck still never synthesizes any.
    private static func edgeSafe(_ location: CGPoint) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }) ?? NSScreen.main
        else { return location }
        let nudged = EdgeNudge.inset(location, in: screen.frame)
        guard hypot(nudged.x - location.x, nudged.y - location.y) > 0.5,
              let primary = NSScreen.screens.first else { return location }
        // CoreGraphics global space is y-down from the primary display's top-left.
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        CGWarpMouseCursorPosition(CGPoint(x: nudged.x, y: primary.frame.maxY - nudged.y))
        return nudged
    }

    func begin(at rawLocation: CGPoint) {
        guard !isActive else { return }
        let location = Self.edgeSafe(rawLocation)
        // Fidget re-grab: cut a recoil in progress and start the new gesture straight away.
        // (Deliberately not forceReset(): that would also end the engine's new gesture.)
        if finishing {
            finishing = false
            overlay.hide()
            context = nil
            capturedRole = nil
        }
        isActive = true
        openedAt = CACurrentMediaTime()
        pin = location
        pointer = location
        capturedRole = nil
        emergeProgress = 0
        bloomProgress = 0
        lastRing = 0

        presenterMode = FeelLabConfig.shared.presenterMode
        presenterIndex = nil
        presenterEngaged = false
        // Hide the system cursor first so the blob is the only pointer you see. (Presenter mode keeps it until a visual starts.)
        if !presenterMode { hideCursor() }

        let ctx = presenterMode ? GrabContext(kind: .clipboard, nucleusTitle: "", items: [])
            : (FeelLab.enabled ? FeelLab.context : ContextResolver.resolve(at: location))
        context = ctx
        overlay.show(pin: location, context: ctx, reducedMotion: reducedMotion)
        if presenterMode { pushPresenter() }
        pushOverlay()

        if reducedMotion {
            emergeProgress = 1
            bloomProgress = 1
            pushOverlay()
        } else {
            startEmergence()
        }
    }

    func pointerMoved(to location: CGPoint) {
        guard isActive, !finishing else { return }
        CursorGuard.shared.checkIn()
        pointer = location
        if presenterMode { handlePresenterMove(); return }
        let available = context?.items.map(\.role) ?? CompassRole.allCases
        let previous = capturedRole
        capturedRole = GestureMath.capture(
            pin: Self.screenSpace(pin), pointer: Self.screenSpace(pointer),
            available: available, current: capturedRole
        )
        // Fidget detents: a tick when a direction latches, and a ratchet click every ~56 pt of stretch.
        if capturedRole != previous, let role = capturedRole {
            Haptics.tick(.alignment)
            Sounds.latch()
            // VoiceOver: say which direction is armed.
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: role.accessibilityLabel]
            )
        }
        let ring = Int(max(0, GestureMath.distance(pin, pointer) - GestureMath.deadZone) / 56)
        if ring != lastRing {
            lastRing = ring
            Haptics.tick(.generic)
        }
        pushOverlay()
    }

    func complete(at location: CGPoint) {
        guard isActive, !finishing else { return }
        pointer = location
        if presenterMode {
            let engaged = presenterEngaged && presenterIndex != nil
            let title = presenterIndex.flatMap { FeelLabConfig.shared.presenterPreset(forSector: $0)?.name }
            if engaged { Haptics.tick(.levelChange); Sounds.commit() }
            finishVisual(commitRole: engaged ? .north : nil) {
                if FeelLab.enabled { NotificationCenter.default.post(name: .pluckFeelResult, object: engaged ? "Presenter: \(title ?? "")" : "Canceled") }
            }
            presenterMode = false; presenterIndex = nil; presenterEngaged = false
            return
        }

        let available = context?.items.map(\.role) ?? []
        let role = GestureMath.roleAtRelease(
            pin: Self.screenSpace(pin), pointer: Self.screenSpace(pointer),
            available: available, current: capturedRole
        )
        let ctx = context
        let resultTitle = FeelLab.title(for: role)
        if role != nil { Haptics.tick(.levelChange); Sounds.commit() }

        finishVisual(commitRole: role) {
            if FeelLab.enabled {
                NotificationCenter.default.post(name: .pluckFeelResult, object: resultTitle)
                return
            }
            if let role, let item = ctx?.items.first(where: { $0.role == role }) {
                ActionRunner.run(item: item, context: ctx)
            }
        }
    }

    func cancel() {
        guard isActive, !finishing else {
            forceReset()
            return
        }
        finishVisual(commitRole: nil) {
            if FeelLab.enabled {
                NotificationCenter.default.post(name: .pluckFeelResult, object: "Canceled")
            }
        }
    }

    func forceReset() {
        finishing = false
        isActive = false
        animTimer?.invalidate()
        animTimer = nil
        overlay.hide()
        showCursor()
        CursorGuard.forceVisible()
        context = nil
        capturedRole = nil
        presenterMode = false; presenterIndex = nil; presenterEngaged = false
        FeelLabConfig.shared.transientPreset = nil
        engine.gestureDidEnd()
    }

    private func finishVisual(commitRole: CompassRole?, after: (() -> Void)?) {
        guard !finishing else { return }
        finishing = true
        animTimer?.invalidate()
        animTimer = nil
        isActive = false
        engine.gestureDidEnd()

        // Do NOT warp the cursor — leave it exactly where the user released. Show it right
        // away; the blob recoils from under it instead of hiding the pointer for the animation.
        showCursor()
        overlay.commit(role: commitRole, pin: pin) { [weak self] in
            guard let self else { return }
            self.overlay.hide()
            self.context = nil
            self.capturedRole = nil
            self.finishing = false
        }
        // Act immediately; the recoil is purely visual.
        after?()

        // Safety net: if the recoil callback never fires, reset anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.finishing else { return }
            self.forceReset()
        }
    }

    private func presenterNames() -> [String] {
        let cfg = FeelLabConfig.shared
        return (0..<cfg.presenterCount).map { cfg.presenterPreset(forSector: $0)?.name ?? "None" }
    }

    private func pushPresenter() {
        let cfg = FeelLabConfig.shared
        overlay.setPresenter(
            .init(count: cfg.presenterCount, radius: CGFloat(cfg.presenterRadius), names: presenterNames(), armed: presenterIndex, engaged: presenterEngaged),
            preset: presenterIndex.flatMap { cfg.presenterPreset(forSector: $0) }
        )
    }

    /// Presenter mode: dragging past the radius arms a direction (its name shows); a little further brings its visual to life.
    private func handlePresenterMove() {
        let cfg = FeelLabConfig.shared
        let radius = CGFloat(cfg.presenterRadius)
        let previous = presenterIndex
        presenterIndex = PresenterMath.capture(pin: pin, pointer: pointer, count: cfg.presenterCount, radius: radius, current: presenterIndex)
        if presenterIndex != previous, presenterIndex != nil { Haptics.tick(.alignment); Sounds.latch() }
        let engagedNow = presenterIndex != nil && PresenterMath.isEngaged(pin: pin, pointer: pointer, radius: radius, wasEngaged: presenterEngaged)
        if engagedNow != presenterEngaged {
            presenterEngaged = engagedNow
            if engagedNow { hideCursor() } else { showCursor() }
        }
        pushPresenter()
        pushOverlay()
    }

    private func pushOverlay() {
        overlay.update(
            pin: pin,
            pointer: pointer,
            captured: capturedRole,
            emerge: emergeProgress,
            bloom: bloomProgress,
            context: context
        )
    }

    /// Blob rises out from under the cursor, then direction labels fade in.
    private func startEmergence() {
        animTimer?.invalidate()
        animStart = Date()
        let emergeDur: TimeInterval = 0.18
        let bloomDelay: TimeInterval = 0.08
        let bloomDur: TimeInterval = 0.28

        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            Task { @MainActor in
                guard self.isActive, let start = self.animStart else { t.invalidate(); return }
                let elapsed = Date().timeIntervalSince(start)

                // Ease-out emerge.
                let e = min(1, elapsed / emergeDur)
                self.emergeProgress = CGFloat(1 - pow(1 - e, 3))

                // Lobes after a beat.
                if elapsed > bloomDelay {
                    let b = min(1, (elapsed - bloomDelay) / bloomDur)
                    self.bloomProgress = CGFloat(1 - pow(1 - b, 3))
                }

                self.pushOverlay()
                if self.emergeProgress >= 1, self.bloomProgress >= 1 {
                    t.invalidate()
                }
            }
        }
    }

    /// All cursor hiding goes through `CursorGuard` (one balanced hide, watchdog, exit hooks).
    private func hideCursor() {
        CursorGuard.shared.hide()
        cursorHidden = true
    }

    private func showCursor() {
        CursorGuard.shared.show()
        cursorHidden = false
    }
}
