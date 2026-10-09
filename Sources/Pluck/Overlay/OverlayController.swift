import AppKit
import Foundation
import PluckCore

@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private var blobView: MetaballView?
    private var screenFrame: CGRect = .zero
    /// Where the current gesture started (global, y-up).
    private var gesturePin: CGPoint = .zero
    private var reducedMotion = false
    private var commitWork: DispatchWorkItem?

    func show(pin: CGPoint, context: GrabContext, reducedMotion: Bool) {
        gesturePin = pin
        self.reducedMotion = reducedMotion
        hide()

        let screen = NSScreen.screens.first { NSMouseInRect(pin, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        screenFrame = screen.frame

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Capture mouse during gesture (nonactivating; no event tap).
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setFrame(screen.frame, display: true)

        let view = MetaballView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.reducedMotion = reducedMotion
        view.items = context.items
        view.tintColor = PluckConfig.shared.tintColor
        view.pin = toView(pin)
        view.head = toView(pin)
        view.pointerTarget = toView(pin)
        panel.contentView = view

        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
        self.blobView = view
        // Lock pin after pin/head are set in view space.
        // Sample the cursor fresh on every display frame (mouse events arrive on their own, irregular schedule).
        view.pointerProvider = { [weak self] in
            guard let self else { return nil }
            return self.headTarget(for: NSEvent.mouseLocation)
        }
        view.startPhysics()
    }

    /// Presenter mode: the armed direction and its visual (nil preset when nothing is armed yet).
    func setPresenter(_ state: MetaballView.PresenterOverlayState, preset: FeelPreset?) {
        blobView?.updatePresenter(state, preset: preset)
    }

    func update(
        pin: CGPoint,
        pointer: CGPoint,
        captured: CompassRole?,
        emerge: CGFloat,
        bloom: CGFloat,
        context: GrabContext?
    ) {
        guard let view = blobView else { return }
        // Head tracks pointer 1:1. Pin was locked in startPhysics — do not move it.
        // The drawn head is the pointer run through the screen-aware reach curve: exaggerated near the pin,
        // exactly 1:1 at the screen edge, with no length cap. Capture/commit still use the raw pointer.
        let target = headTarget(for: pointer)
        view.pointerTarget = target
        if reducedMotion { view.head = view.pointerTarget }   // no physics: the head is the (gained) pointer
        if !view.presenterActive { view.emerge = emerge }
        view.bloom = bloom
        view.captured = captured
        view.items = context?.items ?? []
        // Physics display-link redraws; still nudge for reduced-motion / first frame.
        if reducedMotion { view.needsDisplay = true }
    }

    /// The drawn head position for a raw global pointer position.
    private func headTarget(for pointer: CGPoint) -> CGPoint {
        let cfg = PluckConfig.shared
        // Exact by default: the blob's end is the pointer, so the cursor never appears to jump when it comes back.
        let virtual = cfg.reachExact ? pointer : GestureMath.reachHead(
            pin: gesturePin, pointer: pointer,
            bounds: screenFrame.insetBy(dx: 8, dy: 8), gain: CGFloat(cfg.reachGain)
        )
        var target = toView(virtual)
        if let v = blobView {   // never push the head off-screen
            target.x = min(max(target.x, 8), v.bounds.width - 8)
            target.y = min(max(target.y, 8), v.bounds.height - 8)
        }
        return target
    }

    func commit(role: CompassRole?, pin: CGPoint, completion: @escaping () -> Void) {
        commitWork?.cancel()
        guard let view = blobView else {
            completion()
            return
        }

        var finished = false
        let finish: () -> Void = {
            guard !finished else { return }
            finished = true
            completion()
        }

        // The gesture is over: never let the (invisible) overlay eat the user's next click.
        panel?.ignoresMouseEvents = true
        view.bloom = 0

        if reducedMotion {
            view.head = view.pin
            view.emerge = 0
            view.needsDisplay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                finish()
                self?.hide()
            }
            return
        }

        // Snap back to the pin with a springy overshoot, then melt away. The cursor is already
        // visible at the release point, so the blob visibly recoils from under it.
        view.beginRecoil(role: role) { [weak self] in
            finish()
            self?.hide()
        }
        let fallback = DispatchWorkItem { [weak self] in
            finish()
            self?.hide()
        }
        commitWork = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95, execute: fallback)
    }

    func hide() {
        commitWork?.cancel()
        commitWork = nil
        blobView?.stopPhysics()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        blobView = nil
    }

    private func toView(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
    }
}
