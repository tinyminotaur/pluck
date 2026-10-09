import CoreGraphics
import Foundation

// MARK: - Manifest (what a community pack's pack.json contains)

/// Either a plain number or an expression string, so `"width": 4` and `"width": "3 + 2 * sin(t)"` both work.
public enum PackValue: Codable, Equatable, Sendable {
    case number(Double)
    case expr(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .expr(s); return }
        throw DecodingError.typeMismatch(PackValue.self, .init(codingPath: decoder.codingPath, debugDescription: "expected a number or an expression string"))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .number(let d): try c.encode(d); case .expr(let s): try c.encode(s) }
    }
}

/// A colour: "#rrggbb" or "#rrggbbaa", a theme token ("@a", "@b", "@c", "@body") so the pack follows the chosen
/// colour theme, or an HSV object whose parts may be expressions.
public enum PackColor: Codable, Equatable, Sendable {
    case hex(String)
    case hsv(h: PackValue, s: PackValue, v: PackValue)

    private enum Keys: String, CodingKey { case h, s, v }
    public init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer(), let s = try? c.decode(String.self) { self = .hex(s); return }
        let k = try decoder.container(keyedBy: Keys.self)
        self = .hsv(h: try k.decode(PackValue.self, forKey: .h), s: try k.decodeIfPresent(PackValue.self, forKey: .s) ?? .number(0.8), v: try k.decodeIfPresent(PackValue.self, forKey: .v) ?? .number(1))
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .hex(let s): var c = encoder.singleValueContainer(); try c.encode(s)
        case .hsv(let h, let s, let v):
            var k = encoder.container(keyedBy: Keys.self)
            try k.encode(h, forKey: .h); try k.encode(s, forKey: .s); try k.encode(v, forKey: .v)
        }
    }
}

public struct PackParam: Codable, Equatable, Sendable {
    public var name: String
    public var label: String?
    public var `default`: Double
    public var min: Double
    public var max: Double
}

public struct PackRelease: Codable, Equatable, Sendable {
    /// How long the finale lasts, in seconds (the pack's `tr` variable runs 0 to 1 over this).
    public var duration: Double?
    /// "stay" (the head holds still while the finale plays), "ease" (the head is drawn back smoothly) or "spring".
    public var behavior: String?
}

public struct PackLayer: Codable, Equatable, Sendable {
    public var type: String                    // "path", "shape", "text", "image"
    public var visible: PackValue?
    public var space: String?                  // "span" (default: origin at the pin, x along the span), "head" (origin at the head), "screen"
    public var count: Int?                     // instances (shape, text, image); sample points (path)
    public var along: PackValue?
    public var offset: PackValue?
    public var alpha: PackValue?
    public var color: PackColor?
    public var glow: PackValue?
    // path
    public var width: PackValue?
    public var dash: [Double]?
    public var dashSpeed: PackValue?
    public var fill: PackColor?
    public var close: Bool?
    // shape
    public var shape: String?                  // circle, ring, rect, diamond, star, heart, drop, triangle, cross, spark
    public var size: PackValue?
    public var size2: PackValue?
    public var rotation: PackValue?
    public var stroke: PackColor?
    public var strokeWidth: PackValue?
    // text
    public var text: String?
    public var fontSize: PackValue?
    // image
    public var asset: String?
}

public struct PackManifest: Codable, Equatable, Sendable {
    public var format: Int
    public var id: String
    public var name: String
    public var version: String?
    public var author: String?
    public var license: String?
    public var tagline: String?
    public var theme: String?
    public var params: [PackParam]?
    public var layers: [PackLayer]
    public var release: PackRelease?
}

// MARK: - Draw operations (the program's output each frame)

public struct PackRGBA: Equatable, Sendable {
    public var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    public init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) { self.r = r; self.g = g; self.b = b; self.a = a }
}

public enum PackOp: Sendable {
    case path(points: [CGPoint], color: PackRGBA, width: CGFloat, dash: [CGFloat], dashPhase: CGFloat, glow: CGFloat, fill: PackRGBA?, closed: Bool)
    case shape(kind: String, position: CGPoint, size: CGFloat, size2: CGFloat, rotation: CGFloat, color: PackRGBA, stroke: PackRGBA?, strokeWidth: CGFloat, glow: CGFloat)
    case text(String, position: CGPoint, size: CGFloat, color: PackRGBA, rotation: CGFloat)
    case image(asset: String, position: CGPoint, size: CGFloat, rotation: CGFloat, alpha: CGFloat)
}

public struct PackFrame: Sendable {
    public var t: CGFloat = 0
    public var pin = CGPoint.zero, head = CGPoint.zero
    public var pinR: CGFloat = 20, headR: CGFloat = 12
    public var pull: CGFloat = 0
    public var speed: CGFloat = 0
    public var charge: CGFloat = 0
    public var fired = false
    public var committed = false
    public var tr: CGFloat = 0
    public var emerge: CGFloat = 1
    public var theme: [String: PackRGBA] = [:]
    public var params: [String: Double] = [:]
    public init() {}
}

// MARK: - Validation limits and compile errors

public enum PackLimits {
    public static let maxLayers = 48
    public static let maxCount = 300
    public static let maxPoints = 160
    public static let maxTotalInstances = 700
    public static let maxParams = 12
    public static let maxIDLength = 80
}

public struct PackIssue: Equatable, Sendable, CustomStringConvertible {
    public var where_: String
    public var message: String
    public var description: String { "\(where_): \(message)" }
    public init(where_: String, message: String) { self.where_ = where_; self.message = message }
}

// MARK: - Program

/// A manifest compiled to expressions: ready to be evaluated every frame into draw operations.
public final class PackProgram: @unchecked Sendable {
    public let manifest: PackManifest

    private static let builtinVars = ["t", "s", "i", "n", "u", "chord", "angle", "pull", "pinR", "headR", "mass", "speed", "charge", "fired", "tr", "commit", "emerge", "screenW"]
    private let varIndex: [String: Int]
    private let paramNames: [String]

    private struct Compiled {
        var layer: PackLayer
        var visible: PackExpression?
        var along: PackExpression?, offset: PackExpression?, alpha: PackExpression?
        var width: PackExpression?, dashSpeed: PackExpression?, glow: PackExpression?
        var size: PackExpression?, size2: PackExpression?, rotation: PackExpression?, strokeWidth: PackExpression?, fontSize: PackExpression?
        var hsv: (PackExpression, PackExpression, PackExpression)?
        var fillHSV: (PackExpression, PackExpression, PackExpression)?
        var strokeHSV: (PackExpression, PackExpression, PackExpression)?
        var textParts: [(String, PackExpression?)] = []
    }
    private var compiled: [Compiled] = []

    /// Compile and validate. All problems are collected; the result is nil when there are any.
    public static func compile(_ m: PackManifest) -> (PackProgram?, [PackIssue]) {
        var issues: [PackIssue] = []
        func bad(_ w: String, _ msg: String) { issues.append(PackIssue(where_: w, message: msg)) }
        if m.format != 1 { bad("format", "unsupported format \(m.format) (this app reads format 1)") }
        let idOK = !m.id.isEmpty && m.id.count <= PackLimits.maxIDLength && m.id.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "." || $0 == "-" || $0 == "_" }
        if !idOK { bad("id", "use 1 to \(PackLimits.maxIDLength) characters from a-z, 0-9, '.', '-' and '_'") }
        if m.name.trimmingCharacters(in: .whitespaces).isEmpty || m.name.count > 60 { bad("name", "give the pack a name of up to 60 characters") }
        if m.layers.isEmpty { bad("layers", "a pack needs at least one layer") }
        if m.layers.count > PackLimits.maxLayers { bad("layers", "at most \(PackLimits.maxLayers) layers") }
        let params = m.params ?? []
        if params.count > PackLimits.maxParams { bad("params", "at most \(PackLimits.maxParams) parameters") }
        var names = Set<String>()
        for p in params {
            if !(p.name.first?.isLetter ?? false) || !p.name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) { bad("params.\(p.name)", "names are letters, digits and '_'") }
            if builtinVars.contains(p.name) || names.contains(p.name) { bad("params.\(p.name)", "name already used") }
            if p.min > p.max || p.default < p.min || p.default > p.max { bad("params.\(p.name)", "default must lie between min and max") }
            names.insert(p.name)
        }
        var index: [String: Int] = [:]
        for (i, n) in builtinVars.enumerated() { index[n] = i }
        for (j, p) in params.enumerated() { index[p.name] = builtinVars.count + j }
        let prog = PackProgram(m, index, params.map(\.name))
        var total = 0
        func ex(_ v: PackValue?, _ w: String) -> PackExpression? {
            guard let v else { return nil }
            switch v {
            case .number(let d): return PackExpression(constant: d)
            case .expr(let s):
                do { return try PackExpression(s, variables: index) } catch { bad(w, "\(error)"); return nil }
            }
        }
        func hsv(_ c: PackColor?, _ w: String) -> (PackExpression, PackExpression, PackExpression)? {
            guard case .hsv(let h, let s, let v)? = c else { return nil }
            guard let a = ex(h, w + ".h"), let b = ex(s, w + ".s"), let d = ex(v, w + ".v") else { return nil }
            return (a, b, d)
        }
        func hexOK(_ c: PackColor?, _ w: String) {
            guard case .hex(let s)? = c else { return }
            if s.hasPrefix("@") { if !["@a", "@b", "@c", "@body"].contains(s) { bad(w, "unknown theme colour '\(s)'") }; return }
            let h = s.hasPrefix("#") ? String(s.dropFirst()) : s
            if !(h.count == 6 || h.count == 8) || !h.allSatisfy({ $0.isHexDigit }) { bad(w, "colours look like #rrggbb or #rrggbbaa") }
        }
        for (li, L) in m.layers.enumerated() {
            let w = "layers[\(li)]"
            var c = Compiled(layer: L)
            guard ["path", "shape", "text", "image"].contains(L.type) else { bad(w + ".type", "must be path, shape, text or image"); continue }
            if let sp = L.space, !["span", "head", "screen"].contains(sp) { bad(w + ".space", "must be span, head or screen") }
            let count = L.count ?? (L.type == "path" ? 32 : 1)
            if L.type == "path" { if count < 2 || count > PackLimits.maxPoints { bad(w + ".count", "paths take 2 to \(PackLimits.maxPoints) points") } }
            else { if count < 1 || count > PackLimits.maxCount { bad(w + ".count", "1 to \(PackLimits.maxCount) instances") }; total += count }
            c.visible = ex(L.visible, w + ".visible"); c.along = ex(L.along, w + ".along"); c.offset = ex(L.offset, w + ".offset")
            c.alpha = ex(L.alpha, w + ".alpha"); c.width = ex(L.width, w + ".width"); c.dashSpeed = ex(L.dashSpeed, w + ".dashSpeed"); c.glow = ex(L.glow, w + ".glow")
            c.size = ex(L.size, w + ".size"); c.size2 = ex(L.size2, w + ".size2"); c.rotation = ex(L.rotation, w + ".rotation")
            c.strokeWidth = ex(L.strokeWidth, w + ".strokeWidth"); c.fontSize = ex(L.fontSize, w + ".fontSize")
            c.hsv = hsv(L.color, w + ".color"); c.fillHSV = hsv(L.fill, w + ".fill"); c.strokeHSV = hsv(L.stroke, w + ".stroke")
            hexOK(L.color, w + ".color"); hexOK(L.fill, w + ".fill"); hexOK(L.stroke, w + ".stroke")
            if L.type == "shape" {
                if !["circle", "ring", "rect", "diamond", "star", "heart", "drop", "triangle", "cross", "spark"].contains(L.shape ?? "circle") { bad(w + ".shape", "unknown shape '\(L.shape ?? "")'") }
            }
            if L.type == "image" {
                let a = L.asset ?? ""
                if a.isEmpty || a.contains("..") || a.hasPrefix("/") || a.contains("\\") { bad(w + ".asset", "an asset is a file name inside the pack, like assets/star.png") }
            }
            if L.type == "text" {
                // {expression} segments inside the text are compiled separately.
                var out: [(String, PackExpression?)] = []
                var rest = Substring(L.text ?? "")
                while let open = rest.firstIndex(of: "{") {
                    out.append((String(rest[rest.startIndex..<open]), nil))
                    guard let close = rest[open...].firstIndex(of: "}") else { bad(w + ".text", "unclosed '{'"); break }
                    let inner = String(rest[rest.index(after: open)..<close])
                    do { out.append(("", try PackExpression(inner, variables: index))) } catch { bad(w + ".text", "\(error)") }
                    rest = rest[rest.index(after: close)...]
                }
                out.append((String(rest), nil))
                c.textParts = out
            }
            prog.compiled.append(c)
        }
        if total > PackLimits.maxTotalInstances { bad("layers", "too many shapes in total (\(total); the limit is \(PackLimits.maxTotalInstances))") }
        if let r = m.release, let d = r.duration, d < 0.05 || d > 4 { bad("release.duration", "between 0.05 and 4 seconds") }
        if let r = m.release, let b = r.behavior, !["stay", "ease", "spring"].contains(b) { bad("release.behavior", "stay, ease or spring") }
        return issues.isEmpty ? (prog, []) : (nil, issues)
    }

    private init(_ m: PackManifest, _ index: [String: Int], _ params: [String]) { manifest = m; varIndex = index; paramNames = params }

    public var releaseDuration: CGFloat { CGFloat(manifest.release?.duration ?? 0.9) }
    public var releaseBehavior: ReleaseBehavior {
        switch manifest.release?.behavior { case "ease": return .ease; case "spring": return .spring; default: return .stay }
    }

    private func themeColor(_ token: String, _ f: PackFrame) -> PackRGBA {
        f.theme[token] ?? PackRGBA(r: 1, g: 1, b: 1, a: 1)
    }

    private func rgba(_ spec: PackColor?, _ hsv: (PackExpression, PackExpression, PackExpression)?, _ env: [Double], _ f: PackFrame, alpha: Double) -> PackRGBA? {
        if let hsv {
            let h = hsv.0.eval(env), s = max(0, min(1, hsv.1.eval(env))), v = max(0, min(1, hsv.2.eval(env)))
            let hh = h - floor(h)
            let i = Int(hh * 6), ff = hh * 6 - Double(i), p = v * (1 - s), q = v * (1 - ff * s), t = v * (1 - (1 - ff) * s)
            let (r, g, b): (Double, Double, Double)
            switch i % 6 { case 0: (r, g, b) = (v, t, p); case 1: (r, g, b) = (q, v, p); case 2: (r, g, b) = (p, v, t); case 3: (r, g, b) = (p, q, v); case 4: (r, g, b) = (t, p, v); default: (r, g, b) = (v, p, q) }
            return PackRGBA(r: r, g: g, b: b, a: alpha)
        }
        guard case .hex(let s)? = spec else { return nil }
        if s.hasPrefix("@") { var c = themeColor(s, f); c.a *= alpha; return c }
        let h = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard let v = UInt64(h, radix: 16) else { return nil }
        if h.count == 8 { return PackRGBA(r: Double((v >> 24) & 255) / 255, g: Double((v >> 16) & 255) / 255, b: Double((v >> 8) & 255) / 255, a: Double(v & 255) / 255 * alpha) }
        return PackRGBA(r: Double((v >> 16) & 255) / 255, g: Double((v >> 8) & 255) / 255, b: Double(v & 255) / 255, a: alpha)
    }

    /// Everything to draw this frame.
    public func evaluate(_ f: PackFrame) -> [PackOp] {
        let dx = f.head.x - f.pin.x, dy = f.head.y - f.pin.y
        let chord = Double(hypot(dx, dy))
        let ang = chord > 0.5 ? Double(atan2(dy, dx)) : 0
        let dir = chord > 0.5 ? CGPoint(x: dx / CGFloat(chord), y: dy / CGFloat(chord)) : CGPoint(x: 1, y: 0)
        let nrm = CGPoint(x: -dir.y, y: dir.x)
        let massShare = Double(f.pinR * f.pinR / max(1, f.pinR * f.pinR + f.headR * f.headR))
        var env = [Double](repeating: 0, count: varIndex.count)
        func set(_ name: String, _ v: Double) { if let i = varIndex[name] { env[i] = v } }
        set("t", Double(f.t)); set("chord", chord); set("angle", ang); set("pull", Double(f.pull)); set("pinR", Double(f.pinR)); set("headR", Double(f.headR))
        set("mass", massShare); set("speed", Double(f.speed)); set("charge", Double(f.charge)); set("fired", f.fired ? 1 : 0); set("tr", Double(f.tr))
        set("commit", f.committed ? 1 : 0); set("emerge", Double(f.emerge)); set("screenW", 1500)
        for p in manifest.params ?? [] { set(p.name, f.params[p.name] ?? p.default) }
        var ops: [PackOp] = []
        for c in compiled {
            let L = c.layer
            set("s", 0); set("i", 0); set("n", 1); set("u", 0)
            if let v = c.visible, v.eval(env) == 0 { continue }
            let space = L.space ?? "span"
            func place(_ along: Double, _ offset: Double) -> CGPoint {
                switch space {
                case "screen": return CGPoint(x: f.pin.x + CGFloat(along), y: f.pin.y + CGFloat(offset))
                case "head": return CGPoint(x: f.head.x + dir.x * CGFloat(along) + nrm.x * CGFloat(offset), y: f.head.y + dir.y * CGFloat(along) + nrm.y * CGFloat(offset))
                default: return CGPoint(x: f.pin.x + dir.x * CGFloat(along) + nrm.x * CGFloat(offset), y: f.pin.y + dir.y * CGFloat(along) + nrm.y * CGFloat(offset))
                }
            }
            let count = L.count ?? (L.type == "path" ? 32 : 1)
            switch L.type {
            case "path":
                var pts: [CGPoint] = []
                for k in 0..<count {
                    let s = Double(k) / Double(max(1, count - 1))
                    set("s", s); set("i", Double(k)); set("n", Double(count)); set("u", s)
                    pts.append(place(c.along?.eval(env) ?? s * chord, c.offset?.eval(env) ?? 0))
                }
                set("s", 0.5); set("u", 0.5)
                let alpha = max(0, min(1, c.alpha?.eval(env) ?? 1)) * Double(f.emerge)
                guard let color = rgba(L.color, c.hsv, env, f, alpha: alpha) ?? rgba(.hex("@a"), nil, env, f, alpha: alpha) else { continue }
                let fill = rgba(L.fill, c.fillHSV, env, f, alpha: alpha)
                ops.append(.path(points: pts, color: color, width: CGFloat(max(0.2, min(80, c.width?.eval(env) ?? 3))), dash: (L.dash ?? []).map { CGFloat(max(0.5, $0)) },
                                 dashPhase: CGFloat(c.dashSpeed?.eval(env) ?? 0), glow: CGFloat(max(0, min(40, c.glow?.eval(env) ?? 0))), fill: fill, closed: L.close ?? false))
            default:
                for k in 0..<count {
                    let u = count > 1 ? Double(k) / Double(count - 1) : 0.5
                    set("s", u); set("i", Double(k)); set("n", Double(count)); set("u", u)
                    if let v = c.visible, v.eval(env) == 0 { continue }
                    let pos = place(c.along?.eval(env) ?? 0, c.offset?.eval(env) ?? 0)
                    let alpha = max(0, min(1, c.alpha?.eval(env) ?? 1)) * Double(f.emerge)
                    if alpha < 0.004 { continue }
                    let color = rgba(L.color, c.hsv, env, f, alpha: alpha) ?? rgba(.hex("@a"), nil, env, f, alpha: alpha)!
                    let rot = CGFloat(c.rotation?.eval(env) ?? 0)
                    switch L.type {
                    case "shape":
                        let size = CGFloat(max(0.5, min(600, c.size?.eval(env) ?? 10)))
                        ops.append(.shape(kind: L.shape ?? "circle", position: pos, size: size, size2: CGFloat(max(0.5, min(600, c.size2?.eval(env) ?? Double(size)))), rotation: rot, color: color,
                                          stroke: rgba(L.stroke, c.strokeHSV, env, f, alpha: alpha), strokeWidth: CGFloat(max(0, min(30, c.strokeWidth?.eval(env) ?? 2))),
                                          glow: CGFloat(max(0, min(40, c.glow?.eval(env) ?? 0)))))
                    case "text":
                        var str = ""
                        for (lit, e) in c.textParts { str += lit; if let e { let v = e.eval(env); str += v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) } }
                        ops.append(.text(String(str.prefix(80)), position: pos, size: CGFloat(max(6, min(120, c.fontSize?.eval(env) ?? 14))), color: color, rotation: rot))
                    default:
                        ops.append(.image(asset: L.asset ?? "", position: pos, size: CGFloat(max(2, min(800, c.size?.eval(env) ?? 40))), rotation: rot, alpha: CGFloat(alpha)))
                    }
                }
            }
        }
        return ops
    }

    /// The parameters (with defaults) this pack offers.
    public var params: [PackParam] { manifest.params ?? [] }
}

// MARK: - Decoding helper

public enum PackDecoder {
    public static func decode(_ data: Data) -> (PackManifest?, [PackIssue]) {
        do { return (try JSONDecoder().decode(PackManifest.self, from: data), []) }
        catch let DecodingError.keyNotFound(key, _) { return (nil, [PackIssue(where_: "pack.json", message: "missing '\(key.stringValue)'")]) }
        catch let DecodingError.typeMismatch(_, ctx) { return (nil, [PackIssue(where_: ctx.codingPath.map(\.stringValue).joined(separator: "."), message: ctx.debugDescription)]) }
        catch let DecodingError.dataCorrupted(ctx) { return (nil, [PackIssue(where_: "pack.json", message: ctx.debugDescription)]) }
        catch { return (nil, [PackIssue(where_: "pack.json", message: "\(error.localizedDescription)")]) }
    }
}

// MARK: - Simulation wrapper

/// Runs a pack: tracks the gesture (pull, speed, charge, release) and turns it into draw operations.
public struct PackSim: Sendable {
    public var base = SimBase()
    public var program: PackProgram?
    public var params: [String: Double] = [:]
    public var theme: [String: PackRGBA] = [:]
    private var speed: CGFloat = 0
    private var pull: CGFloat = 0
    public init() {}

    public var isFinished: Bool { base.releaseT > (program?.releaseDuration ?? 0.9) }
    public mutating func reset(pin: CGPoint) { base.start(pin); speed = 0; pull = 0 }
    public mutating func release(commit d: CGPoint?) { base.fire(d) }

    public mutating func step(dt: CGFloat, pin: CGPoint, head: CGPoint) {
        guard dt > 0 else { return }
        let prev = base.head
        base.advance(dt, pin, head)
        speed += (hypot(head.x - prev.x, head.y - prev.y) / dt - speed) * min(1, 9 * dt)
        let target = StyleHash.smoothstep(25, 160, hypot(head.x - pin.x, head.y - pin.y))
        pull += (target - pull) * min(1, 10 * dt)
    }

    public func frame(emerge: CGFloat) -> PackFrame {
        var f = PackFrame()
        let b = base
        f.t = b.time; f.pin = b.pin; f.head = b.head; f.pinR = b.rp; f.headR = b.rh
        f.pull = pull; f.speed = speed
        f.charge = StyleHash.smoothstep(0, 1.6, b.time)
        f.fired = b.fired; f.committed = b.fired && !b.cancelled
        f.tr = b.fired ? min(1, b.releaseT / (program?.releaseDuration ?? 0.9)) : 0
        f.emerge = emerge
        f.theme = theme; f.params = params
        return f
    }

    public func evaluate(emerge: CGFloat) -> [PackOp] { program?.evaluate(frame(emerge: emerge)) ?? [] }
}
