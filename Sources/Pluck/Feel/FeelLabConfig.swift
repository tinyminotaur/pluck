import AppKit
import Combine
import Foundation
import PluckCore

/// Modifier used by the trackpad trigger (modifier + press-and-hold).
enum TriggerModifier: Int, CaseIterable, Identifiable {
    case option, control, command, shift

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        case .shift: return "⇧ Shift"
        }
    }
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .option: return .option
        case .control: return .control
        case .command: return .command
        case .shift: return .shift
        }
    }
}

/// Live-tunable Feel Lab knobs. Persisted in UserDefaults; blob reads them every frame.
@MainActor
final class FeelLabConfig: ObservableObject {
    static let shared = FeelLabConfig()

    private let defaults = UserDefaults.standard
    private let prefix = "pluck.feel."

    // MARK: Mass
    @Published var restRadius: Double { didSet { save("restRadius", restRadius) } }
    @Published var pinMass: Double { didSet { save("pinMass", pinMass) } }
    @Published var headMass: Double { didSet { save("headMass", headMass) } }
    @Published var stretchPull: Double { didSet { save("stretchPull", stretchPull) } }
    @Published var pinMinFraction: Double { didSet { save("pinMinFraction", pinMinFraction) } }
    @Published var headMinFraction: Double { didSet { save("headMinFraction", headMinFraction) } }
    @Published var neckFloor: Double { didSet { save("neckFloor", neckFloor) } }

    // MARK: Physics
    @Published var responsiveness: Double { didSet { save("responsiveness", responsiveness) } }
    @Published var damping: Double { didSet { save("damping", damping) } }
    @Published var sloshAmount: Double { didSet { save("sloshAmount", sloshAmount) } }
    @Published var whipResponse: Double { didSet { save("whipResponse", whipResponse) } }
    @Published var particleCount: Double { didSet { save("particleCount", particleCount) } }

    // MARK: Look / optics
    @Published var shininess: Double { didSet { save("shininess", shininess) } }
    @Published var fresnel: Double { didSet { save("fresnel", fresnel) } }
    @Published var transmission: Double { didSet { save("transmission", transmission) } }
    @Published var absorption: Double { didSet { save("absorption", absorption) } }
    @Published var glassOpacity: Double { didSet { save("glassOpacity", glassOpacity) } }
    @Published var rimStrength: Double { didSet { save("rimStrength", rimStrength) } }
    @Published var shadowStrength: Double { didSet { save("shadowStrength", shadowStrength) } }
    @Published var lightness: Double { didSet { save("lightness", lightness) } }
    @Published var coolTint: Double { didSet { save("coolTint", coolTint) } }
    @Published var facetAmount: Double { didSet { save("facetAmount", facetAmount) } }
    @Published var facetSize: Double { didSet { save("facetSize", facetSize) } }

    // MARK: Fidget
    /// How wobbly the release snap-back is (0 tight … 1 very bouncy).
    @Published var recoilBounce: Double { didSet { save("recoilBounce", recoilBounce) } }
    /// How much the facets sharpen with stretch (0 = constant, 1 = liquid at rest → obsidian when taut).
    @Published var crystallize: Double { didSet { save("crystallize", crystallize) } }
    /// Idle breathing while held still.
    @Published var idleLife: Double { didSet { save("idleLife", idleLife) } }
    @Published var hapticsEnabled: Bool { didSet { saveBool("hapticsEnabled", hapticsEnabled) } }
    /// How much release momentum carries the head past the pin (0 = none, 1 = full flick).
    @Published var flingMomentum: Double { didSet { save("flingMomentum", flingMomentum) } }
    /// Smaller and dimmer, for fidgeting without drawing attention on a shared screen.
    @Published var meetingMode: Bool { didSet { saveBool("meetingMode", meetingMode) } }

    // MARK: Trackpad triggers (the two-button mouse chord always works too)
    /// Modifier + press-and-hold (without moving) starts a gesture.
    @Published var trackpadTriggerEnabled: Bool { didSet { saveBool("trackpadTriggerEnabled", trackpadTriggerEnabled) } }
    @Published var trackpadModifierRaw: Int { didSet { save("trackpadModifierRaw", Double(trackpadModifierRaw)) } }
    @Published var trackpadHoldMs: Double { didSet { save("trackpadHoldMs", trackpadHoldMs) } }
    /// No-click trigger: hold ⌥ (or Hyper), move to stretch, release the modifier to commit.
    @Published var modifierTriggerRaw: Int { didSet { save("modifierTriggerRaw", Double(modifierTriggerRaw)) } }
    @Published var modifierHoldMs: Double { didSet { save("modifierHoldMs", modifierHoldMs) } }
    var modifierTrigger: ModifierTrigger { ModifierTrigger(rawValue: modifierTriggerRaw) ?? .option }
    /// EXPERIMENTAL (private MultitouchSupport): three fingers down starts a gesture.
    @Published var threeFingerEnabled: Bool { didSet { saveBool("threeFingerEnabled", threeFingerEnabled) } }

    var trackpadModifier: TriggerModifier { TriggerModifier(rawValue: trackpadModifierRaw) ?? .option }

    // MARK: Field (metaball iso)
    @Published var gooBlur: Double { didSet { save("gooBlur", gooBlur) } }
    @Published var gooThreshold: Double { didSet { save("gooThreshold", gooThreshold) } }
    @Published var useGooFilter: Bool { didSet { saveBool("useGooFilter", useGooFilter) } }

    private init() {
        restRadius = Self.load("restRadius", 56)
        pinMass = Self.load("pinMass", 0.72)
        headMass = Self.load("headMass", 0.45)
        stretchPull = Self.load("stretchPull", 0.78)
        pinMinFraction = Self.load("pinMinFraction", 0.78)
        headMinFraction = Self.load("headMinFraction", 0.40)
        neckFloor = Self.load("neckFloor", 5)

        responsiveness = Self.load("responsiveness", 0.45)
        damping = Self.load("damping", 0.93)
        sloshAmount = Self.load("sloshAmount", 0.7)
        whipResponse = Self.load("whipResponse", 0.7)
        particleCount = Self.load("particleCount", 16)

        shininess = Self.load("shininess", 0.95)
        fresnel = Self.load("fresnel", 0.85)
        transmission = Self.load("transmission", 0.7)
        absorption = Self.load("absorption", 0.75)
        glassOpacity = Self.load("glassOpacity", 0.92)
        rimStrength = Self.load("rimStrength", 0.55)
        shadowStrength = Self.load("shadowStrength", 0.55)
        lightness = Self.load("lightness", 0.06)
        coolTint = Self.load("coolTint", 0.45)
        facetAmount = Self.load("facetAmount", 0.55)
        facetSize = Self.load("facetSize", 22)
        recoilBounce = Self.load("recoilBounce", 0.6)
        crystallize = Self.load("crystallize", 0.7)
        idleLife = Self.load("idleLife", 0.5)
        hapticsEnabled = Self.loadBool("hapticsEnabled", true)
        flingMomentum = Self.load("flingMomentum", 0.5)
        meetingMode = Self.loadBool("meetingMode", false)
        trackpadTriggerEnabled = Self.loadBool("trackpadTriggerEnabled", false)
        modifierTriggerRaw = Int(Self.load("modifierTriggerRaw", 1))
        modifierHoldMs = Self.load("modifierHoldMs", 250)
        trackpadModifierRaw = Int(Self.load("trackpadModifierRaw", 0))
        trackpadHoldMs = Self.load("trackpadHoldMs", 220)
        threeFingerEnabled = Self.loadBool("threeFingerEnabled", false)

        gooBlur = Self.load("gooBlur", 16)
        gooThreshold = Self.load("gooThreshold", 0.5)
        useGooFilter = Self.loadBool("useGooFilter", true)
    }

    func resetToDefaults() {
        restRadius = 56
        pinMass = 0.72
        headMass = 0.45
        stretchPull = 0.78
        pinMinFraction = 0.78
        headMinFraction = 0.40
        neckFloor = 5
        responsiveness = 0.45
        damping = 0.93
        sloshAmount = 0.7
        whipResponse = 0.7
        particleCount = 16
        shininess = 0.95
        fresnel = 0.85
        transmission = 0.7
        absorption = 0.75
        glassOpacity = 0.92
        rimStrength = 0.55
        shadowStrength = 0.55
        lightness = 0.06
        coolTint = 0.45
        facetAmount = 0.55
        facetSize = 22
        recoilBounce = 0.6
        crystallize = 0.7
        idleLife = 0.5
        hapticsEnabled = true
        flingMomentum = 0.5
        meetingMode = false
        trackpadTriggerEnabled = false
        modifierTriggerRaw = 1
        modifierHoldMs = 250
        trackpadModifierRaw = 0
        trackpadHoldMs = 220
        threeFingerEnabled = false
        gooBlur = 16
        gooThreshold = 0.5
        useGooFilter = true
    }

    var massParams: BlobMassParams {
        BlobMassParams(
            restRadius: CGFloat(restRadius) * (meetingMode ? 0.65 : 1),
            minRadius: CGFloat(neckFloor),
            pinMass: CGFloat(pinMass),
            headMass: CGFloat(headMass),
            stretchPull: CGFloat(stretchPull),
            pinMinFraction: CGFloat(pinMinFraction),
            headMinFraction: CGFloat(headMinFraction)
        )
    }

    var resolvedParticleCount: Int {
        max(6, min(28, Int(particleCount.rounded())))
    }

    var springConstant: CGFloat {
        CGFloat(2 + responsiveness * 20)
    }

    var dampingConstant: CGFloat {
        CGFloat(min(0.99, max(0.7, damping)))
    }

    var tintColor: NSColor {
        let L = CGFloat(lightness)
        let cool = CGFloat(coolTint)
        return NSColor(
            calibratedRed: L * (1 - cool * 0.2),
            green: L * (1 - cool * 0.05),
            blue: L * (1 + cool * 0.7),
            alpha: 1
        )
    }

    private func save(_ key: String, _ value: Double) {
        defaults.set(value, forKey: prefix + key)
    }

    private func saveBool(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: prefix + key)
    }

    private static func load(_ key: String, _ fallback: Double) -> Double {
        let k = "pluck.feel." + key
        if UserDefaults.standard.object(forKey: k) == nil { return fallback }
        return UserDefaults.standard.double(forKey: k)
    }

    private static func loadBool(_ key: String, _ fallback: Bool) -> Bool {
        let k = "pluck.feel." + key
        if UserDefaults.standard.object(forKey: k) == nil { return fallback }
        return UserDefaults.standard.bool(forKey: k)
    }
}
