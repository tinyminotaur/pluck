import CoreGraphics
import Foundation

/// What the head does when you let go, based on what the thing is.
public enum ReleaseBehavior: Sendable {
    /// Snaps back like rubber or liquid: an underdamped spring that overshoots (the bounce knob applies).
    case spring
    /// Reeled or drawn smoothly back with no overshoot (a fishing line, a tentacle, a kite string).
    case ease
    /// Stays exactly where it is while the style plays its own exit: bursting, fading, flying off, firing.
    case stay
}

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
    case stars
    case kite
    case bubbles
    case beam
    case lightning
    case magnet
    case slinky
    case tincan
    case thread
    case pingpong
    case bridge
    case planes
    case water
    case train
    case equalizer
    case dna
    case fishing
    case ribbon
    case tugofwar
    case cradle
    case rainbow
    case dandelion
    case cablecar
    case signal
    case lasso
    case laser
    case marker
    case spotlight
    case callout
    case targetlock
    case marquee
    case jelly
    case freehand
    case yarn
    case pack

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
        case .stars: return "Stars"
        case .kite: return "Kite"
        case .bubbles: return "Soap Bubbles"
        case .beam: return "Energy Beam"
        case .lightning: return "Lightning"
        case .magnet: return "Magnet"
        case .slinky: return "Slinky"
        case .tincan: return "Tin-Can Phone"
        case .thread: return "Red Thread"
        case .pingpong: return "Ping-Pong"
        case .bridge: return "Rope Bridge"
        case .planes: return "Paper Planes"
        case .water: return "Water Arc"
        case .train: return "Toy Train"
        case .equalizer: return "Equalizer"
        case .dna: return "DNA"
        case .fishing: return "Fishing"
        case .ribbon: return "Ribbon Dance"
        case .tugofwar: return "Tug of War"
        case .cradle: return "Newton's Cradle"
        case .rainbow: return "Rainbow"
        case .dandelion: return "Dandelion"
        case .cablecar: return "Cable Car"
        case .signal: return "Signal"
        case .lasso: return "Lasso"
        case .laser: return "Laser Pointer"
        case .marker: return "Highlighter"
        case .spotlight: return "Spotlight"
        case .callout: return "Callout Arrow"
        case .targetlock: return "Target Lock"
        case .marquee: return "Marquee"
        case .jelly: return "Jelly Select"
        case .freehand: return "Freehand Lasso"
        case .yarn: return "Ball of Thread"
        case .pack: return "Community"
        }
    }

    /// How the head moves on release. Most styles are not elastic, so they stay put and play their own finale.
    public var releaseBehavior: ReleaseBehavior {
        switch self {
        case .liquid, .ferro, .slinky: return .spring
        case .tendrils, .fishing, .kite: return .ease
        default: return .stay
        }
    }

    /// Drawn with hand-made vector sprites instead of the glass shader.
    public var isVector: Bool { self == .swarm || self == .jumprope || self == .stars || self == .kite || self == .bubbles || self == .beam || self == .lightning || self == .magnet || self == .slinky || self == .tincan || self == .thread || self == .pingpong || self == .bridge || self == .planes || self == .water || self == .train || self == .equalizer || self == .dna || self == .fishing || self == .ribbon || self == .tugofwar || self == .cradle || self == .rainbow || self == .dandelion || self == .cablecar || self == .signal || self == .lasso || self == .laser || self == .marker || self == .spotlight || self == .callout || self == .targetlock || self == .marquee || self == .jelly || self == .freehand || self == .yarn || self == .pack }

    public var tagline: String {
        switch self {
        case .liquid: return "Stretchy liquid with a pinch-off"
        case .ferro: return "Spikes bristle toward the magnet; iron filings string the field"
        case .crystal: return "A crystal grows toward you, branching and evolving; it shatters on commit"
        case .gravity: return "Two bodies: the heavy pin pulls harder, grains orbit and stream between them"
        case .pearls: return "A beaded necklace on rope physics: it sags, swings and flings its pearls"
        case .swarm: return "Soft twinkling glow-wisps drift between two bright lights, trailing sparkles"
        case .tendrils: return "Tentacles reach for the cursor, undulating and tapering to fine tips"
        case .jumprope: return "A papercraft scene: a bunny hops a striped paper rope at the middle of the span"
        case .stars: return "A constellation draws itself between two guiding stars; commit sends a shooting star"
        case .kite: return "A paper kite on a long string with a ribbon tail, flying from a wooden reel"
        case .bubbles: return "Iridescent soap bubbles drift between two big ones, then pop"
        case .beam: return "Charge an energy ball, pull, and a wave-motion beam blasts out; commit fires it"
        case .lightning: return "Two terminals and a crackling arc that forks and flickers between them; commit discharges it"
        case .magnet: return "Field lines stream from a heavy north pole to a light south pole; the surplus bows away"
        case .slinky: return "A rainbow spring, wide at the heavy end and narrow at the light one, with a wave running along it"
        case .tincan: return "Two tin cans on a taut string take turns talking; notes travel along it"
        case .thread: return "A red thread of fate between two beating hearts, with little hearts drifting along it"
        case .pingpong: return "A glowing ball rallies between two paddles, trailing light"
        case .bridge: return "A little traveller paces a swaying plank bridge between the two posts"
        case .planes: return "Folded paper planes loop and glide from one point to the other"
        case .water: return "A jet arcs from one flask to the other; the water levels are the mass"
        case .train: return "A toy train shuttles between two stations, puffing smoke"
        case .equalizer: return "Two speakers and a row of dancing bars; the heavy end carries the bass"
        case .dna: return "A rotating double helix with colour-paired rungs"
        case .fishing: return "A rod, a bobbing float and a fish that sometimes leaps"
        case .ribbon: return "A long ribbon twirls and curls between the two points"
        case .tugofwar: return "Two critters pull a rope; the flag drifts toward whoever is heavier"
        case .cradle: return "Steel balls click back and forth on a little frame"
        case .rainbow: return "A rainbow arcs between two fluffy clouds"
        case .dandelion: return "Seeds drift off the puffball and sprout at the other end"
        case .cablecar: return "A little gondola glides between two towers"
        case .signal: return "Two stations trade waves and data packets"
        case .lasso: return "A neon rope ends in a spinning loop that cinches shut around the target"
        case .laser: return "A glowing red dot with a comet trail and a little sparkle"
        case .marker: return "A neon marker stroke that follows your path and dries away"
        case .spotlight: return "A stage light dims the screen and pools light on the target"
        case .callout: return "A hand-drawn stop-motion arrow and a scribbled circle"
        case .targetlock: return "A viewfinder HUD closes in and locks on, with a live readout"
        case .marquee: return "A lively desktop-style selection rectangle with marching ants"
        case .jelly: return "An organic selection bubble with real spring physics"
        case .freehand: return "Draws your path and closes it into a glowing selection"
        case .yarn: return "A ball of thread unspools toward you and ends in a lasso loop; let go and it is thrown, cinches shut, and winds back"
        case .pack: return "Animations made and shared by the community"
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
