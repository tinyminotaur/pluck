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
    /// Dead zone once a role is captured: smaller than `deadZone` so hovering on the
    /// edge doesn't flicker between armed and canceled.
    public static let deadZoneExit: CGFloat = 16
    /// Angular hysteresis (radians, per side). Role boundaries sit midway between
    /// neighbours; a captured role is held until the pointer is this far past that line.
    public static let hysteresisAngle: CGFloat = 0.14
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

    /// Distance from `pin` to the edge of `rect` along the unit direction `dir` (0 if the pin is outside).
    public static func rayDistance(from pin: CGPoint, direction dir: CGPoint, in rect: CGRect) -> CGFloat {
        var t = CGFloat.greatestFiniteMagnitude
        if dir.x > 1e-6 { t = min(t, (rect.maxX - pin.x) / dir.x) } else if dir.x < -1e-6 { t = min(t, (rect.minX - pin.x) / dir.x) }
        if dir.y > 1e-6 { t = min(t, (rect.maxY - pin.y) / dir.y) } else if dir.y < -1e-6 { t = min(t, (rect.minY - pin.y) / dir.y) }
        return t == .greatestFiniteMagnitude ? 0 : max(0, t)
    }

    /// Drawn pull length for a raw pointer distance `d`, where `maxDist` is how far the screen extends from the
    /// pin in that direction. There is no artificial length limit: the head can reach any point on screen.
    /// Gain is exaggerated near the pin (a short motion reads as a long stretch) and eases to exactly
    /// 1 : 1 at the edge, so the head arrives at the screen edge when the pointer does. Strictly increasing.
    public static func reachLength(_ d: CGFloat, maxDist: CGFloat, gain: CGFloat) -> CGFloat {
        let x = max(0, d)
        guard maxDist > 1 else { return x }
        if x >= maxDist { return maxDist }
        let g = max(0.001, gain)
        let e = CGFloat(exp(-Double(g)))
        return maxDist * (1 - CGFloat(exp(-Double(g * x / maxDist)))) / (1 - e)
    }

    /// Where the drawn head sits for a pointer position: same direction, gain-mapped length, inside `bounds`.
    public static func reachHead(pin: CGPoint, pointer: CGPoint, bounds: CGRect, gain: CGFloat) -> CGPoint {
        let dx = pointer.x - pin.x
        let dy = pointer.y - pin.y
        let d = hypot(dx, dy)
        guard d > 0.0001 else { return pin }
        let dir = CGPoint(x: dx / d, y: dy / d)
        let reach = rayDistance(from: pin, direction: dir, in: bounds)
        let v = reachLength(d, maxDist: reach, gain: gain)
        return CGPoint(x: pin.x + dir.x * v, y: pin.y + dir.y * v)
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

    /// Capture with hysteresis on both the dead zone and the role boundaries.
    /// `current` stays captured until the pointer is clearly closer (in angle) to
    /// another role, or drops inside `deadZoneExit`.
    public static func capture(
        pin: CGPoint,
        pointer: CGPoint,
        available: [CompassRole],
        current: CompassRole?
    ) -> CompassRole? {
        let held = current.flatMap { available.contains($0) ? $0 : nil }
        let dist = distance(pin, pointer)
        if dist < (held == nil ? deadZone : deadZoneExit) { return nil }

        let ang = angle(from: pin, to: pointer)
        guard let nearest = nearestRole(angle: ang, available: available) else { return nil }

        if let held, held != nearest {
            let heldDelta = abs(shortestAngleDelta(held.angle, ang))
            let nearestDelta = abs(shortestAngleDelta(nearest.angle, ang))
            if heldDelta - nearestDelta < 2 * hysteresisAngle {
                return held
            }
        }
        return nearest
    }

    public static func lobeCenter(pin: CGPoint, role: CompassRole) -> CGPoint {
        let u = role.unit
        return CGPoint(x: pin.x + u.x * lobeDistance, y: pin.y + u.y * lobeDistance)
    }

    /// Role at release. Pass the currently captured role so release matches what the
    /// user saw highlighted (hysteresis included).
    public static func roleAtRelease(
        pin: CGPoint,
        pointer: CGPoint,
        available: [CompassRole],
        current: CompassRole? = nil
    ) -> CompassRole? {
        capture(pin: pin, pointer: pointer, available: available, current: current)
    }

    /// Frame-rate independent per-step damping: `perFrame` is the retention at 60 fps.
    public static func damping(_ perFrame: CGFloat, dt: CGFloat) -> CGFloat {
        pow(perFrame, dt * 60)
    }

    /// Frame-rate independent exponential smoothing weight for `perFrame` retention at 60 fps.
    public static func smoothingAlpha(retain perFrame: CGFloat, dt: CGFloat) -> CGFloat {
        1 - pow(perFrame, dt * 60)
    }
}
