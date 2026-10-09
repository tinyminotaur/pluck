import AppKit
import Combine
import TwangCore

/// Draws a style once, off screen, so its sprites and pipelines are built before the first real gesture. Without this
/// the first frame of a style can take around 10 ms (visible as a hitch); afterwards it is well under 1 ms.
@MainActor
final class StylePrewarm {
    static let shared = StylePrewarm()
    private var bag = Set<AnyCancellable>()
    private var warmed = Set<String>()

    /// Warm the current style now and again whenever the person picks a different one.
    func start() {
        _ = ShapeListMetal.shared
        warm(TwangConfig.shared.style)
        TwangConfig.shared.$styleID
            .dropFirst()
            .sink { [weak self] id in self?.warm(AnimationStyle(rawValue: id) ?? .liquid) }
            .store(in: &bag)
    }

    func warm(_ style: AnimationStyle) {
        guard style != .liquid, warmed.insert(style.rawValue + ":" + TwangConfig.shared.effectivePackID + TwangConfig.shared.effectiveBeamVariantID).inserted else { return }
        let origin = CGPoint(x: 100, y: 100), far = CGPoint(x: 360, y: 140)
        if let r = VectorRunners.make(style) {
            r.reset(pin: origin, radius: 40)
            for _ in 0..<6 { r.step(dt: 1.0 / 120, pin: origin, head: far) }
            let host = VectorStyleHost()
            host.attach(r.layer)
            host.present(r, emerge: 1, glow: 0)
        }
        if let s = ShapeRunners.make(style) {
            s.reset(pin: origin, radius: 40)
            for _ in 0..<6 { s.step(dt: 1.0 / 120, pin: origin, head: far) }
            _ = s.primitives(emerge: 1, glow: 0)
        }
    }
}
