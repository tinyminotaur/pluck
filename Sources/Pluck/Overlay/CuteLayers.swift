import AppKit
import PluckCore
import QuartzCore

// MARK: - Runner abstraction (one object per sprite style, so the view needs no per-style switch)

@MainActor
protocol VectorRunner: AnyObject {
    var layer: CALayer { get }
    var isFinished: Bool { get }
    func reset(pin: CGPoint, radius: CGFloat)
    func step(dt: CGFloat, pin: CGPoint, head: CGPoint)
    func release(commit: Bool, direction: CGPoint)
    func present(emerge: CGFloat, glow: CGFloat)
}

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
        case .beam:
            let l = EnergyLayers()
            var proto = EnergySim()
            proto.variant = EnergyVariant(rawValue: FeelLabConfig.shared.effectiveBeamVariantID) ?? .kamehameha
            proto.chargeThenFire = FeelLabConfig.shared.beamChargeMode
            return SimRunner(sim: proto, layer: l.root,
                             reset: { $0.base.bodyRadius = $2 * 0.7; $0.reset(pin: $1) }, step: { $0.step(dt: $1, pin: $2, head: $3) },
                             release: { $0.release(commit: $1 ? $2 : nil) }, finished: { $0.isFinished },
                             present: { l.update($0.scene(emerge: $1, headGlow: $2)) })
        default:
            return nil
        }
    }
}

// MARK: - Shared drawing helpers

let paperWhite = Sprite.color(255, 250, 238)

func circlePath(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
}

func polyline(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    if let f = pts.first { p.move(to: f); for q in pts.dropFirst() { p.addLine(to: q) } }
    return p
}

@MainActor func paperShape(_ fill: CGColor?, border: CGFloat = 2.4, depth: CGFloat = 1.8) -> CAShapeLayer {
    let l = CAShapeLayer()
    l.fillColor = fill; l.strokeColor = paperWhite; l.lineWidth = border; l.lineJoin = .round; l.lineCap = .round
    if depth > 0 { PaperRopeLayers.paperShadow(l, depth: depth) }
    return l
}

@MainActor func lineLayer(_ color: CGColor, _ width: CGFloat, depth: CGFloat = 0) -> CAShapeLayer {
    let l = CAShapeLayer()
    l.fillColor = nil; l.strokeColor = color; l.lineWidth = width; l.lineCap = .round; l.lineJoin = .round
    if depth > 0 { PaperRopeLayers.paperShadow(l, depth: depth) }
    return l
}

@MainActor
final class DotPool {
    private let parent: CALayer
    private let image: CGImage?
    private(set) var layers: [CALayer] = []
    init(parent: CALayer, image: CGImage?) { self.parent = parent; self.image = image }
    func place(_ i: Int, at p: CGPoint, size: CGFloat, alpha: CGFloat) {
        while layers.count <= i {
            let l = CALayer(); l.contents = image; parent.addSublayer(l); layers.append(l)
        }
        let l = layers[i]
        l.isHidden = alpha < 0.02 || size < 0.3
        l.bounds = CGRect(x: 0, y: 0, width: size, height: size); l.position = p; l.opacity = Float(alpha)
    }
    func hide(from i: Int) { for j in max(0, i)..<layers.count { layers[j].isHidden = true } }
}

let softDot: CGImage? = Sprite.image(CGSize(width: 16, height: 16), scale: 3) { c in
    Sprite.radial(c, center: CGPoint(x: 8, y: 8), radius: 7.5, inner: Sprite.color(255, 255, 255, 1), outer: Sprite.color(255, 255, 255, 0))
}

/// A paper disc with stitching: the stand-in for a "point" in the paper styles.
@MainActor
final class PaperDisc {
    let root = CALayer()
    private let disc = paperShape(nil, border: 2.8, depth: 2.2)
    private let stitch = lineLayer(Sprite.color(255, 255, 255, 0.85), 1.6)
    private let shine = lineLayer(Sprite.color(255, 255, 255, 0.55), 2.2)
    init(_ color: CGColor) {
        disc.fillColor = color
        stitch.lineDashPattern = [4, 4]
        root.addSublayer(disc); root.addSublayer(stitch); root.addSublayer(shine)
    }
    func update(at c: CGPoint, r: CGFloat) {
        disc.path = circlePath(c, r)
        stitch.path = circlePath(c, r * 0.72)
        let p = CGMutablePath(); p.addArc(center: c, radius: r * 0.55, startAngle: .pi * 0.6, endAngle: .pi * 0.9, clockwise: false)
        shine.path = p
    }
}

// MARK: - Ping-pong

@MainActor
final class PingPongLayers {
    let root = CALayer()
    private let net = lineLayer(Sprite.color(255, 255, 255, 0.28), 2)
    private let paddleA = Paddle(Sprite.color(235, 80, 90)), paddleB = Paddle(Sprite.color(70, 140, 230))
    private let ballHalo = CALayer(), ball = CALayer()
    private lazy var trail = DotPool(parent: root, image: softDot)
    private lazy var sparks = DotPool(parent: root, image: softDot)
    private static let ballImg = glossySphere(Sprite.color(255, 255, 255), Sprite.color(255, 188, 90), rim: Sprite.color(255, 250, 238))
    private static let haloImg = glowSprite(Sprite.color(255, 240, 180, 0.8), Sprite.color(255, 200, 100, 0), mid: Sprite.color(255, 220, 130, 0.35))

    init() {
        root.masksToBounds = false
        net.lineDashPattern = [6, 8]
        ballHalo.contents = Self.haloImg; ball.contents = Self.ballImg
        for l in [net, paddleA.root, paddleB.root, ballHalo, ball] { root.addSublayer(l) }
    }

    func update(_ s: PingPongScene) {
        root.opacity = Float(s.alpha)
        net.path = polyline([s.pin, s.head])
        paddleA.update(at: s.pin, r: s.pinRadius, angle: s.paddleAngle + .pi, kick: s.pinKick)
        paddleB.update(at: s.head, r: s.headRadius, angle: s.paddleAngle, kick: s.headKick)
        let br = s.ballRadius
        ball.bounds = CGRect(x: 0, y: 0, width: br * 2.2, height: br * 2.2); ball.position = s.ball
        ballHalo.bounds = CGRect(x: 0, y: 0, width: br * 7, height: br * 7); ballHalo.position = s.ball
        for (i, t) in s.trail.enumerated() { trail.place(i, at: t.0, size: br * (1.7 - CGFloat(i) * 0.07), alpha: t.1) }
        for (i, sp) in s.sparks.enumerated() { sparks.place(i, at: sp.0, size: 7, alpha: sp.1) }
        sparks.hide(from: s.sparks.count)
    }

    @MainActor private final class Paddle {
        let root = CALayer()
        private let handle = paperShape(Sprite.color(206, 150, 96), border: 2, depth: 1.5)
        private let face: CAShapeLayer
        private let ring = lineLayer(Sprite.color(255, 255, 255, 0.7), 2)
        init(_ color: CGColor) {
            face = paperShape(color, border: 2.6, depth: 2)
            for l in [handle, face, ring] { root.addSublayer(l) }
        }
        /// The handle points away from the other paddle; a hit knocks the face back along the axis.
        func update(at p: CGPoint, r: CGFloat, angle: CGFloat, kick: CGFloat) {
            root.position = p
            root.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
            handle.path = CGPath(roundedRect: CGRect(x: -r * 2.1, y: -r * 0.2, width: r * 1.3, height: r * 0.4), cornerWidth: r * 0.2, cornerHeight: r * 0.2, transform: nil)
            let c = CGPoint(x: -kick * r * 0.25, y: 0)
            face.path = circlePath(c, r)
            ring.path = circlePath(c, r * 0.72)
        }
    }
}

// MARK: - Bridge

@MainActor
final class BridgeLayers {
    let root = CALayer()
    private let railA = lineLayer(Sprite.color(236, 214, 170), 3.4, depth: 1.2), railB = lineLayer(Sprite.color(236, 214, 170), 3.4, depth: 1.2)
    private let hangers = lineLayer(Sprite.color(236, 214, 170, 0.9), 1.6)
    private var planks: [CAShapeLayer] = []
    private let postA = paperShape(Sprite.color(150, 104, 70), border: 2.4), postB = paperShape(Sprite.color(150, 104, 70), border: 2.4)
    private let walker = Walker()
    private static let woods = [Sprite.color(214, 160, 104), Sprite.color(196, 140, 90), Sprite.color(224, 176, 120)]

    init() {
        root.masksToBounds = false
        for l in [railB, hangers, railA, postA, postB] { root.addSublayer(l) }
        root.addSublayer(walker.root)
    }

    func update(_ s: BridgeScene) {
        root.opacity = Float(s.alpha)
        while planks.count < s.planks.count {
            let l = paperShape(Self.woods[planks.count % 3], border: 1.8, depth: 1.2)
            root.insertSublayer(l, below: walker.root); planks.append(l)
        }
        let hp = CGMutablePath()
        for (i, pl) in s.planks.enumerated() {
            let l = planks[i]
            let w = pl.width, t: CGFloat = 9
            var tr = CGAffineTransform(translationX: pl.position.x, y: pl.position.y).rotated(by: pl.angle)
            l.path = CGPath(roundedRect: CGRect(x: -w / 2, y: -t / 2, width: w, height: t), cornerWidth: 2.5, cornerHeight: 2.5, transform: &tr)
            if i % 3 == 0, i < s.railA.count * s.planks.count / max(1, s.railA.count) {
                let k = min(s.railA.count - 1, i * (s.railA.count - 1) / max(1, s.planks.count - 1))
                hp.move(to: s.railA[k]); hp.addLine(to: pl.position)
            }
        }
        hangers.path = hp
        railA.path = polyline(s.railA); railB.path = polyline(s.railB)
        for (post, p, r) in [(postA, s.pin, s.pinRadius), (postB, s.head, s.headRadius)] {
            post.path = CGPath(roundedRect: CGRect(x: p.x - r * 0.38, y: p.y - r * 0.9, width: r * 0.76, height: r * 2.2), cornerWidth: r * 0.2, cornerHeight: r * 0.2, transform: nil)
        }
        walker.update(s)
    }

    @MainActor private final class Walker {
        let root = CALayer()
        private let body = paperShape(Sprite.color(255, 243, 222), border: 2.2, depth: 1.6)
        private let hat = paperShape(Sprite.color(235, 90, 100), border: 2, depth: 0)
        private let bobble = paperShape(paperWhite, border: 0, depth: 0)
        private let legA = paperShape(Sprite.color(255, 214, 170), border: 1.6, depth: 0), legB = paperShape(Sprite.color(255, 214, 170), border: 1.6, depth: 0)
        private let eyeA = CAShapeLayer(), eyeB = CAShapeLayer(), cheek = CAShapeLayer()
        init() {
            for l in [legA, legB, body, hat, bobble, eyeA, eyeB, cheek] { root.addSublayer(l) }
            for e in [eyeA, eyeB] { e.fillColor = Sprite.color(66, 48, 48) }
            cheek.fillColor = Sprite.color(255, 143, 163, 0.85)
        }
        func update(_ s: BridgeScene) {
            let R: CGFloat = 20
            root.position = s.walker
            root.transform = CATransform3DScale(CATransform3DMakeRotation(s.walkerAngle, 0, 0, 1), s.walkerFacing, 1, 1)
            body.path = CGPath(ellipseIn: CGRect(x: -R, y: -R * 0.9 + 3 * s.walkerBob, width: R * 2, height: R * 1.8), transform: nil)
            let hp = CGMutablePath(); hp.move(to: CGPoint(x: -R * 0.8, y: R * 0.55 + 3 * s.walkerBob)); hp.addLine(to: CGPoint(x: R * 0.1, y: R * 1.6 + 3 * s.walkerBob))
            hp.addLine(to: CGPoint(x: R * 0.8, y: R * 0.5 + 3 * s.walkerBob)); hp.closeSubpath()
            hat.path = hp
            bobble.path = circlePath(CGPoint(x: R * 0.1, y: R * 1.7 + 3 * s.walkerBob), R * 0.2)
            let sw = s.walkerStep * R * 0.45
            legA.path = CGPath(ellipseIn: CGRect(x: -R * 0.55 + sw - R * 0.3, y: -R * 1.05, width: R * 0.6, height: R * 0.38), transform: nil)
            legB.path = CGPath(ellipseIn: CGRect(x: R * 0.35 - sw - R * 0.3, y: -R * 1.05, width: R * 0.6, height: R * 0.38), transform: nil)
            eyeA.path = circlePath(CGPoint(x: R * 0.15, y: R * 0.12 + 3 * s.walkerBob), R * 0.13)
            eyeB.path = circlePath(CGPoint(x: R * 0.58, y: R * 0.12 + 3 * s.walkerBob), R * 0.13)
            cheek.path = circlePath(CGPoint(x: R * 0.4, y: -R * 0.2 + 3 * s.walkerBob), R * 0.17)
        }
    }
}

// MARK: - Paper planes

@MainActor
final class PlanesLayers {
    let root = CALayer()
    private let discA = PaperDisc(Sprite.color(255, 128, 118)), discB = PaperDisc(Sprite.color(92, 196, 190))
    @MainActor private struct Plane { let box = CALayer(); let upper = paperShape(nil, border: 1.6, depth: 1.8); let lower = paperShape(nil, border: 1.6, depth: 0); let fold = lineLayer(Sprite.color(180, 190, 210), 1.2) }
    private var planes: [Plane] = []
    private lazy var trail = DotPool(parent: root, image: softDot)
    private static let tints: [(CGColor, CGColor)] = [(Sprite.color(255, 255, 255), Sprite.color(205, 220, 245)), (Sprite.color(255, 238, 190), Sprite.color(240, 200, 120)),
                                                      (Sprite.color(255, 214, 224), Sprite.color(240, 160, 190)), (Sprite.color(206, 240, 232), Sprite.color(140, 200, 190))]

    init() {
        root.masksToBounds = false
        root.addSublayer(discA.root); root.addSublayer(discB.root)
    }

    func update(_ s: PlanesScene) {
        root.opacity = Float(s.alpha)
        discA.update(at: s.pin, r: s.pinRadius); discB.update(at: s.head, r: s.headRadius)
        var dot = 0
        while planes.count < s.planes.count {
            let p = Plane()
            for l in [p.upper, p.lower, p.fold] { p.box.addSublayer(l) }
            root.addSublayer(p.box); planes.append(p)
        }
        for (i, pl) in s.planes.enumerated() {
            let p = planes[i]
            for t in pl.trail { trail.place(dot, at: t.0, size: 4.5, alpha: t.1); dot += 1 }
            p.box.opacity = Float(pl.alpha); p.box.isHidden = pl.alpha < 0.02
            p.box.position = pl.position
            let k = pl.size
            let roll = CGFloat(cos(Double(pl.roll)))
            p.box.transform = CATransform3DScale(CATransform3DMakeRotation(pl.angle, 0, 0, 1), k, k * (0.35 + 0.65 * abs(roll)), 1)
            let nose = CGPoint(x: 1, y: 0), tl = CGPoint(x: -0.9, y: 0.6), tr = CGPoint(x: -0.9, y: -0.6), notch = CGPoint(x: -0.45, y: 0)
            let up = CGMutablePath(); up.move(to: nose); up.addLine(to: tl); up.addLine(to: notch); up.closeSubpath()
            let lo = CGMutablePath(); lo.move(to: nose); lo.addLine(to: notch); lo.addLine(to: tr); lo.closeSubpath()
            p.upper.path = up; p.lower.path = lo
            let (a, b) = Self.tints[pl.tint % 4]
            p.upper.fillColor = a; p.lower.fillColor = b
            p.upper.lineWidth = 1.6 / k; p.lower.lineWidth = 1.6 / k; p.fold.lineWidth = 1.2 / k
            p.upper.shadowRadius = 2 / k
            p.fold.path = polyline([nose, notch])
        }
        trail.hide(from: dot)
    }
}

// MARK: - Water arc

@MainActor
final class WaterLayers {
    let root = CALayer()
    private let jet = lineLayer(Sprite.color(120, 200, 255, 0.5), 6)
    private let jetCore = lineLayer(Sprite.color(220, 244, 255, 0.85), 2)
    private let tank = Flask(), cup = Flask()
    private lazy var drops = DotPool(parent: root, image: softDot)
    private lazy var splash = DotPool(parent: root, image: softDot)
    private var rings: [CAShapeLayer] = []

    init() {
        root.masksToBounds = false
        jet.shadowColor = Sprite.color(130, 205, 255); jet.shadowOpacity = 0.8; jet.shadowRadius = 4; jet.shadowOffset = .zero
        for l in [tank.root, cup.root, jet, jetCore] { root.addSublayer(l) }
    }

    func update(_ s: WaterScene) {
        root.opacity = Float(s.alpha)
        let p = polyline(s.arc)
        jet.path = p; jetCore.path = p
        jet.opacity = Float(s.flow); jetCore.opacity = Float(s.flow)
        jet.lineWidth = 5 + 2 * CGFloat(sin(Double(s.time * 9)))
        tank.update(at: s.tank, r: s.tankRadius, level: s.tankLevel, time: s.time)
        cup.update(at: s.cup, r: s.cupRadius, level: s.cupLevel, time: s.time + 1)
        for (i, d) in s.drops.enumerated() { drops.place(i, at: d.0, size: d.2 * 2.4, alpha: d.1 * 0.9) }
        for (i, d) in s.splash.enumerated() { splash.place(i, at: d.0, size: 5, alpha: d.1) }
        while rings.count < s.rings.count {
            let l = lineLayer(Sprite.color(220, 244, 255, 0.9), 2); root.addSublayer(l); rings.append(l)
        }
        for (i, r) in s.rings.enumerated() {
            let c = CGPoint(x: s.cup.x, y: s.cup.y + s.cupRadius * 0.95)
            rings[i].path = CGPath(ellipseIn: CGRect(x: c.x - r.0 * 1.2, y: c.y - r.0 * 0.4, width: r.0 * 2.4, height: r.0 * 0.8), transform: nil)
            rings[i].opacity = Float(r.1)
        }
    }

    /// A glass flask with water: the water level is the mass.
    @MainActor final class Flask {
        let root = CALayer()
        private let glass = paperShape(Sprite.color(220, 240, 255, 0.18), border: 2.6, depth: 1.8)
        private let waterHost = CALayer(), water = CAShapeLayer(), mask = CAShapeLayer()
        private let shine = lineLayer(Sprite.color(255, 255, 255, 0.85), 3)
        init() {
            water.fillColor = Sprite.color(80, 170, 255, 0.9)
            waterHost.mask = mask; waterHost.addSublayer(water)
            mask.fillColor = Sprite.color(0, 0, 0, 1)
            for l in [glass, waterHost, shine] { root.addSublayer(l) }
        }
        func update(at c: CGPoint, r: CGFloat, level: CGFloat, time: CGFloat) {
            glass.path = circlePath(c, r)
            mask.path = circlePath(c, r - 1.5)
            let top = c.y - r + 2 * r * level
            let p = CGMutablePath()
            p.move(to: CGPoint(x: c.x - r, y: c.y - r))
            for i in 0...16 {
                let x = c.x - r + 2 * r * CGFloat(i) / 16
                p.addLine(to: CGPoint(x: x, y: top + 2.2 * CGFloat(sin(Double(x * 0.12 + time * 3)))))
            }
            p.addLine(to: CGPoint(x: c.x + r, y: c.y - r)); p.closeSubpath()
            water.path = p
            let sp = CGMutablePath(); sp.addArc(center: c, radius: r * 0.72, startAngle: .pi * 0.62, endAngle: .pi * 0.9, clockwise: false)
            shine.path = sp
        }
    }
}

// MARK: - Toy train

@MainActor
final class TrainLayers {
    let root = CALayer()
    private let railA = lineLayer(Sprite.color(150, 160, 178), 3.4), railB = lineLayer(Sprite.color(150, 160, 178), 3.4)
    private var ties: [CAShapeLayer] = []
    private var cars: [CarLayer] = []
    private lazy var smoke = DotPool(parent: root, image: softDot)
    private let stationA = House(Sprite.color(255, 128, 118)), stationB = House(Sprite.color(92, 196, 190))

    init() {
        root.masksToBounds = false
        for l in [railA, railB, stationA.root, stationB.root] { root.addSublayer(l) }
    }

    func update(_ s: TrainScene) {
        root.opacity = Float(s.alpha)
        while ties.count < s.ties.count {
            let l = paperShape(Sprite.color(174, 124, 84), border: 1.2, depth: 0.8)
            root.insertSublayer(l, below: railA); ties.append(l)
        }
        for (i, t) in ties.enumerated() {
            guard i < s.ties.count else { t.isHidden = true; continue }
            t.isHidden = false
            var tr = CGAffineTransform(translationX: s.ties[i].position.x, y: s.ties[i].position.y).rotated(by: s.ties[i].angle)
            t.path = CGPath(roundedRect: CGRect(x: -9, y: -2.6, width: 18, height: 5.2), cornerWidth: 1.5, cornerHeight: 1.5, transform: &tr)
        }
        var a: [CGPoint] = [], b: [CGPoint] = []
        for (i, p) in s.track.enumerated() {
            let q = s.track[min(s.track.count - 1, i + 1)], r = s.track[max(0, i - 1)]
            let dx = q.x - r.x, dy = q.y - r.y, l = max(0.001, hypot(dx, dy))
            let nx = -dy / l * 4.2, ny = dx / l * 4.2
            a.append(CGPoint(x: p.x + nx, y: p.y + ny)); b.append(CGPoint(x: p.x - nx, y: p.y - ny))
        }
        railA.path = polyline(a); railB.path = polyline(b)
        while cars.count < s.cars.count { let c = CarLayer(kind: cars.count == 0 ? 0 : 1); root.addSublayer(c.root); cars.append(c) }
        for (i, c) in cars.enumerated() where i < s.cars.count { c.update(s.cars[i]) }
        for (i, sm) in s.smoke.enumerated() { smoke.place(i, at: sm.0, size: sm.2 * 2.2, alpha: sm.1 * 0.8) }
        stationA.update(at: s.pin, r: s.pinRadius); stationB.update(at: s.head, r: s.headRadius)
    }

    @MainActor private final class House {
        let root = CALayer()
        private let body: CAShapeLayer, roof = paperShape(Sprite.color(240, 214, 160), border: 2.2, depth: 0), door = CAShapeLayer()
        init(_ color: CGColor) {
            body = paperShape(color, border: 2.4, depth: 2)
            door.fillColor = Sprite.color(255, 250, 238, 0.9)
            for l in [body, roof, door] { root.addSublayer(l) }
        }
        func update(at c: CGPoint, r: CGFloat) {
            body.path = CGPath(roundedRect: CGRect(x: c.x - r * 0.8, y: c.y - r * 0.6, width: r * 1.6, height: r * 1.2), cornerWidth: 3, cornerHeight: 3, transform: nil)
            let rp = CGMutablePath(); rp.move(to: CGPoint(x: c.x - r * 1.0, y: c.y + r * 0.5)); rp.addLine(to: CGPoint(x: c.x, y: c.y + r * 1.4))
            rp.addLine(to: CGPoint(x: c.x + r * 1.0, y: c.y + r * 0.5)); rp.closeSubpath()
            roof.path = rp
            door.path = CGPath(roundedRect: CGRect(x: c.x - r * 0.2, y: c.y - r * 0.6, width: r * 0.4, height: r * 0.7), cornerWidth: 3, cornerHeight: 3, transform: nil)
        }
    }

    @MainActor private final class CarLayer {
        let root = CALayer()
        private let kind: Int
        private let body: CAShapeLayer, cab = paperShape(Sprite.color(255, 207, 86), border: 1.8, depth: 0)
        private let chimney = paperShape(Sprite.color(70, 70, 92), border: 1.4, depth: 0)
        private let wheelA = paperShape(Sprite.color(70, 70, 92), border: 1.2, depth: 0), wheelB = paperShape(Sprite.color(70, 70, 92), border: 1.2, depth: 0)
        init(kind: Int) {
            self.kind = kind
            body = paperShape(kind == 0 ? Sprite.color(235, 80, 90) : Sprite.color(92, 196, 190), border: 2.2, depth: 1.8)
            for l in [body, cab, chimney, wheelA, wheelB] { root.addSublayer(l) }
        }
        func update(_ c: TrainCar) {
            root.position = c.position
            root.transform = CATransform3DMakeRotation(c.angle, 0, 0, 1)
            let (w, h): (CGFloat, CGFloat) = c.kind == 0 ? (30, 16) : (24, 14)
            root.opacity = 1
            root.transform = CATransform3DScale(root.transform, 1.5, 1.5, 1)
            let col: CGColor = c.kind == 0 ? Sprite.color(235, 80, 90) : (c.kind == 1 ? Sprite.color(255, 207, 86) : Sprite.color(92, 196, 190))
            body.fillColor = col
            body.path = CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: 4, cornerHeight: 4, transform: nil)
            cab.isHidden = c.kind != 0; chimney.isHidden = c.kind != 0
            cab.path = CGPath(roundedRect: CGRect(x: -w / 2, y: h / 2 - 3, width: 11, height: 12), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            chimney.path = CGPath(roundedRect: CGRect(x: w / 2 - 9, y: h / 2 - 2, width: 6, height: 10), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            wheelA.path = circlePath(CGPoint(x: -w * 0.28, y: -h / 2), 3.8); wheelB.path = circlePath(CGPoint(x: w * 0.28, y: -h / 2), 3.8)
        }
    }
}

// MARK: - Equalizer

@MainActor
final class EqualizerLayers {
    let root = CALayer()
    private var bars: [CAShapeLayer] = [], peaks: [CAShapeLayer] = []
    private let speakerA = Speaker(), speakerB = Speaker()
    private var rings: [CAShapeLayer] = []

    init() { root.masksToBounds = false; root.addSublayer(speakerA.root); root.addSublayer(speakerB.root) }

    func update(_ s: EqualizerScene) {
        root.opacity = Float(s.alpha)
        var ang = s.axis + .pi / 2
        if sin(ang) < 0 || (abs(sin(ang)) < 1e-6 && cos(ang) < 0) { ang += .pi }
        let up = CGPoint(x: cos(ang), y: sin(ang))
        while bars.count < s.bars.count {
            let b = CAShapeLayer(), p = CAShapeLayer()
            b.shadowOpacity = 0.9; b.shadowRadius = 6; b.shadowOffset = .zero
            root.insertSublayer(b, at: 0); root.insertSublayer(p, at: 0); bars.append(b); peaks.append(p)
        }
        for (i, bar) in s.bars.enumerated() {
            let c = NSColor(hue: 0.92 - 0.42 * bar.hue, saturation: 0.7, brightness: 1.0, alpha: 1).usingColorSpace(.sRGB)!
            let col = CGColor(srgbRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: 1)
            let w = s.barWidth
            let h = max(3, bar.height)
            var tr = CGAffineTransform(translationX: bar.base.x, y: bar.base.y).rotated(by: ang - .pi / 2)
            bars[i].path = CGPath(roundedRect: CGRect(x: -w / 2, y: 0, width: w, height: h), cornerWidth: w * 0.4, cornerHeight: w * 0.4, transform: &tr)
            bars[i].fillColor = col; bars[i].shadowColor = col
            peaks[i].path = CGPath(roundedRect: CGRect(x: -w / 2, y: max(h + 4, bar.peak + 4), width: w, height: 3), cornerWidth: 1.5, cornerHeight: 1.5, transform: &tr)
            peaks[i].fillColor = Sprite.color(255, 255, 255, 0.9)
        }
        _ = up
        speakerA.update(at: s.pin, r: s.pinRadius, pulse: s.pinPulse)
        speakerB.update(at: s.head, r: s.headRadius, pulse: s.headPulse)
        while rings.count < s.rings.count { let l = lineLayer(Sprite.color(255, 255, 255, 0.6), 2); root.addSublayer(l); rings.append(l) }
        for (i, r) in s.rings.enumerated() { rings[i].path = circlePath(s.pin, r.0 * 1.4); rings[i].opacity = Float(r.1) }
    }

    @MainActor private final class Speaker {
        let root = CALayer()
        private let box = paperShape(Sprite.color(64, 66, 90), border: 2.6, depth: 2.2)
        private let cone = paperShape(Sprite.color(110, 114, 150), border: 1.6, depth: 0)
        private let dust = CAShapeLayer()
        init() { dust.fillColor = Sprite.color(30, 30, 46); for l in [box, cone, dust] { root.addSublayer(l) } }
        func update(at c: CGPoint, r: CGFloat, pulse: CGFloat) {
            box.path = CGPath(roundedRect: CGRect(x: c.x - r, y: c.y - r * 1.15, width: r * 2, height: r * 2.3), cornerWidth: r * 0.28, cornerHeight: r * 0.28, transform: nil)
            cone.path = circlePath(c, r * (0.66 + 0.1 * pulse))
            dust.path = circlePath(c, r * (0.26 + 0.06 * pulse))
        }
    }
}

// MARK: - DNA

@MainActor
final class DNALayers {
    let root = CALayer()
    private let backA = lineLayer(Sprite.color(255, 110, 140, 0.45), 3), backB = lineLayer(Sprite.color(70, 200, 200, 0.45), 3)
    private let frontAEdge = lineLayer(paperWhite, 8), frontBEdge = lineLayer(paperWhite, 8)
    private let frontA = lineLayer(Sprite.color(255, 110, 140), 5), frontB = lineLayer(Sprite.color(70, 200, 200), 5)
    private var rungs: [(CAShapeLayer, CAShapeLayer)] = []
    private let capA = paperShape(Sprite.color(255, 207, 86), border: 2.4), capB = paperShape(Sprite.color(255, 207, 86), border: 2.4)
    private static let pairs: [(CGColor, CGColor)] = [(Sprite.color(255, 207, 86), Sprite.color(96, 160, 255)), (Sprite.color(96, 160, 255), Sprite.color(255, 207, 86)),
                                                      (Sprite.color(110, 220, 130), Sprite.color(190, 120, 240)), (Sprite.color(190, 120, 240), Sprite.color(110, 220, 130))]

    init() {
        root.masksToBounds = false
        for l in [backA, backB, frontAEdge, frontBEdge, frontA, frontB, capA, capB] { root.addSublayer(l) }
    }

    private func split(_ pts: [(CGPoint, CGFloat)]) -> (front: CGPath, back: CGPath) {
        let f = CGMutablePath(), b = CGMutablePath()
        for i in 0..<(pts.count - 1) {
            let (p, q) = (pts[i], pts[i + 1])
            let path = (p.1 + q.1) >= 0 ? f : b
            path.move(to: p.0); path.addLine(to: q.0)
        }
        return (f, b)
    }

    func update(_ s: DNAScene) {
        root.opacity = Float(s.alpha)
        let a = split(s.strandA), b = split(s.strandB)
        backA.path = a.back; backB.path = b.back
        frontA.path = a.front; frontAEdge.path = a.front; frontB.path = b.front; frontBEdge.path = b.front
        while rungs.count < s.rungs.count {
            let x = lineLayer(Sprite.color(255, 255, 255), 3), y = lineLayer(Sprite.color(255, 255, 255), 3)
            root.insertSublayer(x, above: backB); root.insertSublayer(y, above: backB); rungs.append((x, y))
        }
        for (i, r) in s.rungs.enumerated() {
            let mid = CGPoint(x: (r.a.x + r.b.x) / 2, y: (r.a.y + r.b.y) / 2)
            let (ca, cb) = Self.pairs[r.pair % 4]
            rungs[i].0.path = polyline([r.a, mid]); rungs[i].1.path = polyline([mid, r.b])
            rungs[i].0.strokeColor = ca; rungs[i].1.strokeColor = cb
            let w = 2.2 + 1.6 * (r.depth + 1) / 2
            rungs[i].0.lineWidth = w; rungs[i].1.lineWidth = w
            let al = Float(0.45 + 0.55 * (r.depth + 1) / 2)
            rungs[i].0.opacity = al; rungs[i].1.opacity = al
        }
        capA.path = circlePath(s.pin, s.pinRadius * 0.55); capB.path = circlePath(s.head, s.headRadius * 0.55)
    }
}

// MARK: - Fishing

@MainActor
final class FishingLayers {
    let root = CALayer()
    private let water = CAShapeLayer()
    private let rod = lineLayer(Sprite.color(160, 112, 76), 6, depth: 1.6)
    private let rodHi = lineLayer(Sprite.color(206, 156, 112), 2)
    private let reel = paperShape(Sprite.color(235, 80, 90), border: 2.2)
    private let line = lineLayer(Sprite.color(255, 250, 238, 0.95), 1.6)
    private let bobberTop = paperShape(Sprite.color(235, 80, 90), border: 2, depth: 1.4), bobberBot = paperShape(paperWhite, border: 2, depth: 0)
    private var rippleLayers: [CAShapeLayer] = []
    private let fishBody = paperShape(Sprite.color(255, 160, 80), border: 2, depth: 1.6), fishTail = paperShape(Sprite.color(255, 130, 70), border: 2, depth: 0)
    private let fishEye = CAShapeLayer()
    private lazy var splash = DotPool(parent: root, image: softDot)

    init() {
        root.masksToBounds = false
        water.fillColor = Sprite.color(120, 190, 255, 0.28)
        fishEye.fillColor = Sprite.color(66, 48, 48)
        for l in [water, rod, rodHi, reel, line, bobberBot, bobberTop, fishTail, fishBody, fishEye] { root.addSublayer(l) }
    }

    func update(_ s: FishingScene) {
        root.opacity = Float(s.alpha)
        let r = s.headRadius
        water.path = CGPath(ellipseIn: CGRect(x: s.bobber.x - r * 3, y: s.bobber.y - r * 1.6, width: r * 6, height: r * 1.6), transform: nil)
        rod.path = polyline([s.rodBase, s.rodTip]); rodHi.path = polyline([s.rodBase, s.rodTip])
        reel.path = circlePath(CGPoint(x: s.rodBase.x + (s.rodTip.x - s.rodBase.x) * 0.18, y: s.rodBase.y + (s.rodTip.y - s.rodBase.y) * 0.18), s.pinRadius * 0.5)
        line.path = polyline(s.line)
        let br = max(7, r * 0.85)
        let dip = s.bobberDip * br * 0.6
        bobberTop.path = CGPath(ellipseIn: CGRect(x: s.bobber.x - br, y: s.bobber.y - dip, width: br * 2, height: br * 1.7), transform: nil)
        bobberBot.path = CGPath(ellipseIn: CGRect(x: s.bobber.x - br * 0.9, y: s.bobber.y - br * 1.4 - dip, width: br * 1.8, height: br * 1.6), transform: nil)
        while rippleLayers.count < s.ripples.count { let l = lineLayer(Sprite.color(255, 255, 255, 0.8), 1.8); root.insertSublayer(l, above: water); rippleLayers.append(l) }
        for (i, rp) in s.ripples.enumerated() {
            let c = CGPoint(x: s.bobber.x, y: s.bobber.y - br * 0.3)
            rippleLayers[i].path = CGPath(ellipseIn: CGRect(x: c.x - rp.0 * 1.6, y: c.y - rp.0 * 0.5, width: rp.0 * 3.2, height: rp.0), transform: nil)
            rippleLayers[i].opacity = Float(rp.1)
        }
        let showFish = s.fishAlpha > 0.02
        for l in [fishBody, fishTail, fishEye] { l.isHidden = !showFish; l.opacity = Float(s.fishAlpha) }
        if showFish {
            let k: CGFloat = 20
            let tr = CGAffineTransform(translationX: s.fish.x, y: s.fish.y).rotated(by: s.fishAngle)
            var t1 = tr
            fishBody.path = CGPath(ellipseIn: CGRect(x: -k, y: -k * 0.5, width: k * 2, height: k), transform: &t1)
            let tp = CGMutablePath(); tp.move(to: CGPoint(x: -k * 0.8, y: 0)); tp.addLine(to: CGPoint(x: -k * 1.7, y: k * 0.6)); tp.addLine(to: CGPoint(x: -k * 1.7, y: -k * 0.6)); tp.closeSubpath()
            var t2 = tr
            fishTail.path = tp.copy(using: &t2)
            var t3 = tr
            fishEye.path = CGPath(ellipseIn: CGRect(x: k * 0.55, y: k * 0.08, width: 5, height: 5), transform: &t3)
        }
        for (i, sp) in s.splash.enumerated() { splash.place(i, at: sp.0, size: 6, alpha: sp.1) }
        splash.hide(from: s.splash.count)
    }
}

// MARK: - Ribbon

@MainActor
final class RibbonLayers {
    let root = CALayer()
    private var quads: [CAShapeLayer] = []
    private let wand = paperShape(Sprite.color(190, 130, 90), border: 2.2, depth: 1.8)
    private let pom = paperShape(Sprite.color(255, 207, 86), border: 2, depth: 0)
    private let ring = lineLayer(Sprite.color(255, 250, 238), 4, depth: 1.4)

    init() { root.masksToBounds = false; for l in [wand, pom, ring] { root.addSublayer(l) } }

    func update(_ s: RibbonScene) {
        root.opacity = Float(s.alpha)
        let n = s.spine.count
        while quads.count < n - 1 {
            let l = CAShapeLayer(); l.lineWidth = 0.6; root.insertSublayer(l, at: 0); quads.append(l)
        }
        for i in 0..<(n - 1) {
            let a = s.spine[i], b = s.spine[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y, l = max(0.001, hypot(dx, dy))
            let nx = -dy / l, ny = dx / l
            let wa = s.width[i] * max(0.3, abs(s.twist[i])), wb = s.width[i + 1] * max(0.3, abs(s.twist[i + 1]))
            let p = CGMutablePath()
            p.move(to: CGPoint(x: a.x + nx * wa, y: a.y + ny * wa)); p.addLine(to: CGPoint(x: b.x + nx * wb, y: b.y + ny * wb))
            p.addLine(to: CGPoint(x: b.x - nx * wb, y: b.y - ny * wb)); p.addLine(to: CGPoint(x: a.x - nx * wa, y: a.y - ny * wa)); p.closeSubpath()
            quads[i].path = p
            let hue = 0.97 - 0.75 * CGFloat(i) / CGFloat(n)
            let shade: CGFloat = s.twist[i] > 0 ? 1.0 : 0.82
            let c = NSColor(hue: hue.truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: shade, alpha: 1).usingColorSpace(.sRGB)!
            let col = CGColor(srgbRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: 1)
            quads[i].fillColor = col; quads[i].strokeColor = col
        }
        let a = s.spine.first ?? s.pin
        wand.path = CGPath(roundedRect: CGRect(x: s.pin.x - s.pinRadius * 0.28, y: s.pin.y - s.pinRadius * 1.9, width: s.pinRadius * 0.56, height: s.pinRadius * 2.4), cornerWidth: s.pinRadius * 0.2, cornerHeight: s.pinRadius * 0.2, transform: nil)
        pom.path = circlePath(a, s.pinRadius * 0.4)
        ring.path = circlePath(s.head, s.headRadius * 0.7)
    }
}
