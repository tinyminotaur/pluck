import CoreGraphics
import Foundation

public enum GesturePhase: Equatable, Sendable {
    case idle
    case arming(firstButton: MouseButton, startedAt: CFTimeInterval)
    case active
    case committing(role: CompassRole?)
}

public enum MouseButton: Equatable, Sendable {
    case left
    case right

    public var other: MouseButton {
        self == .left ? .right : .left
    }
}

/// Pure geometry for the gesture. Everything is in AppKit screen space: origin bottom-left, **y up**.
public enum GestureMath {
    /// Coincidence window for left+right chord (seconds).
    public static let armWindow: CFTimeInterval = 0.040
    /// Pointer distance from the pin before a role can be captured (points).
    public static let enterDeadZone: CGFloat = 22
    /// Once engaged, the pointer must come back inside this to cancel (smaller than enter, so cancel is deliberate).
    public static let exitDeadZone: CGFloat = 14
    /// Angular hysteresis past a sector boundary before the captured role switches (radians, ~11°).
    public static let hysteresisAngle: CGFloat = 0.20
    /// Distance of bloomed lobe centers from the pin, in drawn (virtual) space.
    public static let lobeDistance: CGFloat = 84

    /// Extra drawn stretch beyond 1:1 once the pull is long, so a short wrist motion reads as a long pull.
    public static let defaultGainBoost: CGFloat = 0.8
    /// Pointer distance over which the gain ramps from 1× to (1 + boost)×.
    public static let gainRamp: CGFloat = 140
    /// The drawn length never exceeds this (soft-saturating), so the drop can't run away.
    public static let defaultMaxLength: CGFloat = 360

    public static func angle(from pin: CGPoint, to point: CGPoint) -> CGFloat {
        atan2(point.y - pin.y, point.x - pin.x)
    }

    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    public static func shortestAngleDelta(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    public static func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        abs(shortestAngleDelta(a, b))
    }

    /// The compass role whose axis is closest to `angle`, among all four.
    public static func nearestRole(angle: CGFloat) -> CompassRole {
        CompassRole.allCases.min(by: { angularDistance($0.angle, angle) < angularDistance($1.angle, angle) })!
    }

    /// Drawn pull length for a raw pointer distance. Monotonic: 1× near the pin, ramping up to
    /// (1 + boost)×, then soft-saturating toward `maxLength`.
    public static func virtualLength(
        _ d: CGFloat,
        gainBoost: CGFloat = defaultGainBoost,
        maxLength: CGFloat = defaultMaxLength
    ) -> CGFloat {
        let x = max(0, d)
        let s = min(1, x / gainRamp)
        let smooth = s * s * (3 - 2 * s)
        let v = x * (1 + max(0, gainBoost) * smooth)
        let knee = maxLength * 0.7
        if v <= knee { return v }
        let room = maxLength - knee
        return knee + room * CGFloat(tanh(Double((v - knee) / room)))
    }

    /// Where the drawn head sits for a given pointer position.
    public static func virtualHead(
        pin: CGPoint,
        pointer: CGPoint,
        gainBoost: CGFloat = defaultGainBoost,
        maxLength: CGFloat = defaultMaxLength
    ) -> CGPoint {
        let dx = pointer.x - pin.x
        let dy = pointer.y - pin.y
        let d = hypot(dx, dy)
        guard d > 0.0001 else { return pin }
        let v = virtualLength(d, gainBoost: gainBoost, maxLength: maxLength)
        return CGPoint(x: pin.x + dx / d * v, y: pin.y + dy / d * v)
    }
}

/// Stateful capture for one gesture: dead zone with hysteresis, angular sectors with hysteresis.
/// What the user sees captured is exactly what commits on release.
public struct GestureTracker {
    public let pin: CGPoint
    public private(set) var pointer: CGPoint
    /// Roles the current context offers. Pulling toward a role not in this list captures nothing.
    public var available: [CompassRole] {
        didSet { refreshCaptured() }
    }
    /// True once the pointer has left the dead zone (until it returns inside the exit radius).
    public private(set) var engaged = false
    /// The role the pointer is aiming at, even if that role has no action.
    public private(set) var pointing: CompassRole?
    /// The role that will commit on release (nil when canceling).
    public private(set) var captured: CompassRole?

    public init(pin: CGPoint, available: [CompassRole] = CompassRole.allCases) {
        self.pin = pin
        self.pointer = pin
        self.available = available
    }

    @discardableResult
    public mutating func update(pointer p: CGPoint) -> CompassRole? {
        pointer = p
        let d = GestureMath.distance(pin, p)
        let threshold = engaged ? GestureMath.exitDeadZone : GestureMath.enterDeadZone
        guard d >= threshold else {
            engaged = false
            pointing = nil
            captured = nil
            return nil
        }
        engaged = true

        let ang = GestureMath.angle(from: pin, to: p)
        let nearest = GestureMath.nearestRole(angle: ang)
        if let current = pointing, current != nearest {
            let dc = GestureMath.angularDistance(current.angle, ang)
            let dn = GestureMath.angularDistance(nearest.angle, ang)
            if dc - dn >= GestureMath.hysteresisAngle { pointing = nearest }
        } else {
            pointing = nearest
        }
        refreshCaptured()
        return captured
    }

    /// Role to run on release.
    public var releaseRole: CompassRole? { engaged ? captured : nil }

    /// Unit direction from the pin toward the pointer, if engaged.
    public var direction: CGPoint? {
        guard engaged else { return nil }
        let d = GestureMath.distance(pin, pointer)
        guard d > 0.0001 else { return nil }
        return CGPoint(x: (pointer.x - pin.x) / d, y: (pointer.y - pin.y) / d)
    }

    private mutating func refreshCaptured() {
        if let p = pointing, available.contains(p) { captured = p } else { captured = nil }
    }
}
