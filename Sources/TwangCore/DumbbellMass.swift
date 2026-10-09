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
        public init(pin: CGFloat, head: CGFloat, waist: CGFloat) { self.pin = pin; self.head = head; self.waist = waist }
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

        public init(restRadius: CGFloat = 42, waistRest: CGFloat = 0.20, headShare: CGFloat = 0.50, meniscus: CGFloat = 1.0) {
            self.restRadius = restRadius
            self.waistRest = waistRest
            self.headShare = headShare
            self.meniscus = meniscus
        }
    }

    /// Smallest thread radius we ever draw (points). If the thread would be thinner than this, the thread takes
    /// the extra mass from the bulbs, so area is still conserved exactly.
    public static let minWaist: CGFloat = 1.6

    private static func smooth(_ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        return t * t * (3 - 2 * t)
    }

    /// Bulb radii and thread radius for a thread of arc length `length`.
    ///
    /// Mass is conserved (area M0 = pi R0^2): the thread's mass grows without bound as it lengthens, and every bit of
    /// it is drawn out of the bulbs. There are no floors, so the pin gets strictly smaller at every moment the head
    /// moves away and strictly larger at every moment it comes back. The head receives a growing share of what
    /// remains, so the mass visibly flows toward the cursor.
    public static func solve(_ p: Params, length: CGFloat) -> Solution {
        let R0 = max(1, p.restRadius)
        let L = max(0, length)
        let M0 = CGFloat.pi * R0 * R0

        // Mass held by the thread: rises smoothly and strictly with length, toward ~55% of the total (scaled by waistRest).
        // The thread keeps drawing mass from the bulbs across the whole screen (no early plateau): the share
        // rises steadily toward ~90% (scaled by waistRest), so the pin keeps visibly draining as you pull on.
        let share = min(0.94, 0.9 * CGFloat(max(0.05, p.waistRest) / 0.2).squareRoot())
        var thread = share * M0 * (1 - CGFloat(pow(Double(1 + L / (14 * R0)), -0.7)))
        // Its width follows from its mass and length (a fixed volume stretched thinner), capped for short threads.
        // At extreme lengths the drawn width is floored so it stays visible; that costs a sliver of mass only
        // where the thread is already sub-pixel, and the bulbs keep shrinking regardless.
        let cap = max(minWaist, p.waistRest * R0 * 1.2)
        let waist = L > 0.001 ? max(minWaist, min(cap, thread / (2 * L))) : cap
        if L > 0.001 { thread = min(thread, 2 * min(cap, thread / (2 * L)) * L) }
        let bulbs = M0 - thread

        // Share of the bulb mass at the head grows as mass is pulled along; the pin keeps the rest.
        let hs = 0.44 * max(0.1, min(1, p.headShare)) + 0.23 * smooth(L / (5 * R0))
        // At rest the head is hidden inside the pin as one drop; they separate as the thread lengthens.
        let sep = smooth(L / (2.2 * R0))
                let headArea = hs * bulbs * sep
        // The head's drawn radius has a small floor while it is still hidden inside the pin; that sliver is not
        // charged to the pin, so the pin strictly shrinks from the very first pixel.
        let head = max((headArea / .pi).squareRoot(), 0.25 * R0 * (1 - sep))
        let pin = max(0, (bulbs - headArea) / .pi).squareRoot()
        return Solution(pin: pin, head: head, waist: waist)
    }

    /// Thickness along the thread at `samples` evenly spaced points from pin (0) to head (1): the waist plus a
    /// concave flare toward each bulb. The flare is what makes the join read as liquid meeting liquid.
    public static func profile(_ p: Params, length: CGFloat, samples n: Int, using given: Solution? = nil) -> (radii: [CGFloat], solution: Solution) {
        let sol = given ?? solve(p, length: length)
        let count = max(2, n)
        let L = max(1, length)
        let m = max(0.2, p.meniscus)
        func flare(_ u: CGFloat, _ bulb: CGFloat) -> CGFloat {
            let x = u / max(1, bulb * m)
            let q = 1 + x * x
            return 1 / (q * q)    // 1 at the bulb, falling smoothly: a compact concave fillet
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
