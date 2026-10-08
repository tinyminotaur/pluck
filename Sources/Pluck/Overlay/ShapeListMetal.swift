import AppKit
import Foundation
import Metal
import PluckCore
import simd

/// Renders a list of `ShapePrim`s (circles, ferrofluid cones, crystal shards) with a dedicated shader. Used by the
/// ferrofluid and crystal styles; the liquid style keeps its own renderer.
///
/// Positions are in the target's local point space (y-up); `scale` is pixels per point.
@MainActor
final class ShapeListMetal {
    static let shared: ShapeListMetal? = ShapeListMetal()
    static let maxPrims = 128

    enum Mode: Float { case ferro = 1, crystal = 2 }

    struct Look {
        var mode: Mode = .ferro
        var lightDir = SIMD2<Float>(-0.45, 0.8)
        var time: Float = 0
        var shininess: Float = 1.0
        var fresnel: Float = 0.9
        var opacity: Float = 0.96
        var shadow: Float = 0.5
        var roleShift: Float = 0
        var smoothK: Float = 14           // points
        var fill: Float = 0.1
        var chrome: Float = 0.8
        var baseColor = SIMD3<Float>(0.012, 0.014, 0.02)
        var themeA = SIMD4<Float>(0.55, 0.75, 1.0, 1.0)
        var themeB = SIMD4<Float>(0.9, 0.95, 1.0, 1.0)
        var themeC = SIMD4<Float>(0.4, 0.5, 0.8, 0.0)
        var gradient = SIMD3<Float>(300, 0.02, 0)
    }

    /// A look for `mode` from a colour theme.
    static func look(mode: Mode, theme t: LiquidTheme, time: Float = 0) -> Look {
        var l = Look()
        l.mode = mode
        l.time = time
        l.baseColor = SIMD3(t.body.r, t.body.g, t.body.b)
        l.themeA = SIMD4(t.a.r, t.a.g, t.a.b, t.sheen)
        l.themeB = SIMD4(t.b.r, t.b.g, t.b.b, t.rim)
        l.themeC = SIMD4(t.c.r, t.c.g, t.c.b, 0)
        l.gradient = SIMD3(t.gradientScale, t.gradientSpeed, t.iridescence)
        l.fill = t.fill
        l.chrome = mode == .ferro ? max(0.55, t.chrome) : t.chrome
        l.opacity = mode == .crystal ? 0.94 : 0.97
        return l
    }

    private struct Uniforms {
        var resolution: SIMD2<Float>
        var lightDir: SIMD2<Float>
        var time: Float
        var shadow: Float
        var shininess: Float
        var fresnel: Float
        var opacity: Float
        var scalePx: Float
        var roleShift: Float
        var mode: Float
        var count: Float
        var smoothK: Float
        var fill: Float
        var chrome: Float
        var baseColor: SIMD4<Float>
        var themeA: SIMD4<Float>
        var themeB: SIMD4<Float>
        var themeC: SIMD4<Float>
        var grad: SIMD4<Float>
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var buffer: MTLBuffer?
    private var cachedTexture: MTLTexture?
    private var cachedSize = (0, 0)

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let v = library.makeFunction(name: "shape_vertex"), let f = library.makeFunction(name: "shape_fragment") else { return nil }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = v
            d.fragmentFunction = f
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            NSLog("Pluck: shape shader failed: \(error)")
            return nil
        }
        buffer = device.makeBuffer(length: Self.maxPrims * 3 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
    }

    func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }

    func encode(into texture: MTLTexture, commandBuffer cmd: MTLCommandBuffer, origin: CGPoint, scale: CGFloat, prims: [ShapePrim], look: Look) {
        guard let buffer else { return }
        let s = Float(scale)
        let count = min(Self.maxPrims, prims.count)
        let ptr = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: Self.maxPrims * 3)
        for i in 0..<count {
            let p = prims[i]
            let ax = Float(p.a.x - origin.x) * s, ay = Float(p.a.y - origin.y) * s
            let bx = Float(p.b.x - origin.x) * s, by = Float(p.b.y - origin.y) * s
            let rb: Float = p.kind == .shard ? Float(p.rb) : Float(p.rb) * s
            ptr[i * 3] = SIMD4(ax, ay, bx, by)
            ptr[i * 3 + 1] = SIMD4(Float(p.ra) * s, rb, Float(p.kind.rawValue + 4 * p.blend.rawValue), 0)
            ptr[i * 3 + 2] = SIMD4(Float(p.emphasis), Float(p.seed), 0, 0)
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)

        let l = look.lightDir
        let ll = simd_length(l)
        let ln = ll > 1e-4 ? l / ll : SIMD2<Float>(-0.45, 0.8)
        var u = Uniforms(
            resolution: SIMD2(Float(texture.width), Float(texture.height)),
            lightDir: ln, time: look.time, shadow: look.shadow, shininess: look.shininess, fresnel: look.fresnel,
            opacity: look.opacity, scalePx: s, roleShift: look.roleShift, mode: look.mode.rawValue,
            count: Float(count), smoothK: look.smoothK * s, fill: look.fill, chrome: look.chrome,
            baseColor: SIMD4(look.baseColor.x, look.baseColor.y, look.baseColor.z, 0),
            themeA: look.themeA, themeB: look.themeB,
            themeC: SIMD4(look.themeC.x, look.themeC.y, look.themeC.z, 0),
            grad: SIMD4(look.gradient.x * s, look.gradient.y, look.gradient.z, 0)
        )
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.setFragmentBuffer(buffer, offset: 0, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }

    /// Headless render to an image (previews).
    func render(size: CGSize, scale: CGFloat, origin: CGPoint = .zero, prims: [ShapePrim], look: Look) -> CGImage? {
        let w = max(2, Int(ceil(size.width * scale))), h = max(2, Int(ceil(size.height * scale)))
        guard w < 4096, h < 4096 else { return nil }
        let texture: MTLTexture
        if let t = cachedTexture, cachedSize == (w, h) { texture = t } else {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .shared
            guard let t = device.makeTexture(descriptor: d) else { return nil }
            cachedTexture = t; cachedSize = (w, h); texture = t
        }
        guard let cmd = queue.makeCommandBuffer() else { return nil }
        encode(into: texture, commandBuffer: cmd, origin: origin, scale: scale, prims: prims, look: look)
        cmd.commit()
        cmd.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        texture.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: Shader

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution; float2 lightDir;
        float time; float shadow; float shininess; float fresnel;
        float opacity; float scalePx; float roleShift; float mode;
        float count; float smoothK; float fill; float chrome;
        float4 baseColor; float4 themeA; float4 themeB; float4 themeC; float4 grad;
    };

    struct VOut { float4 position [[position]]; float2 uv; };

    vertex VOut shape_vertex(uint vid [[vertex_id]]) {
        float2 pos[6] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(-1, 1), float2(1, -1), float2(1, 1) };
        VOut o;
        o.position = float4(pos[vid], 0, 1);
        o.uv = pos[vid] * 0.5 + 0.5;
        return o;
    }

    float smin3(float a, float b, float k) {
        float h = max(k - abs(a - b), 0.0) / k;
        return min(a, b) - h * h * h * k * (1.0 / 6.0);
    }

    float capsuleR(float2 p, float2 a, float2 b, float ra, float rb, thread float &rAt) {
        float2 ba = b - a;
        float h = length(ba);
        if (h < 0.001) { rAt = max(ra, rb); return length(p - a) - rAt; }
        float2 ax = ba / h;
        float2 pa = p - a;
        rAt = mix(ra, rb, clamp(dot(pa, ax) / h, 0.0, 1.0));
        float2 q = float2(abs(dot(pa, float2(-ax.y, ax.x))), dot(pa, ax));
        float bb = clamp((ra - rb) / h, -0.999, 0.999);
        float aa = sqrt(1.0 - bb * bb);
        float kk = dot(q, float2(-bb, aa));
        if (kk < 0.0) return length(q) - ra;
        if (kk > aa * h) return length(q - float2(0.0, h)) - rb;
        return dot(q, float2(aa, bb)) - ra;
    }

    float sdBox(float2 p, float2 b) {
        float2 d = abs(p) - b;
        return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    }

    float sdTri(float2 p, float2 a, float2 b, float2 c) {
        float2 e0 = b - a, e1 = c - b, e2 = a - c;
        float2 v0 = p - a, v1 = p - b, v2 = p - c;
        float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
        float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
        float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
        float s = sign(e0.x * e2.y - e0.y * e2.x);
        float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                           float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                           float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
        return -sqrt(d.x) * sign(d.y);
    }

    struct Hit {
        int idx; float rAt; float2 uv; float2 ax; float len; float w; float tipLen; float emph; float seed; int kind;
    };

    float primDist(float2 p, constant float4 *pr, uint i, thread float &rAt, thread float2 &uv, thread float2 &axo,
                   thread float &len, thread float &wd, thread float &tipLen) {
        float4 A = pr[i * 3], B = pr[i * 3 + 1];
        int kind = int(B.z) & 3;
        rAt = B.x;
        if (kind == 0) return length(p - A.xy) - B.x;
        if (kind == 1) return capsuleR(p, A.xy, A.zw, B.x, B.y, rAt);
        float2 ba = A.zw - A.xy;
        float L = length(ba);
        if (L < 0.5) return length(p - A.xy) - B.x;
        float2 ax = ba / L;
        float2 q = p - A.xy;
        float u = dot(q, ax), v = dot(q, float2(-ax.y, ax.x));
        uv = float2(u, v); axo = ax; len = L; wd = B.x; tipLen = L * B.y;
        float Lb = L - tipLen;
        float dBox = sdBox(float2(u - Lb * 0.5, v), float2(Lb * 0.5, B.x));
        float dTri = sdTri(float2(u, v), float2(Lb, -B.x), float2(L, 0.0), float2(Lb, B.x));
        return min(dBox, dTri);
    }

    float field(float2 p, constant float4 *pr, uint n, float k, thread Hit &hit, bool track) {
        float d = 1e5;
        float bestRaw = 1e5;
        hit.idx = -1; hit.rAt = 8.0; hit.kind = 0; hit.emph = 0.0; hit.seed = 0.0;
        hit.uv = float2(0.0); hit.ax = float2(1.0, 0.0); hit.len = 1.0; hit.w = 1.0; hit.tipLen = 0.0;
        for (uint i = 0; i < n; i++) {
            float rr = 0.0; float2 uv = float2(0.0); float2 ax = float2(1.0, 0.0);
            float L = 1.0, W = 1.0, TL = 0.0;
            int blend = int(pr[i * 3 + 1].z) >> 2;
            float kk = blend == 1 ? k : (blend == 2 ? k * 0.35 : 0.0);
            // Cheap bound: if even the nearest possible point of this shape is farther than the current distance
            // (plus the blend reach), it can neither be the nearest nor change the blend. Skip the exact test.
            {
                float4 Ab = pr[i * 3];
                float2 mid = (Ab.xy + Ab.zw) * 0.5;
                float reach = (int(pr[i * 3 + 1].z) & 3) == 0 ? 0.0 : length(Ab.zw - Ab.xy) * 0.5;
                float bd = length(p - mid) - (reach + max(pr[i * 3 + 1].x, pr[i * 3 + 1].y * ((int(pr[i * 3 + 1].z) & 3) == 1 ? 1.0 : 0.0)));
                if (bd > d + max(kk, 0.5) && bd > 0.0) continue;
            }
            float di = primDist(p, pr, i, rr, uv, ax, L, W, TL);
            d = (blend == 0) ? min(d, di) : smin3(d, di, max(kk, 0.5));
            if (track && di < bestRaw) {
                bestRaw = di;
                hit.idx = int(i); hit.rAt = rr; hit.uv = uv; hit.ax = ax; hit.len = L; hit.w = W; hit.tipLen = TL;
                hit.kind = int(pr[i * 3 + 1].z) & 3; hit.emph = pr[i * 3 + 2].x; hit.seed = pr[i * 3 + 2].y;
            }
        }
        return d;
    }

    float3 palette(float t, constant Uniforms &u) {
        t = fract(t) * 3.0;
        float3 a = u.themeA.xyz, b = u.themeB.xyz, c = u.themeC.xyz;
        if (t < 1.0) return mix(a, b, smoothstep(0.0, 1.0, t));
        if (t < 2.0) return mix(b, c, smoothstep(0.0, 1.0, t - 1.0));
        return mix(c, a, smoothstep(0.0, 1.0, t - 2.0));
    }

    float hash11(float x) { return fract(sin(x * 127.1 + 311.7) * 43758.5453); }

    fragment float4 shape_fragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], constant float4 *pr [[buffer(1)]]) {
        float2 p = in.uv * u.resolution;
        uint n = min(uint(u.count), 128u);
        float k = max(u.smoothK, 1.0);
        Hit hit;
        float d = field(p, pr, n, k, hit, true);

        float2 Ld = u.lightDir;
        // Soft contact shadow outside the shape.
        if (d > 1.0) {
            if (u.shadow < 0.001 || d > k * 1.3) return float4(0.0);
            Hit h2;
            float2 off = float2(-Ld.x, -Ld.y - 0.45) * (0.18 * k);
            float ds = field(p - off, pr, n, k, h2, false);
            return float4(0.0, 0.0, 0.0, saturate(u.shadow * 0.40 * exp(-max(ds, 0.0) / (0.30 * k))));
        }
        float alpha = saturate(0.5 - d);
        if (alpha < 0.02) return float4(0.0);

        float3 V = float3(0.0, 0.0, 1.0);
        float3 L = normalize(float3(Ld, 0.85));
        float3 H = normalize(L + V);
        float2 pin = float2(0.0);
        float gcoord = dot(p, float2(0.8, 0.6)) / max(u.grad.x, 1.0) + u.time * u.grad.y + u.roleShift;
        float3 body = float3(0.0);

        if (u.mode < 1.5) {
            // ---------------- Ferrofluid: mirror-black chrome with sharp ridge highlights ----------------
            float e = 1.1;
            Hit h3;
            float fx = field(p + float2(e, 0.0), pr, n, k, h3, false) - d;
            float fy = field(p + float2(0.0, e), pr, n, k, h3, false) - d;
            float2 gd = float2(fx, fy);
            float gl = length(gd);
            float2 gdir = gl > 1e-4 ? gd / gl : float2(0.0);
            float t = max(0.0, -d);
            float bevel = max(1.5, hit.rAt * 0.85);
            float s = saturate(t / bevel);
            float edgeness = 1.0 - s;
            float h = sqrt(max(0.0, 1.0 - edgeness * edgeness));
            float3 N = normalize(float3(gdir * edgeness, max(0.05, h)));
            float3 P = palette(gcoord + 0.3 * dot(N.xy, float2(0.7, 0.4)), u);

            float3 Nc = normalize(float3(N.xy * 1.7, N.z));
            float3 R = reflect(-V, Nc);
            float sky = smoothstep(-0.35, 0.40, R.y);
            float box = smoothstep(0.76, 0.96, dot(R, normalize(float3(-0.45, 0.75, 0.5))));
            float strip = smoothstep(0.82, 0.98, dot(R, normalize(float3(0.6, -0.4, 0.7))));
            float3 env = mix(float3(0.006, 0.008, 0.014), float3(0.60, 0.66, 0.80), sky * sky) * mix(float3(1.0), P, 0.25)
                       + box * 1.5 + strip * P * 0.8;
            float fres = pow(1.0 - saturate(N.z), 2.6);
            body = u.baseColor.xyz + env * (0.30 + 0.70 * (0.35 + 0.65 * fres)) * u.chrome;
            float spec = pow(saturate(dot(N, H)), mix(40.0, 220.0, saturate(u.shininess)));
            body += spec * 1.7 * float3(1.0);
            body += P * fres * 0.55 * u.themeB.w;
            body += P * hit.emph * (0.30 + 0.5 * fres);
        } else {
            // ---------------- Crystal: faceted hexagonal prisms with glints and refraction ----------------
            float3 N = float3(0.0, 0.0, 1.0);
            float vn = 0.0;
            float along = 0.0;
            float edgeLine = 0.0;
            float tipFlag = 0.0;
            if (hit.kind == 2) {
                float W = max(hit.w, 0.5);
                vn = clamp(hit.uv.y / W, -1.2, 1.2);
                float Lb = hit.len - hit.tipLen;
                along = clamp(hit.uv.x / max(hit.len, 1.0), 0.0, 1.0);
                tipFlag = hit.uv.x > Lb ? 1.0 : 0.0;
                float side = vn < -0.34 ? -1.0 : (vn > 0.34 ? 1.0 : 0.0);
                float3 Nl = side == 0.0 ? float3(0.0, 0.0, 1.0) : float3(0.0, side * 0.62, 0.78);
                if (tipFlag > 0.5) Nl = float3(0.62, (vn > 0.0 ? 1.0 : -1.0) * 0.30, 0.72);
                float tilt = (hash11(hit.seed * 91.7 + 3.0) - 0.5) * 0.30;
                Nl.xy += float2(tilt, (hash11(hit.seed * 53.1 + 7.0) - 0.5) * 0.22);
                float2 perp = float2(-hit.ax.y, hit.ax.x);
                N = normalize(float3(hit.ax * Nl.x + perp * Nl.y, Nl.z));
                float dEdge = min(abs(vn - 0.34), abs(vn + 0.34));
                edgeLine = (1.0 - smoothstep(0.0, 0.10, dEdge)) * (1.0 - tipFlag);
                edgeLine += (tipFlag > 0.5) ? (1.0 - smoothstep(0.0, 0.08, abs(vn))) : 0.0;
            } else {
                float t = max(0.0, -d);
                float s = saturate(t / max(2.0, hit.rAt));
                float2 dir = normalize(p - float2(0.0)) * 0.0;
                N = normalize(float3(dir, 0.6 + 0.4 * s));
            }
            float3 P = palette(gcoord + hit.seed * 0.7 + 0.35 * along, u);
            float diff = saturate(dot(N, L));
            float3 glass = mix(u.baseColor.xyz, P * 0.55, 0.6 + 0.4 * (1.0 - abs(vn)));
            body = glass * (0.30 + 0.85 * diff);
            // refraction fake: light pooling toward the centre ridge and the far end
            body += P * 0.20 * (1.0 - abs(vn)) * (0.4 + 0.6 * along);
            float spec = pow(saturate(dot(N, H)), 80.0) * (0.45 + 1.2 * hit.seed);
            body += spec * float3(1.0, 0.98, 0.95);
            body += edgeLine * P * 0.55 * mix(1.0, 1.6, saturate(hit.emph));
            float fres = pow(1.0 - saturate(N.z), 2.0);
            body += fres * P * 0.35;
            // growth glow at the tip
            body += P * hit.emph * (0.20 + 0.9 * smoothstep(0.55, 1.0, along)) * 0.9;
            // crisp 1 px bright outline (dispersion)
            float outline = 1.0 - smoothstep(0.0, 1.6 * u.scalePx, -d);
            body += outline * 0.35 * mix(float3(1.0), P, 0.4);
        }

        float a = saturate(alpha * u.opacity);
        float outA = a + (1.0 - a) * 0.0;
        return float4(body * a, outA);
    }
    """
}
