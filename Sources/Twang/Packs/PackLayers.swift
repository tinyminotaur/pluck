import AppKit
import TwangCore
import QuartzCore

/// Draws a community pack's draw operations with pooled Core Animation layers.
@MainActor
final class PackLayers {
    let root = CALayer()
    var packDirectory: URL?
    private var paths: [CAShapeLayer] = []
    private var shapes: [CAShapeLayer] = []
    private var texts: [CATextLayer] = []
    private var images: [CALayer] = []
    private static var unit: [String: CGPath] = [:]

    init() { root.masksToBounds = false }

    private static func unitPath(_ kind: String) -> CGPath {
        if let p = unit[kind] { return p }
        let p = CGMutablePath()
        switch kind {
        case "rect": p.addRect(CGRect(x: -1, y: -1, width: 2, height: 2))
        case "diamond": p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 1, y: 0)); p.addLine(to: CGPoint(x: 0, y: -1)); p.addLine(to: CGPoint(x: -1, y: 0)); p.closeSubpath()
        case "triangle": p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 0.87, y: -0.5)); p.addLine(to: CGPoint(x: -0.87, y: -0.5)); p.closeSubpath()
        case "star":
            for i in 0..<10 {
                let r: CGFloat = i % 2 == 0 ? 1 : 0.45, a = .pi / 2 + CGFloat(i) * .pi / 5
                let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        case "heart": p.addPath(heartPath())
        case "drop":
            p.move(to: CGPoint(x: 0, y: 1)); p.addCurve(to: CGPoint(x: 0, y: -1), control1: CGPoint(x: 0.9, y: -0.1), control2: CGPoint(x: 1, y: -1))
            p.addCurve(to: CGPoint(x: 0, y: 1), control1: CGPoint(x: -1, y: -1), control2: CGPoint(x: -0.9, y: -0.1)); p.closeSubpath()
        case "cross":
            let w: CGFloat = 0.3
            p.addRect(CGRect(x: -1, y: -w, width: 2, height: w * 2)); p.addRect(CGRect(x: -w, y: -1, width: w * 2, height: 2))
        case "spark":
            for k in 0..<4 {
                let a = CGFloat(k) * .pi / 2
                let tip = CGPoint(x: cos(a), y: sin(a)), side1 = CGPoint(x: cos(a + .pi / 2) * 0.16, y: sin(a + .pi / 2) * 0.16)
                p.move(to: .zero); p.addQuadCurve(to: tip, control: CGPoint(x: side1.x + tip.x * 0.2, y: side1.y + tip.y * 0.2))
                p.addQuadCurve(to: .zero, control: CGPoint(x: -side1.x + tip.x * 0.2, y: -side1.y + tip.y * 0.2))
            }
        default: p.addEllipse(in: CGRect(x: -1, y: -1, width: 2, height: 2))      // circle, ring
        }
        unit[kind] = p
        return p
    }

    private func color(_ c: PackRGBA) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a) }

    func update(_ ops: [PackOp]) {
        var pi = 0, si = 0, ti = 0, ii = 0
        for op in ops {
            switch op {
            case .path(let pts, let c, let w, let dash, let phase, let glow, let fill, let closed):
                if paths.count <= pi { let l = CAShapeLayer(); l.lineCap = .round; l.lineJoin = .round; root.addSublayer(l); paths.append(l) }
                let l = paths[pi]; pi += 1
                l.isHidden = false
                let p = CGMutablePath()
                if let f = pts.first { p.move(to: f); for q in pts.dropFirst() { p.addLine(to: q) }; if closed { p.closeSubpath() } }
                l.path = p
                l.strokeColor = color(c); l.lineWidth = w
                l.fillColor = fill.map(color)
                l.lineDashPattern = dash.isEmpty ? nil : dash.map { NSNumber(value: Double($0)) }
                l.lineDashPhase = phase
                l.shadowColor = color(c); l.shadowRadius = glow; l.shadowOpacity = glow > 0 ? 1 : 0; l.shadowOffset = .zero
            case .shape(let kind, let pos, let size, let size2, let rot, let c, let stroke, let sw, let glow):
                if shapes.count <= si { let l = CAShapeLayer(); l.lineJoin = .round; root.addSublayer(l); shapes.append(l) }
                let l = shapes[si]; si += 1
                l.isHidden = false
                l.path = Self.unitPath(kind)
                let ring = kind == "ring"
                l.fillColor = ring ? nil : color(c)
                l.strokeColor = ring ? color(c) : stroke.map(color)
                l.lineWidth = (ring ? max(1, sw) : (stroke == nil ? 0 : sw)) / max(0.5, (size + size2) / 2)
                var t = CATransform3DMakeTranslation(pos.x, pos.y, 0)
                t = CATransform3DRotate(t, rot, 0, 0, 1)
                t = CATransform3DScale(t, size, size2, 1)
                l.transform = t
                l.shadowColor = color(c); l.shadowRadius = glow; l.shadowOpacity = glow > 0 ? 1 : 0; l.shadowOffset = .zero
            case .text(let s, let pos, let size, let c, let rot):
                if texts.count <= ti { let l = CATextLayer(); l.contentsScale = 3; l.alignmentMode = .center; root.addSublayer(l); texts.append(l) }
                let l = texts[ti]; ti += 1
                l.isHidden = false
                l.string = s; l.fontSize = size; l.foregroundColor = color(c)
                l.font = NSFont.systemFont(ofSize: size, weight: .semibold)
                l.bounds = CGRect(x: 0, y: 0, width: 260, height: size * 1.4)
                l.position = pos
                l.transform = CATransform3DMakeRotation(rot, 0, 0, 1)
            case .image(let asset, let pos, let size, let rot, let alpha):
                if images.count <= ii { let l = CALayer(); root.addSublayer(l); images.append(l) }
                let l = images[ii]; ii += 1
                l.isHidden = false
                if let dir = packDirectory, let img = PackLibrary.shared.loadImage(pack: dir, asset: asset) {
                    l.contents = img
                    let ratio = CGFloat(img.width) / max(1, CGFloat(img.height))
                    l.bounds = CGRect(x: 0, y: 0, width: size * ratio, height: size)
                }
                l.position = pos; l.opacity = Float(alpha)
                l.transform = CATransform3DMakeRotation(rot, 0, 0, 1)
            }
        }
        for k in pi..<paths.count { paths[k].isHidden = true }
        for k in si..<shapes.count { shapes[k].isHidden = true }
        for k in ti..<texts.count { texts[k].isHidden = true }
        for k in ii..<images.count { images[k].isHidden = true }
    }
}

/// Runs one community pack as a style.
@MainActor
final class PackRunner: VectorRunner {
    private let layers = PackLayers()
    private var sim = PackSim()
    var layer: CALayer { layers.root }
    var isFinished: Bool { sim.isFinished }
    let releaseBehavior: ReleaseBehavior?

    init(pack: PackLibrary.Installed, params: [String: Double], theme: LiquidTheme) {
        sim.program = pack.program
        sim.params = params
        func c(_ x: RGB) -> PackRGBA { PackRGBA(r: CGFloat(x.r), g: CGFloat(x.g), b: CGFloat(x.b), a: 1) }
        sim.theme = ["@a": c(theme.a), "@b": c(theme.b), "@c": c(theme.c), "@body": c(theme.body)]
        layers.packDirectory = pack.directory
        releaseBehavior = pack.program?.releaseBehavior
    }

    func reset(pin: CGPoint, radius: CGFloat) { sim.base.bodyRadius = radius * 0.7; sim.reset(pin: pin) }
    func step(dt: CGFloat, pin: CGPoint, head: CGPoint) { sim.step(dt: dt, pin: pin, head: head) }
    func release(commit: Bool, direction: CGPoint) { sim.release(commit: commit ? direction : nil) }
    func present(emerge: CGFloat, glow: CGFloat) { layers.update(sim.evaluate(emerge: emerge)) }
}
