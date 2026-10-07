import CoreGraphics
import Foundation

/// Tunable mass model for the liquid tether. Feel Lab edits these live.
public struct BlobMassParams: Equatable, Sendable {
    /// Resting blob radius when pin ≈ head (points). Drives total conserved area.
    public var restRadius: CGFloat
    /// Absolute floor for any sample along the tether.
    public var minRadius: CGFloat
    /// How strongly mass prefers the pin (0 = even, 1 = heavy pin).
    public var pinMass: CGFloat
    /// How strongly mass prefers the cursor/head lobe.
    public var headMass: CGFloat
    /// How aggressively stretch pulls mass out of the neck into the ends (0–1+).
    public var stretchPull: CGFloat
    /// Minimum pin radius as a fraction of restRadius.
    public var pinMinFraction: CGFloat
    /// Minimum head radius as a fraction of restRadius.
    public var headMinFraction: CGFloat
    /// Soft cap multiplier on restRadius for any sample.
    public var maxRadiusScale: CGFloat

    public init(
        restRadius: CGFloat = 56,
        minRadius: CGFloat = 5,
        pinMass: CGFloat = 0.72,
        headMass: CGFloat = 0.45,
        stretchPull: CGFloat = 0.78,
        pinMinFraction: CGFloat = 0.78,
        headMinFraction: CGFloat = 0.4,
        maxRadiusScale: CGFloat = 1.35
    ) {
        self.restRadius = restRadius
        self.minRadius = minRadius
        self.pinMass = pinMass
        self.headMass = headMass
        self.stretchPull = stretchPull
        self.pinMinFraction = pinMinFraction
        self.headMinFraction = headMinFraction
        self.maxRadiusScale = maxRadiusScale
    }

    public static let `default` = BlobMassParams()

    public var totalArea: CGFloat { .pi * restRadius * restRadius }
    public var maxRadius: CGFloat { restRadius * maxRadiusScale }
}

/// Fixed-mass liquid tether math — total area conserved; stretch thins the body.
public enum BlobMass {
    /// Back-compat defaults (tests / call sites without explicit params).
    public static var restRadius: CGFloat { BlobMassParams.default.restRadius }
    public static var minRadius: CGFloat { BlobMassParams.default.minRadius }
    public static var maxRadius: CGFloat { BlobMassParams.default.maxRadius }
    public static var totalArea: CGFloat { BlobMassParams.default.totalArea }

    public static func uniformRadius(forLength length: CGFloat, params: BlobMassParams = .default) -> CGFloat {
        let L = max(0, length)
        let M = params.totalArea
        if L < 0.5 { return params.restRadius }
        let disc = L * L + .pi * M
        let r = (-L + sqrt(disc)) / .pi
        return clampRadius(r, params: params)
    }

    public static func radiusProfile(
        length: CGFloat,
        samples: Int,
        params: BlobMassParams = .default
    ) -> [CGFloat] {
        let n = max(2, samples)
        let L = max(0, length)
        let base = uniformRadius(forLength: L, params: params)
        let stretch = min(1, L / (params.restRadius * 5))
        let pull = max(0, params.stretchPull)
        let pinW = max(0.05, params.pinMass)
        let headW = max(0.05, params.headMass)

        var raw = [CGFloat]()
        raw.reserveCapacity(n)
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            let pinLobe = exp(-pow(t / 0.42, 2))
            let headLobe = exp(-pow((1 - t) / 0.26, 2))
            let neck = sin(.pi * t)
            let shaped = base * (
                0.16
                + (1.2 + pinW) * pinLobe * (0.75 + 0.55 * stretch)
                + (0.7 + headW) * headLobe * (0.5 + 0.5 * stretch)
                - pull * neck * stretch
            )
            raw.append(max(params.minRadius * 0.7, shaped))
        }

        return rescaleToTotalArea(radii: raw, length: L, params: params)
    }

    public static func rescaleToTotalArea(
        radii: [CGFloat],
        length: CGFloat,
        params: BlobMassParams = .default
    ) -> [CGFloat] {
        guard radii.count >= 2 else { return radii }
        var out = radii.map { max(params.minRadius * 0.5, $0) }
        for _ in 0..<2 {
            let area = approximateArea(radii: out, length: length)
            let scale = sqrt(params.totalArea / max(1, area))
            out = out.map { min(params.maxRadius, max(params.minRadius, $0 * scale)) }
        }
        let area = approximateArea(radii: out, length: length)
        let scale = sqrt(params.totalArea / max(1, area))
        return out.map { max(params.minRadius * 0.85, $0 * scale) }
    }

    public static func approximateArea(radii: [CGFloat], length: CGFloat) -> CGFloat {
        guard radii.count >= 2 else { return 0 }
        let L = max(0, length)
        let segs = radii.count - 1
        let segLen = L / CGFloat(max(1, segs))
        var body: CGFloat = 0
        for i in 0..<segs {
            body += (radii[i] + radii[i + 1]) * segLen
        }
        let ends = .pi * 0.5 * (radii[0] * radii[0] + radii[radii.count - 1] * radii[radii.count - 1])
        return body + ends
    }

    public static func clampRadius(_ r: CGFloat, params: BlobMassParams = .default) -> CGFloat {
        min(params.maxRadius, max(params.minRadius, r))
    }

    /// Apply visual min floors for pin/head after profile + rescale.
    public static func applyEndFloors(radii: inout [CGFloat], emerge: CGFloat, params: BlobMassParams) {
        guard radii.count >= 2 else { return }
        let e = max(0.08, emerge)
        radii[0] = max(radii[0], params.restRadius * params.pinMinFraction * e)
        radii[radii.count - 1] = max(radii[radii.count - 1], params.restRadius * params.headMinFraction * e)
    }
}
