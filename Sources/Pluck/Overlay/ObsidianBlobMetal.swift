import AppKit
import Foundation
import Metal
import simd

/// Optical blob renderer.
///
/// COORDINATE LOCK (do not “fix” without a failing test):
/// - Circles are in **AppKit view space relative to the render bbox**:
///   `local = world - bbox.origin`, y-up, (0,0) = bottom-left of bbox.
/// - Shader UV maps NDC so y=0 is the bottom of the drawable (matches AppKit).
/// - No CPU Y-flip when building the CGImage.
@MainActor
final class ObsidianBlobMetal {
    static let shared: ObsidianBlobMetal? = ObsidianBlobMetal()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cachedTexture: MTLTexture?
    private var cachedSize: (Int, Int) = (0, 0)
    private var pixelBuffer: UnsafeMutableRawPointer?
    private var pixelBufferBytes = 0

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            NSLog("Pluck: Metal shader compile failed: \(error)")
            return nil
        }
        guard let vert = library.makeFunction(name: "obsidian_vertex"),
              let frag = library.makeFunction(name: "obsidian_fragment") else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vert
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .one
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("Pluck: Metal pipeline failed: \(error)")
            return nil
        }
    }

    deinit { pixelBuffer?.deallocate() }

    /// Circles the shader will read (the smoothed strand has ~3 segments per physics particle).
    static let maxCircles = 96

    struct Circle {
        /// Bbox-local AppKit coords (y-up, origin bottom-left). LOCKED.
        var center: SIMD2<Float>
        var radius: Float
        /// 0...1: how strongly this circle (an action bud) glows with the theme colour. 0 for ordinary mass.
        var emphasis: Float = 0
    }

    struct Look {
        var lightDir: SIMD2<Float>
        var time: Float
        var shininess: Float
        var fresnel: Float
        var transmission: Float
        var opacity: Float
        var edgeSoft: Float
        var baseColor: SIMD3<Float>
        var absorb: SIMD3<Float>
        var glow: SIMD3<Float>
        /// 0 = smooth liquid, 1 = fully chipped obsidian.
        var facet: Float = 0
        /// Facet cell size across the blob, in points.
        var facetSize: Float = 22
        /// 0…1 strength of the slow pulsing glow.
        var ember: Float = 0.5
        /// Theme palette: three stops that cycle across the surface (rgb), with sheen gain in A.w and rim gain in B.w.
        var themeA = SIMD4<Float>(1.00, 0.50, 0.10, 1.0)
        var themeB = SIMD4<Float>(0.85, 0.25, 0.04, 1.0)
        var themeC = SIMD4<Float>(1.00, 0.68, 0.20, 0.0)
        /// Gradient size in points per cycle, drift (cycles/s), tilt-driven iridescence.
        var gradient = SIMD3<Float>(260, 0.02, 0)
        /// Colour glow from within the glass, and chrome-like environment reflection (0...1).
        var fill: Float = 0.1
        var chrome: Float = 0
        /// Damped oval/triangular wobble of the pin and head bulbs: (cos2, sin2, cos3, sin3) amplitudes, as a fraction of radius.
        var pinMode = SIMD4<Float>(repeating: 0)
        var headMode = SIMD4<Float>(repeating: 0)
    }

    /// `circles[0..<spineCount]` form a continuous tapered tether (consecutive samples are joined
    /// by round-cone segments, not drawn as separate discs). Any remaining circles (pin / head
    /// lobes) are smooth-unioned onto it. `fillet` is the blend width in points.
    func render(
        size: CGSize,
        scale: CGFloat,
        circles: [Circle],
        spineCount: Int,
        fillet: CGFloat,
        look: Look
    ) -> CGImage? {
        let w = max(2, Int(ceil(size.width * scale)))
        let h = max(2, Int(ceil(size.height * scale)))
        guard w < 4096, h < 4096 else { return nil }
        guard let texture = texture(width: w, height: h) else { return nil }
        guard let cmd = queue.makeCommandBuffer() else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        enc.setRenderPipelineState(pipeline)

        let light = look.lightDir
        let lightLen = simd_length(light)
        let lightN = lightLen > 1e-4 ? light / lightLen : SIMD2<Float>(-0.45, 0.8)

        var uniforms = Uniforms(
            resolution: SIMD2(Float(w), Float(h)),
            lightDir: lightN,
            time: look.time,
            edgeSoft: look.edgeSoft,
            shininess: look.shininess,
            fresnel: look.fresnel,
            transmission: look.transmission,
            opacity: look.opacity,
            baseColor: SIMD4(look.baseColor.x, look.baseColor.y, look.baseColor.z, 0),
            absorb: SIMD4(look.absorb.x, look.absorb.y, look.absorb.z, 0),
            glow: SIMD4(look.glow.x, look.glow.y, look.glow.z, 0),
            circleCount: UInt32(min(Self.maxCircles, circles.count)),
            spineCount: UInt32(min(Self.maxCircles, max(0, spineCount))),
            fillet: Float(max(1, fillet * scale)),
            facet: min(1, max(0, look.facet)),
            facetSize: max(6, look.facetSize * Float(scale)),
            ember: min(1.5, max(0, look.ember)),
            themeA: look.themeA,
            themeB: look.themeB,
            themeC: SIMD4(look.themeC.x, look.themeC.y, look.themeC.z, look.chrome),
            grad: SIMD4(look.gradient.x * Float(scale), look.gradient.y, look.gradient.z, look.fill),
            pinMode: look.pinMode,
            headMode: look.headMode
        )
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        let s = Float(scale)
        var packed = (0..<Self.maxCircles).map { i -> SIMD4<Float> in
            guard i < circles.count else { return .zero }
            let c = circles[i]
            // LOCKED: scale AppKit-local centers into pixel space. No Y inversion.
            return SIMD4(c.center.x * s, c.center.y * s, max(0.5, c.radius * s), c.emphasis)
        }
        enc.setFragmentBytes(&packed, length: MemoryLayout<SIMD4<Float>>.stride * Self.maxCircles, index: 1)

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        return makeImageScrubbingClearPixels(from: texture, width: w, height: h)
    }

    private func makeImageScrubbingClearPixels(from texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height
        if pixelBuffer == nil || pixelBufferBytes < byteCount {
            pixelBuffer?.deallocate()
            pixelBuffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
            pixelBufferBytes = byteCount
        }
        guard let base = pixelBuffer else { return nil }

        texture.getBytes(base, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        // LOCKED: no vertical flip (flipping breaks pin/cursor mapping).
        // Plate isolation: force near-clear texels to exact 0 so CGImage can't
        // paint a translucent rectangle over empty space.
        let pixels = base.bindMemory(to: UInt8.self, capacity: byteCount)
        var i = 0
        while i < byteCount {
            let a = pixels[i + 3]
            if a < 10 {
                pixels[i] = 0
                pixels[i + 1] = 0
                pixels[i + 2] = 0
                pixels[i + 3] = 0
            }
            i += 4
        }

        let data = Data(bytes: base, count: byteCount)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private func texture(width: Int, height: Int) -> MTLTexture? {
        if let cachedTexture, cachedSize == (width, height) { return cachedTexture }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        cachedTexture = tex
        cachedSize = (width, height)
        return tex
    }

    private struct Uniforms {
        var resolution: SIMD2<Float>
        var lightDir: SIMD2<Float>
        var time: Float
        var edgeSoft: Float
        var shininess: Float
        var fresnel: Float
        var transmission: Float
        var opacity: Float
        var baseColor: SIMD4<Float>
        var absorb: SIMD4<Float>
        var glow: SIMD4<Float>
        var circleCount: UInt32
        var spineCount: UInt32
        var fillet: Float
        var facet: Float
        var facetSize: Float
        var ember: Float
        var themeA: SIMD4<Float>
        var themeB: SIMD4<Float>
        var themeC: SIMD4<Float>
        var grad: SIMD4<Float>
        var pinMode: SIMD4<Float>
        var headMode: SIMD4<Float>
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float2 lightDir;
        float time;
        float edgeSoft;
        float shininess;
        float fresnel;
        float transmission;
        float opacity;
        float4 baseColor;
        float4 absorb;
        float4 glow;
        uint circleCount;
        uint spineCount;
        float fillet;
        float facet;
        float facetSize;
        float ember;
        float4 themeA;
        float4 themeB;
        float4 themeC;
        float4 grad;
        float4 pinMode;
        float4 headMode;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut obsidian_vertex(uint vid [[vertex_id]]) {
        float2 pos[6] = {
            float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
            float2(-1.0,  1.0), float2( 1.0, -1.0), float2( 1.0,  1.0)
        };
        VertexOut o;
        o.position = float4(pos[vid], 0.0, 1.0);
        // LOCKED: uv.y = 0 at NDC bottom → AppKit y-up in field space.
        o.uv = pos[vid] * 0.5 + 0.5;
        return o;
    }

    // Polynomial smooth-min of two signed distances.
    float smin(float a, float b, float k) {
        float h = max(k - abs(a - b), 0.0) / k;
        return min(a, b) - h * h * k * 0.25;
    }

    // Cubic smooth-min: C2-smooth blends, so the join between thread and bulb is one gentle concave curve.
    float smin3(float a, float b, float k) {
        float h = max(k - abs(a - b), 0.0) / k;
        return min(a, b) - h * h * h * k * (1.0 / 6.0);
    }

    // Signed distance (negative inside) and the local tube radius at that point.
    // Radial shape modes: oval (l=2) and triangular (l=3) wobble of a bulb, as a fraction of its radius.
    float modeScale(float2 v, float4 m) {
        float l = length(v);
        if (l < 1e-3) return 0.0;
        v /= l;
        float c2 = v.x * v.x - v.y * v.y, s2 = 2.0 * v.x * v.y;
        float c3 = v.x * (v.x * v.x - 3.0 * v.y * v.y), s3 = v.y * (3.0 * v.x * v.x - v.y * v.y);
        return m.x * c2 + m.y * s2 + m.z * c3 + m.w * s3;
    }

    float2 blobField(float2 p, constant float4 *c, uint n, uint spine, float k, constant Uniforms &u) {
        float d = 1e5;
        float r = 1.0;
        // Tether: tapered round-cone segments between consecutive spine samples (hard union,
        // so the thin neck stays thin and continuous instead of beading into discs).
        for (uint i = 0; i + 1 < spine; i++) {
            float2 a = c[i].xy;
            float2 ab = c[i + 1].xy - a;
            float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-4));
            float rr = mix(c[i].z, c[i + 1].z, t);
            float di = length(p - (a + ab * t)) - rr;
            // Blend the local radius across neighbouring segments so the shading height
            // doesn't step (comb ridges) where the taper changes between samples.
            float w = saturate(0.5 + 0.5 * (d - di) / (0.35 * max(rr, r)));
            r = mix(r, rr, w);
            // Soft union (scaled to the local thickness) removes the crease that a hard min leaves where two
            // tapered segments overlap, which otherwise shows up as regular ribs along a smooth strand.
            d = smin(d, di, max(0.18 * rr, 0.5));
        }
        // Pin / head lobes: smooth-unioned so they pool into the tether like liquid.
        for (uint i = spine; i < n; i++) {
            float rr = max(c[i].z, 1.0);
            // The last two circles are the pin and the head: they carry the wobble modes.
            float modeAmt = 0.0;
            if (i + 2 == n) modeAmt = modeScale(p - c[i].xy, u.pinMode);
            else if (i + 1 == n) modeAmt = modeScale(p - c[i].xy, u.headMode);
            float di = length(p - c[i].xy) - rr * (1.0 + clamp(modeAmt, -0.3, 0.3));
            float w = saturate(0.5 + 0.5 * (d - di) / k);
            r = max(r, mix(r, rr, w));
            d = smin3(d, di, k);
        }
        return float2(d, max(r, 1.0));
    }

    float hash12(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    float vnoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash12(i), hash12(i + float2(1, 0)), f.x),
                   mix(hash12(i + float2(0, 1)), hash12(i + float2(1, 1)), f.x), f.y);
    }

    // Water never holds a perfect shape: a slow two-octave flow warps the field. It is anchored at the
    // pin in screen space (one fixed environment), so it never turns with the cursor, and it is driven
    // by time alone, so the surface keeps moving even when you hold perfectly still.
    float2 waterWarp(float2 p, float2 pin, float amp, float scale, float t) {
        float2 q = (p - pin) / scale;
        float2 w = float2(vnoise(q + float2(t * 0.21, 0.0)) - 0.5,
                          vnoise(q + float2(0.0, t * 0.17) + 7.3) - 0.5);
        // A gentler second swell (never fine ripples: water at this size is smooth).
        w += 0.28 * float2(vnoise(q * 1.7 + float2(-t * 0.29, 3.1)) - 0.5,
                           vnoise(q * 1.7 + float2(t * 0.25, 9.7)) - 0.5);
        return p + w * amp;
    }

    // Pillow profile: rises steeply at the silhouette and flattens toward the core,
    // scaled by the local tube radius so a thin neck reads as a round thread.
    float pillow(float2 f) {
        float u = saturate(-f.x / (f.y * 0.95));
        float v = 1.0 - u;
        return sqrt(max(0.0, 1.0 - v * v));
    }

    float2 hash22(float2 p) {
        p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
        return fract(sin(p) * 43758.5453);
    }

    // Voronoi cells: x = distance to nearest seed, y = gap to second nearest (≈0 on a
    // cell edge), zw = per-cell random pair.
    float4 facetCells(float2 m, thread float2 &toSeed) {
        float2 g = floor(m);
        float2 f = fract(m);
        float d1 = 8.0, d2 = 8.0;
        float2 id = float2(0.0);
        toSeed = float2(0.0);
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                float2 o = float2(float(i), float(j));
                float2 r = o + hash22(g + o) * 0.8 + 0.1 - f;
                float d = dot(r, r);
                if (d < d1) { d2 = d1; d1 = d; id = g + o; toSeed = r; }
                else if (d < d2) { d2 = d; }
            }
        }
        d1 = sqrt(d1); d2 = sqrt(d2);
        return float4(d1, d2 - d1, hash22(id + 17.0));
    }

    // The theme's three colours cycle A -> B -> C -> A. `t` is in cycles.
    float3 themePalette(float t, constant Uniforms &u) {
        t = fract(t) * 3.0;
        float3 a = u.themeA.xyz, b = u.themeB.xyz, c = u.themeC.xyz;
        if (t < 1.0) return mix(a, b, smoothstep(0.0, 1.0, t));
        if (t < 2.0) return mix(b, c, smoothstep(0.0, 1.0, t - 1.0));
        return mix(c, a, smoothstep(0.0, 1.0, t - 2.0));
    }

    fragment float4 obsidian_fragment(VertexOut in [[stage_in]],
                                      constant Uniforms &u [[buffer(0)]],
                                      constant float4 *circles [[buffer(1)]]) {
        float2 p = float2(in.uv.x * u.resolution.x, in.uv.y * u.resolution.y);
        uint n = min(u.circleCount, 96u);
        uint sp = min(u.spineCount, n);
        float k = max(u.fillet, 1.0);

        float2 wPin = (n >= 2u) ? circles[n - 2].xy : float2(0.0);
        // Amplitude scales with the blob (k is the fillet width, ~0.22 × rest radius) and is capped by the
        // local thickness, so a thin neck ripples a little instead of tearing.
        float wAmp = 0.2 * k;
        float wScale = max(wAmp * 6.5, 24.0);
        float2 f00 = blobField(p, circles, n, sp, k, u);
        // Far outside the liquid (beyond any warp): done, without the warped and gradient lookups.
        if (f00.x > wAmp + 4.0) { return float4(0.0, 0.0, 0.0, 0.0); }
        float wAmpL = min(wAmp, 0.5 * f00.y);
        float2 f0 = blobField(waterWarp(p, wPin, wAmpL, wScale, u.time), circles, n, sp, k, u);

        // Obsidian facets live in ONE fixed environment: a screen-aligned cell field anchored at the
        // pin. The liquid moves through it, so the cells never turn, stretch or re-orient when the
        // cursor moves (only the surface curvature changes what each facet catches).
        float4 cell = float4(0.0, 1.0, 0.5, 0.5);
        float2 domeS = float2(0.0);
        if (u.facet > 0.001 && n >= sp + 2u) {
            float2 pin = circles[n - 2].xy;
            float2 m = (p - pin) / u.facetSize;
            float2 toSeed;
            cell = facetCells(m, toSeed);
            // Each plane bulges slightly outward (conchoidal) instead of being dead flat.
            domeS = -toSeed;
            // Chipped, slightly angular silhouette.
            f0.x += u.facet * u.facetSize * 0.09 * (cell.z - 0.5) * 2.0;
        }
        // Anti-aliased silhouette straight from the distance field (~1.5 px feather).
        float alpha = saturate(0.5 - f0.x / 1.5);

        // Plate isolation: empty space is EXACT clear — no contact shadow fill.
        if (alpha < 0.02) {
            return float4(0.0, 0.0, 0.0, 0.0);
        }

        float h = pillow(f0);
        float e = 1.5;
        float2 fxp = blobField(waterWarp(p + float2(e, 0.0), wPin, wAmpL, wScale, u.time), circles, n, sp, k, u);
        float2 fyp = blobField(waterWarp(p + float2(0.0, e), wPin, wAmpL, wScale, u.time), circles, n, sp, k, u);
        float hx = pillow(fxp) - h;
        float hy = pillow(fyp) - h;
        // Rim bevel from the pillow profile, plus a spherical dome from the distance gradient so the
        // whole mass curves like a droplet and highlights slide across it (not only at the silhouette).
        float2 gd = float2(fxp.x - f0.x, fyp.x - f0.x);
        float gl = length(gd);
        float2 gdir = gl > 1e-4 ? gd / gl : float2(0.0);
        // Zero at the medial axis (where the gradient flips, which would leave star-shaped cusps) and on thin
        // necks (where the local radius steps between segments and would leave comb ridges).
        float dome = pow(1.0 - saturate(-f0.x / (f0.y * 0.95)), 1.3) * smoothstep(1.0 * k, 2.6 * k, f0.y);
        float3 N = normalize(float3(-hx * 4.8 + gdir.x * dome * 0.62, -hy * 4.8 + gdir.y * dome * 0.62, 1.0));
        // Flat conchoidal planes: each cell tilts the surface its own way.
        float2 tilt = (cell.zw - 0.5) * 2.0;
        float ripple = sin(cell.x * 38.0 + cell.z * 6.2831) * 0.035;
        float3 Nf = normalize(float3(N.xy * 0.45 + tilt * 0.45 + domeS * 0.30 + domeS * ripple, N.z));
        N = normalize(mix(N, Nf, saturate(u.facet)));
        float3 V = float3(0.0, 0.0, 1.0);
        float3 L = normalize(float3(u.lightDir.x, u.lightDir.y, 0.85));

        float thick = saturate(h);
        // Theme palette in ONE fixed environment: a gradient across the screen (not tied to the cursor) that drifts
        // slowly with time, and shifts with the surface tilt for oil-slick iridescence.
        float gcoord = dot(p - wPin, float2(0.8, 0.6)) / max(u.grad.x, 1.0) + u.time * u.grad.y
                     + u.grad.z * dot(N.xy, float2(0.7, 0.4));
        float3 P = themePalette(gcoord, u);
        float3 P2 = themePalette(gcoord + 0.5, u);
        float3 P3 = themePalette(gcoord + 0.25, u);
        float pulse = 0.65 * (0.5 + 0.5 * sin(u.time * 2.1)) + 0.35 * (0.5 + 0.5 * sin(u.time * 3.4 + 1.3));
        float3 dark = u.baseColor.xyz * 0.55;
        float3 glow = P;
        float tAmt = saturate(u.transmission) * (0.14 + 1.05 * pow(1.0 - thick, 1.9));
        float3 beer = exp(-u.absorb.xyz * thick * 1.7);
        float3 body = mix(dark, glow * beer, tAmt);
        body += u.baseColor.xyz * 0.25 * (0.35 + 0.65 * thick);

        float ndl = saturate(dot(N, L));
        float wrap = saturate(dot(N, normalize(float3(-L.x, -L.y, 0.9))) * 0.5 + 0.5);
        body *= 0.55 + 0.55 * ndl + 0.25 * wrap;
        // Action buds (circles carrying an emphasis value): glow with the theme colour so the label inside reads
        // as light within the glass, and the armed bud lights up fully.
        float budGlow = 0.0;
        for (uint bi = sp; bi < n; bi++) {
            float w = circles[bi].w;
            if (w > 0.001) {
                float dbi = length(p - circles[bi].xy) - circles[bi].z;
                budGlow = max(budGlow, w * exp(-max(dbi, 0.0) * 0.07));
            }
        }
        // Colour fill: the theme colour glowing from within the glass, strongest where it is thin, breathing with the pulse.
        body += P * u.grad.w * (0.30 + 0.70 * pow(1.0 - thick, 1.2)) * (0.55 + 0.45 * ndl) * (0.85 + 0.15 * pulse);
        body += P * budGlow * (0.16 + 0.34 * pow(1.0 - thick, 1.1)) * (0.8 + 0.2 * pulse);

        float fres = pow(1.0 - saturate(dot(N, V)), 2.2) * (0.55 + u.fresnel);
        body += fres * mix(P, float3(1.0), 0.2) * 0.40 * u.themeB.w;

        float3 H = normalize(L + V);
        float gloss = mix(24.0, 130.0, saturate(u.shininess));
        float spec = pow(saturate(dot(N, H)), gloss) * (0.45 + u.shininess);
        body += spec * mix(float3(1.0), P, 0.15) * 1.1 * (1.0 - 0.45 * saturate(u.facet));
        // Wet-glass sheen: a broad soft reflection of a window above-left, plus a faint cool-warm
        // bounce on the far side. This is what makes smooth black read as liquid, not paint.
        float sheen = pow(saturate(dot(N, normalize(float3(-0.35, 0.6, 0.72)))), 7.0);
        body += sheen * (0.10 + 0.22 * u.shininess) * u.themeA.w * mix(float3(1.0), P3, 0.25);
        float bounce = pow(saturate(dot(N, normalize(float3(0.5, -0.6, 0.62)))), 5.0);
        body += bounce * 0.06 * P2;

        // Faint bright seams where planes meet, plus a per-facet glint that wakes up as the
        // light swings with the motion.
        float seam = 1.0 - smoothstep(0.0, 0.07, cell.y);
        body += seam * u.facet * 0.12 * P * (0.4 + 0.6 * thick);
        // Sharp, snap-on glints: only facets whose plane lines up with the light flash, and
        // they flash hard rather than shimmer. Moving the light (i.e. the mouse) sweeps them.
        float glint = smoothstep(0.972, 0.996, dot(N, H)) * (0.35 + 0.65 * cell.w);
        body += glint * u.facet * 0.9 * mix(float3(1.0), P, 0.3) * (1.0 - seam);

        // Chrome: reflect a bright studio environment (sky, dark horizon, a softbox streak) for mirror-like themes.
        if (u.themeC.w > 0.001) {
            // Exaggerate the tilt for the mirror so the sky / horizon bands wrap visibly around a small blob.
            float3 Nc = normalize(float3(N.xy * 2.6, N.z));
            float3 R = reflect(-V, Nc);
            float sky = smoothstep(-0.25, 0.30, R.y);
            float box = smoothstep(0.80, 0.97, dot(R, normalize(float3(-0.4, 0.7, 0.6))));
            float3 env = mix(float3(0.04, 0.05, 0.08), float3(0.92, 0.95, 1.0), sky) + box * 1.1;
            env *= mix(float3(1.0), P, 0.25);
            float frn = 0.35 + 0.65 * pow(1.0 - saturate(N.z), 1.5);
            body = mix(body, env, saturate(u.themeC.w * (0.55 + 0.45 * frn)));
        }

        // Ember: a slow, slightly irregular pulse (two out-of-step sines) of amber light from inside.
        // It pools in the thin edges and crackles faintly along the facet seams.
        float emberAmt = u.ember * (0.35 + 0.65 * pulse);
        float3 emberCol = P * 1.1;
        body += emberCol * emberAmt * (0.30 * pow(1.0 - thick, 1.7) + 0.06 * thick * thick * thick);
        float crackle = 0.5 + 0.5 * sin(u.time * 1.7 + cell.z * 6.2831);
        body += emberCol * emberAmt * seam * saturate(u.facet) * (0.35 + 0.65 * crackle) * 0.9;

        // Interleaved-gradient-noise dither: near-black gradients band badly at 8 bits.
        float ign = fract(52.9829189 * fract(dot(in.position.xy, float2(0.06711056, 0.00583715))));
        body += (ign - 0.5) * (1.4 / 255.0);

        // Opaque black core; only the thin edges are see-through glass.
        float a = saturate(alpha * mix(u.opacity * 0.78, 1.0, smoothstep(0.0, 0.5, thick)));
        return float4(body * a, a);
    }
    """
}

/// Black obsidian with deep amber light bleeding through the thin parts. One definition, used by
/// the live view and the headless preview so they cannot drift apart.
enum ObsidianPalette {
    /// Colour of transmitted light: deep red-amber (0) to hot amber (1).
    static func glow(warmth: Float) -> SIMD3<Float> {
        let w = min(1, max(0, warmth))
        let deep = SIMD3<Float>(0.78, 0.26, 0.04)
        let hot = SIMD3<Float>(1.0, 0.60, 0.14)
        return deep + (hot - deep) * w
    }

    /// Beer-Lambert absorption: thick glass eats blue and green first, so the core goes black and the
    /// thin edges stay amber. `depth` is the Feel Lab "absorption" knob.
    static func absorb(depth: Float) -> SIMD3<Float> {
        SIMD3(0.85 + 0.8 * depth, 1.9 + 1.2 * depth, 3.2 + 1.4 * depth)
    }
}
