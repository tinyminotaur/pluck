import AppKit
import PluckCore
import QuartzCore

import AppKit
import PluckCore
import QuartzCore

// Every animation style is driven through one of two small interfaces, so the live view needs no per-style code:
//
//  - `VectorRunner`: hand-drawn Core Animation sprites (most styles, and community packs).
//  - `ShapeRunner`:  shapes rendered by the glass shader (ferrofluid, crystal, gravity, pearls, tendrils).
//
// Adding a style means writing a pure simulation in PluckCore, a layers class, and one `case` in a factory below.

@MainActor
protocol VectorRunner: AnyObject {
    var layer: CALayer { get }
    var isFinished: Bool { get }
    func reset(pin: CGPoint, radius: CGFloat)
    func step(dt: CGFloat, pin: CGPoint, head: CGPoint)
    func release(commit: Bool, direction: CGPoint)
    func present(emerge: CGFloat, glow: CGFloat)
    /// A runner may override how the head moves on release (community packs choose their own).
    var releaseBehavior: ReleaseBehavior? { get }
}

extension VectorRunner { var releaseBehavior: ReleaseBehavior? { nil } }

@MainActor
final class SimRunner<Sim>: VectorRunner {
    var sim: Sim
    let layer: CALayer
    private let _reset: (inout Sim, CGPoint, CGFloat) -> Void
    private let _step: (inout Sim, CGFloat, CGPoint, CGPoint) -> Void
    private let _release: (inout Sim, Bool, CGPoint) -> Void
    private let _finished: (Sim) -> Bool
    private let _present: (Sim, CGFloat, CGFloat) -> Void

    init(sim: Sim, layer: CALayer,
         reset: @escaping (inout Sim, CGPoint, CGFloat) -> Void,
         step: @escaping (inout Sim, CGFloat, CGPoint, CGPoint) -> Void,
         release: @escaping (inout Sim, Bool, CGPoint) -> Void,
         finished: @escaping (Sim) -> Bool,
         present: @escaping (Sim, CGFloat, CGFloat) -> Void) {
        self.sim = sim; self.layer = layer
        _reset = reset; _step = step; _release = release; _finished = finished; _present = present
    }
    var isFinished: Bool { _finished(sim) }
    func reset(pin: CGPoint, radius: CGFloat) { _reset(&sim, pin, radius) }
    func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { _step(&sim, dt, pin, head) }
    func release(commit: Bool, direction: CGPoint) { _release(&sim, commit, direction) }
    func present(emerge: CGFloat, glow: CGFloat) { _present(sim, emerge, glow) }
}

@MainActor
enum VectorRunners {
    static func make(_ style: AnimationStyle) -> VectorRunner? {
        switch style {
        case .pingpong:
            let l = PingPongLayers()
            return SimRunner(sim: PingPongSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .bridge:
            let l = BridgeLayers()
            return SimRunner(sim: BridgeSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .planes:
            let l = PlanesLayers()
            return SimRunner(sim: PaperPlanesSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .water:
            let l = WaterLayers()
            return SimRunner(sim: WaterArcSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 1.05; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .train:
            let l = TrainLayers()
            return SimRunner(sim: ToyTrainSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .equalizer:
            let l = EqualizerLayers()
            return SimRunner(sim: EqualizerSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.7; $0.reset(pin: $1) },
                             step: { $0.spectrum = AudioSpectrum.shared.snapshot(); $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .dna:
            let l = DNALayers()
            return SimRunner(sim: DNASim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 1.1; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .fishing:
            let l = FishingLayers()
            return SimRunner(sim: FishingSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .ribbon:
            let l = RibbonLayers()
            return SimRunner(sim: RibbonSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .tugofwar:
            let l = TugLayers()
            return SimRunner(sim: TugOfWarSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 1.0; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .cradle:
            let l = CradleLayers()
            return SimRunner(sim: NewtonsCradleSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .rainbow:
            let l = RainbowLayers()
            return SimRunner(sim: RainbowSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .dandelion:
            let l = DandelionLayers()
            return SimRunner(sim: DandelionSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 1.0; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .cablecar:
            let l = CableCarLayers()
            return SimRunner(sim: CableCarSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .signal:
            let l = SignalLayers()
            return SimRunner(sim: SignalSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .lasso:
            let l = LassoLayers()
            return SimRunner(sim: LassoSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .laser:
            let l = LaserLayers()
            return SimRunner(sim: LaserPointerSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .marker:
            let l = MarkerLayers()
            return SimRunner(sim: HighlighterSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .spotlight:
            let l = SpotlightLayers()
            return SimRunner(sim: SpotlightSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .callout:
            let l = CalloutLayers()
            return SimRunner(sim: CalloutArrowSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .targetlock:
            let l = TargetLockLayers()
            return SimRunner(sim: TargetLockSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .marquee:
            let l = MarqueeLayers()
            return SimRunner(sim: MarqueeSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .jelly:
            let l = JellyLayers()
            return SimRunner(sim: JellySim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .freehand:
            let l = FreehandLayers()
            return SimRunner(sim: FreehandLassoSim(), layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.8; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .swarm:
            let l = FireflyLayers()
            return SimRunner(sim: SwarmSim(), layer: l.root,
                             reset: { $0.params.bodyRadius = $2 * 0.62; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.fireflyStates(emerge: $1), pin: $0.pinLantern, head: $0.headLantern, alpha: min(1, $1), headGlow: $2, time: CGFloat(CACurrentMediaTime())) })
        case .jumprope:
            let l = PaperRopeLayers()
            return SimRunner(sim: JumpRopeSim(), layer: l.root,
                             reset: { $0.params.bodyRadius = $2 * 0.72; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.paperScene(emerge: $1, headGlow: $2)) })
        case .stars:
            let l = StarLayers()
            return SimRunner(sim: StarSim(), layer: l.root,
                             reset: { $0.params.bodyRadius = $2 * 0.72; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .kite:
            let l = KiteLayers()
            return SimRunner(sim: KiteSim(), layer: l.root,
                             reset: { $0.params.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .bubbles:
            let l = BubbleLayers()
            return SimRunner(sim: BubbleSim(), layer: l.root,
                             reset: { $0.params.bodyRadius = $2 * 0.75; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.bubbleStates(emerge: $1, headGlow: $2)) })
        case .lightning:
            let l = LightningLayers()
            return SimRunner(sim: LightningSim(), layer: l.root,
                             reset: { $0.params.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .magnet:
            let l = MagnetLayers()
            return SimRunner(sim: MagnetSim(), layer: l.root,
                             reset: { $0.params.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .slinky:
            let l = SlinkyLayers()
            return SimRunner(sim: SlinkySim(), layer: l.root,
                             reset: { $0.params.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .tincan:
            let l = TinCanLayers()
            return SimRunner(sim: TinCanSim(), layer: l.root,
                             reset: { $0.params.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .thread:
            let l = ThreadLayers()
            return SimRunner(sim: ThreadSim(), layer: l.root,
                             reset: { $0.params.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        case .pack:
            let cfg = PluckConfig.shared
            guard let installed = PackLibrary.shared.pack(id: cfg.effectivePackID), installed.isValid else { return nil }
            return PackRunner(pack: installed, params: cfg.packParams(for: installed.id, defaults: installed.program?.params ?? []), theme: cfg.theme)
        case .beam:
            let l = EnergyLayers()
            var proto = EnergySim()
            proto.variant = EnergyVariant(rawValue: PluckConfig.shared.effectiveBeamVariantID) ?? .kamehameha
            proto.chargeThenFire = PluckConfig.shared.beamChargeMode
            return SimRunner(sim: proto, layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        default:
            return nil
        }
    }
}


// MARK: - Glass-shader styles

@MainActor
protocol ShapeRunner: AnyObject {
    var isFinished: Bool { get }
    func reset(pin: CGPoint, radius: CGFloat)
    func step(dt: CGFloat, pin: CGPoint, head: CGPoint)
    func release(commit: Bool, direction: CGPoint)
    func primitives(emerge: CGFloat, glow: CGFloat) -> [ShapePrim]
}

@MainActor
final class ShapeSimRunner<Sim>: ShapeRunner {
    var sim: Sim
    private let _reset: (inout Sim, CGPoint, CGFloat) -> Void
    private let _step: (inout Sim, CGFloat, CGPoint, CGPoint) -> Void
    private let _release: (inout Sim, Bool, CGPoint) -> Void
    private let _finished: (Sim) -> Bool
    private let _prims: (Sim, CGFloat, CGFloat) -> [ShapePrim]

    init(sim: Sim,
         reset: @escaping (inout Sim, CGPoint, CGFloat) -> Void,
         step: @escaping (inout Sim, CGFloat, CGPoint, CGPoint) -> Void,
         release: @escaping (inout Sim, Bool, CGPoint) -> Void,
         finished: @escaping (Sim) -> Bool,
         primitives: @escaping (Sim, CGFloat, CGFloat) -> [ShapePrim]) {
        self.sim = sim
        _reset = reset; _step = step; _release = release; _finished = finished; _prims = primitives
    }
    var isFinished: Bool { _finished(sim) }
    func reset(pin: CGPoint, radius: CGFloat) { _reset(&sim, pin, radius) }
    func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { _step(&sim, dt, pin, head) }
    func release(commit: Bool, direction: CGPoint) { _release(&sim, commit, direction) }
    func primitives(emerge: CGFloat, glow: CGFloat) -> [ShapePrim] { _prims(sim, emerge, glow) }
}

@MainActor
enum ShapeRunners {
    static func make(_ style: AnimationStyle) -> ShapeRunner? {
        switch style {
        case .ferro:
            return ShapeSimRunner(sim: FerroSim(), reset: { $0.params.bodyRadius = $2 * 0.72; $0.reset(pin: $1) },
                                  step: { $0.step(dt: $1, pin: $2, head: $3) }, release: { $0.release(commit: $1 ? $2 : nil) },
                                  finished: { $0.isFinished }, primitives: { $0.primitives(emerge: $1, headGlow: $2) })
        case .crystal:
            return ShapeSimRunner(sim: CrystalSim(), reset: { $0.params.coreRadius = $2 * 0.62; $0.reset(pin: $1, seed: UInt64.random(in: 1...UInt64.max)) },
                                  step: { $0.step(dt: $1, pin: $2, head: $3) },
                                  release: { if $1 { $0.shatter(direction: $2) } else { $0.retract() } },
                                  finished: { $0.isFinished }, primitives: { $0.primitives(emerge: $1, headGlow: $2) })
        case .gravity:
            return ShapeSimRunner(sim: AstroSim(), reset: { $0.params.bodyRadius = $2 * 0.72; $0.reset(pin: $1) },
                                  step: { $0.step(dt: $1, pin: $2, head: $3) }, release: { $0.release(commit: $1 ? $2 : nil) },
                                  finished: { $0.isFinished }, primitives: { $0.primitives(emerge: $1, headGlow: $2) })
        case .pearls:
            return ShapeSimRunner(sim: PearlSim(), reset: { $0.params.bodyRadius = $2 * 0.72; $0.reset(pin: $1) },
                                  step: { $0.step(dt: $1, pin: $2, head: $3) }, release: { $0.release(commit: $1 ? $2 : nil) },
                                  finished: { $0.isFinished }, primitives: { $0.primitives(emerge: $1, headGlow: $2) })
        case .tendrils:
            return ShapeSimRunner(sim: TendrilSim(), reset: { $0.params.bodyRadius = $2 * 0.66; $0.reset(pin: $1) },
                                  step: { $0.step(dt: $1, pin: $2, head: $3) }, release: { $0.release(commit: $1 ? $2 : nil) },
                                  finished: { $0.isFinished }, primitives: { $0.primitives(emerge: $1, headGlow: $2) })
        default:
            return nil
        }
    }
}
