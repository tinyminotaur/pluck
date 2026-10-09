# Liquid blob tether physics and motion (Pluck, macOS, 16-28 particle spine)

Provenance note: web search in this session returned only a handful of citable sources (listed inline). Items marked [KNOWLEDGE] are established techniques recalled from training (Disney principles, Juckett/Chou spring math, Jakobsen, metaball literature) and were NOT re-verified against a fetched page. Items marked [OPINION] are tuning heuristics, not established fact. wwdcnotes.com and several primary pages could not be fetched (DNS failure), so Apple formulas below come from search snippets only.

## 1. Animation principles for liquid: what timings/ranges feel liquid vs jelly vs rubber

### Takeaway
Liquid = low-to-moderate overshoot (one visible overshoot, ~5-15% amplitude), heavy damping of the whole body, plus delayed secondary motion (slosh) of the mass; jelly = lower damping ratio (~0.2-0.35) with several visible oscillations; rubber = stiff, fast, tight return with little mass lag. Apple's own guidance is that bounce ~0.15 is barely bouncy and ~0.3 clearly bouncy; avoid >0.4 for UI.

### Cited Findings
- Apple WWDC23 "Animate with springs" parameterizes springs by duration and bounce; example `.spring(duration: 0.6, bounce: 0.2)`; mass fixed at 1, stiffness derived from duration, damping from duration and bounce — [Apple WWDC23 10158](https://developer.apple.com/fr/videos/play/wwdc2023/10158/)
- Session notes: bounce ~0.15 barely bouncy, ~0.3 noticeably bouncy, be careful above ~0.4 for UI — [WWDC notes via search result](https://wwdcnotes.com/notes/wwdc23/10158) (snippet only, page not fetched)
- Damping-ratio regimes: 0 endless oscillation; (0,1) underdamped always overshoots; 1 critical, fastest non-overshooting return; >1 overdamped — [libadwaita SpringParams docs](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/struct.SpringParams.html)

### Inferences / [KNOWLEDGE] / [OPINION]
- [KNOWLEDGE] Disney principles mapped to the blob: squash and stretch (volume conserved: with a 1D spine, radius ~ 1/sqrt(stretch) in 2D area terms, keep sum(r_i^2 * ds_i) constant), anticipation (tiny 20-40 ms counter-motion/pinch of head before release), overshoot and follow-through (body lags head; on release head overshoots anchor by 5-15%), secondary motion (slosh of mass after head stops), slow-in/slow-out.
- [OPINION] Feel bands for the whole-body recoil spring: liquid zeta 0.45-0.7, period 160-260 ms with slosh sub-oscillators at 1.5-3x the main frequency and lower zeta damping (0.15-0.3) so they ring a bit then die in <400 ms; jelly zeta 0.2-0.35, period 250-400 ms, 3+ visible cycles; rubber zeta 0.3-0.5 but high frequency (period <120 ms), almost no lateral wave. The distinguishing cue for "liquid" is mass lag plus lateral travelling wave along the spine, not oscillation count.
- [OPINION] Keep amplitude of squash/stretch modest: radius modulation from slosh of about +-8-15% of base radius; beyond ~25% reads as jelly/cartoon.

### Gaps
- Could not fetch Disney-for-UI, Rive/Lottie, Material motion, or Apple "Designing Fluid Interfaces" text; no citable numeric "liquid vs jelly" ranges exist in sources found. The bands above are opinion.

## 2. Spring math best practices

### Takeaway
Parameterize by frequency (or period) and damping ratio, not raw stiffness; use a fixed substep (e.g. 240 Hz or 4 substeps at 60/120 Hz) with an accumulator; prefer closed-form or semi-implicit/position-based updates; for stiff spine constraints use PBD/XPBD with several small substeps rather than many iterations per step.

### Cited Findings
- Gaffer on Games "Fix Your Timestep": accumulate frame time, step physics in fixed dt while accumulator >= dt, carry remainder; cap frame time against the spiral of death; interpolate render state between last two physics states — [Fix Your Timestep](https://gafferongames.com/post/fix_your_timestep/); spiral-of-death caveats — [GameDev.net blog](https://www.gamedev.net/blogs/entry/2262574-thoughts-on-fix-your-timestep-and-the-spiral-of-death)
- "Small Steps in Physics Simulation" (Macklin, Storey, Lu, Terdiman, Chentanez, Jeschke, Müller 2019): one large step with n iterations is worse than n substeps with one iteration each; XPBD substepping reduces constraint error and damping loss and is stable over wide stiffness ranges — [EG digital library](https://diglib.eg.org/handle/10.1145/3309486-3340247)
- XPBD lineage and per-substep loop (predict, solve constraints with substep length, recompute velocity from position change): PBD Müller 2006, XPBD Macklin 2016 — [Cornell CS5643 slides](https://www.cs.cornell.edu/courses/cs5643/2025sp/slides/13pbd.pdf)
- Jakobsen "Advanced Character Physics": Verlet integration + constraint relaxation (satisfy constraints one at a time, repeat a few passes), positions corrected directly so no velocity bookkeeping; known to be "bouncy"/inexact with few iterations — [Game Developer reprint](https://gamedeveloper.com/programming/advanced-character-physics); relaxation description — [GameDev.net thread](https://gamedev.net/forums/topic/626870-ropecloth-simulation-problems/)
- Apple spring: mass = 1, stiffness from duration, damping from duration and bounce — [Apple WWDC23 10158](https://developer.apple.com/fr/videos/play/wwdc2023/10158/)

### Inferences / [KNOWLEDGE] / [OPINION]
- [KNOWLEDGE] Parameterization: omega = 2*pi*f (f in Hz), stiffness k = omega^2 (m=1), damping c = 2*zeta*omega. Semi-implicit Euler per substep h: v += (-k*x - c*v)*h; x += v*h. Stable if omega*h < ~2 (zeta=0) and well-behaved for omega*h < ~0.5; at f=6 Hz, h=1/240 s gives omega*h = 0.157, fine.
- [KNOWLEDGE] Exact closed-form damped spring (Juckett/Chou style) is unconditionally stable and frame-rate independent; use it for the head-follow and any single-DOF springs (radius/slosh oscillators) so a variable dt never explodes. Underdamped solution: x(t)=e^(-zeta*omega*t)(x0 cos(wd t) + ((v0+zeta*omega*x0)/wd) sin(wd t)), wd = omega*sqrt(1-zeta^2). Critical: x(t)=(x0+(v0+omega*x0)t)e^(-omega t).
- [KNOWLEDGE] Apple legacy mapping (from training, unverified here): response = period of undamped spring = 2*pi/omega0 (so omega0 = 2*pi/response, k = omega0^2, c = 4*pi*dampingFraction/response); dampingFraction = zeta. WWDC23 form: omega0 = 2*pi/duration (perceptual duration), bounce b>=0 gives zeta = 1 - b, so bounce 0.3 = zeta 0.7, bounce 0.15 = zeta 0.85. Verify exact formula against Apple docs before relying on it.
- [OPINION] Spine recommendation: fixed h = 1/240 s (2 substeps at 120 Hz, 4 at 60 Hz), accumulator capped at ~4 steps; per substep: Verlet integrate with velocity damping exp(-c*h), apply lateral whip impulse, then 2-4 distance-constraint relaxation passes (or XPBD with small compliance for a soft stretch) between neighbors, then bend/straightening spring toward the pin-head line (stiffness via frequency). Clamp head speed injected into the whip impulse (e.g. tanh soft clamp) so a flick of 5000+ px/s cannot blow up the chain. Head is kinematic (set to the pointer) so it carries no spring itself; spring-follow the body, not the head.
- [OPINION] Render interpolation between physics states if physics rate is not a multiple of display rate.

### Gaps
- Chou/Juckett/Holmér/Muratori pages did not appear in search results; formulas above are from memory. Exact Apple duration/bounce formula not retrieved (the session defines separate formulas for bounce >=0 and <0).

## 3. Metaball neck behavior, necking and pinch-off

### Takeaway
A cylindrical liquid bridge is classically unstable once length exceeds circumference (L/D > pi, zero gravity); use that as the physical anchor for when the neck should start to bead up and snap. Cheap tricks: area/volume-conserving radius profile, smooth-min union, and a hysteretic break threshold.

### Cited Findings
- Plateau/Rayleigh limit: a weightless, neutrally buoyant liquid bridge is stable up to length/diameter = pi; breaks beyond that; Plateau observed it experimentally, Rayleigh derived it by linear stability — [arXiv 1010.2562](https://arxiv.org/pdf/1010.2562), [arXiv physics/0407008](https://arxiv.org/pdf/physics/0407008)
- Gravity lowers the threshold below pi — [arXiv physics/0407008](https://arxiv.org/pdf/physics/0407008); (3,0) mode becomes unstable near slenderness 4.49 — [NASA NTRS](https://ntrs.nasa.gov/api/citations/20020029723/downloads/20020029723.pdf)
- Stabilized or viscous-elastic columns can exceed the limit (slenderness >4.5 observed for smectic liquid-crystal columns) — [MDPI Crystals](https://www.mdpi.com/2073-4352/12/8/1092)

### Inferences / [KNOWLEDGE] / [OPINION]
- [KNOWLEDGE] Volume conservation for a stretched slender tube: pi*r^2*L = const so r ~ 1/sqrt(L) (neck radius r = r0*sqrt(L0/L)); this is the standard cheap thinning law. Smooth-min for SDF union: smin(a,b,k) = min(a,b) - h^2*k/4 with h = max(k-|a-b|,0)/k (polynomial, Inigo Quilez); k ~ 0.3-0.8 x base radius gives gooey merging.
- [OPINION] Two-stage necking: below stretch s = L/L0 ~ 1.5 use r ~ s^-0.5; between 1.5 and the break length add an extra accelerating thin-down r *= 1 - smoothstep(s_a, s_b, s)^2 near the weakest point (not mid-span only; bias toward the end with the least mass, add slight noise) so it looks like a capillary neck collapsing; break when neck radius < ~0.12-0.18 x base radius or L/D_eff > pi*(1.5-2.5) (viscous, so well above pi is fine and reads gooey).
- [OPINION] Pinch-off animation: neck collapse is accelerating (self-similar); take 60-120 ms from onset of collapse to separation, then recoil each stub with a spring (zeta ~0.4) toward its blob, optionally leave one satellite droplet (radius ~0.2-0.35 of neck-mass equivalent) with a short ballistic arc of 150-250 ms. Hysteresis: break at s_b, allow re-merge only when gap < ~0.5 x s_b-based distance to avoid flicker; during re-merge use the smooth-min k ramping up over ~80 ms.
- [OPINION] Slosh oscillator modulates radius but should redistribute, not add, volume: apply r_i' = r_i*(1 + a_i) then renormalize sum(r_i'^2 ds_i) to the target.

### Gaps
- No source found for gooey-effect (Bebber) or Jamie Wong metaball articles in this session; metaball specifics are from memory.

## 4. Pointer-follow feel

### Takeaway
Keep the head exactly on the cursor (zero filtering on the head) and let all lag live in the body; if any smoothing is needed (e.g. for specular or velocity estimates) use the 1 euro filter on derived signals, not on the head.

### Cited Findings
- 1 euro filter (Casiez, Roussel, Vogel, CHI 2012): first-order low-pass whose cutoff rises with speed; mincutoff = cutoff at rest (lower = less jitter, more lag), beta = speed coefficient (higher = less lag when fast), dcutoff default 1 Hz for the derivative; beta 0 degrades to plain low-pass; library defaults mincutoff 1.0, beta 0.0; example 1.0 Hz / beta 0.1 at 120 Hz — [HAL paper page](https://hal.archives-ouvertes.fr/hal-00670496), [PyPI oneeurofilter](https://pypi.org/project/oneeurofilter)

### Inferences / [KNOWLEDGE] / [OPINION]
- [KNOWLEDGE] 1 euro formulas: cutoff = fc_min + beta*|dx_hat|; alpha = 1/(1 + tau/Te), tau = 1/(2*pi*cutoff). Pointer coordinates in pixels need beta scaled accordingly (speeds in px/s are large; beta ~0.005-0.05 typical for pixels, tune empirically).
- [OPINION] Velocity for whip impulse and lighting: use a 1 euro-filtered or short exponential average (tau ~ 20-40 ms) of pointer velocity so single-event spikes (macOS coalesced events) do not kick the chain. Use coalesced/predicted mouse events if available; prediction of 1 frame is fine for the head only if it visibly reduces latency, but overshoot on reversal is noticeable, so prefer no prediction.
- [OPINION] Velocity-based lighting: shift the specular highlight/normal bias opposite to velocity direction by a few percent of radius with an exponential lag (~60-100 ms); elongate highlight along the spine with stretch; optional cheap motion trail = render previous-frame mask with 0.85-0.9 fade, or 2-3 offset SDF samples along velocity.
- [OPINION] Direction-threshold feedback (crossing into a lobe's zone): at crossing, fire a 120-180 ms spring impulse on radii (head squash 8-12% then recover, slosh kick amplitude ~0.3), plus a "magnet" pull: add a force on the head's visual blob, not the cursor, toward the lobe centre scaled by smoothstep of proximity, capped to a few px so the head stays glued; add a haptic tick (NSHapticFeedbackManager, alignment pattern) if the user has a trackpad.

### Gaps
- No source on latency perception thresholds or macOS-specific event coalescing was gathered.

## 5. Faceted / obsidian motion without jitter

### Takeaway
Quantize appearance, not physics: simulate smoothly, then snap derived visuals (facet normals, highlight positions, edge steps) with hysteresis and short eased blends; reserve fully stepped motion for discrete events (crystallize on commit).

### Cited Findings
- None found in sources searched.

### Inferences / [OPINION]
- [OPINION] Quantized time ("on twos/threes" animation): update only the facet-shading layer at 20-30 Hz while geometry runs at display rate; this gives a stop-motion crystalline feel without jittering position. Never quantize the head position.
- [OPINION] Facets: compute normal from the smooth SDF gradient then snap to N discrete directions (N 6-12) with hysteresis band of ~15% of the angular step, blending over 1-2 frames, so facets do not flicker on small changes. Make facet size grow with stretch (crystallization at high stretch: blend factor c = smoothstep(1.8, 3.0, s) mixing smooth and snapped normals).
- [OPINION] Commit transition: 80-140 ms crystallize (snap normals to full facets, specular brightens), then 100-160 ms shatter into 6-12 shard polygons using the existing particles as seeds, each given velocity along the spine direction plus random perpendicular jitter, with gravity-free drag, fading in 150-250 ms.
- [OPINION] Shards should inherit the blob's velocity at commit and be eased out (ease-out cubic) to avoid reading as random noise.

### Gaps
- No citable references for obsidian/crystal UI motion were found.

## 6. Commit / cancel animations and durations

### Takeaway
Keep feedback within ~100-250 ms: cancel = spring recoil with 1 overshoot; commit = absorb into target lobe with ease-in then small squash; use the same spring family as the rest of the UI for coherence.

### Cited Findings
- Apple's `.snappy`/`.smooth` style presets and duration/bounce model are the standard way to express such springs in SwiftUI/UIKit/CA — [Apple WWDC23 10158](https://developer.apple.com/fr/videos/play/wwdc2023/10158/); bounce guidance as in section 1.

### Inferences / [OPINION]
- [OPINION] Cancel (snap-back): drive the head back to the pin with a spring, period ~180-240 ms, zeta 0.5-0.6, one overshoot; run the spine under the same constraints so it whips and the slosh rings 2-3 cycles; total settle < 350 ms but control returns immediately (non-blocking). Interruptible: new gesture start adopts current state as initial condition (carry velocity).
- [OPINION] Commit (absorb): head accelerates into target lobe over 120-180 ms (ease-in then spring-settle), tail retracts with 30-50 ms stagger per particle from head to pin (travelling absorption), the lobe gets a pulse (scale 1.0 -> 1.06 -> 1.0 over ~160 ms, zeta ~0.5). Total perceived response < 250 ms.
- [OPINION] Droplets: 2-4 small satellites at 0.15-0.3 x neck radius flung along the last velocity direction, lifetime 200-350 ms, shrinking (area-linear) and absorbed by the lobe via magnet attraction.

### Gaps
- No citable human-factors study on "responsive" thresholds found here; the <250 ms figure is the prompt's guideline and common UI practice, not verified in sources.
