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
    @Published private(set) var pin: CGPoint = .zero
    @Published private(set) var pointer: CGPoint = .zero
    @Published private(set) var emergeProgress: CGFloat = 0
    @Published private(set) var bloomProgress: CGFloat = 0

    private var animTimer: Timer?
    private var openedAt: CFTimeInterval = 0
    private var cursorHidden = false
    private var finishing = false
    private var animStart: Date?

    private var reducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init() {
        engine.session = self
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
        clipboardHistory.stop()
    }

    func begin(at location: CGPoint) {
        guard !isActive, !finishing else { return }
        isActive = true
        openedAt = CACurrentMediaTime()
        pin = location
        pointer = location
        capturedRole = nil
        emergeProgress = 0
        bloomProgress = 0

        // Hide system cursor FIRST so the blob is the only pointer you see.
        hideCursor()

        let ctx = FeelLab.enabled ? FeelLab.context : ContextResolver.resolve(at: location)
        context = ctx
        overlay.show(pin: location, context: ctx, reducedMotion: reducedMotion)
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
        pointer = location
        let available = context?.items.map(\.role) ?? CompassRole.allCases
        capturedRole = GestureMath.capture(pin: pin, pointer: pointer, available: available, current: capturedRole)
        pushOverlay()
    }

    func complete(at location: CGPoint) {
        guard isActive, !finishing else { return }
        pointer = location

        let available = context?.items.map(\.role) ?? []
        let role = GestureMath.roleAtRelease(pin: pin, pointer: pointer, available: available)
        let ctx = context
        let resultTitle = FeelLab.title(for: role)

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
        context = nil
        capturedRole = nil
        engine.gestureDidEnd()
    }

    private func finishVisual(commitRole: CompassRole?, after: (() -> Void)?) {
        guard !finishing else { return }
        finishing = true
        animTimer?.invalidate()
        animTimer = nil
        isActive = false
        engine.gestureDidEnd()

        // Do NOT warp the cursor — leave it exactly where the user released.
        overlay.commit(role: commitRole, pin: pin) { [weak self] in
            guard let self else { return }
            self.showCursor()
            self.overlay.hide()
            self.context = nil
            self.capturedRole = nil
            self.finishing = false
            after?()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.finishing else { return }
            let pending = after
            self.forceReset()
            pending?()
        }
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

    private func hideCursor() {
        // Hide repeatedly — AppKit can re-show the cursor when windows key.
        for _ in 0..<4 { NSCursor.hide() }
        CGDisplayHideCursor(CGMainDisplayID())
        cursorHidden = true
    }

    private func showCursor() {
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        for _ in 0..<4 { NSCursor.unhide() }
        CGDisplayShowCursor(CGMainDisplayID())
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        cursorHidden = false
    }

}
