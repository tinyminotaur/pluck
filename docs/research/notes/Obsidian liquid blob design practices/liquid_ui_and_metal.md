# Liquid-glass / metaball UI design language and macOS Metal overlay best practices (Pluck)

Research depth note: about 14 tool calls. Several sub-questions (Apple WWDC session contents, Metal Best Practices Guide text, ScreenCaptureKit latency, WebGL/CI validation) were not reachable through search. They are listed under Gaps, and the "Inferences" sections hold engineering judgment that is not directly sourced.

## 1. Design language: Liquid Glass and gooey/metaball UI

### Takeaway
Apple's Liquid Glass is defined by lensing (bending and refracting what is behind it), real-time specular highlights that react to motion, content-adaptive colour, and shapes that merge and morph into each other. Most of this is achievable procedurally in a fragment shader. A dark obsidian variant should lean on the specular, rim and morph traits and drop the heavy background lensing, which also helps accessibility.

### Cited Findings
- Apple describes the material as bending and reshaping light from its surroundings ("lensing"), and says Liquid Glass objects materialise in and out by gradually modulating light bending and lensing, so the material stays optically intact during transitions. — [Computerworld](https://www.computerworld.com/article/4004457/wwdc-what-we-know-so-far-about-apples-liquid-glass-ui.html)
- Liquid Glass is rendered in real time, reacts to movement with specular highlights, and its colour is informed by the content around or behind it. Controls also shrink while scrolling and return to size afterwards. — [Macworld](https://www.macworld.com/article/2807925/meet-liquid-glass-apple-redesigns-all-its-interfaces-at-once.html), [Computerworld](https://www.computerworld.com/article/4004457/wwdc-what-we-know-so-far-about-apples-liquid-glass-ui.html)
- Apple exposes Liquid Glass to developers through SwiftUI, UIKit and AppKit APIs. — [Computerworld](https://www.computerworld.com/article/4004457/wwdc-what-we-know-so-far-about-apples-liquid-glass-ui.html)
- SwiftUI `GlassEffectContainer` combines multiple glass shapes into one shape that can morph individual shapes into one another. `glassEffectID(_:in:)` with a `@Namespace` lets SwiftUI animate shapes to and from each other. Both are macOS 26+. The container's `spacing` controls how close shapes must be before they merge. — [Apple: glassEffectID](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:).md), [Apple: GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer.md), [gitconnected guide](https://levelup.gitconnected.com/swiftui-liquid-glass-from-basic-to-a-little-advance-cdef4e4c5b90)
- Smooth-minimum blending is the standard way to get gooey merging in a shader. The polynomial smin is cheap and easy to tune, with k as the blend radius. The exponential smin sums an arbitrary number of shapes smoothly. — [Inigo Quilez, smin](https://iquilezles.org/articles/smin)
- Accessibility settings: Reduce Transparency makes glass more opaque. Increase Contrast adds borders and emphasis. Reduce Motion tones down animations and disables elastic interactions. On macOS Tahoe, enabling Increase Contrast also forces Reduce Transparency on. — [MobileSyrup](https://mobilesyrup.com/2025/06/10/how-apple-is-making-sure-liquid-glass-as-legible-as-possible/), [Infinum](https://infinum.com/blog/apples-ios-26-liquid-glass-sleek-shiny-and-questionably-accessible/)
- Critics measured contrast failures in beta (one case 1.5:1 against a 4.5:1 target), and said the settings help but do not close the gap. These are beta-era reports. — [Infinum](https://infinum.com/blog/apples-ios-26-liquid-glass-sleek-shiny-and-questionably-accessible/)

### Inferences
- Obsidian variant: keep a near-opaque dark body (for example 0.04-0.08 luminance), a thin bright rim or Fresnel edge, one or two soft specular streaks that move with the cursor velocity, a faint inner refraction-style gradient faked from the SDF normal, and smin necks for merging and morphing. Skip true background lensing, since an overlay cannot cheaply sample the background (see section 5).
- A mostly opaque body makes contrast against any desktop depend on the rim and a faint outer glow rather than on transparency, so it fails less than glass over busy content.
- Concentric shapes can be done as nested SDF offsets (d, d+r1, d+r2) with different alpha and highlight strength. Morphing between shapes is a mix or smin of two SDFs driven by a spring-animated parameter. These are design suggestions, not sourced.
- Read `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, `accessibilityDisplayShouldReduceTransparency` and `accessibilityDisplayShouldIncreaseContrast` and pass them as shader uniforms. Under Reduce Motion, snap or fade instead of elastic wobble. Under Reduce Transparency or Increase Contrast, use a fully opaque body and a stronger rim. These property names are from general AppKit knowledge and were not verified in this research.

### Gaps
- I did not retrieve the WWDC25 sessions "Meet Liquid Glass" or "Get to know the new design system", or the HIG Materials page, so there are no first-party quotes on the exact traits or on concentricity guidance.
- Apple's official contrast thresholds for custom materials were not found. WCAG 4.5:1 for text and 3:1 for non-text UI is general knowledge, not verified here.

## 2. Metal best practices for a transient cursor-following overlay

### Takeaway
Replace the readback pipeline with a `CAMetalLayer` (via a layer-backed NSView or MTKView) and present the drawable directly. No `waitUntilCompleted`, no `CGImage`, no CPU alpha scrub. Drive it with `CAMetalDisplayLink` (macOS 14+).

### Cited Findings
- Apple documents `CAMetalLayer` as the layer Metal renders into. You call `nextDrawable()`, render to `drawable.texture`, and call `commandBuffer.present(drawable)`. In AppKit: `view.wantsLayer = true; view.layer = CAMetalLayer()`. Apple suggests MTKView as the higher-level wrapper. — [Apple: CAMetalLayer](https://developer.apple.com/documentation/quartzcore/cametallayer.md)
- Request a drawable as late as possible, release references right after commit, and wrap the render loop in an `autoreleasepool`. Otherwise the pool runs out and `nextDrawable()` returns nil or stalls. — [Apple: CAMetalLayer](https://developer.apple.com/documentation/quartzcore/cametallayer.md)
- Relevant `CAMetalLayer` properties: `pixelFormat`, `colorspace`, `framebufferOnly`, `drawableSize` (in pixels), `presentsWithTransaction`, `displaySyncEnabled`, `wantsExtendedDynamicRangeContent`, `maximumDrawableCount`, `allowsNextDrawableTimeout`, `developerHUDProperties`. — [Apple: CAMetalLayer](https://developer.apple.com/documentation/quartzcore/cametallayer.md)
- `CAMetalDisplayLink` is available from macOS 14.0. You create it with a target `CAMetalLayer`, set a delegate, and add it to a run loop with `add(to:forMode:)`. The delegate method `metalDisplayLink(_:needsUpdate:)` receives an Update carrying the drawable, `targetPresentationTimestamp` and `targetTimestamp` (the deadline). Apple positions it for variable-rate displays where you need finer control over the frame timing window. — [Apple: CAMetalDisplayLink](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink.md), [Update](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/update.md), [delegate method](https://developer.apple.com/documentation/quartzcore/cametaldisplaylinkdelegate/metaldisplaylink(_:needsupdate:).md)
- Transparent layer: set `CAMetalLayer.isOpaque = false` (the Metal-layer `opaque` property). Without it, alpha is ignored. One reference implementation also keeps layer `opacity = 1.0`. — [par-term macos_metal.rs](https://docs.rs/crate/par-term/0.40.0/source/src/macos_metal.rs), [Apple forums: alphaBlendOperation thread](https://developer.apple.com/forums/thread/99048)
- Ghostty avoided transparent flashes on new or resized surfaces by using the layer's `backgroundColor` instead of drawing the background in the shader. — [Ghostty commit mirror](https://git.uoc.run.place/Applied-Software/ghostty/commit/ff9414d9ea7b16a375d41cde8f6f193de7e5db72)

### Inferences (engineering judgment, not sourced)
Suggested configuration:
```swift
let layer = CAMetalLayer()
layer.device = device
layer.pixelFormat = .bgra8Unorm          // cheapest; rgba16Float only if you want EDR highlights
layer.isOpaque = false
layer.framebufferOnly = true             // we never sample the drawable; lets the compositor optimise
layer.maximumDrawableCount = 2           // lowest latency; 3 if you see nextDrawable stalls
layer.allowsNextDrawableTimeout = true   // return nil instead of blocking the main thread
layer.contentsScale = screen.backingScaleFactor
layer.drawableSize = CGSize(width: pts.width*scale, height: pts.height*scale)
// render pass: loadAction = .clear, clearColor = (0,0,0,0)
// fragment output must be PREMULTIPLIED: float4(rgb*a, a); no blending needed if the shader writes the final value
```
- Premultiplied alpha is what Core Animation expects. Writing straight alpha produces dark or bright fringes. Blend factors, if used, would be `one, oneMinusSourceAlpha`.
- Pixel format: bgra8Unorm is enough for an 8-bit-looking dark blob. Dark gradients can band, so add 1/255-amplitude blue-noise or interleaved-gradient dither in the shader. rgba16Float with `wantsExtendedDynamicRangeContent = true` costs double the bandwidth and needs a matching colorspace (for example `extendedLinearDisplayP3`), so only use it if you want HDR specular peaks.
- `presentsWithTransaction` should stay false. It forces the present to synchronise with the main-thread CA transaction, which you only need when resizing the layer in step with other UI. If the layer is resized or moved every frame, keep that to window frame changes (`setFrame`) and keep the drawable size constant.
- In-flight frames: use a `DispatchSemaphore(value: 2 or 3)` released in `commandBuffer.addCompletedHandler`, with ring-buffered uniforms. The blob needs only a few floats, so use `setFragmentBytes` (limit 4 KB per Apple's Metal docs from general knowledge; not verified here) and avoid buffers entirely.
- CAMetalDisplayLink vs CVDisplayLink: CVDisplayLink fires on a background thread and has no per-screen drawable coupling. You must hop to main and request a drawable yourself. CAMetalDisplayLink hands you the drawable at the right time and runs on the run loop you choose. It can be added to a dedicated thread's run loop to keep the main thread free. Set `preferredFrameRateRange` for ProMotion (for example `CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)`) to follow the display. Property names are from general knowledge, so verify them.
- Layer size: size the panel to the blob bounding box plus margin (glow radius and spring overshoot) and move it with `setFrameOrigin`. Rendering a full-screen drawable at Retina 5K is wasteful even for a cheap shader. A small window with a constant `drawableSize` costs little per frame. Compute the shader in local coordinates so the blob does not depend on screen position. If the blob can stretch across a large distance (long gooey trail), either grow the panel or fall back to a screen-sized panel only during that stretch.
- Only run the display link while the overlay is visible and animating. Pause it and `orderOut` the panel when the animation settles.

### Gaps
- I could not fetch the Metal Best Practices Guide or the WWDC22/23 sessions on `CAMetalDisplayLink`, so the exact semantics of `preferredFrameLatency` (the display link property that sets drawable-ready lead time) and `preferredFrameRateRange` are unverified.
- Measured latency numbers for `maximumDrawableCount = 2` versus 3 on macOS were not found.

## 3. Overlay window specifics

### Takeaway
Use a non-activating `NSPanel` in an accessory-policy app with `canJoinAllSpaces` and `fullScreenAuxiliary`. Flags and level alone do not get you above other apps' full-screen Spaces. Hiding the system cursor from a background app is only reliable through undocumented behaviour, so the safer design is to draw the blob and leave the real cursor visible, or to hide it only while the panel can take the foreground.

### Cited Findings
- An Apple Developer Forums thread reports that `canJoinAllSpaces` plus `fullScreenAuxiliary` with a floating or status-bar level did not appear above full-screen apps. DTS-style advice was to use an `NSPanel` with `.nonactivatingPanel` and an accessory activation policy. — [Apple forums: Overlay window above all windows](https://developer.apple.com/forums/thread/826308), [Window visible on all spaces](https://developer.apple.com/forums/thread/26677)
- Apple's docs say the primary, auxiliary and `canJoinAllApplications` behaviours apply to full screen and Stage Manager and are mutually exclusive (use at most one). — [Apple: NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct.md)
- One report found crashes using `popUpMenu` or `screenSaver` levels in a SwiftUI overlay, though the author suspected a beta bug. — [gitconnected write-up](https://levelup.gitconnected.com/swiftui-macos-full-screen-cover-overlay-7a5bd886d795)
- Apple's cursor guide says the hide/show cursor functions require the app to be in the foreground, and `CGDisplayHideCursor`/`CGDisplayShowCursor` calls are balanced through a hide count. — [Apple: Controlling the Mouse Cursor](https://developer.apple.com/library/mac/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/MouseCursor.html)
- Background hiding historically uses the undocumented connection property named `SetsCursorInBackground` via `CGSSetConnectionProperty`. A 2004 list post showed it, and a modern forum thread says it is unsupported, may change between releases, and the Dock keeps cursor control when it is the target, which blocks it. Alternatives raised were warping the cursor offscreen with `CGWarpMouseCursorPosition` or placing a mostly transparent window above the Dock level. I found no source for the string `hidesCursorInBackground`; the sourced name is `SetsCursorInBackground`. — [Apple forums: Hide global mouse cursor on macOS dock](https://developer.apple.com/forums/thread/756199), [cocoa-dev 2004](https://lists.apple.com/archives/cocoa-dev/2004/Oct/msg00606.html)

### Inferences
- Starting point: `NSPanel(styleMask: [.borderless, .nonactivatingPanel])`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `ignoresMouseEvents = true`, `isFloatingPanel = true`, `level = .statusBar` or `.popUpMenu` (try `.screenSaver` only if it must beat full-screen apps; test, per the crash report above), `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `NSApp.setActivationPolicy(.accessory)`. `.stationary` and `.ignoresCycle` come from general knowledge.
- Cursor: prefer not to hide the real cursor. If the design requires hiding it, a reliable fallback is a fully transparent custom cursor pushed via a cursor-rect or `NSCursor.set()` on the overlay while it is key, but a non-activating, click-through panel cannot own the cursor. Treat the private `SetsCursorInBackground` route as best-effort with a graceful fallback (show the blob around the cursor instead of replacing it) and a feature flag. This is judgment, not sourced.
- Multi-display and mixed DPI: create one panel per `NSScreen` or move a single panel between screens. Take `backingScaleFactor` from the screen the panel is currently on and update `layer.contentsScale` and `drawableSize` on `NSWindow.didChangeScreenNotification` / `viewDidChangeBackingProperties`. Convert `NSEvent.mouseLocation` (global, bottom-left origin) to window coordinates. Not sourced.
- Screen-recording privacy: overlays you draw are visible to screen capture by default. Setting `sharingType = .none` on the panel hides it from capture. From general AppKit knowledge, unverified.

### Gaps
- No source confirmed how `.screenSaver` level behaves on macOS 14/15/26 with Stage Manager, or whether Stage Manager respects `fullScreenAuxiliary` for overlays.
- No current source confirmed that `CGSSetConnectionProperty`/`SetsCursorInBackground` still works on macOS 14-26.
- The exact behaviour of the Dock taking cursor control (per the forum thread) is a single report.

## 4. Shader practices

### Takeaway
Let SwiftPM compile `.metal` files into a metallib and load it with `makeDefaultLibrary(bundle: .module)` instead of compiling source strings at runtime. Keep the shader small, branch-light, and use half precision where the result is visual only.

### Cited Findings
- Apple TN3133: SwiftPM treats `.metal` files as resources, compiles the Metal source to a `.metallib` stored in the target's resource bundle, and you load it with `try device.makeDefaultLibrary(bundle: Bundle.module)`. Swift and Metal sources can sit in the same target. — [Apple TN3133](https://developer.apple.com/documentation/technotes/tn3133-packaging-a-renderer.md)
- For custom compile flags (for example debug symbols for shader debugging), TN3133 recommends a Swift Package Build Tool Plugin that runs the `metal` tool and outputs a `.metallib` into the target's resources. — [Apple TN3133](https://developer.apple.com/documentation/technotes/tn3133-packaging-a-renderer.md)
- Older (2020) forum answers said SwiftPM could not compile Metal sources and recommended `.copy` of the `.metal` file or a prebuilt metallib. TN3133 (2022) supersedes that. A `.copy`'d `.metal` file is raw source, not a library. — [Apple forums: Swift Package with Metal](https://developer.apple.com/forums/thread/649579)
- Half precision on Apple GPUs is a speed, memory and power win when used in the right places, but testing on hardware without native half can hide precision bugs. (Source is Unity's Metal documentation, not Apple's.) — [Unity manual](https://docs.unity3d.com/Manual/metal-requirements-and-compatibility.html)
- Smooth-minimum functions and their blend parameter guidance. — [Inigo Quilez, smin](https://iquilezles.org/articles/smin)

### Inferences
- Caveat for the CLI path: TN3133 behaviour describes Xcode-driven builds. Plain `swift build` on the command line has historically not run the Metal compiler for `.metal` resources in some toolchains. Verify on your own toolchain that `swift build` produces `default.metallib` in the `.module` bundle. If not, use the plugin route from TN3133, run `xcrun -sdk macosx metal -c` and `metallib` in a build script and ship the `.metallib` as a resource, or keep runtime `makeLibrary(source:)` as a fallback only. This was not verified.
- Fallback chain: `makeDefaultLibrary(bundle: .module)` then `makeLibrary(source:)` then, if no Metal device (`MTLCreateSystemDefaultDevice() == nil`), a non-Metal Core Animation fallback such as a `CAShapeLayer` blob with a radial gradient.
- Function constants (`[[function_constant(n)]]`) can specialise quality tiers, for example number of highlight layers, dither on or off, Reduce Transparency on or off. Compile pipelines once at launch and keep them cached. Not sourced here.
- Use `half` for colour, highlights and noise. Keep position and SDF distance in `float` near large coordinates. Keep the SDF analytic (a few circles/capsules plus smin), with no loops over unbounded counts. Use `step`/`mix`/`smoothstep` rather than `if`. Early-out with alpha 0 outside the bounding radius to save fragment work (TBDR hardware still shades the covered quad, so shrinking the quad matters more than branching).
- Tile-based deferred rendering: a single full-quad draw into a `.clear`/`.store` attachment is the ideal case. No second pass or sampling of the drawable is needed, so avoid `framebufferOnly = false`.
- Constants: `setFragmentBytes` is fine for a small uniform struct (limit 4 KB). Argument buffers are unnecessary here.
- Debugging: enable the Metal API Validation and Shader Validation scheme options, use Xcode GPU Frame Capture, and the Metal Performance HUD via `CAMetalLayer.developerHUDProperties` (documented on the layer page above, with `MTL_HUD_ENABLED=1` as the environment-variable route, which I did not verify).

### Gaps
- Apple's Metal Best Practices Guide and "Optimize Metal Performance for Apple silicon" session were not retrieved, so no first-party quantitative guidance on half precision, register pressure or branching cost.
- I did not confirm the 4 KB `setFragmentBytes` limit from Apple docs in this session (it is widely cited).

## 5. Background refraction / lensing on macOS

### Takeaway
A third-party overlay cannot sample what is behind it for free. ScreenCaptureKit would work but adds a permission prompt, a capture stream and latency, which is a poor fit for a transient utility blob. Fake the look from the blob's own SDF, or use system materials where a material suffices.

### Cited Findings
- Since Sequoia, apps using screen-capture APIs get recurring permission prompts. Apple moved from weekly to monthly in beta 6, with an "Allow for one month" choice, and the prompt says the app is requesting to bypass the system private window picker. — [TidBITS](https://talk.tidbits.com/t/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly/28621), [heise](https://heise.de/-9973354)
- Apple recommended moving from `CGDisplayStream`/`CGWindowListCreateImage` to ScreenCaptureKit and `SCContentSharingPicker`; one developer found ScreenCaptureKit alone did not avoid the prompts on 15.0 beta 7. — [heise](https://heise.de/-9973354), [Apple forums: ScreenCaptureKit tag](https://developer.apple.com/forums/tags/screencapturekit?page=4)
- SwiftUI Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `glassEffectID`) are macOS 26+ and give system lensing and morphing for SwiftUI content. — [Apple: GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer.md)

### Inferences
- With macOS 14 as the floor, `glassEffect` can only be an optional enhancement behind `if #available(macOS 26, *)`, for example hosting a SwiftUI view with glass in an `NSHostingView`. It will not follow a Metal shader's exact SDF shape and its look is system-controlled, so it conflicts with a custom obsidian look. Treat it as a reference to imitate, not a dependency.
- For macOS 14-compatible faking: `NSVisualEffectView` (material `.hudWindow` or `.underWindowBackground`) masked to the blob shape gives real blur-behind, but masking it to a changing SDF shape per frame via `CAShapeLayer` mask is costly and edges are hard. Alternatively, fake lensing by shading with the SDF normal, an environment gradient, and a subtle chromatic offset on the rim. For an obsidian (mostly opaque) body this is visually sufficient.
- Not sourced: if ScreenCaptureKit were used, you would need `SCContentFilter(display:excludingWindows:[overlay])` to exclude your own overlay, and you would pay for a stream plus 1-2 frames of latency, so the blob would refract slightly stale content.

### Gaps
- No data found on SCStream latency or GPU/power cost, or on `excludingWindows` behaviour.
- Apple's documentation for `NSVisualEffectView` / CALayer backdrop filters on arbitrary shapes was not retrieved.

## 6. Testing shaders without a Mac

### Takeaway
Use macOS CI runners for the real compile (`xcrun metal`, `swift build/test`), and an optional WebGL/GLSL port of the SDF math for headless visual regression on Linux. Both are mostly engineering judgment; the sourced facts concern runner availability.

### Cited Findings
- GitHub's macOS 14 runner image is being retired: deprecation began July 6 and it is fully unsupported by November 2 (as reported by a migration guide). macOS 15 images remain, with a macOS 26 image whose default Xcode was set to 26.6 on 2026.07.21 per release notes. Pin the runner label and Xcode version explicitly. — [C# Corner: macOS 14 retirement](https://www.c-sharpcorner.com/article/github-actions-macos-14-retirement-what-ci-pipelines-need-to-change), [runner-images release notes](https://newreleases.io/project/github/actions/runner-images/release/macos-15%2F20260720.0353)
- Shader math ports readily to GLSL: Inigo Quilez's smin and the `glsl-smooth-min` / LYGIA GLSL ports exist. — [glslify/glsl-smooth-min](https://github.com/glslify/glsl-smooth-min), [Inigo Quilez](https://iquilezles.org/articles/smin)

### Inferences
- CI: a `macos-15` job running `swift build && swift test`, plus `xcrun -sdk macosx metal -c Shaders.metal -o /dev/null` (or via the SwiftPM build) to catch syntax errors. A test that creates `MTLCreateSystemDefaultDevice()`, loads the library, and renders one frame to an offscreen texture then compares pixels is feasible on hosted runners if a Metal device is exposed, which is not guaranteed on virtualised runners (unverified).
- Newer Xcode versions may require the Metal Toolchain as a separate component (`xcodebuild -downloadComponent MetalToolchain`). This comes from the search tool's own-knowledge note and is unverified. Add a step that checks `xcrun metal --version` and downloads it if missing.
- Linux/Chromium path: keep the blob's SDF/shading as a small portable function, port to GLSL ES, render in headless Chromium with a WebGL canvas, and screenshot-diff. Metal and GLSL differ in precision and in sRGB handling, so only use it for shape and composition, not exact colour. SPIRV-Cross can convert SPIR-V to MSL, but the reverse (MSL to GLSL) is not supported; Apple's Metal shader converter targets DXIL to Metal. These tooling statements are from general knowledge and were not verified in this session.
- Add a pure-Swift reference implementation of the SDF (the same smin function) with unit tests for geometry (neck width versus k, bounding radius) so the maths is tested on Linux without a GPU.

### Gaps
- I did not verify that GitHub-hosted macOS runners expose a Metal GPU device, or whether `xcrun metal` needs the separately downloaded toolchain on the current images.
- No source was retrieved on WebGL headless screenshot approaches, SPIRV-Cross direction support, or metal-shaderconverter.
