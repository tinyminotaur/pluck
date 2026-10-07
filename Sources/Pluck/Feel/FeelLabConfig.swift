import AppKit
import Combine
import Foundation
import PluckCore

/// Live-tunable Feel Lab knobs. Persisted in UserDefaults; the gesture reads them every frame.
/// (Keys use the `pluck.feel2.` prefix so values saved by the first prototype don't override new defaults.)
@MainActor
final class FeelLabConfig: ObservableObject {
    static let shared = FeelLabConfig()

    private let prefix = "pluck.feel2."
    private var loading = true

    // MARK: Mass
    @Published var restRadius: Double { didSet { save("restRadius", restRadius) } }
    @Published var stretchPull: Double { didSet { save("stretchPull", stretchPull) } }
    @Published var neckFloor: Double { didSet { save("neckFloor", neckFloor) } }
    @Published var pinMass: Double { didSet { save("pinMass", pinMass) } }
    @Published var headMass: Double { didSet { save("headMass", headMass) } }
    @Published var pinMinFraction: Double { didSet { save("pinMinFraction", pinMinFraction) } }
    @Published var headMinFraction: Double { didSet { save("headMinFraction", headMinFraction) } }

    // MARK: Stretch
    @Published var gainBoost: Double { didSet { save("gainBoost", gainBoost) } }
    @Published var maxLength: Double { didSet { save("maxLength", maxLength) } }
    @Published var lobeDistance: Double { didSet { save("lobeDistance", lobeDistance) } }
    @Published var lobeSize: Double { didSet { save("lobeSize", lobeSize) } }

    // MARK: Physics
    @Published var headFrequency: Double { didSet { save("headFrequency", headFrequency) } }
    @Published var headDamping: Double { didSet { save("headDamping", headDamping) } }
    @Published var neckFrequency: Double { didSet { save("neckFrequency", neckFrequency) } }
    @Published var neckDamping: Double { didSet { save("neckDamping", neckDamping) } }
    @Published var sloshAmount: Double { didSet { save("sloshAmount", sloshAmount) } }
    @Published var particleCount: Double { didSet { save("particleCount", particleCount) } }

    // MARK: Look
    @Published var blend: Double { didSet { save("blend", blend) } }
    @Published var bevel: Double { didSet { save("bevel", bevel) } }
    @Published var shininess: Double { didSet { save("shininess", shininess) } }
    @Published var fresnel: Double { didSet { save("fresnel", fresnel) } }
    @Published var transmission: Double { didSet { save("transmission", transmission) } }
    @Published var absorption: Double { didSet { save("absorption", absorption) } }
    @Published var glassOpacity: Double { didSet { save("glassOpacity", glassOpacity) } }
    @Published var rimStrength: Double { didSet { save("rimStrength", rimStrength) } }
    @Published var shadowStrength: Double { didSet { save("shadowStrength", shadowStrength) } }
    @Published var coolTint: Double { didSet { save("coolTint", coolTint) } }

    private struct Defaults {
        static let values: [String: Double] = [
            "restRadius": 36, "stretchPull": 0.78, "neckFloor": 4,
            "pinMass": 0.72, "headMass": 0.45, "pinMinFraction": 0.78, "headMinFraction": 0.42,
            "gainBoost": 0.8, "maxLength": 360, "lobeDistance": 84, "lobeSize": 0.34,
            "headFrequency": 62, "headDamping": 0.78, "neckFrequency": 34, "neckDamping": 0.6,
            "sloshAmount": 0.7, "particleCount": 18,
            "blend": 20, "bevel": 15, "shininess": 0.9, "fresnel": 0.85, "transmission": 0.75,
            "absorption": 0.7, "glassOpacity": 0.94, "rimStrength": 0.6, "shadowStrength": 0.55, "coolTint": 0.45,
        ]
    }

    private static func load(_ key: String, _ prefix: String) -> Double {
        let k = prefix + key
        if UserDefaults.standard.object(forKey: k) == nil { return Defaults.values[key] ?? 0 }
        return UserDefaults.standard.double(forKey: k)
    }

    private init() {
        let p = prefix
        restRadius = Self.load("restRadius", p)
        stretchPull = Self.load("stretchPull", p)
        neckFloor = Self.load("neckFloor", p)
        pinMass = Self.load("pinMass", p)
        headMass = Self.load("headMass", p)
        pinMinFraction = Self.load("pinMinFraction", p)
        headMinFraction = Self.load("headMinFraction", p)
        gainBoost = Self.load("gainBoost", p)
        maxLength = Self.load("maxLength", p)
        lobeDistance = Self.load("lobeDistance", p)
        lobeSize = Self.load("lobeSize", p)
        headFrequency = Self.load("headFrequency", p)
        headDamping = Self.load("headDamping", p)
        neckFrequency = Self.load("neckFrequency", p)
        neckDamping = Self.load("neckDamping", p)
        sloshAmount = Self.load("sloshAmount", p)
        particleCount = Self.load("particleCount", p)
        blend = Self.load("blend", p)
        bevel = Self.load("bevel", p)
        shininess = Self.load("shininess", p)
        fresnel = Self.load("fresnel", p)
        transmission = Self.load("transmission", p)
        absorption = Self.load("absorption", p)
        glassOpacity = Self.load("glassOpacity", p)
        rimStrength = Self.load("rimStrength", p)
        shadowStrength = Self.load("shadowStrength", p)
        coolTint = Self.load("coolTint", p)
        loading = false
    }

    func resetToDefaults() {
        let d = Defaults.values
        restRadius = d["restRadius"]!; stretchPull = d["stretchPull"]!; neckFloor = d["neckFloor"]!
        pinMass = d["pinMass"]!; headMass = d["headMass"]!
        pinMinFraction = d["pinMinFraction"]!; headMinFraction = d["headMinFraction"]!
        gainBoost = d["gainBoost"]!; maxLength = d["maxLength"]!
        lobeDistance = d["lobeDistance"]!; lobeSize = d["lobeSize"]!
        headFrequency = d["headFrequency"]!; headDamping = d["headDamping"]!
        neckFrequency = d["neckFrequency"]!; neckDamping = d["neckDamping"]!
        sloshAmount = d["sloshAmount"]!; particleCount = d["particleCount"]!
        blend = d["blend"]!; bevel = d["bevel"]!
        shininess = d["shininess"]!; fresnel = d["fresnel"]!; transmission = d["transmission"]!
        absorption = d["absorption"]!; glassOpacity = d["glassOpacity"]!
        rimStrength = d["rimStrength"]!; shadowStrength = d["shadowStrength"]!; coolTint = d["coolTint"]!
    }

    // MARK: Derived

    func tetherParams(reduceMotion: Bool) -> LiquidTetherParams {
        LiquidTetherParams(
            mass: BlobMassParams(
                restRadius: CGFloat(restRadius),
                minRadius: CGFloat(neckFloor),
                pinMass: CGFloat(pinMass),
                headMass: CGFloat(headMass),
                stretchPull: CGFloat(stretchPull),
                pinMinFraction: CGFloat(pinMinFraction),
                headMinFraction: CGFloat(headMinFraction)
            ),
            headFrequency: CGFloat(headFrequency),
            headDamping: CGFloat(headDamping),
            neckFrequency: CGFloat(neckFrequency),
            neckDamping: CGFloat(neckDamping),
            slosh: CGFloat(sloshAmount),
            particleCount: Int(particleCount.rounded()),
            lobeDistance: CGFloat(lobeDistance),
            lobeRadiusFraction: CGFloat(lobeSize),
            reduceMotion: reduceMotion
        )
    }

    func look(time: Float, light: SIMD2<Float>) -> BlobRenderer.Look {
        var l = BlobRenderer.Look()
        l.lightDir = light
        l.time = time
        l.blend = Float(blend)
        l.bevel = Float(bevel)
        l.shininess = Float(shininess)
        l.fresnel = Float(fresnel)
        l.transmission = Float(transmission)
        l.absorption = Float(absorption)
        l.opacity = Float(glassOpacity)
        l.shadow = Float(shadowStrength)
        l.rim = Float(rimStrength)
        l.coolTint = Float(coolTint)
        return l
    }

    private func save(_ key: String, _ value: Double) {
        guard !loading else { return }
        UserDefaults.standard.set(value, forKey: prefix + key)
    }
}
