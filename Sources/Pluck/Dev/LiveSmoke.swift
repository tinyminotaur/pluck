import AppKit
import CoreGraphics
import ImageIO
import PluckCore
import UniformTypeIdentifiers

/// `Pluck --live-smoke out.png`: opens a small borderless, click-through window for a few seconds, drives the REAL
/// view (Metal layer + vsync display link) with a scripted pull, measures real frame pacing, and saves what the
/// window server actually composited. No input hooks, no cursor changes, no permissions.
@MainActor
enum LiveSmoke {
    static func run(outputPath: String, style: String = "liquid") -> Never {
        let savedStyle = FeelLabConfig.shared.styleID, savedTheme = FeelLabConfig.shared.themeID
        FeelLabConfig.shared.styleID = style
        switch style {
        case "ferro": FeelLabConfig.shared.themeID = ThemeLibrary.ferrofluid.id
        case "crystal": FeelLabConfig.shared.themeID = ThemeLibrary.amethyst.id
        default: break
        }
        defer { FeelLabConfig.shared.styleID = savedStyle; FeelLabConfig.shared.themeID = savedTheme }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let size = CGSize(width: 1000, height: 560)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]   // same as the real overlay panel
        window.ignoresMouseEvents = true
        window.hasShadow = false

        let view = MetaballView(frame: NSRect(origin: .zero, size: size))
        window.contentView = view
        window.orderFrontRegardless()

        let pin = CGPoint(x: 220, y: 280)
        view.pin = pin
        view.head = pin
        view.pointerTarget = pin
        view.emerge = 1
        view.bloom = 1
        view.items = FeelLab.context.items
        view.startPhysics()
        view.debugRecordFrames = true
        print("LiveSmoke: screen \(Int(screen.frame.width))x\(Int(screen.frame.height)) scale \(screen.backingScaleFactor) | window \(Int(window.frame.width))x\(Int(window.frame.height)) visible=\(window.isVisible) occluded=\(!window.occlusionState.contains(.visible)) | liveMetal path=\(view.debugLiveMetal)")

        let start = CACurrentMediaTime()
        var captured = false
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
            MainActor.assumeIsolated {
                let t = CGFloat(CACurrentMediaTime() - start)
                // Pull east over 0.7 s, sweep up and around, hold.
                var p = pin
                if t < 0.7 { p = CGPoint(x: pin.x + 480 * (t / 0.7), y: pin.y) }
                else if t < 2.4 {
                    let a = (t - 0.7) / 1.7 * 1.3
                    p = CGPoint(x: pin.x + 480 * cos(a), y: pin.y + 480 * sin(a) * 0.55)
                } else { p = CGPoint(x: pin.x + 480 * cos(1.3), y: pin.y + 480 * sin(1.3) * 0.55) }
                view.debugDrive(pointer: p, armed: t > 0.9 ? .east : nil)

                if t > 3.0, !captured {
                    captured = true
                    if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming]),
                       let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outputPath) as CFURL, UTType.png.identifier as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, image, nil)
                        CGImageDestinationFinalize(dest)
                        print("LiveSmoke: wrote \(outputPath) (\(image.width)x\(image.height))")
                    } else {
                        print("LiveSmoke: window capture unavailable")
                    }
                }
                if t > 3.6 {
                    let iv = view.debugFrameIntervals.dropFirst(10).sorted()
                    if iv.isEmpty {
                        print("LiveSmoke: no frames recorded (display link did not run)")
                    } else {
                        let avg = iv.reduce(0, +) / Double(iv.count)
                        let p50 = iv[iv.count / 2], p95 = iv[Int(Double(iv.count) * 0.95)], mx = iv.last ?? 0
                        let slow = iv.filter { $0 > 0.025 }.count
                        print(String(format: "LiveSmoke: %d frames | avg %.1f ms (%.0f fps) | p50 %.1f | p95 %.1f | worst %.1f ms | >25ms: %d",
                                     iv.count, avg * 1000, 1 / avg, p50 * 1000, p95 * 1000, mx * 1000, slow))
                    }
                    let pr = view.debugStylePrims()
                    if !pr.isEmpty {
                        let tight = pr.filter { $0.blend == .tight }
                        if !tight.isEmpty {
                            let xs = tight.map { Double($0.a.x) }, ys = tight.map { Double($0.a.y) }
                            print("LiveSmoke: beads x \(Int(xs.min()!))...\(Int(xs.max()!)) y \(Int(ys.min()!))...\(Int(ys.max()!)) | head at (\(Int(view.debugHead.x)),\(Int(view.debugHead.y)))")
                        }
                        print("LiveSmoke: style prims \(pr.count) | beads \(tight.count)" + (tight.first.map { " first bead at (\(Int($0.a.x)),\(Int($0.a.y)) r=\(String(format: "%.1f", Double($0.ra)))" } ?? ""))
                    }
                    view.stopPhysics()
                    FeelLabConfig.shared.styleID = savedStyle
                    FeelLabConfig.shared.themeID = savedTheme
                    exit(0)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        app.run()
        exit(0)
    }
}
