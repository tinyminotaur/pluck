import AppKit
import Foundation
import TwangCore

/// Headless render of the real Metal blob shader to a PNG (`Twang --render-preview out.png`).
/// Used by CI so the look can be inspected without a display or a local Mac.
/// Grid: rows = light direction, columns = rest / stretched / taut.
@MainActor
enum PreviewRender {
    /// `themes == nil`: the standard grid (rows = light directions, current theme). Otherwise one row per theme.
    static func run(outputPath: String, themes: [LiquidTheme]? = nil) -> Int32 {
        guard let metal = ObsidianBlobMetal.shared else {
            FileHandle.standardError.write(Data("PreviewRender: no Metal device or shader failed to compile\n".utf8))
            return 2
        }

        let tile = CGSize(width: 500, height: 300)
        let scale: CGFloat = 2
        let scenes: [(pin: CGPoint, head: CGPoint, sag: CGFloat)] = [
            (CGPoint(x: 170, y: 150), CGPoint(x: 210, y: 140), 0),
            (CGPoint(x: 130, y: 150), CGPoint(x: 300, y: 120), 10),
            (CGPoint(x: 70, y: 170), CGPoint(x: 440, y: 90), -26),
        ]
        let lightSet: [SIMD2<Float>] = [SIMD2(-0.45, 0.8), SIMD2(0.6, 0.6), SIMD2(-0.2, -0.7)]
        let rows: [(light: SIMD2<Float>, theme: LiquidTheme)] = themes.map { ts in ts.map { (SIMD2<Float>(-0.45, 0.8), $0) } }
            ?? lightSet.map { ($0, TwangConfig.shared.theme) }
        let lights = rows.map(\.light)

        let W = Int(tile.width * scale) * scenes.count
        let H = Int(tile.height * scale) * lights.count
        guard let ctx = CGContext(
            data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return 3 }
        ctx.setFillColor(CGColor(red: 0.79, green: 0.8, blue: 0.83, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        for (r, row) in rows.enumerated() {
            let light = row.light
            let theme = row.theme
            for (c, s) in scenes.enumerated() {
                let n = 16
                let dx = s.head.x - s.pin.x, dy = s.head.y - s.pin.y
                let len = hypot(dx, dy)
                let prof = DumbbellMass.profile(DumbbellMass.Params(restRadius: 42), length: len, samples: n)
                var radii = prof.radii
                radii[0] = min(radii[0], prof.solution.pin * 0.88)
                radii[n - 1] = min(radii[n - 1], prof.solution.head * 0.88)
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
                // Round pin and head bulbs last (the shader treats the final two circles as pin and head).
                circles.append(.init(center: SIMD2(Float(s.pin.x), Float(s.pin.y)), radius: Float(prof.solution.pin)))
                circles.append(.init(center: SIMD2(Float(s.head.x), Float(s.head.y)), radius: Float(prof.solution.head)))

                let stretchT = min(1, max(0, (len - 40) / 200))
                let eased = stretchT * stretchT * (3 - 2 * stretchT)
                // Facets are off while the liquid is being tuned (TwangConfig.facetsEnabled).
                let facet: Float = 0
                _ = eased

                let look = ObsidianBlobMetal.Look(
                    lightDir: light, time: 1.3, shininess: 0.95, fresnel: 0.85, transmission: 0.7,
                    opacity: 0.92, shadow: 0.5,
                    baseColor: SIMD3(theme.body.r, theme.body.g, theme.body.b),
                    absorb: SIMD3(theme.absorb.r, theme.absorb.g, theme.absorb.b),
                    glow: SIMD3(theme.a.r, theme.a.g, theme.a.b),
                    facet: facet, facetSize: 22, ember: theme.ember,
                    themeA: SIMD4(theme.a.r, theme.a.g, theme.a.b, theme.sheen),
                    themeB: SIMD4(theme.b.r, theme.b.g, theme.b.b, theme.rim),
                    themeC: SIMD4(theme.c.r, theme.c.g, theme.c.b, 0),
                    gradient: SIMD3(theme.gradientScale, theme.gradientSpeed, theme.iridescence),
                    fill: theme.fill,
                    chrome: theme.chrome
                )
                guard let image = metal.render(
                    size: tile, scale: scale, circles: circles, spineCount: strandCount,
                    fillet: 42 * 0.38, look: look
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

    /// `Twang --render-compass out.png`: the real MetaballView drawn headlessly, with its integrated action labels.
    /// Rows are themes; columns are rest, pulled east (Go armed), and pulled north (Keep armed).
    static func runCompass(outputPath: String) -> Int32 {
        let tile = CGSize(width: 520, height: 380)
        let scale: CGFloat = 2
        let themes = [ThemeLibrary.obsidianEmber, ThemeLibrary.oilSlick, ThemeLibrary.neonJelly]
        let cols: [(pointer: CGPoint, armed: CompassRole?)] = [
            (CGPoint(x: 170, y: 190), nil),
            (CGPoint(x: 430, y: 200), .east),
            (CGPoint(x: 175, y: 330), .north),
        ]
        let W = Int(tile.width * scale) * cols.count, H = Int(tile.height * scale) * themes.count
        guard let ctx = CGContext(
            data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return 3 }
        ctx.setFillColor(CGColor(red: 0.16, green: 0.17, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let saved = TwangConfig.shared.themeID
        defer { TwangConfig.shared.themeID = saved }
        let items = Playground.context.items
        for (r, theme) in themes.enumerated() {
            TwangConfig.shared.themeID = theme.id
            for (c, col) in cols.enumerated() {
                let view = MetaballView(frame: NSRect(origin: .zero, size: tile))
                view.debugPose(pin: CGPoint(x: 170, y: 190), pointer: col.pointer, armed: col.armed, items: items, seconds: 1.6)
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(c) * tile.width * scale, y: CGFloat(themes.count - 1 - r) * tile.height * scale)
                ctx.scaleBy(x: scale, y: scale)
                ctx.clip(to: CGRect(origin: .zero, size: tile))
                let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = gc
                view.draw(CGRect(origin: .zero, size: tile))
                NSGraphicsContext.restoreGraphicsState()
                ctx.restoreGState()
                view.stopPhysics()
            }
        }
        guard let out = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { return 5 }
        do { try png.write(to: URL(fileURLWithPath: outputPath)); print("PreviewRender: wrote \(outputPath)"); return 0 }
        catch { return 7 }
    }

    /// `Twang --render-styles out.png`: every style (headless), four frames each: at rest, pulled, far, and armed or
    /// fired. Environment: `TWANG_STYLES=a,b` renders only those styles; `TWANG_PREVIEW_DIR=left|up|down|diag` pulls in
    /// another direction (to check nothing turns upside down).
    static func runStyles(outputPath: String) -> Int32 {
        PackLibrary.shared.start()
        guard let shapes = ShapeListMetal.shared else { return 2 }
        let tile = CGSize(width: 560, height: 340)
        let scale: CGFloat = 2
        let chords: [CGFloat] = [0, 150, 330, 330]

        // One row per style (the beam style once per energy variant, the Community style once per installed pack).
        struct Row { var style: AnimationStyle; var theme: LiquidTheme; var variant: Int }
        let glassTheme: [AnimationStyle: LiquidTheme] = [.ferro: ThemeLibrary.ferrofluid, .crystal: ThemeLibrary.amethyst, .gravity: ThemeLibrary.moltenGold,
                                                         .pearls: ThemeLibrary.mercury, .tendrils: ThemeLibrary.curse]
        var allRows: [Row] = []
        for st in AnimationStyle.allCases where st != .liquid {
            let n = st == .beam ? EnergyVariant.allCases.count : (st == .pack ? max(1, PackLibrary.shared.packs.filter(\.isValid).count) : 1)
            for v in 0..<n { allRows.append(Row(style: st, theme: glassTheme[st] ?? ThemeLibrary.mist, variant: v)) }
        }
        let only = (ProcessInfo.processInfo.environment["TWANG_STYLES"] ?? "").split(separator: ",").map(String.init)
        let rows = only.isEmpty ? allRows : allRows.filter { only.contains($0.style.rawValue) }
        let W = Int(tile.width * scale) * chords.count, H = Int(tile.height * scale) * max(1, rows.count)
        guard let ctx = CGContext(
            data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return 3 }
        ctx.setFillColor(CGColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        let dirName = ProcessInfo.processInfo.environment["TWANG_PREVIEW_DIR"] ?? "right"
        let pullDir: CGPoint = { switch dirName { case "left": return CGPoint(x: -1, y: 0); case "up": return CGPoint(x: 0, y: 1); case "down": return CGPoint(x: 0, y: -1)
            case "diag": return CGPoint(x: -0.8, y: -0.6); default: return CGPoint(x: 1, y: 0) } }()
        let pin = (dirName == "left" || dirName == "diag") ? CGPoint(x: tile.width - 130, y: 170) : (dirName == "down" ? CGPoint(x: 120, y: tile.height - 90) : CGPoint(x: 120, y: dirName == "up" ? 70 : 170))
        let dt: CGFloat = 1.0 / 120

        for (r, row) in rows.enumerated() {
            for (c, chord) in chords.enumerated() {
                let armed: CGFloat = c == 3 ? 1 : 0
                // The path the head takes. A gentle S for most; a diagonal box for the marquee; a loop for the lasso.
                let head: (CGFloat) -> CGPoint = { k in
                    switch row.style {
                    case .marquee: return CGPoint(x: pin.x + max(40, chord) * k * 0.9, y: pin.y + max(40, chord) * 0.7 * k)
                    case .freehand: let a = k * 2 * .pi * 0.92; let rr = max(50, chord * 0.3); return CGPoint(x: pin.x + rr * sin(a), y: pin.y + rr - rr * cos(a))
                    default:
                        return CGPoint(x: pin.x + pullDir.x * chord * k * (pullDir.y == 0 ? 1 : 0.55) + (pullDir.y != 0 ? 18 * k : 0),
                                       y: pin.y + pullDir.y * chord * k * (pullDir.x == 0 ? 0.62 : 0.55) + (pullDir.y == 0 ? 18 * k * CGFloat(sin(Double(k * 3))) : 0))
                    }
                }
                if row.style == .beam {
                    TwangConfig.shared.beamVariantID = EnergyVariant.allCases[row.variant % EnergyVariant.allCases.count].rawValue
                    TwangConfig.shared.beamChargeMode = true
                }
                if row.style == .pack {
                    let valid = PackLibrary.shared.packs.filter(\.isValid)
                    if !valid.isEmpty { TwangConfig.shared.packID = valid[row.variant % valid.count].id }
                }
                if ProcessInfo.processInfo.environment["TWANG_PREVIEW_VERBOSE"] != nil { FileHandle.standardError.write(Data("row \(r) \(row.style) col \(c)\n".utf8)) }

                var t: CGFloat = 0
                if let glass = ShapeRunners.make(row.style) {
                    glass.reset(pin: pin, radius: 42)
                    let endT: CGFloat = row.style == .crystal ? (chord == 0 ? 2.4 : 3.2) : 2.4
                    while t < endT { glass.step(dt: dt, pin: pin, head: head(min(1, t / 0.9))); t += dt }
                    let look = ShapeListMetal.look(mode: row.style == .crystal ? .crystal : .ferro, theme: row.theme, time: 1.3)
                    guard let img = shapes.render(size: tile, scale: scale, prims: glass.primitives(emerge: 1, glow: armed), look: look) else { return 4 }
                    ctx.draw(img, in: CGRect(x: CGFloat(c) * tile.width * scale, y: CGFloat(rows.count - 1 - r) * tile.height * scale, width: tile.width * scale, height: tile.height * scale))
                    continue
                }
                guard let runner = VectorRunners.make(row.style) else { continue }
                runner.reset(pin: pin, radius: 42)
                if row.style == .beam {
                    // Charge, aim (columns 0 and 1), then fire (columns 2 and 3).
                    while t < (c == 0 ? 1.0 : 1.9) { runner.step(dt: dt, pin: pin, head: head(min(1, t / 0.5))); t += dt }
                    if c >= 2 { runner.release(commit: true, direction: CGPoint(x: 1, y: 0)); for _ in 0..<Int(120 * (c == 2 ? 0.22 : 0.62)) { runner.step(dt: dt, pin: pin, head: head(1)) } }
                } else {
                    let endT: CGFloat = (row.style == .marker || row.style == .laser) ? 0.55 + CGFloat(c) * 0.12 : (row.style == .freehand ? 1.2 + CGFloat(c) * 0.3 : 2.6 + CGFloat(c) * 0.37)
                    while t < endT { runner.step(dt: dt, pin: pin, head: head(min(1, t / (row.style == .freehand ? 1.1 : 0.9)))); t += dt }
                    if c == 3 { runner.release(commit: true, direction: CGPoint(x: 1, y: 0)); for _ in 0..<14 { runner.step(dt: dt, pin: pin, head: head(1)) } }
                }
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(c) * tile.width * scale, y: CGFloat(rows.count - 1 - r) * tile.height * scale)
                ctx.scaleBy(x: scale, y: scale)
                ctx.clip(to: CGRect(x: 0, y: 0, width: tile.width, height: tile.height))
                let host = VectorStyleHost()
                host.attach(runner.layer)
                host.present(runner, emerge: 1, glow: armed)
                host.pruneHidden()
                host.root.render(in: ctx)
                ctx.restoreGState()
            }
        }
        guard let out = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { return 5 }
        do { try png.write(to: URL(fileURLWithPath: outputPath)); print("PreviewRender: wrote \(outputPath)"); return 0 }
        catch { return 7 }
    }

    /// `Twang --style-perf`: the per-frame cost (simulation + layer updates) of every sprite style, in milliseconds.
    static func runPerf() -> Int32 {
        let pin = CGPoint(x: 300, y: 400)
        var rows: [(String, Double, Double)] = []
        for st in AnimationStyle.allCases {
            guard let runner = VectorRunners.make(st) else { continue }
            let host = VectorStyleHost()
            host.attach(runner.layer)
            runner.reset(pin: pin, radius: 42)
            var worst = 0.0, total = 0.0
            let frames = 360
            for i in 0..<frames {
                let k = min(1, CGFloat(i) / 60)
                let head = CGPoint(x: pin.x + 620 * k, y: pin.y + 40 * CGFloat(sin(Double(i) * 0.05)) * k)
                let t0 = CFAbsoluteTimeGetCurrent()
                runner.step(dt: 1.0 / 120, pin: pin, head: head)
                runner.step(dt: 1.0 / 120, pin: pin, head: head)
                host.present(runner, emerge: 1, glow: 0)
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                total += ms; worst = max(worst, ms)
            }
            rows.append((st.rawValue, total / Double(frames), worst))
        }
        print(String(format: "%-12@ %8@ %8@", "style" as NSString, "avg ms" as NSString, "worst" as NSString))
        for r in rows.sorted(by: { $0.1 > $1.1 }) { print(String(format: "%-12@ %8.3f %8.3f", r.0 as NSString, r.1, r.2)) }
        return 0
    }

    /// `Twang --render-style-commit out.png`: the real view driving each style through a pull, then a commit.
    static func runStyleCommit(outputPath: String) -> Int32 {
        guard let shapes = ShapeListMetal.shared else { return 2 }
        let tile = CGSize(width: 620, height: 300)
        let scale: CGFloat = 2
        let times: [CGFloat] = [0, 0.05, 0.12, 0.25, 0.45]
        let combos: [(AnimationStyle, LiquidTheme)] = [(.ferro, ThemeLibrary.ferrofluid), (.crystal, ThemeLibrary.amethyst)]
        let W = Int(tile.width * scale) * times.count, H = Int(tile.height * scale) * combos.count
        guard let ctx = CGContext(
            data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return 3 }
        ctx.setFillColor(CGColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let savedStyle = TwangConfig.shared.styleID, savedTheme = TwangConfig.shared.themeID
        defer { TwangConfig.shared.styleID = savedStyle; TwangConfig.shared.themeID = savedTheme }
        for (r, combo) in combos.enumerated() {
            TwangConfig.shared.styleID = combo.0.rawValue
            TwangConfig.shared.themeID = combo.1.id
            let view = MetaballView(frame: NSRect(origin: .zero, size: tile))
            view.debugPose(pin: CGPoint(x: 110, y: 150), pointer: CGPoint(x: 440, y: 160), armed: .east,
                           items: Playground.context.items, seconds: 2.2)
            let pre = view.debugStylePrims()
            print("style \(combo.0.rawValue): before commit \(pre.count) prims | circles \(pre.filter { $0.kind == .circle }.count) (tight \(pre.filter { $0.blend == .tight }.count)) cones \(pre.filter { $0.kind == .cone }.count) shards \(pre.filter { $0.kind == .shard }.count)")
            view.debugCommit(role: .east)
            var t: CGFloat = 0
            for (c, target) in times.enumerated() {
                while t < target - 1e-5 { view.debugAdvance(dt: 1.0 / 240); t += 1.0 / 240 }
                let look = ShapeListMetal.look(mode: combo.0 == .ferro ? .ferro : .crystal, theme: combo.1, time: 1.3)
                if let img = shapes.render(size: tile, scale: scale, prims: view.debugStylePrims(), look: look) {
                    ctx.draw(img, in: CGRect(x: CGFloat(c) * tile.width * scale, y: CGFloat(combos.count - 1 - r) * tile.height * scale,
                                             width: tile.width * scale, height: tile.height * scale))
                }
            }
            view.stopPhysics()
        }
        guard let out = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { return 5 }
        do { try png.write(to: URL(fileURLWithPath: outputPath)); print("PreviewRender: wrote \(outputPath)"); return 0 }
        catch { return 7 }
    }

    /// `Twang --render-pinch out.png`: pull east, commit, and show the pinch-off over the next 420 ms.
    static func runPinch(outputPath: String) -> Int32 {
        let tile = CGSize(width: 560, height: 260)
        let scale: CGFloat = 2
        let times: [CGFloat] = [0, 0.04, 0.08, 0.14, 0.24, 0.42]
        let cols = 3
        let rows = (times.count + cols - 1) / cols
        let W = Int(tile.width * scale) * cols, H = Int(tile.height * scale) * rows
        guard let ctx = CGContext(
            data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return 3 }
        ctx.setFillColor(CGColor(red: 0.16, green: 0.17, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let items = Playground.context.items
        let view = MetaballView(frame: NSRect(origin: .zero, size: tile))
        let pin = CGPoint(x: 120, y: 130)
        view.debugPose(pin: pin, pointer: CGPoint(x: 330, y: 130), armed: .east, items: items, seconds: 1.4)
        view.debugCommit(role: .east)
        var t: CGFloat = 0
        for (i, target) in times.enumerated() {
            while t < target - 1e-5 { view.debugAdvance(dt: 1.0 / 240); t += 1.0 / 240 }
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(i % cols) * tile.width * scale, y: CGFloat(rows - 1 - i / cols) * tile.height * scale)
            ctx.scaleBy(x: scale, y: scale)
            ctx.clip(to: CGRect(origin: .zero, size: tile))
            let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc
            view.draw(CGRect(origin: .zero, size: tile))
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
        }
        view.stopPhysics()
        guard let out = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { return 5 }
        do { try png.write(to: URL(fileURLWithPath: outputPath)); print("PreviewRender: wrote \(outputPath)"); return 0 }
        catch { return 7 }
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
