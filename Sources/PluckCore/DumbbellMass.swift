import CoreGraphics
import Foundation

/// The shape of a stretched liquid: two round bulbs (the pin and the head) joined by a thin thread, with smooth
/// concave blends (menisci) where the thread meets each bulb. Volume is conserved: as the thread lengthens and
/// carries more liquid, the bulbs shrink. At rest the two bulbs coincide as one round drop.
///
/// This replaces the earlier heuristic taper (a straight cone, which read as a stick) with the silhouette real
/// stretched liquids have: round ends, a waist, and concave curves between them.
public enum DumbbellMass {
    public struct Solution: Equatable, Sendable {
        public var pin: CGFloat
        public var head: CGFloat
        public var waist: CGFloat
    }

    public struct Params: Equatable, Sendable {
        /// Radius of the drop at rest (points).
        public var restRadius: CGFloat
        /// Thread radius at rest, as a fraction of the rest radius (thicker = gloopier, thinner = more delicate).
        public var waistRest: CGFloat
        /// Fraction of the bulb mass that goes to the head (the pin keeps the rest).
        public var headShare: CGFloat
        /// How far the concave blend reaches along the thread, as a fraction of the bulb radius.
        public var meniscus: CGFloat

        public init(restRadius: CGFloat = 56, waistRest: CGFloat = 0.20, headShare: CGFloat = 0.40, meniscus: CGFloat = 0.85) {
            self.restRadius = restRadius
            self.waistRest = waistRest
            self.headShare = headShare
            self.meniscus = meniscus
        }
    }

    /// Smallest thread radius we ever draw (points): thin, but always visible.
    public static let minWaist: CGFloat = 3.0

    private static func smooth(_ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        return t * t * (3 - 2 * t)
    }

    /// Bulb radii and thread radius for a thread of arc length `length`.
    public static func solve(_ p: Params, length: CGFloat) -> Solution {
        let R0 = max(1, p.restRadius)
        let L = max(0, length)
        let area0 = .pi * R0 * R0

        // Thread thins as it lengthens (it is being drawn out), but never below a visible floor.
        let waist = max(minWaist, p.waistRest * R0 / CGFloat(sqrt(Double(1 + L / (1.6 * R0)))))
        let threadArea = 2 * waist * L
        // The bulbs keep whatever the thread doesn't hold, never less than 18% of the whole.
        let bulbArea = max(0.18 * area0, area0 - threadArea)
        let hs = max(0.1, min(0.9, p.headShare))
        let pinFull = (bulbArea * (1 - hs) / .pi).squareRoot()
        let headFull = (bulbArea * hs / .pi).squareRoot()

        // At rest the two coincide as one drop of radius R0; they separate as the thread lengthens.
        let split = smooth(L / (1.4 * R0))
        return Solution(
            pin: R0 + (pinFull - R0) * split,
            head: R0 + (headFull - R0) * split,
            waist: waist
        )
    }

    /// Thickness along the thread at `samples` evenly spaced points from pin (0) to head (1): the waist plus a
    /// concave flare toward each bulb. The flare is what makes the join read as liquid meeting liquid.
    public static func profile(_ p: Params, length: CGFloat, samples n: Int) -> (radii: [CGFloat], solution: Solution) {
        let sol = solve(p, length: length)
        let count = max(2, n)
        let L = max(1, length)
        let m = max(0.2, p.meniscus)
        func flare(_ u: CGFloat, _ bulb: CGFloat) -> CGFloat {
            let x = u / max(1, bulb * m)
            let q = 1 + x * x
            return 1 / (q * q)    // 1 at the bulb, falling smoothly: a concave, hyperbola-like blend
        }
        var radii = [CGFloat]()
        radii.reserveCapacity(count)
        for i in 0..<count {
            let s = CGFloat(i) / CGFloat(count - 1)
            let u = s * L
            let r = sol.waist
                + (sol.pin - sol.waist) * flare(u, sol.pin)
                + (sol.head - sol.waist) * flare(L - u, sol.head)
            radii.append(max(sol.waist, r))
        }
        return (radii, sol)
    }
}
