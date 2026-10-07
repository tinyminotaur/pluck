import AppKit
import CoreGraphics
import Foundation
import PluckCore

/// SAFE chord detection: listen only.
///
/// - `NSEvent` global/local monitors only. Never a `CGEventTap` (those can swallow input and lock the machine).
/// - Never synthesizes mouse or keyboard events.
/// - Every gesture has hard limits: Escape cancels, a failsafe timer ends it, the hardware button state is
///   re-checked every frame (a missed mouse-up can't strand a gesture), and ⌃⌥⌘P force-quits.
@MainActor
final class ChordEngine {
    weak var session: PluckSession?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var panicMonitor: Any?

    private var held: Set<MouseButton> = []
    private var gestureActive = false
    private var failsafeTimer: Timer?

    /// Absolute cap per gesture. After this the gesture ends and the cursor is restored, no exceptions.
    private static let failsafeSeconds: TimeInterval = 12

    var isRunning: Bool { globalMonitor != nil }
    /// Always false: event taps are disabled for safety.
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
        NSLog("Pluck: listen-only NSEvent driver (no event tap)")
    }

    func stop() {
        endGestureLocally()
        removeNSEvent()
        removePanicHotkey()
        held.removeAll()
    }

    func gestureDidEnd() {
        endGestureLocally()
        held = physicalHeld()
    }

    func resetHard() {
        endGestureLocally()
        held.removeAll()
        session?.forceReset()
        held = physicalHeld()
    }

    /// Ground truth from the HID system: are both buttons still physically down?
    /// Always true when no gesture is running.
    func buttonsStillHeld() -> Bool {
        guard gestureActive else { return true }
        return isDown(.left) && isDown(.right)
    }

    // MARK: Monitors (never modify or swallow events)

    private func installNSEvent() {
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .leftMouseDragged, .rightMouseDragged,
            .mouseMoved, .keyDown,
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in
            self?.deliver(e)
        }
        // The local monitor MUST return the event unchanged. Returning nil would swallow it.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            self?.deliver(e)
            return e
        }
    }

    private func removeNSEvent() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    /// Monitors fire on the main thread; handle inline so there's no extra queue hop between the event and the frame.
    private nonisolated func deliver(_ event: NSEvent) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { onNSEvent(event) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.onNSEvent(event) } }
        }
    }

    /// Ctrl+Option+Cmd+P force-quits Pluck even if a gesture is wedged.
    private func installPanicHotkey() {
        panicMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let wantsPanic = event.modifierFlags.contains([.control, .option, .command])
                && event.charactersIgnoringModifiers?.lowercased() == "p"
            guard wantsPanic else { return }
            DispatchQueue.main.async {
                NSLog("Pluck: PANIC hotkey: force quit")
                CursorGuard.forceVisible()
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
        switch event.type {
        case .leftMouseDown: handleDown(.left)
        case .rightMouseDown: handleDown(.right)
        case .leftMouseUp: handleUp(.left)
        case .rightMouseUp: handleUp(.right)
        case .leftMouseDragged, .rightMouseDragged, .mouseMoved: handleMove()
        case .keyDown:
            if event.keyCode == 53 { cancelActive() } // Escape
        default: break
        }
    }

    // MARK: State machine

    private func handleDown(_ button: MouseButton) {
        if frontmostExcluded() {
            held.insert(button)
            return
        }
        let other = button.other
        if !gestureActive, held.contains(other) || isDown(other) {
            held = [.left, .right]
            gestureActive = true
            armFailsafe()
            // Never synthesize mouse-ups: that can desync apps and feels like a lockout.
            session?.begin(at: Self.mouseLocation())
            return
        }
        held.insert(button)
    }

    private func handleUp(_ button: MouseButton) {
        held.remove(button)
        guard gestureActive else { return }
        // End as soon as either button is released.
        endGestureLocally()
        session?.complete(at: Self.mouseLocation())
    }

    private func handleMove() {
        if gestureActive {
            session?.pointerMoved(to: Self.mouseLocation())
        } else if CursorGuard.shared.isHidden, session?.isActive != true {
            // Cursor hidden with no gesture running: never leave it that way.
            CursorGuard.shared.show()
            CursorGuard.forceVisible()
        }
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

    // MARK: Helpers

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
        let timer = Timer(timeInterval: Self.failsafeSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                NSLog("Pluck: gesture failsafe (%.0fs): releasing", Self.failsafeSeconds)
                self.cancelActive()
                CursorGuard.forceVisible()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        failsafeTimer = timer
    }

    private func clearFailsafe() {
        failsafeTimer?.invalidate()
        failsafeTimer = nil
    }

    static func mouseLocation() -> CGPoint {
        NSEvent.mouseLocation
    }
}
