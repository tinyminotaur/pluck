import AppKit
import Foundation
import PluckCore

/// Owns one Pluck gesture: tracker, overlay, cursor, and what happens on release.
@MainActor
final class PluckSession: ObservableObject {
    let engine = ChordEngine()
    let overlay = OverlayController()
    let clipboardHistory = ClipboardHistory.shared

    private(set) var isActive = false
    private var context: GrabContext?
    private var tracker = GestureTracker(pin: .zero)
    private var beganAt: CFTimeInterval = 0
    private var bloomed = false

    /// Lobes bloom a beat after the drop appears; experts flick before this and the direction still counts.
    private static let bloomDelay: CFTimeInterval = 0.07

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
        overlay.hide()
        CursorGuard.shared.show()
        CursorGuard.forceVisible()
        clipboardHistory.stop()
    }

    // MARK: Gesture

    func begin(at location: CGPoint) {
        guard !isActive else { return }
        isActive = true
        beganAt = CACurrentMediaTime()
        bloomed = false

        // Show the drop first. Everything else (context lookup) happens after the first frame is out.
        let items: [CompassItem] = FeelLab.enabled ? FeelLab.context.items : []
        context = FeelLab.enabled ? FeelLab.context : nil
        tracker = GestureTracker(pin: location, available: items.map(\.role))

        CursorGuard.shared.hide()
        overlay.show(pin: location, items: items, reducedMotion: reducedMotion) { [weak self] _ in
            self?.frame()
        }

        if !FeelLab.enabled {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                let ctx = ContextResolver.resolve(at: location)
                self.context = ctx
                self.tracker.available = ctx.items.map(\.role)
                self.overlay.setItems(ctx.items)
            }
        }
    }

    /// Runs once per display frame while a gesture is live: fresh pointer sample, then ground-truth checks.
    private func frame() {
        guard isActive else { return }
        if !engine.buttonsStillHeld() {
            // A mouse-up was missed. Trust the hardware, not our bookkeeping.
            complete(at: ChordEngine.mouseLocation())
            return
        }
        pointerMoved(to: ChordEngine.mouseLocation())
        if !bloomed, CACurrentMediaTime() - beganAt >= Self.bloomDelay {
            bloomed = true
            overlay.setBloom(true)
        }
    }

    func pointerMoved(to location: CGPoint) {
        guard isActive else { return }
        tracker.update(pointer: location)
        overlay.setPointer(location)
        overlay.setCaptured(tracker.captured)
    }

    func complete(at location: CGPoint) {
        guard isActive else { return }
        tracker.update(pointer: location)
        let role = tracker.releaseRole
        let direction = tracker.direction
        let ctx = context
        finish(role: role, direction: direction)

        if FeelLab.enabled {
            NotificationCenter.default.post(name: .pluckFeelResult, object: FeelLab.title(for: role))
            return
        }
        if let role, let item = ctx?.items.first(where: { $0.role == role }) {
            ActionRunner.run(item: item, context: ctx)
        }
    }

    func cancel() {
        guard isActive else {
            forceReset()
            return
        }
        finish(role: nil, direction: nil)
        if FeelLab.enabled {
            NotificationCenter.default.post(name: .pluckFeelResult, object: "Canceled")
        }
    }

    /// Hard reset: no animation, cursor guaranteed visible.
    func forceReset() {
        isActive = false
        overlay.hide()
        context = nil
        CursorGuard.shared.show()
        CursorGuard.forceVisible()
        engine.gestureDidEnd()
    }

    private func finish(role: CompassRole?, direction: CGPoint?) {
        isActive = false
        engine.gestureDidEnd()
        // The cursor comes back the instant you let go; the liquid finishes its animation on its own.
        CursorGuard.shared.show()
        overlay.release(commit: role != nil ? direction : nil, role: role)
    }
}
