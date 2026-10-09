import CoreGraphics
import Foundation

/// Presenter mode: press and hold, then drag out past a radius in one of 4 or 8 directions. The direction picks a
/// visual (rather than an action); dragging a little further brings it to life between the two points.
/// Directions are in AppKit view space (y up), numbered clockwise from north.
public enum PresenterMath {
    public static let names8 = ["North", "North-East", "East", "South-East", "South", "South-West", "West", "North-West"]

    /// The slots used with 4 directions are 0 (N), 2 (E), 4 (S), 6 (W) of the 8.
    public static func slotIndices(count: Int) -> [Int] { count == 4 ? [0, 2, 4, 6] : Array(0..<8) }

    /// Default visuals, by preset id, for the 8 directions (N, NE, E, SE, S, SW, W, NW).
    public static let defaultSlots = ["toy-train", "callout-arrow", "laser-pointer", "highlighter", "neon-lasso", "target-lock", "wave-motion", "stage-spotlight"]

    /// Angle of a sector's centre (radians, y-up, counter-clockwise from +x) for a clockwise-from-north index.
    public static func centerAngle(index: Int, count: Int) -> CGFloat {
        .pi / 2 - CGFloat(index) * 2 * .pi / CGFloat(count)
    }

    private static func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return abs(d)
    }

    /// The armed sector (0..<count), or nil while the pointer is inside the radius. Once armed, a sector sticks until the
    /// pointer is clearly in another one (a little hysteresis), and releases when it falls well back inside the radius.
    public static func capture(pin: CGPoint, pointer: CGPoint, count: Int, radius: CGFloat, current: Int?) -> Int? {
        let dx = pointer.x - pin.x, dy = pointer.y - pin.y
        let dist = hypot(dx, dy)
        if dist < radius * (current == nil ? 1 : 0.72) { return nil }
        let theta = atan2(dy, dx)
        let step = 2 * .pi / CGFloat(count)
        if let cur = current, angularDistance(theta, centerAngle(index: cur, count: count)) < step / 2 + 0.16 { return cur }
        var idx = Int(((.pi / 2 - theta) / step).rounded())
        idx = ((idx % count) + count) % count
        return idx
    }

    /// Dragging this far past the radius brings the visual to life.
    public static let engageMargin: CGFloat = 26
    public static func isEngaged(pin: CGPoint, pointer: CGPoint, radius: CGFloat, wasEngaged: Bool) -> Bool {
        let d = hypot(pointer.x - pin.x, pointer.y - pin.y)
        return d > radius + (wasEngaged ? engageMargin * 0.4 : engageMargin)
    }

    /// The selection state across a whole gesture.
    public struct Selection: Equatable, Sendable {
        public var index: Int?
        public var engaged: Bool
        public init(index: Int? = nil, engaged: Bool = false) { self.index = index; self.engaged = engaged }
    }

    /// One pointer move. The first time the pointer leaves the radius it picks a direction, and that choice is then
    /// locked until the gesture ends: moving to another direction, or back inside the ring, changes nothing. Dragging a
    /// little further brings the chosen visual to life, and once alive it stays alive.
    public static func advance(_ s: Selection, pin: CGPoint, pointer: CGPoint, count: Int, radius: CGFloat) -> Selection {
        var out = s
        if out.index == nil {
            out.index = capture(pin: pin, pointer: pointer, count: count, radius: radius, current: nil)
        }
        if out.index != nil, !out.engaged {
            out.engaged = isEngaged(pin: pin, pointer: pointer, radius: radius, wasEngaged: false)
        }
        return out
    }

    /// Parse a stored comma-separated slot list into exactly 8 ids, falling back to the defaults for blanks.
    public static func parseSlots(_ s: String?) -> [String] {
        let parts = (s ?? "").split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        return (0..<8).map { i in i < parts.count && !parts[i].isEmpty ? parts[i] : defaultSlots[i] }
    }
}
