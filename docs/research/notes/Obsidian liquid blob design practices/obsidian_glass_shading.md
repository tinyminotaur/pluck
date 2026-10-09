# Obsidian / volcanic-glass shading for a 2D SDF liquid blob (Metal fragment shader)

Research caveat: iquilezles.org and Wikipedia were unreachable from the sandbox (DNS failure), and web search returned no Shadertoy obsidian shaders, no Apple Liquid Glass sessions, no GPU Gems chapters. Only the sourced items below are cited. Everything else is engineering judgment, listed under Inferences and flagged as opinion/untested.

## 1. What visual properties define convincing obsidian?

### Takeaway
Obsidian is amorphous volcanic glass: vitreous luster, curved (conchoidal) fracture, near-black body. Sheen variants (gold/silver, rainbow/fire) come from oriented inclusions and thin-film or flow-layer effects, not from the base glass. Sources disagree on the exact cause of rainbow sheen, so treat that as a look target rather than physics to simulate.

### Cited Findings
- No crystal structure, so it fractures conchoidally (smooth curved surfaces, not flat cleavage planes), which is also why edges are very sharp — [Search summary of Wikipedia/rockhounding sources](https://www.rockhounding.org/rockhounding-wiki/rocks-metals-minerals-crystals-gemstones/rocks/obsidian). The "atoms thick" edge claim comes from a low-quality page; ignore it.
- Luster is vitreous (glassy); Mohs 5-6, specific gravity about 2.4 — [Wikipedia: Obsidian](https://en.wikipedia.org/wiki/Obsidian) (via search snippet; page not fetched).
- Gold/silver sheen: tiny gas bubbles stretched flat along flow layers — [Wikipedia: Obsidian](https://en.wikipedia.org/wiki/Obsidian) (snippet). An older USGS report says the gold sheen resolves under magnification into thin beams of red and yellow light, attributed to minute cracks — [USGS 7th Annual Report](https://www.nps.gov/parkhistory/online_books/geology/publications/rpt/7-1/sec3.htm).
- Rainbow/fire sheen: Wikipedia attributes it to magnetite nanoparticle inclusions (thin-film interference) and rainbow striping to oriented hedenbergite nanorods; Oregon State suggests oriented microscopic feldspar or mica crystals along flow layers — [Wikipedia](https://en.wikipedia.org/wiki/Obsidian) vs [Oregon State](https://volcano.oregonstate.edu/volcanic-minerals/obsidian). Sources conflict on cause; both place the effect along flow layers.
- A 3D-artist forum describes the target look as very dark, highly reflective, "a tiny bit transparent" — [Daz forum](https://www.daz3d.com/forums/discussion/comment/704362). Weak source (forum opinion).

### Inferences
- Thin edges transmitting a smoky brown/amber light (well known from real flakes and arrowheads, but I did not obtain a citable source) is the key cue separating obsidian from black plastic: absorption coefficients should be high in blue, lower in red (for example sigma = (1.2, 2.5, 4.0) per unit thickness), so thin areas glow dark amber and thick areas go to about zero.
- Sheen variants map naturally to a flow-band term: a low-frequency stripe field along the blob's material-space axis that modulates specular color (gold: constant warm tint; rainbow: thin-film hue ramp from cos(phase + k * (1 - N.V))), visible only in a narrow angular window. Keep intensity low (under 0.3) so the body stays black.

### Gaps
- No artist breakdowns (Substance/Blender obsidian tutorials), Shadertoy shaders, or reference photos with measured colors were found.

## 2. Techniques for faking glass/obsidian with a 2D SDF

### Takeaway
The established ingredients are Schlick Fresnel with F0 about 0.04, exponential (Beer-Lambert) absorption driven by thickness, and a reflection term. For a near-black material, reflection/Fresnel/specular carry nearly all of the perceived image; absorption matters mostly at thin rims.

### Cited Findings
- Schlick: R(theta) = R0 + (1 - R0)(1 - cos theta)^5, R0 = ((n1-n2)/(n1+n2))^2; glass n about 1.52 gives about 0.04 — [Graphics forum / course notes](https://wp.faculty.wmi.amu.edu.pl/CGP2.pdf) (search snippet). Dielectric F0 table: plastic/glass 0.040-0.045, water 0.020, gems 0.050-0.080 — [Unity forum summary](https://discussions.unity.com/t/need-help-understanding-the-fresnel-equation-for-pbr/660320).
- Beer-Lambert: I = I0 * exp(-a * d); real-time glass multiplies transmitted color by exp(-sigma * thickness), applied per RGB channel, which is approximate versus spectral — [luma.gl glass effects](https://luma.gl/docs/api-guide/shaders/glass-effects) and [Charles Univ. thesis](https://dspace.cuni.cz/handle/20.500.11956/203078).
- luma.gl's glass material combines scene-color transmission, Schlick reflection, dispersion, Beer-Lambert absorption and roughness-dependent highlights (marked experimental) — [luma.gl](https://luma.gl/docs/api-reference/experimental/glass-material).

### Inferences
- Thickness proxy: use the pillow height h (from SDF depth) as path length, d = 2h or h / max(N.z, 0.3). Transmitted = background * exp(-sigma * d). With high sigma, interior is essentially black except within a thin rim band, which matches obsidian.
- Perceptual priority (opinion): (1) Fresnel-weighted studio reflection with a few hard bright shapes (softboxes/strips) so the black body reads as glossy; (2) sharp spec glints; (3) smoky rim transmission; (4) subtle refraction offset of backdrop (uv += n.xy * h * 0.02-0.05), which can be skipped for a menu-bar overlay if the blob is nearly opaque; (5) everything else. Matcap/procedural gradient environment lookup via reflect(view, n) is cheaper than anything physical: a function of n.xy plus 2-4 smoothstep strips costs a few ALU ops.
- Use F0 about 0.04-0.06 but boost the artistic reflection (multiplier 1.5-3x) since a black body has no diffuse to compete; keep a separate small constant ambient so the body is not pure 0.
- Blinn-Phong with exponent 200-800 for sharp glints; consider a normalized (n+8)/(8pi) factor.

### Gaps
- No source on Apple Liquid Glass optics specifics or Shadertoy 2D-SDF glass; unverified.

## 3. Faceting (Voronoi/cell normals, conchoidal look, animation)

### Takeaway
A workable approach is F1/F2 Voronoi in material space, with per-cell hashed normal tilt and F2-F1 for edges. The "low-poly sticker" risk is addressed by blending cell tilt with the smooth pillow normal, using curved (domed) facets rather than flat ones, and keeping facet contrast low in non-glint regions. The citable material here is limited to the Voronoi mechanics.

### Cited Findings
- Track nearest and second-nearest feature points; the difference F2-F1 approaches zero at cell borders, giving edges without an edge-detect pass; zero edge width gives flat cells — [GameDev.net shaderlab 22](https://gamedev.net/shaderlab/22-voronoi-cells/).
- A shader cannot propagate a mesh normal across pixels; per-cell normals must be derived from the cell hash/ID in the shader — [Blender Artists thread](https://blenderartists.org/t/how-to-map-normals-to-voronoi-texture-cells/1556329).
- Cell gradient/normal-strength controls give cells a raised-facet look — [Resonite PBS VoronoiCrystal](https://wiki.resonite.com/PBS_VoronoiCrystal); a "facet shape" parameter plus flat/gradient/normal lighting modes exists in [Kineme Worley](https://kineme.net/MacOSX/105).

### Inferences (opinion, untested)
- Normal-space faceting (tilt N by a cell vector) is better than SDF-space faceting (displacing the field) for shading, since it does not move the silhouette; use SDF-space only for the chipped silhouette, with small amplitude (under 1-2 px at 1x) and edge treatment via the same AA.
- Conchoidal look: use domed cells, n = normalize(blend(nPillow, vec3(t*k + (p - c)*m, 1), w)) with m > 0 gives curved scoop. Add ripple (concentric rings, "hackle lines") by modulating tilt with sin(freq * |p - c|) at low amplitude (0.02-0.05). Use 2 octaves of Voronoi (a large cell scale plus smaller one at about 0.4 weight), anisotropic (stretch cells along the flow axis).
- Edge treatment: dark thin seam where F2-F1 < ~0.03 cell units with a bright 1px highlight on the lit side, rather than outlined cells; fade seam width by 1/fwidth so it stays about 1 px.
- Temporal stability: compute Voronoi in material-space coordinates (parameterized along the segment chain arclength and across-width), not screen space, so facets stretch with the blob; avoid per-frame random re-seeding; hash cell IDs only.
- Animation: quantize the light-driven term per facet (smoothstep with narrow width on dot(n_facet, L) or half-vector), so glints "snap" on and off across planes as light direction or blob orientation changes; add a per-facet phase offset so they don't flash in unison. Keep twinkle subtle: 2-4 facets lit at once.

### Gaps
- No artist breakdown or shader write-up found on conchoidal-fracture shading specifically.

## 4. Anti-aliasing, alpha, banding, wide gamut

### Takeaway
Dithering with interleaved gradient noise is cheap and suited to dark gradients and animation. Other items are standard practice I could not source.

### Cited Findings
- IGN: fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))), no texture reads, from Jimenez (2014) — [LYGIA IGN](https://git.gay/kaneraZh/lygia/src/branch/main/color/dither/interleavedGradientNoise.msl) and [0b5vr note](https://scrapbox.io/0b5vr/Interleaved_Gradient_Noise).
- Dithering smooths low-precision gradients but doesn't remove the band structure itself; Floyd-Steinberg is bad in animation, Bayer can be distracting, noise-based is preferred — [kodewerx](https://blog.kodewerx.org/2017/08/3d-renderer-dithering.html).
- Static dithering ignores local brightness; adaptive approaches reduce visible noise in darks — [USPTO 12361604](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12361604).

### Inferences (unsourced, standard practice)
- Add dither of about +/- 0.5-1.0 / 255 (before quantization, after tone mapping) with IGN seeded by pixel coord (plus frame offset only if no visible crawl). Do it in the same space as the output (linear dither is wrong for 8-bit sRGB output; dither after encoding).
- SDF alpha AA: alpha = clamp(0.5 - d / fwidth(d), 0, 1) (or smoothstep(-w, w, -d) with w = 0.5-1 px in pixels; d in pixels). Output premultiplied: rgb * alpha, matching a premultiplied blend state (one, oneMinusSourceAlpha). Pitfall: adding rim/spec glow after multiplying by alpha, or using non-premultiplied blending with a CAMetalLayer that expects premultiplied, gives dark/bright fringes. Specular should be added to premultiplied rgb but is clipped by alpha.
- macOS: Display P3 / extended-range pixel formats (bgr10_xr, rgba16Float with extended sRGB) give more dark steps; if rendering to rgba8 sRGB, dithering matters more. Verify the CAMetalLayer colorspace; glints could exceed 1.0 in EDR but keep body below about 0.02 linear.

### Gaps
- No Apple Metal documentation retrieved on pixel formats/EDR; unverified.

## 5. Performance

### Takeaway
Nothing sourced; the following is standard-practice reasoning to be profiled.

### Inferences (opinion)
- Cost scales with segments x field evaluations. Finite-difference normals with forward/tetrahedron differences use 3-4 evaluations vs 5 (central + center) or 6 (central); tetrahedron technique (iq's normalsSDF; could not re-fetch to verify) is 4. Forward differences with the center sample already known need 3 extra (4 total with center, 3 if center reused).
- Better: compute the gradient analytically in the same loop that finds the min/smooth-union (each primitive returns d and grad d; combine with the same blend weights), reducing to about 1x cost.
- Bounding-box culling: compute a per-segment bbox on CPU (inflated by blend radius + chip amplitude + AA), skip the fragment shader for pixels outside the union bbox (draw a tight quad), and early-out for far pixels (d_bbox > margin) before looping.
- Render at half resolution only if the AA and facet edges tolerate it; for a small menu-bar blob, full-res on a tight quad is usually cheaper than a resolve pass. Evaluate Voronoi only inside the blob (d < 0) and skip it when facet strength is zero.
- Move per-segment constants (inverse lengths, tapered cone terms) to the CPU/uniform buffer.

### Gaps
- No benchmarks for Apple Silicon found; all numbers are unmeasured.
