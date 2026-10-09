import CoreGraphics
import Foundation

/// Underdamped spring used for the release snap-back. Pure math so it can be unit-tested.
public enum RecoilSpring {
    /// Damping ratio for a 0…1 "bounce" knob: 0 = tight (ζ≈0.72), 1 = very wobbly (ζ≈0.22).
    public static func zeta(bounce: CGFloat) -> CGFloat {
        0.72 - 0.5 * min(1, max(0, bounce))
    }

    /// Angular frequency for a given oscillation period (seconds).
    public static func omega(period: CGFloat) -> CGFloat {
        2 * .pi / max(0.05, period)
    }

    /// One semi-implicit Euler step of x'' = -ω²x - 2ζω x' toward the origin.
    public static func step(
        x: inout CGPoint,
        v: inout CGPoint,
        omega: CGFloat,
        zeta: CGFloat,
        h: CGFloat
    ) {
        let ax = -omega * omega * x.x - 2 * zeta * omega * v.x
        let ay = -omega * omega * x.y - 2 * zeta * omega * v.y
        v.x += ax * h
        v.y += ay * h
        x.x += v.x * h
        x.y += v.y * h
    }
}
