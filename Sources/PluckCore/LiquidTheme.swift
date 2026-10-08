import Foundation

public struct RGB: Codable, Equatable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float
    public init(_ r: Float, _ g: Float, _ b: Float) { self.r = r; self.g = g; self.b = b }

    public func mixed(with o: RGB, _ t: Float) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }

    /// A displayable colour (0...1.5 allows slightly over-bright stops).
    public var isValid: Bool { isWithin(0, 1.5) }

    public func isWithin(_ lo: Float, _ hi: Float) -> Bool {
        [r, g, b].allSatisfy { $0.isFinite && $0 >= lo && $0 <= hi }
    }
}

/// A colour style for the liquid. Three colours cycle across the surface (a gradient that drifts slowly and, for
/// iridescent themes, shifts with the surface tilt); the body, absorption and glow set the material.
public struct LiquidTheme: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var tagline: String
    /// The three palette stops that cycle A → B → C → A across the surface.
    public var a: RGB
    public var b: RGB
    public var c: RGB
    /// Body colour of the glass itself (near black for obsidian, light for mercury).
    public var body: RGB
    /// Per-channel absorption (at the default depth): thick glass eats the high channels first.
    public var absorb: RGB
    /// Strength of the slow pulsing glow, soft sheen reflection, and edge rim.
    public var ember: Float
    public var sheen: Float
    public var rim: Float
    /// Gradient size (points per full cycle), drift speed (cycles per second), and tilt-driven iridescence.
    public var gradientScale: Float
    public var gradientSpeed: Float
    public var iridescence: Float
    /// Soft glow of the palette colour from within the glass (0 = colour only at the thin rim).
    public var fill: Float
    /// 0...1 mirror-like reflection of a bright studio environment (1 = chrome).
    public var chrome: Float

    /// The palette at `t` (cycles). Mirrors the shader exactly so tests can check continuity.
    public func color(at t: Float) -> RGB {
        var x = t - floor(t)
        x *= 3
        func smooth(_ v: Float) -> Float { v * v * (3 - 2 * v) }
        if x < 1 { return a.mixed(with: b, smooth(x)) }
        if x < 2 { return b.mixed(with: c, smooth(x - 1)) }
        return c.mixed(with: a, smooth(x - 2))
    }

    public var isValid: Bool {
        [a, b, c, body].allSatisfy(\.isValid) && absorb.isWithin(0, 8) && ember >= 0 && sheen >= 0 && rim >= 0
            && gradientScale > 1 && fill >= 0 && fill <= 1.5 && chrome >= 0 && chrome <= 1 && !id.isEmpty && !name.isEmpty
    }
}

public enum ThemeLibrary {
    public static let obsidianEmber = LiquidTheme(
        id: "obsidian-ember", name: "Obsidian Ember", tagline: "Black glass with an amber heartbeat",
        a: RGB(1.00, 0.50, 0.10), b: RGB(0.85, 0.25, 0.04), c: RGB(1.00, 0.68, 0.20),
        body: RGB(0.035, 0.028, 0.024), absorb: RGB(1.45, 2.8, 4.25),
        ember: 0.55, sheen: 1.0, rim: 1.0, gradientScale: 260, gradientSpeed: 0.02, iridescence: 0, fill: 0.1, chrome: 0
    )
    public static let oilSlick = LiquidTheme(
        id: "oil-slick", name: "Oil Slick", tagline: "Black with a magenta, teal and gold sheen",
        a: RGB(0.95, 0.20, 0.65), b: RGB(0.10, 0.80, 0.75), c: RGB(0.95, 0.75, 0.15),
        body: RGB(0.020, 0.022, 0.030), absorb: RGB(2.0, 2.2, 2.0),
        ember: 0.45, sheen: 1.2, rim: 1.6, gradientScale: 230, gradientSpeed: 0.04, iridescence: 1.2, fill: 0.22, chrome: 0
    )
    public static let aurora = LiquidTheme(
        id: "aurora", name: "Aurora", tagline: "Green, cyan and violet light in deep night",
        a: RGB(0.15, 0.95, 0.55), b: RGB(0.15, 0.75, 0.95), c: RGB(0.60, 0.30, 0.95),
        body: RGB(0.015, 0.025, 0.040), absorb: RGB(2.6, 1.6, 1.2),
        ember: 0.60, sheen: 0.9, rim: 1.2, gradientScale: 220, gradientSpeed: 0.04, iridescence: 0.5, fill: 0.3, chrome: 0
    )
    public static let moltenGold = LiquidTheme(
        id: "molten-gold", name: "Molten Gold", tagline: "Liquid metal glowing gold to red",
        a: RGB(1.00, 0.78, 0.20), b: RGB(1.00, 0.45, 0.08), c: RGB(0.90, 0.20, 0.05),
        body: RGB(0.040, 0.030, 0.020), absorb: RGB(1.2, 2.4, 4.2),
        ember: 0.85, sheen: 1.4, rim: 1.1, gradientScale: 300, gradientSpeed: 0.03, iridescence: 0.2, fill: 0.42, chrome: 0
    )
    public static let mercury = LiquidTheme(
        id: "mercury", name: "Mercury", tagline: "Bright chrome, cool silver-blue",
        a: RGB(0.85, 0.90, 1.00), b: RGB(0.70, 0.78, 0.95), c: RGB(0.95, 0.95, 0.98),
        body: RGB(0.30, 0.33, 0.38), absorb: RGB(0.15, 0.15, 0.18),
        ember: 0.05, sheen: 3.2, rim: 0.7, gradientScale: 400, gradientSpeed: 0.01, iridescence: 0.15, fill: 0.0, chrome: 0.9
    )
    public static let neonJelly = LiquidTheme(
        id: "neon-jelly", name: "Neon Jelly", tagline: "Candy pink, cyan and lilac, glowing",
        a: RGB(1.00, 0.25, 0.65), b: RGB(0.20, 0.85, 1.00), c: RGB(0.70, 0.45, 1.00),
        body: RGB(0.10, 0.04, 0.12), absorb: RGB(0.5, 0.9, 0.7),
        ember: 0.90, sheen: 1.3, rim: 1.4, gradientScale: 160, gradientSpeed: 0.07, iridescence: 0.8, fill: 0.55, chrome: 0
    )
    public static let deepSea = LiquidTheme(
        id: "deep-sea", name: "Deep Sea", tagline: "Bioluminescent teal and blue",
        a: RGB(0.05, 0.85, 0.80), b: RGB(0.05, 0.50, 0.85), c: RGB(0.30, 0.95, 0.60),
        body: RGB(0.010, 0.030, 0.045), absorb: RGB(3.2, 1.6, 1.4),
        ember: 0.70, sheen: 0.9, rim: 1.2, gradientScale: 240, gradientSpeed: 0.03, iridescence: 0.3, fill: 0.32, chrome: 0
    )
    public static let sunsetLava = LiquidTheme(
        id: "sunset-lava", name: "Sunset Lava", tagline: "Red, rose and orange, pulsing hot",
        a: RGB(1.00, 0.30, 0.10), b: RGB(0.95, 0.15, 0.35), c: RGB(1.00, 0.60, 0.15),
        body: RGB(0.040, 0.015, 0.015), absorb: RGB(1.0, 3.0, 4.5),
        ember: 1.00, sheen: 1.0, rim: 1.2, gradientScale: 200, gradientSpeed: 0.05, iridescence: 0.4, fill: 0.4, chrome: 0
    )

    public static let mist = LiquidTheme(
        id: "mist", name: "Mist", tagline: "Quiet, clear glass in soft blue and lilac",
        a: RGB(0.58, 0.76, 1.00), b: RGB(0.82, 0.70, 1.00), c: RGB(0.66, 0.90, 0.98),
        body: RGB(0.20, 0.24, 0.32), absorb: RGB(0.55, 0.45, 0.35),
        ember: 0.0, sheen: 1.7, rim: 0.8, gradientScale: 380, gradientSpeed: 0.015, iridescence: 0.25,
        fill: 0.42, chrome: 0.22
    )

    public static let ferrofluid = LiquidTheme(
        id: "ferrofluid", name: "Ferrofluid", tagline: "Mirror-black with cold electric-blue highlights",
        a: RGB(0.45, 0.70, 1.00), b: RGB(0.80, 0.90, 1.00), c: RGB(0.35, 0.45, 0.85),
        body: RGB(0.008, 0.010, 0.016), absorb: RGB(3.0, 3.0, 3.0),
        ember: 0.0, sheen: 2.0, rim: 1.2, gradientScale: 420, gradientSpeed: 0.01, iridescence: 0.2,
        fill: 0.0, chrome: 0.9
    )
    public static let amethyst = LiquidTheme(
        id: "amethyst", name: "Amethyst", tagline: "Violet and rose crystal with bright glints",
        a: RGB(0.65, 0.35, 0.95), b: RGB(0.95, 0.55, 0.95), c: RGB(0.45, 0.30, 0.85),
        body: RGB(0.030, 0.020, 0.050), absorb: RGB(1.0, 2.0, 1.0),
        ember: 0.3, sheen: 1.4, rim: 1.2, gradientScale: 200, gradientSpeed: 0.03, iridescence: 0.5,
        fill: 0.35, chrome: 0
    )
    public static let frost = LiquidTheme(
        id: "frost", name: "Frost", tagline: "Ice-blue and white, cold and sharp",
        a: RGB(0.65, 0.88, 1.00), b: RGB(0.92, 0.98, 1.00), c: RGB(0.45, 0.75, 0.95),
        body: RGB(0.050, 0.080, 0.120), absorb: RGB(2.0, 1.0, 0.6),
        ember: 0.1, sheen: 1.6, rim: 1.4, gradientScale: 260, gradientSpeed: 0.02, iridescence: 0.3,
        fill: 0.40, chrome: 0
    )

    public static let all: [LiquidTheme] = [
        obsidianEmber, mist, oilSlick, aurora, moltenGold, mercury, neonJelly, deepSea, sunsetLava,
        ferrofluid, amethyst, frost,
    ]

    public static func theme(id: String) -> LiquidTheme? { all.first { $0.id == id } }

    /// A fresh, harmonious theme from a seed: a dark glass body tinted toward the hue, with three palette stops
    /// spread around the colour wheel by golden-ratio-ish steps so they always sit well together.
    public static func random(seed: UInt64) -> LiquidTheme {
        var rng = SplitMix64(seed: seed)
        let h0 = Double(rng.unit())
        let spread = 0.22 + Double(rng.unit()) * 0.18
        func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGB {
            let hh = (h - floor(h)) * 6
            let i = Int(hh) % 6
            let f = hh - floor(hh)
            let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
            let (r, g, b): (Double, Double, Double)
            switch i {
            case 0: (r, g, b) = (v, t, p)
            case 1: (r, g, b) = (q, v, p)
            case 2: (r, g, b) = (p, v, t)
            case 3: (r, g, b) = (p, q, v)
            case 4: (r, g, b) = (t, p, v)
            default: (r, g, b) = (v, p, q)
            }
            return RGB(Float(r), Float(g), Float(b))
        }
        let a = hsv(h0, 0.78, 1.0)
        let b = hsv(h0 + spread, 0.82, 0.96)
        let c = hsv(h0 + spread * 2.1, 0.70, 1.0)
        let body = hsv(h0 + 0.5, 0.45, 0.04 + Double(rng.unit()) * 0.03)
        // Absorb the colours opposite the hue most, so thin edges glow in the theme colour.
        let comp = hsv(h0 + 0.5, 1.0, 1.0)
        let absorb = RGB(0.6 + comp.r * 3.2, 0.6 + comp.g * 3.2, 0.6 + comp.b * 3.2)
        return LiquidTheme(
            id: "custom", name: "Surprise", tagline: "A one-off palette",
            a: a, b: b, c: c, body: body, absorb: absorb,
            ember: 0.55 + Float(rng.unit()) * 0.35,
            sheen: 1.0 + Float(rng.unit()) * 0.5,
            rim: 1.0 + Float(rng.unit()) * 0.6,
            gradientScale: 140 + Float(rng.unit()) * 200,
            gradientSpeed: 0.02 + Float(rng.unit()) * 0.05,
            iridescence: Float(rng.unit()) * 1.0,
            fill: 0.25 + Float(rng.unit()) * 0.25,
            chrome: 0
        )
    }
}

/// A named combination of feel knobs and a theme that performs one distinct way. Values are keyed by the
/// Feel Lab knob names; a preset applies on top of `PresetLibrary.baseline`, so switching presets always
/// returns every knob to a known state first.
public struct FeelPreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let tagline: String
    public let themeID: String
    public let values: [String: Double]
    public var style: AnimationStyle = .liquid
}

public enum PresetLibrary {
    /// The shipped defaults for every knob a preset may touch.
    public static let baseline: [String: Double] = [
        "restRadius": 57, "waistRest": 0.20, "headShare": 0.50, "meniscus": 1.0,
        "responsiveness": 0.45, "damping": 0.93, "sloshAmount": 0.7, "whipResponse": 0.7, "particleCount": 16,
        "shininess": 0.95, "fresnel": 0.85, "transmission": 0.7, "absorption": 0.75, "glassOpacity": 0.92,
        "rimStrength": 0.55, "shadowStrength": 0.55, "ember": 1.0,
        "recoilBounce": 0.6, "crystallize": 0.7, "idleLife": 0.5, "flingMomentum": 0.5,
        "reachGain": 1.8, "gravity": 0.6, "magnetPull": 52, "magnetWeight": 0.62, "magnetStick": 0.9,
    ]

    public static let all: [FeelPreset] = [
        FeelPreset(id: "obsidian-ember", name: "Obsidian Ember", tagline: "The default: heavy black glass, amber heartbeat",
                   themeID: "obsidian-ember", values: [:]),
        FeelPreset(id: "minimal-elegant", name: "Minimal & Elegant", tagline: "Calm clear glass; quiet, smooth, no drama",
                   themeID: "mist", values: [
                    "restRadius": 46, "waistRest": 0.16, "headShare": 0.50, "meniscus": 1.1,
                    "gravity": 0.15, "magnetPull": 58, "magnetWeight": 0.7, "magnetStick": 0.8,
                    "sloshAmount": 0.4, "idleLife": 0.35, "recoilBounce": 0.35, "flingMomentum": 0.3,
                    "reachGain": 1.8, "glassOpacity": 0.88, "shininess": 1.0, "transmission": 0.9,
                    "shadowStrength": 0.4, "rimStrength": 0.5,
                   ]),
        FeelPreset(id: "lava-lamp", name: "Lava Lamp", tagline: "Slow, heavy, drippy; sinks and sloshes lazily",
                   themeID: "sunset-lava", values: [
                    "restRadius": 70, "gravity": 1.1, "magnetPull": 28, "magnetWeight": 0.5, "magnetStick": 0.4,
                    "sloshAmount": 1.2, "damping": 0.96, "whipResponse": 0.3, "idleLife": 1.0, "reachGain": 1.4,
                    "recoilBounce": 0.9, "waistRest": 0.30, "headShare": 0.50, "meniscus": 1.2,
                    "shininess": 0.7, "transmission": 0.9, "glassOpacity": 0.9,
                   ]),
        FeelPreset(id: "mercury", name: "Mercury", tagline: "Tight, fast, glossy chrome droplet",
                   themeID: "mercury", values: [
                    "restRadius": 43, "gravity": 0.8, "magnetPull": 100, "magnetWeight": 0.78, "magnetStick": 1.4,
                    "sloshAmount": 0.35, "damping": 0.9, "recoilBounce": 0.35, "idleLife": 0.3, "reachGain": 2.2,
                    "waistRest": 0.14, "headShare": 0.50, "shininess": 1.4, "fresnel": 1.1, "transmission": 0.2, "glassOpacity": 1.0,
                    "rimStrength": 0.5, "flingMomentum": 0.8,
                   ]),
        FeelPreset(id: "water", name: "Water", tagline: "Loose and wobbly; ripples and rings after every move",
                   themeID: "deep-sea", values: [
                    "restRadius": 54, "gravity": 0.7, "magnetPull": 40, "magnetWeight": 0.42, "magnetStick": 0.3,
                    "sloshAmount": 1.35, "whipResponse": 1.1, "damping": 0.95, "idleLife": 1.1, "recoilBounce": 1.0,
                    "flingMomentum": 0.9, "glassOpacity": 0.82, "transmission": 1.0, "waistRest": 0.18, "headShare": 0.50, "meniscus": 1.0,
                   ]),
        FeelPreset(id: "taffy", name: "Taffy", tagline: "Stretches forever; thick, stringy, slow to let go",
                   themeID: "neon-jelly", values: [
                    "restRadius": 54, "waistRest": 0.34, "headShare": 0.50, "meniscus": 1.3, "gravity": 0.25,
                    "magnetPull": 36, "magnetWeight": 0.7, "reachGain": 3.0, "sloshAmount": 0.5, "damping": 0.97,
                    "recoilBounce": 0.7, "glassOpacity": 0.85,
                   ]),
        FeelPreset(id: "aurora-silk", name: "Aurora Silk", tagline: "Floaty and weightless, always drifting",
                   themeID: "aurora", values: [
                    "restRadius": 49, "gravity": 0.1, "magnetPull": 34, "magnetWeight": 0.55, "sloshAmount": 0.9,
                    "idleLife": 1.4, "damping": 0.97, "reachGain": 2.2, "recoilBounce": 0.8, "waistRest": 0.15, "headShare": 0.50, "meniscus": 1.2,
                    "glassOpacity": 0.9,
                   ]),
        FeelPreset(id: "flick", name: "Flick", tagline: "Snappy and precise for expert marking",
                   themeID: "oil-slick", values: [
                    "restRadius": 40, "gravity": 0.3, "magnetPull": 120, "magnetWeight": 0.85, "magnetStick": 1.8,
                    "sloshAmount": 0.3, "whipResponse": 0.4, "damping": 0.88, "idleLife": 0.3, "recoilBounce": 0.2,
                    "reachGain": 2.6, "flingMomentum": 0.2, "waistRest": 0.13, "headShare": 0.50,
                   ]),
        FeelPreset(id: "jelly-bounce", name: "Jelly Bounce", tagline: "Springy and playful; wobbles back and forth",
                   themeID: "neon-jelly", values: [
                    "restRadius": 51, "gravity": 0.5, "magnetPull": 46, "magnetWeight": 0.35, "magnetStick": 0.6,
                    "sloshAmount": 1.3, "whipResponse": 1.0, "recoilBounce": 1.0, "flingMomentum": 1.1,
                    "idleLife": 1.0, "glassOpacity": 0.88,
                   ]),
        FeelPreset(id: "molten-gold", name: "Molten Gold", tagline: "Heavy liquid metal that glows as it moves",
                   themeID: "molten-gold", values: [
                    "restRadius": 59, "gravity": 0.9, "magnetPull": 44, "magnetWeight": 0.58, "magnetStick": 1.0,
                    "sloshAmount": 0.9, "idleLife": 0.8, "shininess": 1.25, "transmission": 0.6, "glassOpacity": 0.96,
                   ]),
    ]

    /// Presets in the non-liquid styles. They reuse the same knobs (size, magnet pull, gravity, ...) where they apply.
    public static let styled: [FeelPreset] = [
        FeelPreset(id: "ferrofluid", name: "Ferrofluid", tagline: "Black chrome that bristles toward the magnet; filings string the field",
                   themeID: "ferrofluid", values: [
                    "restRadius": 59, "magnetPull": 90, "magnetWeight": 0.78, "magnetStick": 0.5, "reachGain": 1.9,
                    "idleLife": 0.4, "glassOpacity": 0.97, "shadowStrength": 0.55, "shininess": 1.2,
                   ], style: .ferro),
        FeelPreset(id: "iron-filings", name: "Iron Filings", tagline: "Ferrofluid in silver, snappier and sparser",
                   themeID: "mercury", values: [
                    "restRadius": 51, "magnetPull": 110, "magnetWeight": 0.85, "magnetStick": 0.3, "reachGain": 2.2,
                    "idleLife": 0.3, "glassOpacity": 0.97, "shininess": 1.1,
                   ], style: .ferro),
        FeelPreset(id: "amethyst-crystal", name: "Amethyst Crystal", tagline: "A violet crystal grows toward you, branching as you move",
                   themeID: "amethyst", values: [
                    "restRadius": 62, "magnetPull": 70, "magnetWeight": 0.9, "magnetStick": 0.2, "reachGain": 2.0,
                    "idleLife": 0.5, "glassOpacity": 0.96, "shadowStrength": 0.4,
                   ], style: .crystal),
        FeelPreset(id: "frost", name: "Frost", tagline: "Ice crystals spread along your path, cold and sharp",
                   themeID: "frost", values: [
                    "restRadius": 57, "magnetPull": 80, "magnetWeight": 0.92, "magnetStick": 0.15, "reachGain": 2.3,
                    "idleLife": 0.4, "glassOpacity": 0.96, "shadowStrength": 0.35,
                   ], style: .crystal),
        FeelPreset(id: "binary-star", name: "Binary Star", tagline: "A heavy body and a light one; dust orbits and streams between them",
                   themeID: "molten-gold", values: [
                    "restRadius": 59, "magnetPull": 85, "magnetWeight": 0.9, "magnetStick": 0.2, "reachGain": 2.2,
                    "idleLife": 0.4, "glassOpacity": 0.97, "shadowStrength": 0.35,
                   ], style: .gravity),
        FeelPreset(id: "deep-space", name: "Deep Space", tagline: "A cold blue planet and its moon, trailing glittering rings",
                   themeID: "deep-sea", values: [
                    "restRadius": 54, "magnetPull": 70, "magnetWeight": 0.88, "magnetStick": 0.25, "reachGain": 2.0,
                    "idleLife": 0.5, "glassOpacity": 0.96, "shadowStrength": 0.3,
                   ], style: .gravity),
        FeelPreset(id: "pearl-necklace", name: "Pearl Necklace", tagline: "A string of glossy pearls that sags and swings",
                   themeID: "mercury", values: [
                    "restRadius": 48, "magnetPull": 60, "magnetWeight": 0.8, "magnetStick": 0.3, "reachGain": 2.0,
                    "idleLife": 0.4, "glassOpacity": 0.97, "shadowStrength": 0.4,
                   ], style: .pearls),
        FeelPreset(id: "fireflies", name: "Fireflies", tagline: "A glowing swarm that follows your hand through the dark",
                   themeID: "aurora", values: [
                    "restRadius": 44, "magnetPull": 90, "magnetWeight": 0.7, "magnetStick": 0.25, "reachGain": 2.2,
                    "idleLife": 0.6, "glassOpacity": 0.95, "shadowStrength": 0.2,
                   ], style: .swarm),
        FeelPreset(id: "anemone", name: "Anemone", tagline: "Soft tentacles reach for the cursor and sway",
                   themeID: "neon-jelly", values: [
                    "restRadius": 46, "magnetPull": 55, "magnetWeight": 0.8, "magnetStick": 0.3, "reachGain": 2.0,
                    "idleLife": 0.6, "glassOpacity": 0.95, "shadowStrength": 0.3,
                   ], style: .tendrils),
    ]

    /// Every preset: the liquid ones, then ferrofluid, crystal and gravity.
    public static var everything: [FeelPreset] { all + styled }

    public static func preset(id: String) -> FeelPreset? { (all + styled).first { $0.id == id } }

    /// Knob values for a preset: baseline overlaid with the preset's own.
    public static func resolvedValues(_ p: FeelPreset) -> [String: Double] {
        baseline.merging(p.values) { _, new in new }
    }
}
