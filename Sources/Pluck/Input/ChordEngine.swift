import AppKit
import CoreGraphics
import Foundation
import Combine
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

    /// The gesture ends and the cursor is restored after this long without any pointer movement
    /// or button activity (a fidget toy is held a long time, but never abandoned).
    private static let idleSeconds: TimeInterval = 12
    /// Absolute cap — after this, gesture ends and cursor is restored. No exceptions.
    private static let hardCapSeconds: TimeInterval = 30 * 60
    private enum Source { case chord, hold, touch, modifier }
    private var gestureSource: Source = .chord
    private var holdArm = HoldArm()
    private var holdTimer: Timer?
    private var modArm = HoldArm()
    private var modTimer: Timer?
    private var touchCount = 0
    private var touchTimer: Timer?
    private var touchArm = HoldArm()
    private var touchElig = TouchEligibility()
    private var touchRelease = TouchReleaseDebounce()
    private var touchReleaseTimer: Timer?
    private var configSub: AnyCancellable?
    private var gestureStartedAt: CFTimeInterval = 0
    private var gesturePin: CGPoint = .zero
    /// Modifier state as reported by the flagsChanged events themselves. (Polling the HID or NSEvent state was
    /// wrong for held Hyper/remapped keys and ended gestures at the next 1 s tick: see gesture.log.)
    private var lastModifiers: ModifierSet = []
    private var lastActivityAt: CFTimeInterval = 0
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
        configSub = FeelLabConfig.shared.$threeFingerEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.setThreeFinger(on) }
        NSLog("Pluck: SAFE listen-only NSEvent driver (no event tap)")
    }

    func stop() {
        configSub = nil
        setThreeFinger(false)
        cancelHold()
        cancelModifierWatch()
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
            .mouseMoved, .keyDown, .flagsChanged,
            .scrollWheel, .magnify, .rotate, .swipe, .smartMagnify,
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
            handleDown(.left, at: loc, modifiers: event.modifierFlags)
        case .rightMouseDown:
            handleDown(.right, at: loc)
        case .leftMouseUp:
            handleUp(.left, at: loc)
        case .rightMouseUp:
            handleUp(.right, at: loc)
        case .leftMouseDragged, .rightMouseDragged, .mouseMoved:
            handleMove(at: loc)
        case .flagsChanged:
            handleFlags(ModifierSet(event.modifierFlags))
        case .scrollWheel, .magnify, .rotate, .swipe, .smartMagnify:
            // Two-finger scroll/pinch/rotate move content, not the pointer: never mistake them for a summon.
            touchElig.scrolled(at: CACurrentMediaTime())
            cancelTouchWatch()
            cancelModifierWatch()
        case .keyDown:
            cancelModifierWatch() // typing with ⌥ held is not our gesture
            if event.keyCode == 53 { // Escape
                cancelActive()
            }
        default:
            break
        }
    }

    // MARK: - State machine

    private func handleDown(_ button: MouseButton, at location: CGPoint, modifiers: NSEvent.ModifierFlags = []) {
        cancelModifierWatch() // a click means this is ordinary use
        if frontmostExcluded() {
            held.insert(button)
            return
        }

        // Trackpad trigger: modifier + press and hold (without moving). A normal quick click or
        // drag never matures, so ordinary use is unaffected.
        let cfg = FeelLabConfig.shared
        if button == .left, !gestureActive, cfg.trackpadTriggerEnabled,
           modifiers.contains(cfg.trackpadModifier.flag), !isDown(.right) {
            beginHoldWatch(at: location, holdSeconds: cfg.trackpadHoldMs / 1000)
        }

        let other = button.other
        if !gestureActive, held.contains(other) || isDown(other) {
            held = [.left, .right]
            cancelHold()
            // Do NOT synthesize mouse-ups. That can desync apps and feel like a lockout.
            startGesture(source: .chord, at: location)
            return
        }

        held.insert(button)
    }

    private func handleUp(_ button: MouseButton, at location: CGPoint) {
        held.remove(button)
        cancelHold()
        guard gestureActive else { return }

        // End as soon as either button is released (safer than waiting for both).
        // Waiting for both empty caused stuck "active" if one up was missed.
        endLog("button up")
        endGestureLocally()
        session?.complete(at: location)
    }

    private func handleMove(at location: CGPoint) {
        if holdArm.isPressed { holdArm.move(to: location) }
        if modArm.isPressed { modArm.move(to: location) }
        if touchArm.isPressed { touchArm.move(to: location) }
        guard gestureActive else { return }
        let now = CACurrentMediaTime()
        lastActivityAt = now
        guard now - lastMoveAt >= Self.moveHz else { return }
        lastMoveAt = now
        session?.pointerMoved(to: location)
    }

    // MARK: - No-click modifier trigger

    private func handleFlags(_ held: ModifierSet) {
        lastModifiers = held
        let trigger = FeelLabConfig.shared.modifierTrigger
        if gestureActive, gestureSource == .modifier {
            // Releasing the modifier commits, exactly like releasing a mouse button.
            if !trigger.shouldContinue(held: held) {
                let loc = Self.mouseLocation()
                endLog("modifier released (flagsChanged)")
                endGestureLocally()
                session?.complete(at: loc)
            }
            return
        }
        guard !gestureActive else { return }
        if trigger.shouldArm(held: held), !isDown(.left), !isDown(.right), !frontmostExcluded() {
            beginModifierWatch(trigger)
        } else {
            cancelModifierWatch()
        }
    }

    private func beginModifierWatch(_ trigger: ModifierTrigger) {
        guard modTimer == nil else { return }
        let seconds = FeelLabConfig.shared.modifierHoldMs / 1000
        modArm = HoldArm(
            holdSeconds: seconds,
            moveTolerance: trigger.requiresStillness ? 8 : .greatestFiniteMagnitude
        )
        modArm.press(at: Self.mouseLocation(), time: CACurrentMediaTime())
        modTimer = Timer.scheduledTimer(withTimeInterval: seconds + 0.01, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.modifierWatchMatured(trigger) }
        }
    }

    private func modifierWatchMatured(_ trigger: ModifierTrigger) {
        modTimer = nil
        let live = lastModifiers
        guard modArm.isReady(at: CACurrentMediaTime()),
              !gestureActive, !isDown(.left), !isDown(.right),
              trigger.shouldArm(held: live), !frontmostExcluded() else {
            modArm.release()
            return
        }
        modArm.release()
        startGesture(source: .modifier, at: Self.mouseLocation())
    }

    private func cancelModifierWatch() {
        modTimer?.invalidate()
        modTimer = nil
        modArm.release()
    }

    // MARK: - Trackpad triggers

    private func beginHoldWatch(at location: CGPoint, holdSeconds: Double) {
        cancelHold()
        holdArm = HoldArm(holdSeconds: holdSeconds, moveTolerance: 8)
        holdArm.press(at: location, time: CACurrentMediaTime())
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdSeconds + 0.01, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.holdMatured() }
        }
    }

    private func holdMatured() {
        holdTimer = nil
        let cfg = FeelLabConfig.shared
        guard holdArm.isReady(at: CACurrentMediaTime()),
              !gestureActive,
              isDown(.left),
              NSEvent.modifierFlags.contains(cfg.trackpadModifier.flag) else {
            holdArm.release()
            return
        }
        holdArm.release()
        held = [.left]
        startGesture(source: .hold, at: Self.mouseLocation())
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdArm.release()
    }

    private func setThreeFinger(_ on: Bool) {
        if on {
            MultitouchMonitor.shared.start { [weak self] count in
                DispatchQueue.main.async { self?.touchCountChanged(count) }
            }
        } else {
            MultitouchMonitor.shared.stop()
            cancelTouchWatch()
            touchElig = TouchEligibility()
            touchCount = 0
        }
    }

    private func finishTouchGesture() {
        touchReleaseTimer?.invalidate()
        touchReleaseTimer = nil
        let loc = Self.mouseLocation()
        endLog("fingers lifted (count \(touchCount))")
        endGestureLocally()
        session?.complete(at: loc)
    }

    private func cancelTouchWatch() {
        touchTimer?.invalidate()
        touchTimer = nil
        touchArm.release()
    }

    private func touchCountChanged(_ count: Int) {
        let now = CACurrentMediaTime()
        touchElig.countChanged(count, at: now)
        touchCount = count
        // Any change in the number of contacts restarts the dwell from scratch.
        cancelTouchWatch()

        if gestureActive, gestureSource == .touch {
            // Contact counts flicker while fingers move: only release after the count has stayed below three
            // for a moment (or every finger is up). Lifting your hand is still immediate.
            touchRelease.update(count: count, at: now)
            touchReleaseTimer?.invalidate()
            touchReleaseTimer = nil
            if touchRelease.shouldRelease(at: now) {
                finishTouchGesture()
            } else if count < 3 {
                touchReleaseTimer = Timer.scheduledTimer(withTimeInterval: touchRelease.grace + 0.01, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.gestureActive, self.gestureSource == .touch else { return }
                        if self.touchRelease.shouldRelease(at: CACurrentMediaTime()) { self.finishTouchGesture() }
                    }
                }
            }
            return
        }
        guard !gestureActive, touchElig.canArm(at: now) else { return }

        // Rest-to-arm: three fingers must stay put for the hold time. If they start moving first,
        // it is an ordinary three-finger drag and we never take over.
        let seconds = FeelLabConfig.shared.threeFingerHoldMs / 1000
        touchArm = HoldArm(holdSeconds: seconds, moveTolerance: 8)
        touchArm.press(at: Self.mouseLocation(), time: now)
        touchTimer = Timer.scheduledTimer(withTimeInterval: seconds + 0.01, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.touchTimer = nil
                let t = CACurrentMediaTime()
                let ready = self.touchArm.isReady(at: t) && self.touchElig.canArm(at: t)
                self.touchArm.release()
                guard ready, !self.gestureActive, !self.frontmostExcluded() else { return }
                self.startGesture(source: .touch, at: Self.mouseLocation())
            }
        }
    }

    private func endLog(_ reason: String) {
        let t = CACurrentMediaTime() - gestureStartedAt
        let d = GestureMath.distance(gesturePin, Self.mouseLocation())
        Diagnostics.log(String(format: "end   source=%@ reason=%@ held=%.2fs pointerDist=%.0f", "\(gestureSource)", reason, t, d))
    }

    private func startGesture(source: Source, at location: CGPoint) {
        gestureSource = source
        gesturePin = location
        Diagnostics.log("begin source=\(source) at=(\(Int(location.x)),\(Int(location.y)))")
        touchRelease.reset()
        gestureActive = true
        armFailsafe()
        session?.begin(at: location)
    }

    private func cancelActive() {
        guard gestureActive || (session?.isActive == true) else { return }
        endLog("cancel (Escape or failsafe)")
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
        gestureStartedAt = CACurrentMediaTime()
        lastActivityAt = gestureStartedAt
        failsafeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.gestureActive else { return }
                CursorGuard.shared.checkIn()
                let now = CACurrentMediaTime()
                let idle = now - self.lastActivityAt
                let total = now - self.gestureStartedAt
                guard idle > Self.idleSeconds || total > Self.hardCapSeconds else { return }
                NSLog("Pluck: gesture failsafe (idle %.0fs, total %.0fs) — releasing", idle, total)
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
        CursorGuard.forceVisible()
    }

    static func mouseLocation() -> CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: p.y)
    }
}

extension ModifierSet {
    init(_ flags: NSEvent.ModifierFlags) {
        var s: ModifierSet = []
        if flags.contains(.control) { s.insert(.control) }
        if flags.contains(.option) { s.insert(.option) }
        if flags.contains(.shift) { s.insert(.shift) }
        if flags.contains(.command) { s.insert(.command) }
        self = s
    }
}
