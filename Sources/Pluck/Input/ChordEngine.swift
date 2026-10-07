import AppKit
import CoreGraphics
import Foundation
import PluckCore

/// SAFE chord detection — listen only.
///
/// - Uses `NSEvent` global/local monitors only (Accessibility).
/// - Never installs a `CGEventTap` (those can swallow mouse/keyboard and lock the machine).
/// - Never synthesizes mouse/keyboard events.
/// - Never drives System Settings with keystrokes.
/// - Hard time limit on every gesture; Escape cancels; panic hotkey force-quits Pluck.
@MainActor
final class ChordEngine {
    weak var session: PluckSession?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var panicMonitor: Any?

    private var held: Set<MouseButton> = []
    private var gestureActive = false
    private var failsafeTimer: Timer?
    private var lastMoveAt: CFTimeInterval = 0

    /// Absolute cap — after this, gesture ends and cursor is restored. No exceptions.
    private static let failsafeSeconds: TimeInterval = 20
    private static let moveHz: CFTimeInterval = 1.0 / 90.0

    var isRunning: Bool { globalMonitor != nil }
    /// Always false — event taps are disabled for safety.
    var usingEventTap: Bool { false }

    func start() {
        stop()
        guard Permissions.accessibilityTrusted else {
            NSLog("Pluck: Accessibility required (listen-only)")
            return
        }

        held = physicalHeld()
        installNSEvent()
        installPanicHotkey()
        NSLog("Pluck: SAFE listen-only NSEvent driver (no event tap)")
    }

    func stop() {
        endGestureLocally()
        removeNSEvent()
        removePanicHotkey()
        held.removeAll()
        forceCursorVisible()
    }

    func gestureDidEnd() {
        endGestureLocally()
        held = physicalHeld()
    }

    func resetHard() {
        endGestureLocally()
        held.removeAll()
        forceCursorVisible()
        session?.forceReset()
        held = physicalHeld()
    }

    // MARK: - Monitors (never modify/swallow events)

    private func installNSEvent() {
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .leftMouseDragged, .rightMouseDragged,
            .mouseMoved, .keyDown,
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in
            DispatchQueue.main.async { self?.onNSEvent(e) }
        }
        // Local monitor MUST return the event unchanged — never nil (nil swallows).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            DispatchQueue.main.async { self?.onNSEvent(e) }
            return e
        }
    }

    private func removeNSEvent() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    /// Ctrl+Option+Cmd+P — force-quit Pluck even if a gesture is wedged.
    /// Installed as a separate listen-only monitor so it cannot be gated on gesture state.
    private func installPanicHotkey() {
        panicMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let wantsPanic = event.modifierFlags.contains([.control, .option, .command])
                && event.charactersIgnoringModifiers?.lowercased() == "p"
            guard wantsPanic else { return }
            DispatchQueue.main.async {
                NSLog("Pluck: PANIC hotkey — force quit")
                self?.resetHard()
                NSApp.terminate(nil)
            }
        }
    }

    private func removePanicHotkey() {
        if let panicMonitor { NSEvent.removeMonitor(panicMonitor) }
        panicMonitor = nil
    }

    private func onNSEvent(_ event: NSEvent) {
        let loc = Self.mouseLocation()

        switch event.type {
        case .leftMouseDown:
            handleDown(.left, at: loc)
        case .rightMouseDown:
            handleDown(.right, at: loc)
        case .leftMouseUp:
            handleUp(.left, at: loc)
        case .rightMouseUp:
            handleUp(.right, at: loc)
        case .leftMouseDragged, .rightMouseDragged, .mouseMoved:
            handleMove(at: loc)
        case .keyDown:
            if event.keyCode == 53 { // Escape
                cancelActive()
            }
        default:
            break
        }
    }

    // MARK: - State machine

    private func handleDown(_ button: MouseButton, at location: CGPoint) {
        if frontmostExcluded() {
            held.insert(button)
            return
        }

        let other = button.other
        if !gestureActive, held.contains(other) || isDown(other) {
            held = [.left, .right]
            gestureActive = true
            armFailsafe()
            // Do NOT synthesize mouse-ups. That can desync apps and feel like a lockout.
            session?.begin(at: location)
            return
        }

        held.insert(button)
    }

    private func handleUp(_ button: MouseButton, at location: CGPoint) {
        held.remove(button)
        guard gestureActive else { return }

        // End as soon as either button is released (safer than waiting for both).
        // Waiting for both empty caused stuck "active" if one up was missed.
        endGestureLocally()
        session?.complete(at: location)
    }

    private func handleMove(at location: CGPoint) {
        guard gestureActive else { return }
        let now = CACurrentMediaTime()
        guard now - lastMoveAt >= Self.moveHz else { return }
        lastMoveAt = now
        session?.pointerMoved(to: location)
    }

    private func cancelActive() {
        guard gestureActive || (session?.isActive == true) else { return }
        endGestureLocally()
        session?.cancel()
    }

    private func endGestureLocally() {
        clearFailsafe()
        gestureActive = false
    }

    // MARK: - Helpers

    private func physicalHeld() -> Set<MouseButton> {
        var s = Set<MouseButton>()
        if isDown(.left) { s.insert(.left) }
        if isDown(.right) { s.insert(.right) }
        return s
    }

    private func isDown(_ button: MouseButton) -> Bool {
        let id: CGMouseButton = button == .left ? .left : .right
        return CGEventSource.buttonState(.hidSystemState, button: id)
    }

    private func frontmostExcluded() -> Bool {
        ExcludeList.shared.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func armFailsafe() {
        clearFailsafe()
        failsafeTimer = Timer.scheduledTimer(withTimeInterval: Self.failsafeSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                NSLog("Pluck: gesture failsafe (%.1fs) — releasing", Self.failsafeSeconds)
                self.cancelActive()
                self.forceCursorVisible()
            }
        }
    }

    private func clearFailsafe() {
        failsafeTimer?.invalidate()
        failsafeTimer = nil
    }

    private func forceCursorVisible() {
        for _ in 0..<12 { NSCursor.unhide() }
        CGDisplayShowCursor(CGMainDisplayID())
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    static func mouseLocation() -> CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: p.y)
    }
}
