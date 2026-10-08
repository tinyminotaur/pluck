import CoreGraphics
import Foundation

/// Water is never one perfect disc. The pin and the head are each a small cluster of overlapping lumps
/// of different sizes that drift slowly around their centre (and jiggle with inertia), so the silhouette
/// is lopsided and always changing. Pure and seeded, so it is testable and every gesture gets its own shape.
public struct BlobLumpSpec: Equatable, Sendable {
    /// Starting angle and slow orbital speed (rad/s, signed) around the cluster centre.
    public var angle0: CGFloat
    public var orbit: CGFloat
    /// Distance from the centre and size, as fractions of the base radius.
    public var dist: CGFloat
    public var size: CGFloat
    /// Breathing phase, and the jiggle spring (each lump wobbles at its own pace).
    public var phase: CGFloat
    public var omega: CGFloat
    public var zeta: CGFloat
}

public enum BlobLumps {
    public static func specs(seed: UInt64, count: Int) -> [BlobLumpSpec] {
        var rng = SplitMix64(seed: seed)
        return (0..<max(0, count)).map { i in
            // Spread the starting angles but jitter them so the arrangement is never regular.
            let base = CGFloat(i) / CGFloat(max(1, count)) * 2 * .pi
            let jitter = (rng.unit() - 0.5) * 1.4
            let dir: CGFloat = rng.unit() < 0.5 ? -1 : 1
            return BlobLumpSpec(
                angle0: base + jitter,
                orbit: dir * (0.12 + rng.unit() * 0.38),
                dist: 0.30 + rng.unit() * 0.42,
                size: 0.46 + rng.unit() * 0.34,
                phase: rng.unit() * 2 * .pi,
                omega: 9 + rng.unit() * 8,
                zeta: 0.20 + rng.unit() * 0.16
            )
        }
    }

    /// Where a lump sits at `time`, given the cluster centre/radius and its current jiggle offset.
    public static func place(
        _ s: BlobLumpSpec,
        center: CGPoint,
        baseRadius: CGFloat,
        time: CGFloat,
        jiggle: CGPoint = .zero
    ) -> (center: CGPoint, radius: CGFloat) {
        let a = s.angle0 + s.orbit * time
        // The distance and size breathe slowly and out of step, so nothing ever repeats exactly.
        let d = s.dist * (1 + 0.16 * CGFloat(sin(Double(time * 0.7 + s.phase))))
        let r = s.size * (1 + 0.10 * CGFloat(sin(Double(time * 1.3 + s.phase * 1.7))))
        return (
            CGPoint(
                x: center.x + CGFloat(cos(Double(a))) * d * baseRadius + jiggle.x,
                y: center.y + CGFloat(sin(Double(a))) * d * baseRadius + jiggle.y
            ),
            r * baseRadius
        )
    }
}

struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> CGFloat {
        CGFloat(Double(next() >> 11) / Double(1 << 53))
    }
}
