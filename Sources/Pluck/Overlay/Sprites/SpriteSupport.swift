import AppKit
import PluckCore
import QuartzCore

// MARK: - Sprite drawing helpers

enum Sprite {
    static func color(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    static func image(_ size: CGSize, scale: CGFloat = 3, _ draw: (CGContext) -> Void) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAllowsAntialiasing(true)
        draw(ctx)
        return ctx.makeImage()
    }

    static func radial(_ ctx: CGContext, center: CGPoint, radius: CGFloat, inner: CGColor, outer: CGColor) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [inner, outer] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
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
