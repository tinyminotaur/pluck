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

    struct Circle {
        /// Bbox-local AppKit coords (y-up, origin bottom-left). LOCKED.
        var center: SIMD2<Float>
        var radius: Float
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
            circleCount: UInt32(min(32, circles.count)),
            spineCount: UInt32(min(32, max(0, spineCount))),
            fillet: Float(max(1, fillet * scale)),
            facet: min(1, max(0, look.facet)),
            facetSize: max(6, look.facetSize * Float(scale))
        )
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        let s = Float(scale)
        var packed = (0..<32).map { i -> SIMD4<Float> in
            guard i < circles.count else { return .zero }
            let c = circles[i]
            // LOCKED: scale AppKit-local centers into pixel space. No Y inversion.
            return SIMD4(c.center.x * s, c.center.y * s, max(0.5, c.radius * s), 0)
        }
        enc.setFragmentBytes(&packed, length: MemoryLayout<SIMD4<Float>>.stride * 32, index: 1)

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
        var _pad: UInt32 = 0
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
        uint _pad;
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

    // Signed distance (negative inside) and the local tube radius at that point.
    float2 blobField(float2 p, constant float4 *c, uint n, uint spine, float k) {
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
            d = min(d, di);
        }
        // Pin / head lobes: smooth-unioned so they pool into the tether like liquid.
        for (uint i = spine; i < n; i++) {
            float rr = max(c[i].z, 1.0);
            float di = length(p - c[i].xy) - rr;
            float w = saturate(0.5 + 0.5 * (d - di) / k);
            r = max(r, mix(r, rr, w));
            d = smin(d, di, k);
        }
        return float2(d, max(r, 1.0));
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

    fragment float4 obsidian_fragment(VertexOut in [[stage_in]],
                                      constant Uniforms &u [[buffer(0)]],
                                      constant float4 *circles [[buffer(1)]]) {
        float2 p = float2(in.uv.x * u.resolution.x, in.uv.y * u.resolution.y);
        uint n = min(u.circleCount, 32u);
        uint sp = min(u.spineCount, n);
        float k = max(u.fillet, 1.0);

        float2 f0 = blobField(p, circles, n, sp, k);

        // Obsidian facets live in the blob's own material space (along the pin→head axis and
        // across it), so they stretch, shear and re-catch the light as the liquid moves.
        float4 cell = float4(0.0, 1.0, 0.5, 0.5);
        float2 fdir = float2(1.0, 0.0);
        float2 domeS = float2(0.0);
        if (u.facet > 0.001 && n >= sp + 2u) {
            float2 a = circles[n - 2].xy;
            float2 ab = circles[n - 1].xy - a;
            float len = length(ab);
            float2 dir = len > 1.0 ? ab / len : float2(1.0, 0.0);
            float2 rel = p - a;
            float cellAlong = max(len * 0.25, u.facetSize);
            float2 m = float2(dot(rel, dir) / cellAlong, dot(rel, float2(-dir.y, dir.x)) / u.facetSize);
            float2 toSeed;
            cell = facetCells(m, toSeed);
            fdir = dir;
            // Cell-space offset from the facet's seed, turned into a screen-space direction:
            // each plane bulges slightly outward (conchoidal) instead of being dead flat.
            float2 outward = -toSeed;
            domeS = outward.x * dir + outward.y * float2(-dir.y, dir.x);
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
        float hx = pillow(blobField(p + float2(e, 0.0), circles, n, sp, k)) - h;
        float hy = pillow(blobField(p + float2(0.0, e), circles, n, sp, k)) - h;
        float3 N = normalize(float3(-hx * 4.8, -hy * 4.8, 1.0));
        // Flat conchoidal planes: each cell tilts the surface its own way.
        float2 tilt = (cell.zw - 0.5) * 2.0;
        float ripple = sin(cell.x * 38.0 + cell.z * 6.2831) * 0.035;
        float3 Nf = normalize(float3(N.xy * 0.45 + tilt * 0.45 + domeS * 0.30 + domeS * ripple, N.z));
        N = normalize(mix(N, Nf, saturate(u.facet)));
        float3 V = float3(0.0, 0.0, 1.0);
        float3 L = normalize(float3(u.lightDir.x, u.lightDir.y, 0.85));

        float thick = saturate(h);
        float3 dark = u.baseColor.xyz * 0.35 + float3(0.02, 0.025, 0.04);
        float3 glow = u.glow.xyz;
        float tAmt = saturate(u.transmission) * (0.55 + 0.9 * pow(1.0 - thick, 1.35));
        float3 beer = exp(-u.absorb.xyz * thick * 1.1);
        float3 body = mix(dark, glow * beer, tAmt);
        body += float3(0.04, 0.045, 0.06) * (0.35 + 0.65 * thick);

        float ndl = saturate(dot(N, L));
        float wrap = saturate(dot(N, normalize(float3(-L.x, -L.y, 0.9))) * 0.5 + 0.5);
        body *= 0.55 + 0.55 * ndl + 0.25 * wrap;

        float fres = pow(1.0 - saturate(dot(N, V)), 2.2) * (0.55 + u.fresnel);
        body += fres * float3(0.85, 0.9, 1.0) * 0.85;

        float3 H = normalize(L + V);
        float gloss = mix(12.0, 48.0, saturate(u.shininess));
        float spec = pow(saturate(dot(N, H)), gloss) * (0.45 + u.shininess);
        body += spec * float3(1.0) * 1.1 * (1.0 - 0.45 * saturate(u.facet));

        // Faint bright seams where planes meet, plus a per-facet glint that wakes up as the
        // light swings with the motion.
        float seam = 1.0 - smoothstep(0.0, 0.07, cell.y);
        body += seam * u.facet * 0.12 * float3(0.75, 0.85, 1.0) * (0.4 + 0.6 * thick);
        // Sharp, snap-on glints: only facets whose plane lines up with the light flash, and
        // they flash hard rather than shimmer. Moving the light (i.e. the mouse) sweeps them.
        float glint = smoothstep(0.972, 0.996, dot(N, H)) * (0.35 + 0.65 * cell.w);
        body += glint * u.facet * 0.9 * float3(1.0, 0.97, 0.92) * (1.0 - seam);

        // Interleaved-gradient-noise dither: near-black gradients band badly at 8 bits.
        float ign = fract(52.9829189 * fract(dot(in.position.xy, float2(0.06711056, 0.00583715))));
        body += (ign - 0.5) * (1.4 / 255.0);

        float a = saturate(alpha * u.opacity);
        return float4(body * a, a);
    }
    """
}
