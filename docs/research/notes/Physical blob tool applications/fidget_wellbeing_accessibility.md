# Fidget, wellbeing, creative and accessibility applications for a tactile liquid-blob tool (Pluck)

Method note: ~8 searches, mostly search-result summaries; I did not fetch primary papers or Apple HIG pages. Items marked "unverified" come from my background knowledge and have no citation. Design opinion is kept in Inferences, never in Cited Findings. Nothing here is medical advice.

## 1. What does research say about fidgeting, attention, ADHD and anxiety, and what makes fidget objects satisfying?

### Takeaway
Evidence that fidget toys (especially spinners) improve attention is weak and leans negative in classroom and memory studies. Small, unobtrusive movement may help some people with ADHD, but studies are small and inconsistent. Fidget tools should be positioned as "pleasant, optional, low-demand," not as an attention or ADHD aid.

### Cited Findings
- No dedicated meta-analysis of fidget spinners and ADHD attention was found in search; evidence is small studies plus narrative reviews, leaning negative for spinners — [PopSci](https://www.popsci.com/science/does-fidgeting-help-focus/) and the search summary of reviews below.
- A 2020 classroom A-B-A-B study of 60 young children with ADHD associated spinner use with poorer attention (small, single-setting) — summarized via [Learning & the Brain](https://www.learningandthebrain.com/blog/do-fidget-spinners-help-children-with-adhd/) and [LiveScience](https://www.livescience.com/59894-fidget-spinners-not-supported-by-science.html) (I did not verify the exact study from these pages).
- A 2019 study (Soares, quoted in PopSci) found about an 11% impairment in remembering video details in college students using a spinner; Soares cautions it does not apply to every individual — [PopSci](https://www.popsci.com/science/does-fidgeting-help-focus/)
- A 2023 narrative review (Kriescher et al.) found no evidence that fidget toys improve attention or behaviour, with possible negative effects; it did not appraise study quality. A 2022 review found some evidence for emotional regulation or stress benefit but concluded classroom downsides outweigh them. An Australian evidence summary could not recommend fidget toys as a sensory intervention but noted they may reduce disruptive behaviour in students with ADHD — [INSPED PDF](https://www.insped.org.au/wp-content/uploads/2024/11/fidget-toys.pdf) and [PopSci](https://www.popsci.com/science/does-fidgeting-help-focus/) (attribution of each review to its source page is imprecise; verify before quoting).
- Amico & Schaefer (2019): none of the fidget products improved memory versus baseline; spinner and doodling reduced performance. Spencer-Mueller & Fenske (2024): doodling did not reduce boredom/mind-wandering or increase retention. A thesis reviewing 15 studies on fidgeting/doodling found inconsistent evidence, weighted toward positive, with quantity/quality too low for firm conclusions — [BPS summary](https://bps.org.uk/impact-small-motor-activity-attention-and-learning-children), [Southampton blog](https://blog.soton.ac.uk/edpsych/2020/07/30/the-impact-of-small-motor-activity-on-attention-and-learning-in-children/), [Guelph](https://www.uoguelph.ca/research/article/u-g-study-challenges-learning-benefits-doodling-and-fidgeting)
- Sarver/Rapport (2015, J Abnormal Child Psychology; 29 boys with ADHD vs 23 typical): more movement accompanied better working-memory performance, consistent with a "compensatory" view of hyperactivity; Sarver cautions only minor, at-desk movement and not disruptive activity — [FSU PDF](https://www.psy.fsu.edu/clc/Publications/CLC_Sarver2015.pdf), [UCF](https://www.ucf.edu/news/kids-with-adhd-must-squirm-to-learn/)
- Andrade (2010): doodlers recalled 29% more (7.5 vs 5.8 of 16 items) — [Time](https://content.time.com/time/health/article/0,8599,1882127,00.html); contradicted by later null/negative results above.
- Proposed neurochemical mechanisms for fidgeting benefits are hypothesis, not established (search summary of [PopSci](https://www.popsci.com/science/does-fidgeting-help-focus/)).

### Inferences
- A tool that is visually captivating may compete for attention (the plausible reason spinners did poorly); a quiet, peripheral, low-demand fidget is likelier to be neutral. This is inference, not tested for on-screen blobs.
- Safe marketing language: "a calm thing to do with your hands/cursor," not "improves focus" or "ADHD tool."
- Design opinion (uncited, from product analysis): satisfying physical fidgets share graded resistance, clean rebound, a predictable rhythm with slight variability, tactile detents (pop-it, clicky switches), and no required goal. Pluck's spring/slosh and haptic ticks map to these; I found no sourced study quantifying these properties.
- Not researched in depth: Pocket Fidget, Neko/desktop pets, Playdate crank, Teenage Engineering, ASMR literature.

### Gaps
- No peer-reviewed study of digital/on-screen fidget interfaces or cursor-based fidgeting found.
- No evidence found on ASMR-like or "satisfying micro-interaction" effects on stress; no sourced UX writing (Kowalski, Freiberg, Comeau, NN/g) was retrieved.
- Anxiety-specific fidget evidence not found beyond the review statements above. App Store/Product Hunt reviews of fidget apps not reviewed.

## 2. Meeting-friendly design: silence, discretion, screen-share leakage, resource use

### Takeaway
`NSWindow.sharingType = .none` is a useful but unreliable hint; ScreenCaptureKit and fullscreen can bypass it, so explicit exclusion and a "pause when sharing" behavior are needed. Silent, low-opacity, auto-idle defaults are design choices rather than researched findings.

### Cited Findings
- Setting `sharingType` to `NSWindowSharingNone` asks the window server to exclude the window from capture, but some apps use capture methods that bypass it — [Level Up Coding](https://levelup.gitconnected.com/how-i-made-a-desktop-app-invisible-to-screen-sharing-electron-os-level-tricks-5734513c1e67)
- Electron's fix for ScreenCaptureKit: find NSWindows with `sharingType == none`, match `windowNumber` to `SCWindow`, and pass them as excluded windows in `SCContentFilter` — [Electron commit mirror](https://ayakael.net/mirrors/electron/commit/fd88908457a986f06e310e80499e4b2775d8ba70)
- Reported pitfalls: a ScreenCaptureKit sample initially captured a `NSWindowSharingNone` app until filters were toggled — [Apple forums](https://developer.apple.com/forums/thread/808016); sharingType reportedly not honored in fullscreen — [Apple forums](https://developer.apple.com/forums/thread/69290); Zoom showed flicker with the flag set, while Teams hid it reliably — [Zoom community](https://community.zoom.com/meetings-2/flickering-window-in-the-screen-capture-of-zoom-mac-desktop-client-when-nswindowsharingnone-is-set-35876)
- Apple documents `requestSharing(ofWindow:)` as a newer sharing API (not read in detail) — [Apple docs](https://developer.apple.com/documentation/appkit/nswindow/requestsharingofwindow(_:completionhandler:).md)

### Inferences
- Treat leakage as a privacy risk: the blob overlay itself is not sensitive but shows that the user is fidgeting; the launcher's labels may reveal actions. Hide labels or the whole overlay when screen sharing is detected (detection method not researched), and test across Zoom, Teams, Meet, QuickTime and screenshots.
- Defaults (design opinion): no sound, no haptics beyond light ticks, reduced size/opacity option, no flashes, render loop stops entirely at rest (zero CPU while idle), cap to display refresh and pause on battery saver/Low Power Mode.

### Gaps
- No data on CPU/battery cost of comparable overlay apps; no tested method to detect that the screen is being shared.

## 3. Wellbeing features: paced breathing, breaks, streaks

### Takeaway
Slow-paced breathing (about 6 breaths/min) has modest, short-term evidence for reducing stress/negative emotion; micro-breaks give small boosts in vigor and reduced fatigue with no significant performance gain overall. Frame any such mode as relaxation, never as treatment.

### Cited Findings
- Slow-paced breathing meta-review: reliable short-term cardiovascular improvement and modest reduction in negative emotions; long-term effects not established; "slow-paced" defined as near 6 cycles/min, near resonance frequency — [Springer (Mindfulness 2023)](https://link.springer.com/article/10.1007/s12671-023-02294-2)
- Breathwork meta-analysis of 12 RCTs (785 adults) linked to lower stress, with inconsistent study quality; individually taught instruction appeared better than group — [News-Medical](https://www.news-medical.net/news/20230113/Review-and-meta-analysis-suggests-breathwork-may-be-effective-for-improving-stress-and-mental-health.aspx)
- Another summary reports anxiety g = -0.32 (20 RCTs) and stress g = -0.35 — [Simply Psychology](https://www.simplypsychology.org/?p=72165) (secondary source; verify against the paper).
- Devillers et al. Bayesian study: moderate evidence slow breathing reduces state anxiety, no HRV improvement in a small sample; many breathing studies lack proper sham controls — [CBS MPG PDF](https://www.cbs.mpg.de/2436414/c20_devillers.pdf)
- Micro-breaks meta-analysis (Albulescu et al. 2022, PLOS ONE; 22 samples, N=2335): vigor d=.36, fatigue reduction d=.35 (both small); overall performance d=.16, not significant; effects on performance only for less demanding tasks; longer breaks helped more — [DOAJ record](https://doaj.org/article/c6f37b6ba159469296b2cb968b65505f), [EurekAlert](https://www.eurekalert.org/news-releases/962663)

### Inferences
- A 4-6 bpm breathing blob (inflate/deflate guided by a held press) is consistent with the literature on pacing, but no study tests this interface; keep claims to "paced breathing guide."
- Design opinion on streaks: avoid loss-framed streaks, guilt notifications and leaderboards; offer private, optional, quiet tallies (no research retrieved on dark patterns).
- A micro-break prompt should be opt-in, infrequent and dismissible with one gesture.

### Gaps
- Not retrieved: primary studies, safety notes for breathing practice (e.g., dizziness, people with respiratory/anxiety conditions), evidence on Do Not Disturb/focus-mode integration, and gamification literature.

## 4. Creative and expressive uses

### Takeaway
No sources were found; the ideas below are speculative product ideas, not findings.

### Cited Findings
- None retrieved.

### Inferences
- Candidate uses (uncited design opinion): liquid cursor-finder/highlighter for presenters and teachers; ink-drip brush or color picker via stretch distance and direction; optional quiet music toy with pitch mapped to stretch (off by default); physics demo for spring/damping teaching; screen annotation. For screen-recording uses, the sharingType exclusion must be user-toggleable the other way (include in capture).

### Gaps
- Competitor/precedent research (Neko, desktop pets, cursor highlighters, slime apps, App Store reviews) was not done.

## 5. Accessibility: motor, low vision, vestibular, cognitive; WCAG and Apple

### Takeaway
WCAG 2.2 requires single-pointer alternatives to dragging (2.5.7, AA) and 24x24 CSS px minimum targets (2.5.8, AA); flashing must stay under three per second (2.3.1). WCAG formally targets web content, so for a native macOS app these are best-practice benchmarks; Apple's own APIs expose the user's Reduce Motion/Transparency/Contrast settings.

### Cited Findings
- 2.5.7 Dragging Movements (AA): functionality using dragging must be achievable by a single pointer without dragging unless dragging is essential — [W3C What's New in WCAG 2.2](https://w3.org/WAI/standards-guidelines/wcag/new-in-22/), [Tabnav](https://tabnav.com/academy/wcag/success-criterion-2.5.7)
- 2.5.8 Target Size (Minimum) (AA): at least 24x24 CSS px, with exceptions for spacing, an equivalent control, etc.; 44x44 is the AAA guidance — [W3C What's New](https://w3.org/WAI/standards-guidelines/wcag/new-in-22/), [Dequeue University](https://dequeuniversity.com/resources/wcag-2.2)
- 2.3.1 Three Flashes or Below Threshold: more than three flashes per second is a Level A failure unless below flash thresholds; 2.2.2 requires pause/stop for moving content over 5 seconds — [Webflow checklist](https://webflow.com/accessibility/checklist/task/use-subtle-animations-that-dont-flash-more-than-recommended), [Primer](https://primer.style/accessibility/design-guidance/motion-and-animation) (secondary sources)
- macOS exposes `NSWorkspace.accessibilityDisplayShouldReduceTransparency`, observed via `accessibilityDisplayOptionsDidChangeNotification` — [Apple docs](https://developer.apple.com/tutorials/data/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducetransparency.md); Reduce Motion, Increase Contrast and Reduce Transparency are user settings in Accessibility > Display — [Apple Support](https://support.apple.com/guide/mac-help/change-display-preferences-for-accessibility-unac089/12.0/mac/12.0)
- On Apple platforms, dwell-style activation exists in AssistiveTouch (visionOS settings: movement tolerance, dwell time); I could not confirm the macOS equivalent in these results — [Apple Vision Pro guide](https://support.apple.com/guide/apple-vision-pro/tan0ba69a1f1/visionos)

### Inferences
- Pluck's two-button chord and drag-to-direction gesture are exactly what 2.5.1/2.5.7 spirit targets; provide alternatives: a keyboard-hold trigger, a click-to-toggle (sticky) mode, a dwell-to-summon option, and a way to pick an action by keyboard/menu without any pointer path (design opinion).
- Motor: large dead zone, direction snapping with hysteresis (sticky selection), tremor smoothing, adjustable hold time/threshold, one-handed operation, cancel by returning to origin or Esc (design opinion).
- Low vision/VoiceOver: announce the highlighted action; large high-contrast labels; Increase Contrast switches from faceted glints to solid edges. Vestibular: under Reduce Motion, replace slosh/overshoot with a direct linear follow and no screen-wide movement; under Reduce Transparency, no blur. Cognitive: keep the direction-to-action mapping stable and visible (design opinion).
- Specular glints should never strobe: limit changes to well under 3 Hz and avoid large saturated flashes.

### Gaps
- Unverified (from background knowledge, no fetch): WCAG 2.5.1 Pointer Gestures (path-based gestures need single-pointer alternatives), exact Apple HIG text on Accessibility/Motion/Pointing devices, `accessibilityDisplayShouldReduceMotion` details, and macOS Switch Control/Dwell Control behaviour. Fetch W3C Understanding docs and developer.apple.com/design/human-interface-guidelines/accessibility and /motion before quoting.

## 6. Risks and anti-patterns

### Takeaway
Main documented risks are weak benefit/overclaiming, capture leakage, and attention cost; the others below are design reasoning without sources.

### Cited Findings
- Fidget objects may impair memory/attention in some studies (see Section 1: [PopSci](https://www.popsci.com/science/does-fidgeting-help-focus/), [Guelph](https://www.uoguelph.ca/research/article/u-g-study-challenges-learning-benefits-doodling-and-fidgeting))
- sharingType is not reliable in all capture/fullscreen situations (Section 2).
- Breathing evidence is short-term and quality-limited (Section 3).

### Inferences
- Gimmick fatigue: novelty fades; keep it a utility with a quick path to the launcher action, and provide an easy off switch (opinion).
- Accidental triggers: chord/hold gestures could fire during games, drawing apps or remote desktop; offer per-app exclusion and require deliberate hold (opinion).
- Battery: idle loop must be fully stopped; use display-synced rendering only while visible (opinion).
- Overclaiming: avoid "reduces anxiety/ADHD" language; add a note that it is not a medical device or treatment (opinion).

### Gaps
- No data on accidental-trigger rates, motion-sickness incidence for small on-screen motion, or user reviews of comparable apps.
