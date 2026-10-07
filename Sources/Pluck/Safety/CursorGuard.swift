import AppKit
import CoreGraphics
import Foundation

/// The only place that hides or shows the system cursor.
///
/// Rules, learned the hard way (an unbalanced per-frame `NSCursor.hide()` once left the cursor gone for good):
/// - Hide happens **once** per gesture and is paired with exactly one show.
/// - A watchdog on a background queue restores the cursor if the main thread stops checking in, or if the
///   cursor has been hidden too long, so a hung UI can never strand it.
/// - `forceVisible()` is idempotent and safe to call from anywhere, including signal handlers' dispatch sources.
final class CursorGuard: @unchecked Sendable {
    static let shared = CursorGuard()

    /// The cursor is never allowed to stay hidden longer than this.
    static let maxHiddenSeconds: TimeInterval = 10
    /// If the main thread doesn't call `checkIn()` for this long while hidden, restore.
    static let staleSeconds: TimeInterval = 1.0

    private let lock = NSLock()
    private var hidden = false
    private var hiddenAt: CFAbsoluteTime = 0
    private var lastCheckIn: CFAbsoluteTime = 0
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "pluck.cursorguard", qos: .userInteractive)

    var isHidden: Bool {
        lock.lock(); defer { lock.unlock() }
        return hidden
    }

    /// Hide the cursor for a gesture. No-op if already hidden by us.
    func hide() {
        lock.lock()
        if hidden { lock.unlock(); return }
        hidden = true
        hiddenAt = CFAbsoluteTimeGetCurrent()
        lastCheckIn = hiddenAt
        lock.unlock()

        NSCursor.hide()
        CGDisplayHideCursor(CGMainDisplayID())
        startWatchdog()
    }

    /// Main thread calls this every frame while hidden.
    func checkIn() {
        lock.lock()
        lastCheckIn = CFAbsoluteTimeGetCurrent()
        lock.unlock()
    }

    /// Pair of `hide()`. Safe to call when not hidden.
    func show() {
        lock.lock()
        let wasHidden = hidden
        hidden = false
        lock.unlock()
        stopWatchdog()
        if wasHidden {
            NSCursor.unhide()
            CGDisplayShowCursor(CGMainDisplayID())
        }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    /// Belt and braces: make the cursor visible no matter what our bookkeeping says.
    static func forceVisible() {
        let d = CGMainDisplayID()
        for _ in 0..<6 { CGDisplayShowCursor(d) }
        for _ in 0..<2 { NSCursor.unhide() }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    private func startWatchdog() {
        stopWatchdog()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.25, repeating: 0.25)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let isHidden = self.hidden
            let now = CFAbsoluteTimeGetCurrent()
            let stale = now - self.lastCheckIn > Self.staleSeconds
            let tooLong = now - self.hiddenAt > Self.maxHiddenSeconds
            if isHidden && (stale || tooLong) { self.hidden = false }
            self.lock.unlock()
            if isHidden && (stale || tooLong) {
                NSLog("Pluck: cursor watchdog restoring cursor (%@)", stale ? "main thread stalled" : "hidden too long")
                CursorGuard.forceVisible()
                self.stopWatchdog()
            }
        }
        lock.lock()
        timer = t
        lock.unlock()
        t.resume()
    }

    private func stopWatchdog() {
        lock.lock()
        let t = timer
        timer = nil
        lock.unlock()
        t?.cancel()
    }

    /// Restore the cursor on every way the process can end that we can intercept.
    static func installExitHooks() {
        atexit { CursorGuard.forceVisible() }
        for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInteractive))
            src.setEventHandler {
                CursorGuard.forceVisible()
                exit(0)
            }
            src.resume()
            exitSources.append(src)
        }
    }

    nonisolated(unsafe) private static var exitSources: [DispatchSourceSignal] = []
}
