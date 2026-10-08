import CoreGraphics
import Foundation

/// Turns the physics chain (a handful of particles joined by straight tapered segments, which read as
/// angular and faceted) into a smooth, natural strand: a Catmull-Rom curve through the particles with
/// smoothly varying thickness.
public enum StrandSmoothing {
    /// A few passes of [1 2 1]/4 on the thickness profile (ends held), so the taper has no kinks.
    public static func smoothRadii(_ r: [CGFloat], passes: Int) -> [CGFloat] {
        guard r.count > 2, passes > 0 else { return r }
        var out = r
        for _ in 0..<passes {
            var next = out
            for i in 1..<(out.count - 1) {
                next[i] = (out[i - 1] + 2 * out[i] + out[i + 1]) * 0.25
            }
            out = next
        }
        return out
    }

    /// Resample with `subdivisions` points per original segment. Endpoints are preserved exactly, so the
    /// strand still starts at the pin and ends at the head. Count is `(n - 1) * subdivisions + 1`.
    public static func resample(
        points: [CGPoint],
        radii: [CGFloat],
        subdivisions: Int
    ) -> (points: [CGPoint], radii: [CGFloat]) {
        let n = points.count
        guard n >= 3, radii.count == n, subdivisions > 1 else { return (points, radii) }
        var outP: [CGPoint] = []
        var outR: [CGFloat] = []
        outP.reserveCapacity((n - 1) * subdivisions + 1)
        outR.reserveCapacity((n - 1) * subdivisions + 1)

        func p(_ i: Int) -> CGPoint { points[max(0, min(n - 1, i))] }
        func r(_ i: Int) -> CGFloat { radii[max(0, min(n - 1, i))] }

        for i in 0..<(n - 1) {
            let p0 = p(i - 1), p1 = p(i), p2 = p(i + 1), p3 = p(i + 2)
            let r0 = r(i - 1), r1 = r(i), r2 = r(i + 1), r3 = r(i + 2)
            let lo = min(r1, r2) * 0.85
            let hi = max(r1, r2) * 1.15
            for s in 0..<subdivisions {
                let t = CGFloat(s) / CGFloat(subdivisions)
                outP.append(CGPoint(x: spline(p0.x, p1.x, p2.x, p3.x, t), y: spline(p0.y, p1.y, p2.y, p3.y, t)))
                // Thickness follows the same spline but never overshoots its neighbours (no beads or pinches).
                outR.append(max(lo, min(hi, spline(r0, r1, r2, r3, t))))
            }
        }
        outP.append(points[n - 1])
        outR.append(radii[n - 1])
        return (outP, outR)
    }

    private static func spline(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ t: CGFloat) -> CGFloat {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
    }
}

/// Debounces the three-finger release. Contact counts flicker while fingers move, so dropping below three
/// for an instant must not end the gesture. Lifting every finger releases immediately.
public struct TouchReleaseDebounce: Sendable {
    public var grace: Double
    private var belowSince: Double?
    private var count = 3

    public init(grace: Double = 0.18) { self.grace = grace }

    public mutating func reset() { belowSince = nil; count = 3 }

    public mutating func update(count n: Int, at t: Double) {
        count = n
        if n >= 3 { belowSince = nil } else if belowSince == nil { belowSince = t }
    }

    public func shouldRelease(at t: Double) -> Bool {
        if count == 0 { return true }
        guard let b = belowSince else { return false }
        return t - b >= grace
    }
}
