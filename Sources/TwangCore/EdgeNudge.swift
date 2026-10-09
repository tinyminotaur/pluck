import CoreGraphics

/// Keeps the grab point far enough from a screen edge that every direction is reachable.
///
/// The pointer physically stops at the screen edge, so a gesture that starts on the edge can never
/// pull outward past the dead zone. Nudging the pin inward fixes that without changing any slice.
public enum EdgeNudge {
    /// Clearance from each edge: dead zone plus comfortable travel.
    public static let defaultMargin: CGFloat = 72

    public static func inset(_ p: CGPoint, in frame: CGRect, margin: CGFloat = defaultMargin) -> CGPoint {
        CGPoint(x: clamp(p.x, frame.minX, frame.maxX, margin), y: clamp(p.y, frame.minY, frame.maxY, margin))
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat, _ margin: CGFloat) -> CGFloat {
        // Tiny screens: just center.
        if hi - lo <= margin * 2 { return (lo + hi) / 2 }
        return min(hi - margin, max(lo + margin, v))
    }
}
