import AppKit
import Foundation
import ImageIO
import Metal
import PluckCore
import UniformTypeIdentifiers

/// `Pluck --snapshot <dir>`: renders scripted gestures offscreen to PNGs (light + dark backdrops).
/// Touches no input, no cursor, no permissions — safe for iterating on look and physics.
@MainActor
enum Snapshot {
    private static let canvas = CGSize(width: 520, height: 400)
    private static let scale: CGFloat = 2
    private static let pin = CGPoint(x: 170, y: 190)

    static func run(outputDir: String) -> Int32 {
        guard let renderer = BlobRenderer() else {
            print("Metal unavailable")
            return 1
        }
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let cfg = FeelLabConfig.shared

        struct Scenario {
            let name: String
            let build: (FeelLabConfig) -> LiquidView
        }

        func drive(
            _ cfg: FeelLabConfig,
            roles: [CompassRole] = CompassRole.allCases,
            duration: CGFloat,
            bloomAt: CGFloat = 0.08,
            release: (at: CGFloat, commit: Bool)? = nil,
            path: (CGFloat) -> CGPoint
        ) -> LiquidView {
            let items = FeelLab.context.items.filter { roles.contains($0.role) }
            let view = LiquidView(frame: NSRect(origin: .zero, size: canvas))
            view.begin(pin: pin, items: items, reduceMotion: false, startDisplayLink: false)
            var tracker = GestureTracker(pin: pin, available: roles)
            var time: CGFloat = 0
            var released = false
            let dt: CGFloat = 1.0 / 120
            while time < duration {
                let p = path(time)
                tracker.update(pointer: p)
                if !released {
                    view.setTarget(GestureMath.virtualHead(pin: pin, pointer: p, gainBoost: CGFloat(cfg.gainBoost), maxLength: CGFloat(cfg.maxLength)))
                    view.setCaptured(tracker.captured)
                    if time >= bloomAt { view.setBloom(true) }
                }
                if let r = release, !released, time >= r.at {
                    released = true
                    view.release(commit: r.commit ? tracker.direction : nil, role: r.commit ? tracker.releaseRole : nil)
                }
                view.advanceManually(dt: dt)
                time += dt
            }
            return view
        }

        func ease(_ x: CGFloat) -> CGFloat { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }

        let scenarios: [Scenario] = [
            .init(name: "1-arming-60ms") { c in drive(c, duration: 0.06, bloomAt: 9) { _ in pin } },
            .init(name: "2-rest-bloomed") { c in drive(c, duration: 0.6) { _ in pin } },
            .init(name: "3-pull-east-70") { c in
                drive(c, duration: 0.9) { t in CGPoint(x: pin.x + 70 * ease(t / 0.2), y: pin.y) }
            },
            .init(name: "4-long-northeast-260") { c in
                drive(c, duration: 1.0) { t in
                    let e = ease(t / 0.25)
                    return CGPoint(x: pin.x + 150 * e, y: pin.y + 110 * e)
                }
            },
            .init(name: "5-whip-mid-swing") { c in
                drive(c, duration: 0.52) { t in
                    let a = -0.6 + 4.2 * ease((t - 0.2) / 0.3)
                    let r: CGFloat = 120
                    return CGPoint(x: pin.x + cos(a) * r, y: pin.y + sin(a) * r * 0.9)
                }
            },
            .init(name: "6-captured-north") { c in
                drive(c, duration: 0.9) { t in CGPoint(x: pin.x + 6, y: pin.y + 82 * ease(t / 0.2)) }
            },
            .init(name: "7-commit-east-40ms") { c in
                drive(c, duration: 0.9 + 0.04, release: (at: 0.9, commit: true)) { t in
                    CGPoint(x: pin.x + 80 * ease(t / 0.2), y: pin.y)
                }
            },
            .init(name: "8-commit-east-120ms") { c in
                drive(c, duration: 0.9 + 0.12, release: (at: 0.9, commit: true)) { t in
                    CGPoint(x: pin.x + 80 * ease(t / 0.2), y: pin.y)
                }
            },
            .init(name: "9-cancel-90ms") { c in
                drive(c, duration: 0.9 + 0.09, release: (at: 0.9, commit: false)) { t in
                    CGPoint(x: pin.x + 80 * ease(t / 0.2), y: pin.y)
                }
            },
            .init(name: "10-two-roles-only") { c in
                drive(c, roles: [.east, .south], duration: 0.8) { t in CGPoint(x: pin.x + 70 * ease(t / 0.2), y: pin.y) }
            },
        ]

        var failures = 0
        for s in scenarios {
            let view = s.build(cfg)
            let look = cfg.look(time: 1.0, light: SIMD2(-0.45, 0.8))
            guard var rgba = render(renderer: renderer, tether: view.tether, look: look) else { failures += 1; continue }
            addLabels(from: view, to: &rgba)
            let w = Int(canvas.width * scale), h = Int(canvas.height * scale)
            let out = sheet(rgba: rgba, w: w, h: h)
            let path = (outputDir as NSString).appendingPathComponent("\(s.name).png")
            if write(out.data, width: out.width, height: h, to: path) { print("wrote \(path)") } else { failures += 1 }
        }
        return failures == 0 ? 0 : 1
    }

    /// Composites the real label layers (premultiplied) over the rendered liquid.
    private static func addLabels(from view: LiquidView, to bgra: inout [UInt8]) {
        let w = Int(canvas.width * scale), h = Int(canvas.height * scale)
        var labels = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
        labels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue) else { return }
            ctx.scaleBy(x: scale, y: scale)
            view.renderLabels(into: ctx)
        }
        // A bitmap CGContext's memory is already top-row-first, same as the Metal readback: no flip.
        let flipped = labels
        for i in stride(from: 0, to: bgra.count, by: 4) {
            let la = Float(flipped[i + 3]) / 255
            for c in 0..<4 {
                let v = Float(flipped[i + c]) + Float(bgra[i + c]) * (1 - la)
                bgra[i + c] = UInt8(max(0, min(255, v)))
            }
        }
    }

    private static func render(renderer: BlobRenderer, tether: LiquidTether, look: BlobRenderer.Look) -> [UInt8]? {
        let w = Int(canvas.width * scale), h = Int(canvas.height * scale)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: BlobRenderer.pixelFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let tex = renderer.device.makeTexture(descriptor: desc),
              let cmd = renderer.makeCommandBuffer() else { return nil }
        renderer.encode(into: tex, commandBuffer: cmd, origin: .zero, scale: scale, primitives: tether.primitives(), look: look)
        cmd.commit()
        cmd.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    /// Left: light desktop. Right: dark desktop. Premultiplied BGRA over a gradient backdrop.
    private static func sheet(rgba bgra: [UInt8], w: Int, h: Int) -> (data: [UInt8], width: Int) {
        let outW = w * 2
        var out = [UInt8](repeating: 255, count: outW * h * 4)
        for half in 0..<2 {
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    let b = Float(bgra[i]) / 255, g = Float(bgra[i + 1]) / 255, r = Float(bgra[i + 2]) / 255, a = Float(bgra[i + 3]) / 255
                    let fy = Float(y) / Float(h)
                    // Backdrops with a little structure so edges/shadows are judged against detail.
                    let stripe: Float = ((x / 24 + y / 24) % 2 == 0) ? 0.0 : 0.025
                    let bg: (Float, Float, Float)
                    if half == 0 {
                        let v = 0.93 - 0.08 * fy + stripe
                        bg = (v, v, v + 0.01)
                    } else {
                        let v = 0.10 + 0.06 * fy + stripe
                        bg = (v, v + 0.005, v + 0.02)
                    }
                    let o = (y * outW + half * w + x) * 4
                    out[o] = UInt8(max(0, min(255, (b + bg.2 * (1 - a)) * 255)))
                    out[o + 1] = UInt8(max(0, min(255, (g + bg.1 * (1 - a)) * 255)))
                    out[o + 2] = UInt8(max(0, min(255, (r + bg.0 * (1 - a)) * 255)))
                    out[o + 3] = 255
                }
            }
        }
        return (out, outW)
    }

    private static func write(_ bgra: [UInt8], width: Int, height: Int, to path: String) -> Bool {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue))
        guard let provider = CGDataProvider(data: Data(bgra) as CFData),
              let img = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                space: cs, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest)
    }
}
