import AppKit
import Foundation
import Metal
import PluckCore
import simd

/// GPU renderer for the liquid: smooth-unioned round capsules shaded as dark glass.
///
/// - Geometry arrives as `BlobPrimitive`s in AppKit view space (y up). The target texture covers a window of
///   that space whose bottom-left is `origin`; `scale` is pixels per point.
/// - Output is premultiplied alpha, cleared to transparent, so it can be presented directly from a
///   `CAMetalLayer` (no CPU readback, no waiting on the GPU).
final class BlobRenderer {
    static let maxPrimitives = 48

    struct Look {
        var lightDir = SIMD2<Float>(-0.45, 0.8)
        var time: Float = 0
        /// Smooth-union radius (points). Larger = gooier merges.
        var blend: Float = 20
        /// Glassy bevel depth (points).
        var bevel: Float = 15
        var shininess: Float = 0.9
        var fresnel: Float = 0.85
        var transmission: Float = 0.75
        var absorption: Float = 0.7
        var opacity: Float = 0.94
        var shadow: Float = 0.55
        var rim: Float = 0.6
        var coolTint: Float = 0.45
        var baseColor = SIMD3<Float>(0.028, 0.032, 0.048)
    }

    private struct Uniforms {
        var a: SIMD4<Float>     // resolution.xy, lightDir.xy
        var b: SIMD4<Float>     // time, scale, blend(px), bevel(px)
        var c: SIMD4<Float>     // shininess, fresnel, transmission, absorption
        var d: SIMD4<Float>     // opacity, shadow, rim, coolTint
        var base: SIMD4<Float>  // base rgb, primitive count
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vert = library.makeFunction(name: "blob_vertex"),
                  let frag = library.makeFunction(name: "blob_fragment") else { return nil }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vert
            desc.fragmentFunction = frag
            desc.colorAttachments[0].pixelFormat = Self.pixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("Pluck: Metal setup failed: \(error)")
            return nil
        }
    }

    func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }

    /// Encode one frame into `texture`. `origin` is the view-space point at the texture's bottom-left.
    func encode(
        into texture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        origin: CGPoint,
        scale: CGFloat,
        primitives: [BlobPrimitive],
        look: Look
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)

        let s = Float(scale)
        let lightLen = simd_length(look.lightDir)
        let light = lightLen > 1e-4 ? look.lightDir / lightLen : SIMD2<Float>(-0.45, 0.8)

        let count = min(Self.maxPrimitives, primitives.count)
        var uniforms = Uniforms(
            a: SIMD4(Float(texture.width), Float(texture.height), light.x, light.y),
            b: SIMD4(look.time, s, look.blend * s, look.bevel * s),
            c: SIMD4(look.shininess, look.fresnel, look.transmission, look.absorption),
            d: SIMD4(look.opacity, look.shadow, look.rim, look.coolTint),
            base: SIMD4(look.baseColor.x, look.baseColor.y, look.baseColor.z, Float(count))
        )
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        var packed = [SIMD4<Float>](repeating: .zero, count: Self.maxPrimitives * 2)
        for i in 0..<count {
            let p = primitives[i]
            packed[i * 2] = SIMD4(
                Float(p.a.x - origin.x) * s, Float(p.a.y - origin.y) * s,
                Float(p.b.x - origin.x) * s, Float(p.b.y - origin.y) * s
            )
            // w = 1 marks the continuous body chain (hard union); lobes and droplets blend softly.
            packed[i * 2 + 1] = SIMD4(Float(p.ra) * s, Float(p.rb) * s, Float(p.glow), p.isBody ? 1 : 0)
        }
        enc.setFragmentBytes(&packed, length: MemoryLayout<SIMD4<Float>>.stride * packed.count, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }

    // MARK: Shader

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 a; float4 b; float4 c; float4 d; float4 base;
    };

    struct VOut { float4 position [[position]]; float2 uv; };

    vertex VOut blob_vertex(uint vid [[vertex_id]]) {
        float2 pos[6] = {
            float2(-1, -1), float2(1, -1), float2(-1, 1),
            float2(-1, 1),  float2(1, -1), float2(1, 1)
        };
        VOut o;
        o.position = float4(pos[vid], 0, 1);
        o.uv = pos[vid] * 0.5 + 0.5;   // uv.y = 0 at the bottom: matches AppKit y-up
        return o;
    }

    // Distance to a round capsule (circle `ra` at a, circle `rb` at b). `rAt` is the capsule's radius at the
    // point closest to p, interpolated, so the bevel depth stays continuous along the neck.
    float capsule(float2 p, float2 a, float2 b, float ra, float rb, thread float &rAt) {
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

    float smin(float a, float b, float k) {
        float h = max(k - abs(a - b), 0.0) / k;
        return min(a, b) - h * h * k * 0.25;
    }

    // Signed distance of the whole liquid. The body chain is a hard union (it is one continuous
    // piece; soft-unioning 27 neighbours would inflate the neck). Lobes and droplets merge softly.
    float field(float2 p, constant float4 *pr, uint n, float k, thread float &glow, thread float &rNear, bool wantGlow) {
        float body = 1e6;
        float best = 1e6;
        rNear = 12.0;
        glow = 0.0;
        for (uint i = 0; i < n; i++) {
            float4 g = pr[i * 2];
            float4 r = pr[i * 2 + 1];
            if (r.w > 0.5) {
                float rr = 0.0;
                float di = capsule(p, g.xy, g.zw, r.x, r.y, rr);
                body = min(body, di);
                if (di < best) { best = di; rNear = rr; }
                if (wantGlow && r.z > 0.001) glow += r.z * exp(-max(di, 0.0) * 0.08);
            }
        }
        float d = body;
        for (uint i = 0; i < n; i++) {
            float4 g = pr[i * 2];
            float4 r = pr[i * 2 + 1];
            if (r.w <= 0.5) {
                float rr = 0.0;
                float di = capsule(p, g.xy, g.zw, r.x, r.y, rr);
                d = smin(d, di, k);
                if (di < best) { best = di; rNear = rr; }
                if (wantGlow && r.z > 0.001) glow += r.z * exp(-max(di, 0.0) * 0.08);
            }
        }
        return d;
    }

    float3 environment(float3 R, float2 Ld) {
        float up = saturate(R.y * 0.5 + 0.5);
        float3 c = mix(float3(0.015, 0.018, 0.03), float3(0.10, 0.12, 0.19), up);
        // Key softbox on the light side.
        float2 q = R.xy - Ld * 0.62;
        c += smoothstep(0.62, 0.0, length(q * float2(1.0, 1.5))) * float3(1.0, 0.97, 0.93) * 1.7;
        // Cool strip on the far side.
        float2 q2 = R.xy + Ld * 0.8;
        c += smoothstep(0.38, 0.0, length(q2 * float2(1.7, 0.85))) * float3(0.35, 0.58, 1.0) * 0.95;
        return c;
    }

    fragment float4 blob_fragment(VOut in [[stage_in]],
                                  constant Uniforms &u [[buffer(0)]],
                                  constant float4 *pr [[buffer(1)]]) {
        float2 res = u.a.xy;
        float2 p = in.uv * res;
        float2 Ld = u.a.zw;
        float scale = u.b.y;
        float k = max(1.0, u.b.z);
        float bevel = max(2.0, u.b.w);
        uint n = min(uint(u.base.w), 48u);
        float shadowAmt = u.d.y;

        float glow = 0.0;
        float rNear = 12.0;
        float d = field(p, pr, n, k, glow, rNear, true);

        // Soft contact shadow, offset away from the light.
        float shadow = 0.0;
        if (shadowAmt > 0.001) {
            float dummy = 0.0, dummyR = 0.0;
            float2 off = float2(-Ld.x, -Ld.y - 0.45) * 7.0 * scale;
            float ds = field(p - off, pr, n, k, dummy, dummyR, false);
            shadow = shadowAmt * 0.5 * exp(-max(ds, 0.0) / (13.0 * scale));
        }

        float aShape = saturate(0.5 - d);
        if (aShape <= 0.0) {
            return float4(0.0, 0.0, 0.0, saturate(shadow));
        }

        // Surface normal from the distance gradient, shaped as a rounded bevel.
        float e = 1.25 * scale;
        float dd = 0.0, dr = 0.0;
        float gx = field(p + float2(e, 0), pr, n, k, dd, dr, false) - field(p - float2(e, 0), pr, n, k, dd, dr, false);
        float gy = field(p + float2(0, e), pr, n, k, dd, dr, false) - field(p - float2(0, e), pr, n, k, dd, dr, false);
        float2 grad = float2(gx, gy);
        float2 g = length(grad) > 1e-5 ? normalize(grad) : float2(0.0, 1.0);

        float t = max(0.0, -d);
        float bevelEff = max(1.5, min(bevel, rNear * 0.85));
        float s = saturate(t / bevelEff);
        float edgeness = 1.0 - s;                    // 1 at the rim, 0 deep inside
        float h = sqrt(max(0.0, 1.0 - edgeness * edgeness));   // dome height
        float3 N = normalize(float3(g * edgeness, max(0.05, h)));
        float3 V = float3(0.0, 0.0, 1.0);
        float3 L = normalize(float3(Ld, 0.9));

        float shininess = u.c.x, fresnelAmt = u.c.y, transmission = u.c.z, absorption = u.c.w;
        float rimAmt = u.d.z, cool = u.d.w;

        // Dark glass body with light bleeding through the thin edges.
        float3 body = u.base.rgb;
        float thin = pow(1.0 - h, 1.5);
        float3 coolCol = float3(0.22, 0.46, 0.95);
        float3 violet = float3(0.52, 0.32, 0.88);
        float3 tint = mix(violet, coolCol, 0.5 + 0.5 * dot(g, -Ld));
        float3 trans = tint * transmission * thin * exp(-absorption * h * 1.4) * 0.85;
        // Caustic pooling on the side away from the light.
        float caustic = pow(saturate(dot(g, -Ld)), 3.0) * smoothstep(0.0, 0.55, edgeness) * (1.0 - edgeness * 0.4);
        trans += float3(0.45, 0.7, 1.0) * caustic * 0.32 * transmission;

        // Reflections.
        float3 R = reflect(-V, N);
        float3 env = environment(R, Ld);
        float F = 0.05 + 0.95 * pow(1.0 - saturate(N.z), 3.0);
        float3 refl = env * (F * (0.55 + fresnelAmt) + 0.10 + 0.10 * shininess);

        float3 H = normalize(L + V);
        float gloss = mix(36.0, 260.0, saturate(shininess));
        float spec = pow(saturate(dot(N, H)), gloss) * (0.7 + shininess);
        float3 specCol = float3(1.0, 0.99, 0.97) * spec * 1.25;

        // Iridescent rim.
        float rim = pow(1.0 - saturate(N.z), 2.6) * rimAmt;
        float3 rimCol = mix(float3(0.45, 0.85, 1.0), float3(0.85, 0.55, 1.0), 0.5 + 0.5 * dot(g, Ld)) * mix(0.7, 1.0, cool);

        // Accent glow for the captured role.
        float gl = saturate(glow);
        float3 glowCol = float3(0.30, 0.78, 1.0) * gl * (0.28 + 0.9 * pow(1.0 - saturate(N.z), 1.4));

        float3 col = body + trans + refl + specCol + rim * rimCol + glowCol;

        float a = aShape * mix(u.d.x * 0.80, u.d.x, s);
        a = saturate(a + gl * 0.04);
        // Premultiplied, composited over the shadow.
        float outA = a + (1.0 - a) * saturate(shadow);
        return float4(col * a, outA);
    }
    """
}
