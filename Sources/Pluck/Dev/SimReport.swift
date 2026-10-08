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
        smoothness()
        return 0
    }

    /// How smooth is the motion at 120 Hz with realistic timing noise? A constant-speed pull is simulated with
    /// jittered frame times; we measure how much the head's per-frame velocity wobbles (px/s RMS, lower is
    /// smoother) and how much the thread/bulb shape twitches (RMS of frame-to-frame radius change, pt).
    static func smoothness() {
        func run(label: String, perFramePointer: Bool, frameJitter: Double) {
            let pin = CGPoint(x: 200, y: 400)
            let view = MetaballView(frame: NSRect(x: 0, y: 0, width: 2000, height: 900))
            view.pin = pin; view.head = pin; view.pointerTarget = pin; view.emerge = 1
            view.startPhysics(driveManually: true)
            var rng = SystemRandomNumberGenerator()
            var t: Double = 0, lastEvent: Double = 0
            var held = pin
            var headX: [Double] = [], radiusDelta: [Double] = [], lastRadii: [CGFloat] = []
            let base = 1.0 / 120.0
            while t < 2.4 {
                let dt = base + Double.random(in: -frameJitter...frameJitter, using: &rng)
                t += dt
                let speed = 900.0                                      // px/s, steady pull to the right
                let exact = CGPoint(x: pin.x + CGFloat(min(t, 2.2) * speed * 0.6), y: pin.y)
                if perFramePointer {
                    held = exact                                       // sampled fresh every frame
                } else if t - lastEvent >= 1.0 / 90.0 {                // mouse events: ~90 Hz sample-and-hold
                    held = exact; lastEvent = t
                }
                view.pointerTarget = held
                view.emerge = 1
                view.debugAdvance(dt: CGFloat(dt))
                let st = view.debugState
                if t > 0.7 {
                    headX.append(Double(st.head.x))
                    if lastRadii.count == st.radii.count {
                        let d = zip(st.radii, lastRadii).map { Double($0 - $1) }
                        radiusDelta.append((d.reduce(0) { $0 + $1 * $1 } / Double(d.count)).squareRoot())
                    }
                    lastRadii = st.radii
                }
            }
            // per-frame velocity jitter: deviation of each frame's displacement from its local average
            var jitter = 0.0, n = 0
            for i in 2..<(headX.count - 2) {
                let v = headX[i + 1] - headX[i]
                let avg = (headX[i + 2] - headX[i - 2]) / 4
                jitter += (v - avg) * (v - avg); n += 1
            }
            let velRMS = (jitter / Double(max(1, n))).squareRoot() * 120
            let shapeRMS = (radiusDelta.reduce(0) { $0 + $1 * $1 } / Double(max(1, radiusDelta.count))).squareRoot()
            print(String(format: "  %@  velocity jitter %.1f px/s RMS | shape twitch %.3f pt/frame RMS", label.padding(toLength: 44, withPad: " ", startingAt: 0), velRMS, shapeRMS))
            view.stopPhysics()
        }
        print("smoothness @120 Hz (lower is smoother):")
        run(label: "events at 90 Hz, jittered frames (+/-0.3 ms)", perFramePointer: false, frameJitter: 0.0003)
        run(label: "pointer sampled per frame, jittered frames", perFramePointer: true, frameJitter: 0.0003)
        run(label: "pointer sampled per frame, perfect frames", perFramePointer: true, frameJitter: 0)
    }
}
