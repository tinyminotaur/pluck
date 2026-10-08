import AppKit
import Foundation
import PluckCore

/// Headless render of the real Metal blob shader to a PNG (`Pluck --render-preview out.png`).
/// Used by CI so the look can be inspected without a display or a local Mac.
/// Grid: rows = light direction, columns = rest / stretched / taut.
@MainActor
enum PreviewRender {
    static func run(outputPath: String) -> Int32 {
        guard let metal = ObsidianBlobMetal.shared else {
            FileHandle.standardError.write(Data("PreviewRender: no Metal device or shader failed to compile\n".utf8))
            return 2
        }

        let tile = CGSize(width: 500, height: 300)
        let scale: CGFloat = 2
        let params = BlobMassParams.default
        let scenes: [(pin: CGPoint, head: CGPoint, sag: CGFloat)] = [
            (CGPoint(x: 170, y: 150), CGPoint(x: 210, y: 140), 0),
            (CGPoint(x: 130, y: 150), CGPoint(x: 300, y: 120), 10),
            (CGPoint(x: 70, y: 170), CGPoint(x: 440, y: 90), -26),
        ]
        let lights: [SIMD2<Float>] = [SIMD2(-0.45, 0.8), SIMD2(0.6, 0.6), SIMD2(-0.2, -0.7)]

        let W = Int(tile.width * scale) * scenes.count
        let H = Int(tile.height * scale) * lights.count
        guard let ctx = CGContext(
            data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return 3 }
        ctx.setFillColor(CGColor(red: 0.79, green: 0.8, blue: 0.83, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        for (r, light) in lights.enumerated() {
            for (c, s) in scenes.enumerated() {
                let n = 16
                let dx = s.head.x - s.pin.x, dy = s.head.y - s.pin.y
                let len = hypot(dx, dy)
                let radii = BlobMass.radiusProfile(length: len, samples: n, params: params)
                let nx = -dy / max(len, 1), ny = dx / max(len, 1)
                var circles: [ObsidianBlobMetal.Circle] = []
                for i in 0..<n {
                    let t = CGFloat(i) / CGFloat(n - 1)
                    let bow = sin(.pi * t) * s.sag * (1 - 0.3 * t)
                    circles.append(.init(
                        center: SIMD2(Float(s.pin.x + dx * t + nx * bow), Float(s.pin.y + dy * t + ny * bow)),
                        radius: Float(radii[i])
                    ))
                }
                // Same smoothing as the live view: spline through the particles, softened taper.
                let smooth = StrandSmoothing.resample(
                    points: circles.map { CGPoint(x: CGFloat($0.center.x), y: CGFloat($0.center.y)) },
                    radii: StrandSmoothing.smoothRadii(circles.map { CGFloat($0.radius) }, passes: 2),
                    subdivisions: 3
                )
                circles = zip(smooth.points, smooth.radii).map {
                    ObsidianBlobMetal.Circle(center: SIMD2(Float($0.x), Float($0.y)), radius: Float($1))
                }
                let strandCount = circles.count
                // Organic lump clusters (same generator as the live view), then pin and head last.
                let pinR0 = max(radii[0], params.restRadius * params.pinMinFraction * 0.75)
                let headR0 = max(radii[n - 1], params.restRadius * params.headMinFraction * 0.85)
                for sp in BlobLumps.specs(seed: UInt64(7 + c), count: 4) {
                    let l = BlobLumps.place(sp, center: s.pin, baseRadius: pinR0, time: 1.3)
                    circles.append(.init(center: SIMD2(Float(l.center.x), Float(l.center.y)), radius: Float(l.radius)))
                }
                for sp in BlobLumps.specs(seed: UInt64(99 + c), count: 2) {
                    let l = BlobLumps.place(sp, center: s.head, baseRadius: headR0, time: 1.3)
                    circles.append(.init(center: SIMD2(Float(l.center.x), Float(l.center.y)), radius: Float(l.radius)))
                }
                circles.append(.init(center: SIMD2(Float(s.pin.x), Float(s.pin.y)),
                                     radius: Float(max(radii[0], params.restRadius * params.pinMinFraction * 0.75))))
                circles.append(.init(center: SIMD2(Float(s.head.x), Float(s.head.y)),
                                     radius: Float(max(radii[n - 1], params.restRadius * params.headMinFraction * 0.85))))

                let stretchT = min(1, max(0, (len - 40) / 200))
                let eased = stretchT * stretchT * (3 - 2 * stretchT)
                // Facets are off while the liquid is being tuned (FeelLabConfig.facetsEnabled).
                let facet: Float = 0
                _ = eased

                let look = ObsidianBlobMetal.Look(
                    lightDir: light, time: 1.3, shininess: 0.95, fresnel: 0.85, transmission: 0.7,
                    opacity: 0.92, edgeSoft: 0.1,
                    baseColor: SIMD3(0.04, 0.034, 0.03),
                    absorb: ObsidianPalette.absorb(depth: 0.75),
                    glow: ObsidianPalette.glow(warmth: 0.45),
                    facet: facet, facetSize: 22, ember: 0.55
                )
                guard let image = metal.render(
                    size: tile, scale: scale, circles: circles, spineCount: strandCount,
                    fillet: params.restRadius * 0.22, look: look
                ) else {
                    FileHandle.standardError.write(Data("PreviewRender: render failed\n".utf8))
                    return 4
                }
                print(stats(of: image, label: "light\(r) scene\(c) len=\(Int(len)) facet=\(String(format: "%.2f", facet))"))
                // Row 0 at the top of the output image.
                let origin = CGPoint(
                    x: CGFloat(c) * tile.width * scale,
                    y: CGFloat(lights.count - 1 - r) * tile.height * scale
                )
                ctx.draw(image, in: CGRect(origin: origin, size: CGSize(width: tile.width * scale, height: tile.height * scale)))
            }
        }

        guard let out = ctx.makeImage() else { return 5 }
        let rep = NSBitmapImageRep(cgImage: out)
        guard let png = rep.representation(using: .png, properties: [:]) else { return 6 }
        do {
            try png.write(to: URL(fileURLWithPath: outputPath))
            print("PreviewRender: wrote \(outputPath) (\(W)x\(H))")
            return 0
        } catch {
            FileHandle.standardError.write(Data("PreviewRender: \(error)\n".utf8))
            return 7
        }
    }

    /// Coverage and brightness summary so a log reader can sanity-check a render without the PNG.
    private static func stats(of image: CGImage, label: String) -> String {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let c = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return "\(label): stats unavailable" }
        var covered = 0
        var lumSum = 0.0
        var lumMax = 0.0
        var bright = 0
        var i = 0
        while i < buf.count {
            let a = Double(buf[i + 3])
            if a > 16 {
                covered += 1
                let lum = (0.2126 * Double(buf[i]) + 0.7152 * Double(buf[i + 1]) + 0.0722 * Double(buf[i + 2])) / max(a, 1)
                lumSum += lum
                lumMax = max(lumMax, lum)
                if lum > 0.8 { bright += 1 }
            }
            i += 4
        }
        let total = Double(w * h)
        let cov = Double(covered) / total * 100
        let mean = covered > 0 ? lumSum / Double(covered) : 0
        let glint = covered > 0 ? Double(bright) / Double(covered) * 100 : 0
        return String(format: "%@: coverage=%.1f%% meanLum=%.2f maxLum=%.2f glintPixels=%.1f%%",
                      label, cov, mean, lumMax, glint)
    }
}
