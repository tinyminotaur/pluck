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

/// Live-tunable settings. Persisted in UserDefaults; blob reads them every frame.
@MainActor
final class PluckConfig: ObservableObject {
    static let shared = PluckConfig()

    private let defaults = UserDefaults.standard
    private let prefix = "pluck.feel."

    // MARK: Mass
    @Published var restRadius: Double { didSet { save("restRadius", restRadius) } }
    @Published var pinMass: Double { didSet { save("pinMass", pinMass) } }
    @Published var headMass: Double { didSet { save("headMass", headMass) } }
    @Published var stretchPull: Double { didSet { save("stretchPull", stretchPull) } }
    @Published var pinMinFraction: Double { didSet { save("pinMinFraction", pinMinFraction) } }
    @Published var headMinFraction: Double { didSet { save("headMinFraction", headMinFraction) } }
    /// Thread thickness at rest (fraction of the rest radius), pin/head mass split, and how far the concave blend reaches.
    @Published var waistRest: Double { didSet { save("waistRest", waistRest) } }
    @Published var headShare: Double { didSet { save("headShare", headShare) } }
    @Published var meniscus: Double { didSet { save("meniscus", meniscus) } }
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
    /// Amber warmth (0 = deep red-amber, 1 = hot amber). Stored under the legacy key `coolTint`.
    @Published var coolTint: Double { didSet { save("coolTint", coolTint) } }
    /// Glow intensity multiplier (the theme sets the base strength of its pulsing glow).
    @Published var ember: Double { didSet { save("glowGain", ember) } }
    /// Selected look and feel. `themeID == "custom"` uses `customTheme` (a "Surprise me" palette).
    @Published var themeID: String { didSet { saveString("themeID", themeID) } }
    @Published var presetID: String { didSet { saveString("presetID", presetID) } }
    /// How the gesture is drawn: liquid, ferrofluid or crystal.
    @Published var styleID: String { didSet { saveString("styleID", styleID) } }
    @Published private(set) var customTheme: LiquidTheme? { didSet { saveCustomTheme() } }
    /// Master switch for the chipped-obsidian facets. Off while the liquid itself is being tuned.
    @Published var facetsEnabled: Bool { didSet { saveBool("facetsEnabled", facetsEnabled) } }
    @Published var facetAmount: Double { didSet { save("facetAmount", facetAmount) } }
    @Published var facetSize: Double { didSet { save("facetSize", facetSize) } }

    // MARK: Fidget
    /// How wobbly the release snap-back is (0 tight … 1 very bouncy).
    @Published var recoilBounce: Double { didSet { save("recoilBounce", recoilBounce) } }
    /// How much the facets sharpen with stretch (0 = constant, 1 = liquid at rest → obsidian when taut).
    @Published var crystallize: Double { didSet { save("crystallize", crystallize) } }
    /// Idle breathing while held still.
    @Published var idleLife: Double { didSet { save("idleLife", idleLife) } }
    // MARK: Liquid in a container (gravity + magnetic pull)
    /// Reach gain: how much a short motion is exaggerated. The head can reach anywhere on screen (no length cap);
    /// 0 = plain 1:1, higher = a smaller motion reaches farther.
    @Published var reachGain: Double { didSet { save("reachGain", reachGain) } }
    /// Downward pull: the tether sags and mass pools at the low point.
    @Published var gravity: Double { didSet { save("gravity", gravity) } }
    /// How tightly the head follows the cursor (rad/s). Lower = heavier liquid that trails and sloshes.
    @Published var magnetPull: Double { didSet { save("magnetPull", magnetPull) } }
    /// Damping of that pull. Below ~0.8 it overshoots and wobbles into place.
    @Published var magnetWeight: Double { didSet { save("magnetWeight", magnetWeight) } }
    /// Extra stiffness right at the cursor: trails when far, snaps and sticks when close.
    @Published var magnetStick: Double { didSet { save("magnetStick", magnetStick) } }
    @Published var hapticsEnabled: Bool { didSet { saveBool("hapticsEnabled", hapticsEnabled) } }
    /// Very quiet system sounds on latch and commit. Off by default.
    @Published var soundEnabled: Bool { didSet { saveBool("soundEnabled", soundEnabled) } }
    /// Equalizer style follows system audio (needs Screen Recording permission). Off by default.
    /// Which anime energy attack the Energy Beam style uses, and whether it fires on release (charge mode).
    @Published var beamVariantID: String { didSet { UserDefaults.standard.set(beamVariantID, forKey: "feelLab.beamVariantID") } }
    @Published var beamChargeMode: Bool { didSet { saveBool("beamChargeMode", beamChargeMode) } }
    /// The blob's end sits exactly under the real pointer (so the cursor never seems to jump when it reappears).
    @Published var reachExact: Bool { didSet { saveBool("reachExact", reachExact) } }
    /// "actions" (a direction picks an action) or "presenter" (a direction picks a visual).
    @Published var interactionModeID: String { didSet { saveString("interactionModeID", interactionModeID) } }
    /// Presenter mode: 4 or 8 directions, how far to drag before one is chosen, and the preset ids for the 8 directions.
    @Published var presenterCount: Int { didSet { UserDefaults.standard.set(presenterCount, forKey: "pluck.feel.presenterCount") } }
    @Published var presenterRadius: Double { didSet { save("presenterRadius", presenterRadius) } }
    @Published var presenterSlotsRaw: String { didSet { saveString("presenterSlotsRaw", presenterSlotsRaw) } }
    /// Community packs: the chosen pack for the Community style, per-pack slider values, and the online library address.
    @Published var packID: String { didSet { saveString("packID", packID) } }
    @Published var packParamsJSON: String { didSet { saveString("packParamsJSON", packParamsJSON) } }
    @Published var libraryURL: String { didSet { saveString("libraryURL", libraryURL) } }
    /// Overall size of everything drawn, relative to the screen (1 = the original size).
    @Published var sizeScale: Double { didSet { save("sizeScale", sizeScale) } }
    /// Opt-in beta: run real actions (copy, share, search, save, tile windows) instead of only drawing.
    @Published var realActions: Bool { didSet { RealActions.enabled = realActions; NotificationCenter.default.post(name: .pluckRealActionsChanged, object: nil) } }
    /// Opt-in: keep a small local log of why gestures begin and end.
    @Published var diagnosticsEnabled: Bool { didSet { Diagnostics.enabled = diagnosticsEnabled } }
    @Published var audioReactive: Bool { didSet { saveBool("audioReactive", audioReactive) } }
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
    /// Three fingers must rest without moving this long before it arms (so a normal three-finger drag is untouched).
    @Published var threeFingerHoldMs: Double { didSet { save("threeFingerHoldMs", threeFingerHoldMs) } }

    var trackpadModifier: TriggerModifier { TriggerModifier(rawValue: trackpadModifierRaw) ?? .option }

    // MARK: Field (metaball iso)
    @Published var gooBlur: Double { didSet { save("gooBlur", gooBlur) } }
    @Published var gooThreshold: Double { didSet { save("gooThreshold", gooThreshold) } }
    @Published var useGooFilter: Bool { didSet { saveBool("useGooFilter", useGooFilter) } }

    private init() {
        restRadius = Self.load("restRadius", 57)
        pinMass = Self.load("pinMass", 0.72)
        headMass = Self.load("headMass", 0.45)
        stretchPull = Self.load("stretchPull", 0.78)
        pinMinFraction = Self.load("pinMinFraction", 0.55)
        headMinFraction = Self.load("headMinFraction", 0.40)
        neckFloor = Self.load("neckFloor", 6.5)
        waistRest = Self.load("waistRest", 0.20)
        headShare = Self.load("headShare", 0.50)
        meniscus = Self.load("meniscus", 1.0)

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
        ember = Self.load("glowGain", 1.0)
        themeID = UserDefaults.standard.string(forKey: "pluck.feel.themeID") ?? ThemeLibrary.obsidianEmber.id
        presetID = UserDefaults.standard.string(forKey: "pluck.feel.presetID") ?? PresetLibrary.all[0].id
        styleID = UserDefaults.standard.string(forKey: "pluck.feel.styleID") ?? AnimationStyle.liquid.rawValue
        customTheme = UserDefaults.standard.data(forKey: "pluck.feel.customTheme").flatMap { try? JSONDecoder().decode(LiquidTheme.self, from: $0) }
        facetsEnabled = Self.loadBool("facetsEnabled", false)
        facetAmount = Self.load("facetAmount", 0.55)
        facetSize = Self.load("facetSize", 22)
        recoilBounce = Self.load("recoilBounce", 0.6)
        crystallize = Self.load("crystallize", 0.7)
        idleLife = Self.load("idleLife", 0.5)
        reachGain = Self.load("reachGain", 1.8)
        gravity = Self.load("gravity", 0.6)
        magnetPull = Self.load("magnetPull", 52)
        magnetWeight = Self.load("magnetWeight", 0.62)
        magnetStick = Self.load("magnetStick", 0.9)
        hapticsEnabled = Self.loadBool("hapticsEnabled", true)
        soundEnabled = Self.loadBool("soundEnabled", false)
        audioReactive = Self.loadBool("audioReactive", false)
        realActions = RealActions.enabled
        diagnosticsEnabled = Diagnostics.enabled
        sizeScale = Self.load("sizeScale", 1.25)
        packID = UserDefaults.standard.string(forKey: "pluck.feel.packID") ?? ""
        packParamsJSON = UserDefaults.standard.string(forKey: "pluck.feel.packParamsJSON") ?? "{}"
        libraryURL = UserDefaults.standard.string(forKey: "pluck.feel.libraryURL") ?? ""
        interactionModeID = UserDefaults.standard.string(forKey: "pluck.feel.interactionModeID") ?? "actions"
        presenterCount = UserDefaults.standard.integer(forKey: "pluck.feel.presenterCount") == 8 ? 8 : 4
        presenterRadius = Self.load("presenterRadius", 64)
        presenterSlotsRaw = UserDefaults.standard.string(forKey: "pluck.feel.presenterSlotsRaw") ?? PresenterMath.defaultSlots.joined(separator: ",")
        reachExact = Self.loadBool("reachExact", true)
        beamVariantID = UserDefaults.standard.string(forKey: "feelLab.beamVariantID") ?? EnergyVariant.kamehameha.rawValue
        beamChargeMode = Self.loadBool("beamChargeMode", true)
        flingMomentum = Self.load("flingMomentum", 0.5)
        meetingMode = Self.loadBool("meetingMode", false)
        trackpadTriggerEnabled = Self.loadBool("trackpadTriggerEnabled", false)
        modifierTriggerRaw = Int(Self.load("modifierTriggerRaw", 1))
        modifierHoldMs = Self.load("modifierHoldMs", 250)
        trackpadModifierRaw = Int(Self.load("trackpadModifierRaw", 0))
        trackpadHoldMs = Self.load("trackpadHoldMs", 220)
        threeFingerEnabled = Self.loadBool("threeFingerEnabled", false)
        threeFingerHoldMs = Self.load("threeFingerHoldMs", 200)

        gooBlur = Self.load("gooBlur", 16)
        gooThreshold = Self.load("gooThreshold", 0.5)
        useGooFilter = Self.loadBool("useGooFilter", true)
    }

    func resetToDefaults() {
        restRadius = 57
        pinMass = 0.72
        headMass = 0.45
        stretchPull = 0.78
        pinMinFraction = 0.55
        headMinFraction = 0.40
        neckFloor = 6.5
        waistRest = 0.20
        headShare = 0.50
        meniscus = 1.0
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
        ember = 1.0
        themeID = ThemeLibrary.obsidianEmber.id
        presetID = PresetLibrary.all[0].id
        styleID = AnimationStyle.liquid.rawValue
        facetsEnabled = false
        facetAmount = 0.55
        facetSize = 22
        recoilBounce = 0.6
        crystallize = 0.7
        idleLife = 0.5
        reachGain = 1.8
        gravity = 0.6
        magnetPull = 52
        magnetWeight = 0.62
        magnetStick = 0.9
        hapticsEnabled = true
        soundEnabled = false
        audioReactive = false
        sizeScale = 1.25
        interactionModeID = "actions"; presenterCount = 4; presenterRadius = 64
        presenterSlotsRaw = PresenterMath.defaultSlots.joined(separator: ",")
        reachExact = true
        beamVariantID = EnergyVariant.kamehameha.rawValue
        beamChargeMode = true
        flingMomentum = 0.5
        meetingMode = false
        trackpadTriggerEnabled = false
        modifierTriggerRaw = 1
        modifierHoldMs = 250
        trackpadModifierRaw = 0
        trackpadHoldMs = 220
        threeFingerEnabled = false
        threeFingerHoldMs = 200
        gooBlur = 16
        gooThreshold = 0.5
        useGooFilter = true
    }

    /// The dumbbell shape: round pin and head joined by a thin thread with concave blends.
    var dumbbell: DumbbellMass.Params {
        DumbbellMass.Params(
            restRadius: CGFloat(restRadius * sizeScale) * (meetingMode ? 0.65 : 1),
            waistRest: CGFloat(waistRest),
            headShare: CGFloat(headShare),
            meniscus: CGFloat(meniscus)
        )
    }

    var massParams: BlobMassParams {
        BlobMassParams(
            restRadius: CGFloat(restRadius * sizeScale) * (meetingMode ? 0.65 : 1),
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
        // Warm black: obsidian with a trace of amber, not blue.
        return NSColor(
            calibratedRed: L * (1 + cool * 0.9),
            green: L * (1 + cool * 0.25),
            blue: L * (1 - cool * 0.3),
            alpha: 1
        )
    }

    // MARK: Themes and presets

    var style: AnimationStyle { transientPreset?.style ?? AnimationStyle(rawValue: styleID) ?? .liquid }

    // MARK: Presenter mode

    var presenterMode: Bool { interactionModeID == "presenter" }
    var presenterSlots: [String] { PresenterMath.parseSlots(presenterSlotsRaw) }
    func setPresenterSlot(_ index: Int, to id: String) {
        var slots = presenterSlots
        guard slots.indices.contains(index) else { return }
        slots[index] = id
        presenterSlotsRaw = slots.joined(separator: ",")
    }
    /// The preset a presenter direction (0..<presenterCount) maps to.
    func presenterPreset(forSector sector: Int) -> FeelPreset? {
        let indices = PresenterMath.slotIndices(count: presenterCount)
        guard indices.indices.contains(sector) else { return nil }
        return PresetLibrary.preset(id: presenterSlots[indices[sector]])
    }
    /// While a presenter visual is showing, this overrides style, colours and beam variant without touching the saved choice.
    var transientPreset: FeelPreset?
    var effectiveBeamVariantID: String { transientPreset?.variant ?? beamVariantID }
    /// The blob's rest radius after the overall size scale and meeting mode.
    var effectiveRestRadius: CGFloat { CGFloat(restRadius * sizeScale) * (meetingMode ? 0.65 : 1) }
    var effectivePackID: String { transientPreset?.style == .pack ? (transientPreset?.variant ?? packID) : packID }

    /// Slider values for a pack, falling back to each parameter's default.
    func packParams(for id: String, defaults: [PackParam]) -> [String: Double] {
        let all = (try? JSONSerialization.jsonObject(with: Data(packParamsJSON.utf8))) as? [String: [String: Double]] ?? [:]
        var out: [String: Double] = [:]
        for p in defaults { out[p.name] = all[id]?[p.name] ?? p.default }
        return out
    }
    func setPackParam(_ id: String, _ name: String, _ value: Double) {
        var all = (try? JSONSerialization.jsonObject(with: Data(packParamsJSON.utf8))) as? [String: [String: Double]] ?? [:]
        all[id, default: [:]][name] = value
        if let d = try? JSONSerialization.data(withJSONObject: all), let s = String(data: d, encoding: .utf8) { packParamsJSON = s }
    }

    /// The active theme (a built-in, or the last "Surprise me" palette).
    var theme: LiquidTheme {
        if let t = transientPreset, let th = ThemeLibrary.theme(id: t.themeID) { return th }
        if themeID == "custom", let customTheme { return customTheme }
        return ThemeLibrary.theme(id: themeID) ?? ThemeLibrary.obsidianEmber
    }

    /// Knob name -> property, so presets can set knobs by name.
    private static let knobPaths: [String: ReferenceWritableKeyPath<PluckConfig, Double>] = [
        "restRadius": \.restRadius, "stretchPull": \.stretchPull, "neckFloor": \.neckFloor,
        "pinMass": \.pinMass, "headMass": \.headMass, "pinMinFraction": \.pinMinFraction,
        "headMinFraction": \.headMinFraction, "responsiveness": \.responsiveness, "damping": \.damping,
        "sloshAmount": \.sloshAmount, "whipResponse": \.whipResponse, "particleCount": \.particleCount,
        "shininess": \.shininess, "fresnel": \.fresnel, "transmission": \.transmission,
        "absorption": \.absorption, "glassOpacity": \.glassOpacity, "rimStrength": \.rimStrength,
        "shadowStrength": \.shadowStrength, "ember": \.ember, "recoilBounce": \.recoilBounce,
        "crystallize": \.crystallize, "idleLife": \.idleLife, "flingMomentum": \.flingMomentum,
        "waistRest": \.waistRest, "headShare": \.headShare, "meniscus": \.meniscus,
        "reachGain": \.reachGain, "gravity": \.gravity, "magnetPull": \.magnetPull,
        "magnetWeight": \.magnetWeight, "magnetStick": \.magnetStick,
    ]

    /// Apply a preset: every knob to the baseline, then the preset's own values, then its theme.
    func apply(preset: FeelPreset) {
        for (key, value) in PresetLibrary.resolvedValues(preset) {
            if let path = Self.knobPaths[key] { self[keyPath: path] = value }
        }
        themeID = preset.themeID
        styleID = preset.style.rawValue
        presetID = preset.id
        if let v = preset.variant { if preset.style == .pack { packID = v } else { beamVariantID = v } }
    }

    /// Change only the colours, keeping the current feel.
    func apply(theme t: LiquidTheme) {
        themeID = t.id
    }

    /// A one-off random palette.
    func surpriseMe() {
        customTheme = ThemeLibrary.random(seed: UInt64.random(in: 0...UInt64.max))
        themeID = "custom"
    }

    private func saveCustomTheme() {
        if let customTheme, let data = try? JSONEncoder().encode(customTheme) {
            UserDefaults.standard.set(data, forKey: "pluck.feel.customTheme")
        }
    }
    private func saveString(_ key: String, _ value: String) {
        defaults.set(value, forKey: prefix + key)
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
