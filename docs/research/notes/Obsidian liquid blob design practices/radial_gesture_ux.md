# Radial / gesture direction-selection UX for a 4-direction press-drag-release selector (Pluck)

Method note: ~12 searches; most paper PDFs (billbuxton.com, dgp.toronto.edu) were unreachable via fetch, so findings rest on search-result abstracts/summaries. Items marked [RULE OF THUMB] are my own judgement, not sourced. Numbers not in a source are not presented as research-backed.

## 1. What HCI research says about 4 vs 8 items, slice width, delay, novice-to-expert

### Takeaway
Breadth 4 is the safest case in the literature: it tolerates far more depth than breadth 8 at the same error ceiling, and ~8 is the accepted breadth limit. Pie/marking menus are faster than linear menus mainly because direction is a large-target, fixed-distance task; the classic design delays the visual menu (~1/3 s) so experts "mark ahead", though later work questions whether the delay is necessary.

### Cited Findings
- Callahan et al. (CHI '88) found pie menus faster (about 15%) and with fewer errors than linear menus, attributing it to fixed distance and enlarged targets (Fitts' law) and reduced drift; subjects were novices. The 15% figure is reported secondhand and I could not verify it against the paper's tables. — [UMD abstract](https://sites.umiacs.umd.edu/node/16962); [Hopkins retrospective](https://www.osnews.com/story/30371/pie-menus-a-30-year-retrospective/); [NN/g CHI88 trip report](https://www.nngroup.com/articles/trip-report-chi-88/)
- Kurtenbach & Buxton (CHI '93): keeping errors under 10%, breadth 4 allows up to 4 levels deep; breadth 8 allows only 2 levels. — [search summary of Kurtenbach & Buxton 1993 (Autodesk research page)](https://www-pt.autodesk.com/research/publications/the-limits-of-expert)
- Zhao, Agrawala & Hinckley (CHI '06): accuracy drops substantially beyond breadth 8; angular accuracy determines feasible breadth (more items = smaller angle between items). A patent summary cites breadth-4 holding accuracy to depth 4 and breadth-8 about 93% at depth 3. — [Zone & Polygon Menus](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/Zone-Polygon-Menus-CHI-2006.pdf); [patent summary](https://patents.google.com/patent/US7603633)
- Kurtenbach & Buxton (CHI '94 field study): marks were on average 3.5x faster than menu selection; experts still fall back to the menu to refresh memory. — [User learning and performance with marking menus](https://www-pt.autodesk.com/research/publications/user-learning-and-performance)
- Classic marking-menu novice mode: user presses and waits about 1/3 s (~330 ms) for the radial menu to appear; experts just make the mark without waiting. Delay is argued to encourage memory retrieval. — [Kurtenbach et al. 1993 / Autodesk](https://www-int.autodesk.com/research/publications/an-empirical-evaluation-of); [Henderson & Lank, necessity of delay](https://hal.archives-ouvertes.fr/hal-02463247)
- Henderson & Lank (three experiments) found no obvious systematic performance or usability advantage to delay-and-mark mode; only ~260 ms benefit, after significant training and with two items. — [HAL](https://hal.archives-ouvertes.fr/hal-02463247)
- Wave menus (Bailly, Lecolinet, Nigay, INTERACT '07): novice-mode feedback that previsualizes submenu items and path was faster and more accurate than multi-stroke menus. Flower menus (AVI '08) add curved strokes to reach many items and were better for expert memorization than linear/polygon menus. Relevant mainly as evidence that richer novice feedback (path + preview) helps. — [Wave menus](https://gillesbailly.fr/wavelet.html); [Flower menus](https://gillesbailly.fr/flowermenu.html)
- Blender: drag-style pie (press key, nudge toward item, release) is the fast path; releasing without moving leaves menu open for click-style. The center disc must be touched/exited for a direction to be valid. — [Blender pie manual wiki](https://wiki.blender.org/index.php/User:Psy-Fi/Pie_Menus_Manual); [Blender manual](https://docs.blender.org/manual/en/3.5/interface/controls/buttons/menus.html)

### Inferences
- With 4 items each slice nominally spans 90 deg, comfortably above the angular-accuracy limits implied by 8-item breadth (45 deg); 4-way is in the low-error regime, so errors will come from dead-zone/hysteresis/overshoot handling, not angular precision.
- Pluck's 80 ms label bloom is much shorter than the classic ~330 ms. Short delay favors novices but means labels flash on every flick; for experts, consider hiding labels while the pointer is moving fast (see recommendations). Henderson & Lank weaken the case for a long mandatory delay, so a modest delay (see section 6) is defensible.
- Pluck's labels change by context (text/link/file/window), which undermines expert memorization of direction; fixed role positions (Keep=N etc.) are what preserve muscle memory (Blender notes fixed positions for the same reason). Labels varying while roles stay fixed is the right design; keep the role-to-direction mapping invariant.

### Gaps
- Could not retrieve per-direction error rates, angular-width data, or the exact delay parameter from the original papers (Kurtenbach thesis, Zhao & Balakrishnan 2004, Lepinski 2010); fetch of billbuxton.com and dgp.toronto.edu failed.
- No source found for "Gesture Select" or Hotstrings specifics; not covered.
- No empirical data found for minimum activation distance in px for mouse-driven marks.

## 2. Dead zone, activation distance, hysteresis, overshoot, cancel

### Takeaway
Research I could access does not give numeric dead-zone values; the best evidence is design precedent (Blender requires leaving a center disc before a direction is valid) and the Fitts/steering logic that radial targets are effectively unbounded in depth. Specific numbers below are rules of thumb.

### Cited Findings
- Blender: a direction is valid only when the pointer touches or extends beyond the center disc; release inside selects nothing. — [Blender wiki](https://wiki.blender.org/index.php/User:Psy-Fi/Pie_Menus_Manual)
- Callahan: pie menus fix the distance factor and enlarge targets, i.e. slices extend outward indefinitely so overshoot is harmless. — [UMD abstract](https://sites.umiacs.umd.edu/node/16962)
- Blender bug: a pie menu clamped to a window edge auto-validated the item in that direction, causing accidental selection. Lesson: never let edge clamping place the pointer inside an active slice at open. — [Blender T49029](https://developer.blender.org/T49029)
- Nielsen/Norman on gestural UIs: accidental activation and unrecoverable actions are core risks. — [Norman & Nielsen column reprint](https://jnd.org/gestural-interfaces-a-step-backwards-in-usability/)

### Inferences
- [RULE OF THUMB] Current 24 pt arm / 16 pt stay-armed (hysteresis ratio 1.5) is in a sensible range; it is larger than typical click-vs-drag slop (~3-5 pt on macOS) and so avoids accidental commits. Consider velocity-adaptive arming: arm earlier (e.g. 12-16 pt) if the pointer speed is high and direction is stable (flick), later if slow/jittery.
- [RULE OF THUMB] 8 deg angular hysteresis on a 90 deg slice is fine; between adjacent slices it effectively widens the held slice to ~106 deg, which is good because overshoot/drift from a diagonal is the main 4-way error.
- Cancel-by-return-to-center has precedent (Blender center disc); pair it with an explicit Escape (already present) and make the cancel zone visually distinct (blob retracts/greys), since it is otherwise invisible.
- Because slices are unbounded radially, overshoot never needs handling beyond keeping the armed target latched (do not drop target at large radius).

### Gaps
- No sourced numeric dead-zone values for mouse marking menus; no direct source for steering-law application. Fitts/steering analysis is my inference only.

## 3. Feedback: armed-target confirmation, progressive disclosure, haptics, audio, cursor, accessibility

### Takeaway
Visual confirmation must carry the load with a mouse, because trackpad haptics only fire when a finger is on the trackpad. Apple says to pair haptics with visual feedback and give a non-gesture alternative for gesture-only actions.

### Cited Findings
- NSHapticFeedbackManager targets Force Touch trackpads; the system may suppress feedback if the user is not touching the trackpad; call only in response to user actions; pair with visual feedback; alignment pattern fits dragging into line. — [Apple NSHapticFeedbackManager](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager.md); [ForceTouchCatalog sample](https://developer.apple.com/library/archive/samplecode/ForceTouchCatalog/Listings/ForceTouchCatalog_MasterViewController_swift.html)
- Forum anecdote: performer calls only produced feedback while a finger was on the pad (unofficial, possibly outdated). — [Apple forums](https://developer.apple.com/forums/thread/70605)
- Apple accessibility guidance (via search summary): offer alternatives to gestures, avoid hard gestures (multi-finger, long-press), do not break system gestures. I could not confirm the exact HIG text. — [Apple HIG accessibility](https://developer-rno.apple.com/design/human-interface-guidelines/foundations/accessibility)
- Wave menus: showing path and preview of next items in novice mode improves speed/accuracy. — [Wave menus](https://gillesbailly.fr/wavelet.html)

### Inferences
- With a two-button mouse chord, no haptic path exists; use haptic only as an optional bonus when a trackpad is detected as the pointing device (alignment pattern on arm and on role change), always paired with visual change.
- [RULE OF THUMB] Armed-state feedback should change at least two channels at once (blob head snaps/magnetizes toward the label, label scales ~1.1-1.2x and takes accent color). The 1.75x stretch gain is plausibly good for making direction legible; ensure the head clamps to a max length so it does not cover the label.
- [RULE OF THUMB] Honor Reduce Motion (NSWorkspace.accessibilityDisplayShouldReduceMotion): replace blob stretch/bloom with instant crossfade/opacity states; keep selection logic identical.
- Provide a keyboard alternative (e.g. arrow keys or N/E/S/W letters while chord is held, or a hotkey that opens the same four-role panel) and VoiceOver announcements of armed role; follows the Apple "non-gesture alternative" guidance.
- Left-handed button swapping: define the chord in terms of the system's logical primary/secondary buttons (or detect both-down regardless of which) to avoid breaking users who swap buttons. Not sourced; implementation detail to verify.

### Gaps
- No primary source on cursor hiding vs ghosting, audio cues, or Reduce Motion specifics in this pass.

## 4. Anti-patterns: discoverability, occlusion, edges, multi-monitor, destructive release

### Takeaway
Hidden gestures fail on discoverability, memorability and accidental activation; the fixes are an onboarding/novice mode, edge-aware placement that never auto-selects, and making release non-destructive or undoable.

### Cited Findings
- Hidden gestures: low discoverability, low memorability, accidental activation; gestures are best as expert accelerators or with strong physical metaphor. — [Nielsen iPad study quoted](https://lists.gnome.org/archives/usability/2011-May/msg00011.html); [ignorethecode summary](https://ignorethecode.net/blog/2010/05/30/nielsen_and_norman_on_gestures/); [Norman & Nielsen](https://jnd.org/gestural-interfaces-a-step-backwards-in-usability/)
- Hopkins: ideally center the pie at the press point; if shifted to fit the screen, warp the cursor by the same offset (complex, violates least astonishment); alternative is half pies at edges and quarter pies in corners; slices can run to the screen edge so the window only needs room for labels. — [Sugar-devel Hopkins post](https://lists.sugarlabs.org/archive/sugar-devel/2007-February/001614.html); [pie menu text compilation](https://nic.funet.fi/pub/graphics/misc/news+mails/Comp.graphics/piemenues.txt)
- Blender: edge clamping caused auto-selection of the edge item. — [Blender T49029](https://developer.blender.org/T49029)

### Inferences
- Pluck anchors at the pin, so there is no cursor warp problem: keep the pin where the user pressed and shift only the labels (flip a label to the inner side of its arrow, e.g. W label to the right of pin near left edge is wrong direction; instead keep direction but place label inside the screen, or shorten/stack). [RULE OF THUMB] Keep the slice geometry identical regardless of label placement so direction logic is edge-independent.
- Occlusion: labels should sit beyond the blob head along its axis, offset away from the cursor/hand; for S, the label below can collide with the Dock; for N near the menu bar, flip text to a pill inset. [RULE OF THUMB]
- Destructive release: roles Keep/Go/Give/Ask are not destructive per se, but Give may send data; keep an undo/confirm or toast with Undo for outward-effect roles. Escape and return-to-pin cancel remain the main safeguards.
- Multi-monitor/Retina: use a single global coordinate space (points, not pixels), compute edge distances per NSScreen frame (visibleFrame for menu bar/Dock), and handle pin on a screen seam by testing against the union of screens. [RULE OF THUMB, not sourced]

### Gaps
- No sourced guidance on macOS-specific coordinate pitfalls, menu bar/Dock avoidance, or multi-monitor behavior.

## 5. Precedents

### Takeaway
Blender's drag-vs-click duality, marking menus' mark-ahead, and Hopkins' pie-menu edge handling are the best-documented precedents; I found no usable sources for Opera, Windows Ink, Logitech, or macOS Quick Actions in this pass.

### Cited Findings
- Blender: dual modes (drag-release quick select vs release-without-move click select), fixed item positions, center disc as dead zone/cancel, key accelerators. — [Blender wiki](https://wiki.blender.org/index.php/User:Psy-Fi/Pie_Menus_Manual); [Blender manual](https://docs.blender.org/manual/en/3.5/interface/controls/buttons/menus.html)
- Blender flaw: edge-clamped menu auto-validates an item. — [Blender T49029](https://developer.blender.org/T49029)
- Marking menus: popup delay ~1/3 s with mark-ahead for experts. — [Autodesk](https://www-int.autodesk.com/research/publications/an-empirical-evaluation-of)
- iPad/gesture-heavy UIs criticized for hidden operations. — [Norman & Nielsen](https://jnd.org/gestural-interfaces-a-step-backwards-in-usability/)

### Inferences
- Pluck's chord-hold-drag-release is the same shape as Blender's drag-style; borrowing the click-style fallback (release without moving keeps the picker open) would aid novices but conflicts with "release near pin cancels"; consider a short grace window (e.g. brief hold) or keep cancel as is for simplicity. [RULE OF THUMB]

### Gaps
- Opera mouse gestures, Windows Ink flicks, game radial wheels, Logitech gesture button, macOS Quick Actions, iOS peek/pop: no sources gathered; not evaluated.

## 6. Tuning recommendations (summary, with evidence level)

| Parameter | Current | Recommendation | Evidence |
|---|---|---|---|
| Items | 4 | Keep 4 (well below 8-item limit; errors <10% even at deeper levels) | Research-backed (Kurtenbach & Buxton 1993; Zhao 2006) |
| Slice width | 90 deg | Keep; hysteresis 8 deg ok; optionally widen the armed slice by 10-15 deg | Rule of thumb |
| Arm distance | 24 pt | Keep for slow drags; allow ~14-16 pt when peak speed is high and direction stable (flick) | Rule of thumb |
| Stay-armed | 16 pt | Keep; ensure target stays latched at any larger radius | Rule of thumb; unbounded slice per Callahan |
| Label delay | ~80 ms bloom | Treat 80 ms as bloom animation; add a short gate (~150-300 ms or until speed drops) before full labels so fast flickers never see them; classic reference is ~330 ms | 330 ms research-backed; shorter gate rule of thumb; Henderson & Lank say long delay not clearly needed |
| Flick commit | none | On release with high velocity and stable direction, commit even if under 24 pt | Rule of thumb |
| W/E vs N/S | equal | Optionally widen E/W slices slightly (text labels are wide) | Rule of thumb, unverified |
| Haptics | none | Optional trackpad-only alignment haptic with visual cue | Apple docs |
| Reduce Motion | ? | Respect; swap blob animation for fades | Rule of thumb |
| Keyboard/VoiceOver | ? | Provide non-gesture path | Apple HIG guidance (secondary summary) |
| Edge handling | ? | Keep pin fixed; shift/flip labels only; never auto-select at open | Blender bug lesson; Hopkins |
| Auto-cancel | 20 s | Fine; no source |  Rule of thumb |
