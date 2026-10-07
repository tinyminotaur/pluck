import AppKit
import Foundation
import PluckCore

/// The transparent, click-through panel that hosts the liquid for one gesture.
///
/// The panel ignores mouse events entirely: it can never swallow or delay a click, and it never takes focus.
@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private var view: LiquidView?
    private var screenFrame: CGRect = .zero
    private var pin: CGPoint = .zero
    private var onFrame: ((CGFloat) -> Void)?

    var isShowing: Bool { panel != nil }

    func show(pin: CGPoint, items: [CompassItem], reducedMotion: Bool, onFrame: @escaping (CGFloat) -> Void) {
        hide()
        self.pin = pin
        self.onFrame = onFrame

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
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.setFrame(screen.frame, display: false)

        let view = LiquidView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFrame = { [weak self] dt in self?.onFrame?(dt) }
        panel.contentView = view
        panel.orderFrontRegardless()

        self.panel = panel
        self.view = view
        view.begin(pin: toView(pin), items: items, reduceMotion: reducedMotion)
    }

    /// Feed the raw global pointer; the overlay applies the gain curve to get the drawn head.
    func setPointer(_ global: CGPoint) {
        guard let view else { return }
        let cfg = FeelLabConfig.shared
        let head = GestureMath.virtualHead(
            pin: pin,
            pointer: global,
            gainBoost: CGFloat(cfg.gainBoost),
            maxLength: CGFloat(cfg.maxLength)
        )
        view.setTarget(toView(head))
    }

    func setCaptured(_ role: CompassRole?) { view?.setCaptured(role) }
    func setBloom(_ on: Bool) { view?.setBloom(on) }
    func setItems(_ items: [CompassItem]) { view?.setItems(items) }

    /// Play the release animation, then tear down.
    func release(commit direction: CGPoint?, role: CompassRole?) {
        guard let view else { return }
        view.onFinished = { [weak self] in self?.hide() }
        view.release(commit: direction, role: role)
    }

    func hide() {
        view?.onFinished = nil
        view?.stop()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        view = nil
    }

    private func toView(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
    }
}
