import CoreGraphics
import Foundation

/// How the gesture is drawn and how it responds to movement. Independent of colour themes and feel presets:
/// every style shares the same triggers, gesture logic, labels and palettes.
public enum AnimationStyle: String, Codable, CaseIterable, Sendable {
    case liquid
    case ferro
    case crystal
    case gravity
    case pearls
    case swarm
    case tendrils
    case jumprope

    public var name: String {
        switch self {
        case .liquid: return "Liquid"
        case .ferro: return "Ferrofluid"
        case .crystal: return "Crystal"
        case .gravity: return "Gravity"
        case .pearls: return "Pearls"
        case .swarm: return "Fireflies"
        case .tendrils: return "Tendrils"
        case .jumprope: return "Jump Rope"
        }
    }

    /// Drawn with hand-made vector sprites instead of the glass shader.
    public var isVector: Bool { self == .swarm || self == .jumprope }

    public var tagline: String {
        switch self {
        case .liquid: return "Stretchy liquid with a pinch-off"
        case .ferro: return "Spikes bristle toward the magnet; iron filings string the field"
        case .crystal: return "A crystal grows toward you, branching and evolving; it shatters on commit"
        case .gravity: return "Two bodies: the heavy pin pulls harder, grains orbit and stream between them"
        case .pearls: return "A beaded necklace on rope physics: it sags, swings and flings its pearls"
        case .swarm: return "Real fireflies with flapping wings and glowing lanterns drift between two jar lights"
        case .tendrils: return "Tentacles reach for the cursor, undulating and tapering to fine tips"
        case .jumprope: return "A papercraft scene: a bunny hops a striped paper rope at the middle of the span"
        }
    }
}

/// One shape for the shape-list renderer (used by the ferrofluid and crystal styles).
public struct ShapePrim: Equatable, Sendable {
    public enum Kind: Int, Sendable {
        /// Circle of radius `ra` at `a`.
        case circle = 0
        /// Tapered round cone from `a` (radius `ra`) to `b` (radius `rb`): a ferrofluid spike.
        case cone = 1
        /// Crystal: an elongated prism from base `a` to tip `b`, half-width `ra`, pointed over the last `rb` (fraction) of its length.
        case shard = 2
    }

    /// How the shape merges with others: hard union, smooth blend, or a tight blend.
    public enum Blend: Int, Sendable { case hard = 0, soft = 1, tight = 2 }

    public var kind: Kind
    public var a: CGPoint
    public var b: CGPoint
    public var ra: CGFloat
    public var rb: CGFloat
    public var blend: Blend
    /// 0...1 glow (a growing tip, an armed head).
    public var emphasis: CGFloat
    /// Stable per-shape random value (crystal facet tilt and colour).
    public var seed: CGFloat

    public init(kind: Kind, a: CGPoint, b: CGPoint = .zero, ra: CGFloat, rb: CGFloat = 0,
                blend: Blend = .hard, emphasis: CGFloat = 0, seed: CGFloat = 0) {
        self.kind = kind; self.a = a; self.b = b; self.ra = ra; self.rb = rb
        self.blend = blend; self.emphasis = emphasis; self.seed = seed
    }

    /// Conservative bounds, for sizing the render target.
    public var bounds: CGRect {
        switch kind {
        case .circle:
            return CGRect(x: a.x - ra, y: a.y - ra, width: ra * 2, height: ra * 2)
        case .cone:
            let r = max(ra, rb)
            return CGRect(x: min(a.x, b.x) - r, y: min(a.y, b.y) - r, width: abs(a.x - b.x) + 2 * r, height: abs(a.y - b.y) + 2 * r)
        case .shard:
            let r = ra
            return CGRect(x: min(a.x, b.x) - r, y: min(a.y, b.y) - r, width: abs(a.x - b.x) + 2 * r, height: abs(a.y - b.y) + 2 * r)
        }
    }
}

/// Small deterministic hash used by the style simulations.
enum StyleHash {
    static func unit(_ i: Int, _ salt: Int = 0) -> CGFloat {
        var x = UInt64(truncatingIfNeeded: i &* 0x9E37_79B1 &+ salt &* 0x85EB_CA6B &+ 0x27D4_EB2F)
        x ^= x >> 15; x = x &* 0x2C1B_3C6D
        x ^= x >> 12; x = x &* 0x297A_2D39
        x ^= x >> 15
        return CGFloat(Double(x & 0xFFFFFF) / Double(0x1000000))
    }

    static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - a) / max(1e-6, b - a)))
        return t * t * (3 - 2 * t)
    }
}
