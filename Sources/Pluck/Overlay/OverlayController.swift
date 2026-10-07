import AppKit
import Foundation
import PluckCore

@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private var blobView: MetaballView?
    private var screenFrame: CGRect = .zero
    private var reducedMotion = false
    private var commitWork: DispatchWorkItem?

    func show(pin: CGPoint, context: GrabContext, reducedMotion: Bool) {
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
        view.tintColor = FeelLabConfig.shared.tintColor
        view.pin = toView(pin)
        view.head = toView(pin)
        panel.contentView = view

        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
        self.blobView = view
        // Lock pin after pin/head are set in view space.
        view.startPhysics()
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
        view.head = toView(pointer)
        view.emerge = emerge
        view.bloom = bloom
        view.captured = captured
        view.items = context?.items ?? []
        // Physics display-link redraws; still nudge for reduced-motion / first frame.
        if reducedMotion { view.needsDisplay = true }
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

        // Collapse mass back to the pin — cursor stays where the user released.
        view.head = view.pin
        view.emerge = 0
        view.bloom = 0
        view.needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            finish()
            self?.hide()
        }
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
