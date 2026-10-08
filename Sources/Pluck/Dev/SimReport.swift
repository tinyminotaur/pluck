import AppKit
import Foundation
import PluckCore

/// `Pluck --sim-report`: drives the real MetaballView physics headlessly with scripted pulls and prints how far
/// the head and strand actually extend. No window, no input, no cursor: purely a diagnostic.
@MainActor
enum SimReport {
    static func run() -> Int32 {
        let pin = CGPoint(x: 200, y: 400)
        print("target  held  head-dist  lag   strand-len  min-r  max-r  head-r")
        for target in [60, 120, 200, 300, 450, 700] as [CGFloat] {
            let view = MetaballView(frame: NSRect(x: 0, y: 0, width: 1600, height: 900))
            view.pin = pin
            view.head = pin
            view.pointerTarget = pin
            view.emerge = 1
            view.startPhysics(driveManually: true)
            let dt: CGFloat = 1.0 / 120
            // Ramp the pointer out over 0.25 s (a quick pull), then hold it for 1.5 s.
            var t: CGFloat = 0
            var report: [String] = []
            while t < 1.75 {
                let k = min(1, t / 0.25)
                view.pointerTarget = CGPoint(x: pin.x + target * k, y: pin.y)
                view.emerge = 1
                view.debugAdvance(dt: dt)
                t += dt
                if [0.5, 1.0, 1.75].contains(where: { abs($0 - t) < dt / 2 }) {
                    let s = view.debugState
                    var len: CGFloat = 0
                    for i in 1..<s.spine.count { len += hypot(s.spine[i].x - s.spine[i - 1].x, s.spine[i].y - s.spine[i - 1].y) }
                    let dist = hypot(s.head.x - pin.x, s.head.y - pin.y)
                    let lag = target - (s.head.x - pin.x)
                    report.append(String(format: "%5.0f  %4.2f  %9.1f  %4.1f  %10.1f  %5.1f  %5.1f  %6.1f",
                                         Double(target), Double(t), Double(dist), Double(lag), Double(len),
                                         Double(s.radii.min() ?? 0), Double(s.radii.max() ?? 0), Double(s.radii.last ?? 0)))
                }
            }
            report.forEach { print($0) }
            // Real draw cost at this stretch (this is what sets the live frame rate).
            if let ctx = CGContext(data: nil, width: 3200, height: 1800, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.scaleBy(x: 2, y: 2)
                _ = view.debugRenderMillis(into: ctx)   // warm-up (shader/pipeline)
                var total = 0.0
                let frames = 12
                for _ in 0..<frames { total += view.debugRenderMillis(into: ctx) }
                print(String(format: "        draw: %.1f ms/frame  -> %.0f fps ceiling", total / Double(frames), 1000 / (total / Double(frames))))
            }
            view.stopPhysics()
        }
        return 0
    }
}
