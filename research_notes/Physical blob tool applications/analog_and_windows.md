# Analog-parameter and window-management applications of a stretchable blob gesture (Pluck, macOS 14+)

Scope note: ~17 searches/fetches. Several named prior-art items (Angry Birds slingshot, Dynamic Island, Force Touch scrubbing, jog-shuttle, BetterTouchTool, Android/ChromeOS flick, Apple HIG haptics page, Josh Comeau/Rauno/Linear/Rive articles) could NOT be fetched or confirmed; they are listed under Gaps. Everything under "Inferences" is design judgment, not sourced fact. Codebase facts come from /home/user/pluck/docs/HANDOFF.md and the file listing (read directly, not web-sourced).

## 1. Analog parameter control: how have apps/hardware used drag distance or tension as a continuous value, and which Pluck mappings are worth it?

### Takeaway
Well-sourced prior art for "drag distance = value" is thin in what I could retrieve; the solid evidence is Figma-style scrubbing (with a speed/precision modifier), pressure-widget research (about six discernible levels, only with visual feedback), and Apple's detent haptic patterns. Best Pluck mappings are those with few discrete levels or a visible scale in the blob itself; fine continuous parameters (volume, scrub) need a precision modifier.

### Cited Findings
- Figma scrubbing: hold Option/Alt over a numeric field and drag left/right to change the value; a community reply says moving the cursor toward the top/bottom of the screen changes scrub speed (faster/slower). A WebStudio post claims Shift changes sensitivity; this is unverified and conflicts with the vertical-position claim. — [Figma forum](https://forum.figma.com/questions/25774); [WebStudio help](https://help.webstudio.is/mouse-dragging-property-values-qLN0jJJHl18N)
- Figma scrub reliability complaints: Option-drag "doesn't work everywhere", and narrow hover targets on fields without icons (staff says the narrow target is unintentional). Lesson: discoverability/affordance is the fiddly part. — [Figma forum](https://forum.figma.com/report-a-problem-6/option-drag-alt-drag-not-working-in-all-number-fields-37280)
- Pull-to-refresh: invented by Loren Brichter in Tweetie (2007-08) by making refresh part of the scroll gesture instead of a crammed button; he later argued "pull-to-do-action" is the better name. Threshold/elasticity details were not found. — [Wikipedia: Pull-to-refresh](https://en.wikipedia.org/wiki/Pull-to-refresh); [MacStories interview](https://www.macstories.net/news/loren-brichter-talks-about-pull-to-refresh-patent-and-design-process/); [Jared Sinclair, pull to do action](https://jaredsinclair.com/2013/12/20/pull-to-do-action.html)
- Pressure Widgets (Ramos, Boulos, Balakrishnan, CHI 2004): stylus pressure as continuous or discrete-threshold widgets; abstract also tests techniques for confirming selection. A press summary reports people can readily identify about six discrete pressure levels, but only with appropriate visual feedback (secondary source). — [Ramos CHI 2004 PDF](https://www.dgp.toronto.edu/~bonzo/docs/p1375-ramos.pdf); [Varsity summary](https://thevarsity.ca/2004/09/23/succeeding-under-pressure/)
- Pressure Marks (CHI 2007) argues selection and action are usually separated, creating a time lower bound equal to the sum of the parts, and lets a single gesture indicate both. — search result abstract summary, see [Ramos DGP TR](https://www.dgp.toronto.edu/~ravin/papers/dgp-tr-2004-003.pdf) (related; I did not read the 2007 paper itself)
- Logitech MX Master 4 pairs customizable haptics with the Actions Ring (a radial overlay at the cursor in Logi Options+); one reviewer called haptics on ring navigation pleasant but closer to novelty than productivity gain. Logitech's "33% time saved / 63% fewer movements" are vendor claims from a 37-user internal study. — [Tbreak](https://tbreak.com/logitech-mx-master-4-uae-haptics-actions-ring/); [Business Wire](https://www.businesswire.com/news/home/20250930356623/en)
- Velocity handling for flicks: Emil Kowalski's "apple-design" skill (secondary mirror, attributing to WWDC18 "Designing Fluid Interfaces") says project the resting position from release velocity using exponential decay (decel rate ~0.998 normal, ~0.99 snappier) and snap to the target nearest the projection; pass release velocity as spring initial velocity; decompose 2D motion into independent X/Y springs. I could not verify the constants against Apple's sample code. — [mirror](https://mcpservers.org/agent-skills/emilkowalski/apple-design)

### Inferences (design judgment, not sourced)
Ranked parameter mappings for Pluck (stretch = distance from pin, along a latched direction):
1. Discrete-level stretch with detents (3-5 notches along the tether, tick haptic per notch; Pluck already ticks every ~56 pt). Fits "six levels with feedback" evidence. Uses: undo depth (1/2/3 steps), paste-history item index, number of items, priority (P1-P3), zoom presets. Draw notch marks/numbers on the tether so the scale is visible.
2. Distance = commit stage (see section 3), the safest analog use.
3. Continuous scrub (volume, brightness, playback position) with a precision mode: Figma shows a modifier/axis for speed is needed. Candidate: perpendicular offset or hold-slow = fine mode, or log mapping. Risk: blob tether has max extent so absolute range is limited; use relative/rate control (stretch = rate, like jog-shuttle) for long ranges and the blob's spring-back as the natural "return to zero" of a rate control. Rate control for scrub/zoom is likely the most natural fit since the spring supplies the neutral.
4. Speed -> intensity is weak: speed is noisy, unseen, and already gates label display in Pluck (labels suppressed on fast flicks). Use only for binary intent (flick = fast-commit), not graded values.
5. Release velocity -> throw (section 2); the strongest "physical" mapping.
Pitfall list: mixing too many parameters on one drag (distance, direction, speed) makes the gesture unlearnable; keep direction = which action, distance = how much/confirm, release velocity = only throw.

### Gaps
- No retrieved sources on Angry Birds/slingshot aim studies, iOS rubber-band formula, Dynamic Island, Force Touch scrubbing, jog-shuttle ergonomics, BetterTouchTool, or Tesla/Apple "peek and pop". Claims about them are absent here on purpose.
- No quantitative data on user precision for distance-based continuous control with a mouse (Fitts-style or "elastic input" CHI papers not found; searching "elastic input rate control" for isotonic vs elastic devices (Zhai) is the suggested next lead).

## 2. Slingshot / fling: throwing windows, files, selections; prior art and AX/Spaces constraints

### Takeaway
Moving/resizing other apps' windows via the Accessibility API is mainstream (Rectangle, Magnet, Moom) and needs no SIP changes, but there is no public API for moving windows between Spaces; every tool that does it uses private APIs or SIP-disabled injection. Throw-to-edge/other-display/snap is cheap and safe; throw-to-Space is not.

### Cited Findings
- Rectangle supports macOS 14+ and uses the Accessibility API (AXUIElement) to move/resize windows; its README says it cannot move windows between desktops because "Apple never released a public API for doing this"; Rectangle Pro has next/previous Space actions. — [Rectangle README](https://github.com/rxhanson/Rectangle); README also lists known issues: it "cannot override an app's minimum window size", iTerm2 resizes by character-width increments by default.
- Per the maintainers' summary, apps that move windows between Spaces use unsupported methods that may break with macOS updates. — [Rectangle README](https://github.com/rxhanson/Rectangle) via search summary
- yabai: moving, swapping, creating, destroying spaces, window opacity/shadows/animations, sticky windows, layers and PiP require partially disabling SIP so a scripting addition can be injected into Dock.app. Apple Silicon macOS 13+ uses `csrutil enable --without fs --without debug --without nvram`; Apple repairs can re-enable SIP. A search summary said `yabai -m window --space N --focus` may work with SIP enabled, but one Reddit comment contradicts; unresolved. — [yabai wiki: Disabling SIP](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection); [yabai Commands](https://github.com/koekeishiya/yabai/wiki/Commands)
- Hammerspoon hs.spaces is built on private APIs plus Accessibility hacks and the docs warn Apple could change them any time; the older standalone module could only move windows that are on one space to a user space, and did not reposition across displays. I found no source documenting a macOS 14 regression. — [Hammerspoon hs.spaces docs](https://www.hammerspoon.org/docs/hs.spaces.html); [asmagill undocumented spaces](https://github.com/asmagill/hs._asm.undocumented.spaces)
- Full-screen: a Rectangle issue records that windows don't move past/with full-screen windows (Spectacle and Magnet likewise); the maintainer notes AX can detect full-screen status. Moom docs: full-screen creates a separate Space. — [Rectangle issue #51](https://github.com/rxhanson/rectangle/issues/51); [Moom release notes](https://manytricks.com/moom/releasenotes)
- AX write quirks: a write to kAXPositionAttribute can return success whether or not the app honors it, so read the frame back; setting AXEnhancedUserInterface=true on an app is reported to break window positioning in tools like Magnet; common workaround (unverified, from the search tool's general knowledge) is to set it false during the move and restore it; Electron/Chromium apps showed stutter on AX resize. — [Apple Cocoa-dev thread](https://lists.apple.com/archives/Cocoa-dev/2007/Nov/msg00892.html); [Electron PR #7206](https://github.com/electron/electron/pull/7206); [Apple dev forum thread](https://developer.apple.com/forums/thread/659755)
- Fluid-interface technique for throws: project from release velocity, then spring to the nearest target (see section 1). — [mirror](https://mcpservers.org/agent-skills/emilkowalski/apple-design)

### Inferences
- Throw semantics: direction (N/E/S/W already latched) picks the destination class; projected landing point (velocity projection) picks the specific snap zone (left half, right half, quarter, other display, maximize). Do not use raw release point; use projected point so a short hard flick throws far.
- Cheap: throw to halves/maximize/next display via AXPosition+AXSize, with fallback readback check and min-size handling. Needs a window-under-pointer lookup (Pluck's ContextResolver already reads "window" under the pointer via AX). Moving the window while the blob is up: the blob can pull a ghost rather than the live window (see section 3).
- Throw to another Space: avoid in v1. Only safe public-ish alternative is to synthesize the native macOS drag-to-screen-edge or Mission Control shortcuts, which conflicts with Pluck's listen-only rule (no synthesized input). Honest options: omit, or detect and label "unsupported".
- Full-screen windows: detect via AXFullScreen and show a disabled/greyed lobe rather than failing silently.
- File flick: "send to folder/AirDrop" requires file operations or NSSharingService; moving files via FileManager is straightforward, but destinations must be user-configured per direction (and trust/undo issues, so require commit stage and an undo toast).
- Magnet/Rectangle already offer drag-to-edge snapping; Pluck's differentiation is that it works from anywhere in the window (not just title bar) with a preview and analog confirm. This is a positioning claim, not sourced.
- Pluck is currently listen-only (NSEvent monitors, no event tap), so the underlying app also receives the press/drag (HANDOFF known issue). For window-throw, that means a title-bar press could also drag the window natively; trigger modifier (option-hold) must not collide with native window dragging.

### Gaps
- No sources found for: Amethyst, BetterSnapTool, Stage Manager, Mission Control gestures, Android/ChromeOS flick, or Apple's own macOS Sequoia tiling behavior; no macOS 14+/15-specific confirmation of which private Space APIs still work (CGSMoveWindowsToManagedSpace etc.); no confirmation whether AX can address windows on other Spaces (commonly reported as not enumerable via AX; unverified here).
- ScreenCaptureKit for ghost previews: sequoia prompts monthly re-authorization for screen recording ("requesting to bypass the system private window picker") and Apple ties alerts to older CGWindowList/CGDisplayStream APIs; whether single-frame SCScreenshotManager avoids the prompt was not confirmed. — [TidBITS](https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly); [heise](https://heise.de/-9973354). A screenshot-tool developer says the new API is slower and less reliable than the old one (anecdotal, via the same search).

## 3. Tension as commitment: stretch distance as confirm, and pre-commit previews

### Takeaway
Marking-menu research supports the novice-then-expert model: show guidance on dwell, let experts flick without it, and keep the mark simple; pressure-widget research supports a separate confirm step with visible feedback. Pluck's two-zone stretch (preview then commit) is consistent with this but there is no direct study of elastic-distance-as-confirm.

### Cited Findings
- Kurtenbach and Buxton (CHI 1994) field case study: experienced users shifted heavily to marks; marks averaged 3.5x faster than menu selection; experts sometimes return to menus to refresh memory; study had only two users. Design principles in Kurtenbach's thesis: self-revelation, guidance, rehearsal. — [Buxton MMUserLearn](https://billbuxton.com/MMUserLearn.html); [Berkeley summary](https://people.eecs.berkeley.edu/~fox/summaries/ui/marking_menus.html); [Autodesk Research](https://www.research.autodesk.com/publications/user-learning-and-performance-with-marking-menus/)
- Limits of expert performance (Kurtenbach and Buxton, InterCHI 1993): empirical bounds on breadth/depth before marking becomes slow or error-prone. — [Autodesk PDF](https://research.autodesk.com/app/uploads/2023/03/the-limits-of-expert.pdf_recyw5wL6ekPqcE4Q.pdf)
- Zhao and Balakrishnan (UIST 2004): simple (multi-stroke) marks were faster and more accurate than compound zig-zag strokes, especially at large breadth; a CHI 2006 follow-up reports breadth-8 depth-3 (512 items) at 93% accuracy. — [UIST 2004 PDF](https://www.dgp.toronto.edu/~ravin/papers/uist2004_simplemm.pdf); [Zone polygon menus CHI 2006](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/Zone-Polygon-Menus-CHI-2006.pdf)
- Pressure Widgets compared techniques for confirming selection once a pressure target was acquired, and showed discrete levels need visual feedback. — [Ramos CHI 2004](https://www.dgp.toronto.edu/~bonzo/docs/p1375-ramos.pdf)

### Inferences
- Proposed three-zone stretch: 0-24 pt dead zone (existing), then "preview" zone where the lobe shows a ghost of the result (target window outline at snapped position, clipboard item text, image thumbnail), then beyond a visible threshold ring the blob "pinches"/crystallizes = commit armed. Release in preview zone = cancel (snap-back, no action); release past threshold = commit. Maps to marking-menu "novice sees, expert flicks": a fast flick past the threshold commits without needing the preview (Pluck's HANDOFF already lists "flick-commit + earlier arming on fast stable flicks").
- Risk-scaled thresholds: destructive actions (delete, close, move files) need greater stretch than reversible ones (snap window). Tension itself communicates weight.
- Cancel by returning to the pin (existing dashed cancel ring) is a free, learnable undo.
- Safe default for window throws: preview-only ghost drawn in the overlay (a rounded rect outline) without capturing the screen (no ScreenCaptureKit). A real window thumbnail needs Screen Recording permission.

### Gaps
- No found HCI study on elastic/spring-return drag distance as a confirmation gesture; closest are pressure-widget and marking-menu results above (inference by analogy). Cannot cite a specific optimal commit-threshold distance.

## 4. Magnetic latching, detents, haptics, and visual snap

### Takeaway
Apple's AppKit exposes exactly the right trackpad patterns (alignment for snaps, levelChange for stepped values) with explicit guidance to pair with visuals and use sparingly; spring-animation guidance emphasizes interruptibility, velocity continuity, and overshoot for trustworthy snaps.

### Cited Findings
- NSHapticFeedbackManager patterns: generic, alignment (object snaps into line, e.g., drawing alignment guide; also reaching min/max or a preferred position) and levelChange (moving between discrete levels). Obtain via defaultPerformer; system may override (no haptic if finger not on trackpad); call only in response to user-initiated actions; pair with visual feedback; use sparingly. NSAlignmentFeedbackFilter exists for drags with alignment bumps. — [AppKit reference search results: feedbackPattern](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager/feedbackpattern.md); [NSAlignmentFeedbackFilter](https://developer.apple.com/documentation/appkit/nsalignmentfeedbackfilter.md); [ForceTouchCatalog sample](https://developer.apple.com/library/archive/samplecode/ForceTouchCatalog/Listings/ForceTouchCatalog_MasterViewController_swift.html)
- Animation principles (secondary mirror attributing WWDC18): every animation interruptible; start new animations from the current on-screen value; blend velocity on reversal ("brick wall" if hard-cut); springs are inherently interruptible and velocity-aware. — [mirror](https://mcpservers.org/agent-skills/emilkowalski/apple-design)
- Logitech MX Master 4 ties haptic feedback to Actions Ring navigation (vendor product design) — [Tbreak](https://tbreak.com/logitech-mx-master-4-uae-haptics-actions-ring/)
- Pluck already: trackpad ticks on direction latch and every ~56 pt stretch; latch squash; armed pop spring; commit confirmation flash (repo, docs/HANDOFF.md).

### Inferences
- Use `.alignment` for lobe latch and commit-threshold crossing; `.levelChange` for stepped parameter notches (current code uses one haptic type; verify which). Haptics only fire when a finger is on a trackpad, so mouse users get none: every detent needs a visual (blob squash) and optionally a faint sound, and the design must not depend on haptics. Mouse chord trigger users get no haptic; trackpad-hold users do.
- Visual snap trust: squash on arrival, small overshoot, settle; keep durations short; same snap logic for commit as for latch. (Squash/stretch and overshoot are Disney principles; no direct source retrieved.)

### Gaps
- Could not retrieve Apple HIG Haptics page, Josh Comeau (fetch failed: DNS), Rauno Freiberg, Linear, Rive, Material motion, or Disney-principle sources; no sourced numbers for haptic timing or overshoot amounts.

## 5. Feasibility in this codebase

### Takeaway
Ideas built only on existing gesture state (distance, direction latch, release velocity, haptics, label UI) are cheap; anything that moves other apps' windows needs an AX layer and handling edge cases; Spaces and live window previews need risky or permission-heavy infrastructure.

### Cited Findings (codebase facts from repo)
- Fixed 240 Hz physics accumulator, spring snap-back with fling momentum (RecoilSpring), latched role captured on release (GestureMath), haptic ticks, ContextResolver reads selection/link/file/image/window via AX, ActionRunner exists, Feel Lab mode currently disables real actions, app is listen-only by design (NSEvent monitors, no CGEventTap, never synthesize input). — /home/user/pluck/docs/HANDOFF.md; files under /home/user/pluck/Sources/Pluck and /home/user/pluck/Sources/PluckCore
- Known perf issue: overlay renders via offscreen Metal texture + CPU readback every frame; a CAMetalLayer rewrite is planned. — /home/user/pluck/docs/HANDOFF.md
- Public-API external window moves need Accessibility permission, which Pluck already requests (Permissions/).

### Inferences (tiering; my judgment)
Cheap (days, existing infrastructure):
- Stretch-notch detents for discrete values (undo depth, item count, priority), reuse the 56 pt haptic tick.
- Preview/commit two-zone stretch and threshold ring; flick-commit; cancel by return-to-pin.
- Release-velocity "throw" projected to pick one of the N/E/S/W targets or strength of an action (e.g., throw distance chooses near vs far target).
- Rate-control scrub (stretch = rate) for volume/zoom via existing ActionRunner hooks, if actions use system APIs already allowed.
Medium (new but public APIs):
- Window snapping by throw: AXUIElement lookup of window under pointer (partly exists), set AXPosition/AXSize with readback, min-size and AXEnhancedUserInterface handling, multi-display coordinate conversion (AppKit y-up vs AX top-left origin; note the repo already hit a y-flip bug), AXFullScreen detection.
- Drawn-outline ghost of the target frame inside overlay (no capture).
- File flick to configured folder via FileManager; AirDrop/share via NSSharingService (needs UI/pickers).
Hard / risky:
- Moving windows between Spaces (no public API; private CGS calls or SIP-disabled injection like yabai; fragile across macOS updates).
- Live window thumbnails in the blob (ScreenCaptureKit: Screen Recording permission, monthly re-prompt on macOS 15, perf concerns, plus the blob renderer's CPU readback path).
- Per-app scripting (AppleScript/ScriptingBridge) for app-specific parameters: needs Automation permission prompts per target app.
- Synthesizing drag-to-edge or Mission Control gestures: violates listen-only rule.

Recommended ranking (value x feasibility, my judgment):
1. Two-zone stretch preview/commit with risk-scaled thresholds (cheap, high trust).
2. Window throw-snap to halves/quarters/maximize/next display with outline ghost (medium effort, clear value; direct competition with Rectangle/Magnet).
3. Detented stretch for stepped values: undo depth, paste-history depth (cheap).
4. Rate-control scrub for volume/zoom with spring-return neutral (cheap-medium, needs precision/fine mode).
5. File flick to configured destinations with undo (medium).
6. Throw to other Space / live thumbnails (defer).

### Gaps
- I did not read ActionRunner/ContextResolver/Haptics source line by line, so claims on existing capabilities (e.g., whether the window under pointer is already resolved with an AXUIElement reference, which haptic pattern is used) come from HANDOFF.md and file names and should be verified.
