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

/// Pure geometry helpers for stretch / magnet / dead-zone — unit-testable without AppKit.
public enum GestureMath {
    /// Coincidence window for left+right chord (seconds).
    public static let armWindow: CFTimeInterval = 0.040
    /// Distance from pin before a role can capture (points).
    public static let deadZone: CGFloat = 24
    /// Drawn stretch exaggeration so short flicks read as long pulls.
    public static let stretchGain: CGFloat = 1.75
    /// Soft magnet snap radius around a lobe (points, after gain).
    public static let magnetRadius: CGFloat = 72
    /// Hysteresis: once captured, stay until this much closer to another role.
    public static let hysteresis: CGFloat = 22
    /// Distance of lobe centers from pin when bloomed.
    public static let lobeDistance: CGFloat = 84
    public static let pinRadius: CGFloat = 22
    public static let headRadius: CGFloat = 18
    public static let lobeRadius: CGFloat = 16

    /// Angle of vector from pin to point, screen coords (y down).
    public static func angle(from pin: CGPoint, to point: CGPoint) -> CGFloat {
        atan2(point.y - pin.y, point.x - pin.x)
    }

    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Visual head position: pin + (pointer - pin) * stretchGain.
    public static func stretchedHead(pin: CGPoint, pointer: CGPoint) -> CGPoint {
        let dx = pointer.x - pin.x
        let dy = pointer.y - pin.y
        return CGPoint(x: pin.x + dx * stretchGain, y: pin.y + dy * stretchGain)
    }

    /// Nearest role by angle among available roles. Nil if none.
    public static func nearestRole(angle: CGFloat, available: [CompassRole]) -> CompassRole? {
        guard !available.isEmpty else { return nil }
        return available.min(by: {
            abs(shortestAngleDelta($0.angle, angle)) < abs(shortestAngleDelta($1.angle, angle))
        })
    }

    public static func shortestAngleDelta(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    /// Magnetic capture with hysteresis. `current` stays until another role is clearly closer.
    public static func capture(
        pin: CGPoint,
        pointer: CGPoint,
        available: [CompassRole],
        current: CompassRole?
    ) -> CompassRole? {
        let dist = distance(pin, pointer)
        if dist < deadZone { return nil }

        let head = stretchedHead(pin: pin, pointer: pointer)
        let ang = angle(from: pin, to: head)
        guard let nearest = nearestRole(angle: ang, available: available) else { return nil }

        let nearestLobe = lobeCenter(pin: pin, role: nearest)
        let nearestDist = distance(head, nearestLobe)

        if let current, available.contains(current) {
            let currentLobe = lobeCenter(pin: pin, role: current)
            let currentDist = distance(head, currentLobe)
            if currentDist - nearestDist < hysteresis {
                return current
            }
        }

        if nearestDist <= magnetRadius || dist >= deadZone {
            return nearest
        }
        return current
    }

    public static func lobeCenter(pin: CGPoint, role: CompassRole) -> CGPoint {
        let u = role.unit
        return CGPoint(x: pin.x + u.x * lobeDistance, y: pin.y + u.y * lobeDistance)
    }

    /// Role at release: angle-based, independent of the drawn blob.
    public static func roleAtRelease(pin: CGPoint, pointer: CGPoint, available: [CompassRole]) -> CompassRole? {
        if distance(pin, pointer) < deadZone { return nil }
        return nearestRole(angle: angle(from: pin, to: pointer), available: available)
    }
}
