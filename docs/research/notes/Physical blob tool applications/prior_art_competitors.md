# Prior art and competitors for a context-aware radial/gesture launcher on macOS

Research limits: web search worked, but direct page fetches (raycast.com, popclip.app, logi.com, pie-menu.com) failed with DNS errors, so most facts come from search snippets, aggregators and GitHub. No Reddit, Hacker News, MacStories or Product Hunt comment text was retrievable, so no verbatim user quotes were obtained. Most of the requested products (Hammerspoon, Contexts, Dropzone, Maccy, Jitouch, MultiClutch, StrokesPlus, Blender, game wheels, Dynamic Island, Teleport, Flick, Nova/Fluid) were not researched; they appear under Gaps.

## 1. Survey of alternatives: what they do, pricing, distribution

### Takeaway
Radial menus on Mac exist as small indie one-time-purchase apps (Radial, Pie Menu, Launchy) plus a free open-source cross-platform one (Kando). Hardware vendors (Logitech) ship a radial ring bundled with mice. Mainstream launchers (Raycast, Alfred, Keyboard Maestro, LaunchBar) are keyboard-first and monetise via subscription (Raycast) or one-time licences (the rest). None found combine radial UI, content-under-pointer context and physical/tactile animation.

### Cited Findings
- Raycast: free plan includes Clipboard History, Quicklinks, Calculator, Snippets, Emoji Picker, Window Management. Pro is listed at $10/month monthly or $8/month annual; Pro adds unlimited clipboard history, notes, cloud sync, custom themes, translator; advanced AI is an add-on. Third-party listings disagree on team pricing. — [Raycast pricing (as surfaced in search)](https://www.raycast.com/pricing); [costbench](https://costbench.com/software/ai-productivity/raycast/)
- Raycast Pro described as $96/year or $10/month; Pro + Advanced AI $192/year. — [The Sweet Setup / pricing aggregators](https://thesweetsetup.com/heres-what-you-need-to-know-about-raycast-pro/) (search listing only; figures come from the search summary, not a fetched page)
- Alfred: Powerpack licences are one-time. Single User licence covers one user on two Macs for the current version; Mega Supporter gives lifetime updates. An aggregator lists £34 and £59; official USD price not confirmed. — [Alfred license types](https://alfredapp.com/help/powerpack/license-types); [toolradar](https://toolradar.com/tools/alfred/pricing)
- Keyboard Maestro: one-time, US$36, up to five Macs per user. — [Keyboard Maestro wiki](https://wiki.keyboardmaestro.com/manual/Purchase)
- LaunchBar: only an undated Macworld price ($29 single, $49 family) found; treat as possibly outdated. — [Macworld](https://www.macworld.com/article/562356/launchbar-review-mac-gems.html)
- BetterTouchTool: Standard licence (2 years of updates) and Lifetime licence; one source says $12 and $24, others disagree; also on Setapp. Supports Magic Mouse, Magic Trackpad, built-in trackpads, plus normal-mouse gestures. — [BTT docs](https://docs.folivora.ai/docs/601_magic_mouse_trackpad.html); [dev.classmethod](https://dev.classmethod.jp/articles/renewing-bettertouchtool-license-after-expiration-notice-for-two-years/); [atsoho](https://atsoho.com/apps/p/bettertouchtool)
- PopClip: selection popup; one-time, about $14.99 on Mac App Store (Macworld) with a demo limited to 150 uses; other sources say $17 or EUR 20 and 100 to 250 uses (conflicting). Extensions are installed by double-clicking a downloaded file; some extensions request extra permissions. Extension count cited as 209 in one review (older sources 144). — [Macworld](https://www.macworld.com/article/706796/popclip-review.html); [AlternativeTo](https://alternativeto.net/software/popclip/about); [PCWeenies](https://pcweenies.com/?p=9212); [ifun.de](https://www.ifun.de/popclip-fuer-mac-kontextmenue-fuer-textauswahl-bringt-mehr-produktivitaet-86545/)
- Yoink: $8.99 one-time (Mac App Store or direct), also on Setapp; Nov 2025 post says direct purchase now available. — [Eternal Storms blog](https://blog.eternalstorms.at/2025/11/03/yoink-for-mac-v3-6-104-now-available-also-as-direct-purchase/); [Macworld](https://www.macworld.com/article/620102/yoink-review-mac-gems.html)
- Paste: about $30/year per a 2024 Setapp review; unclear whether bundled or separate. — [daveswift Setapp review](https://daveswift.com/setapp/)
- Radial (Gustav Lübker): macOS pie-menu launcher at the cursor; opens apps, inserts snippets, runs workflows/scripts/AppleScript; macros change with the foreground app; extra menus (launcher, emoji, file picker, app switcher) reached with keys 1-5; v4.0 added sub-menus and a menu switcher (the two most requested features). AlternativeTo lists $15 one-time (unverified). Product Hunt launch: 94 upvotes, 8 comments. — [feedbagel](https://feedbagel.com/post/radial-a-modern-pie-menu-for-macos-with-context-aware-macros-and-quick-access-fe); [Product Hunt](https://www.producthunt.com/p/radial); [AlternativeTo](https://alternativeto.net/software/radial/about); [HN profile](https://news.ycombinator.com/threads?id=Glubker)
- Pie Menu (Marius Hauken): one shortcut shows a circular menu of the active app's shortcuts; Mac App Store plus Setapp; free tier limited to 10 uses per day; Product Hunt offered discounted lifetime access. — [hunted.space](https://hunted.space/product/pie-menu)
- Launchy: radial app launcher/switcher, Dock and Cmd+Tab alternative, iCloud sync of preferences. — [Product Hunt](https://www.producthunt.com/p/launchy-app-launcher-switcher/launchy-for-macos)

### Inferences
- The one-time $9 to $36 band (Yoink, PopClip, Radial, Keyboard Maestro) is the norm for single-purpose Mac utilities; subscription is mostly Raycast (platform with AI/cloud) and Paste. A gesture utility priced like Raycast Pro would be out of pattern.
- Product Hunt engagement for Radial (94 upvotes) suggests a niche, not a mass market for pie menus.

### Gaps
- No adoption numbers (users, revenue) found for any of these.
- Not researched: Hammerspoon, Contexts, Dropzone, Maccy, Shortcuts/Quick Actions, Services menu, Look Up/Live Text, Jitouch, MultiClutch, StrokesPlus, browser gestures, Flick, Nova/Fluid, Dynamic Island, Universal Control.

## 2. Detailed comparables: Kando, Logitech Actions Ring, PopClip, Raycast Quick Links/Snippets

### Takeaway
Kando proves open-source demand for pie menus (6.4k GitHub stars) with app-bound menus; Logitech's ring proves a hardware-vendor path but is gated to Logitech devices; PopClip proves context-of-selection actions and a distributable extension format; Raycast shows free core features plus store/extension ecosystem.

### Cited Findings
- Kando: free, open source, cross-platform (Windows, macOS, Linux), mostly TypeScript; GitHub shows 6.4k stars and 220 forks; funded by donations (Ko-fi, GitHub Sponsors); author says he does not plan to monetise it. Supports nested menus, per-app menus (appear only when a given app is focused), graphical editor, default trigger Ctrl+Space, actions: launch apps, simulate shortcuts, open files/URLs; works with mouse, stylus, touch, controller. Author previously built Fly-Pie (GNOME). — [GitHub](https://github.com/kando-menu/kando); [UbuntuHandbook](https://ubuntuhandbook.org/index.php/2024/12/kando-pie-menu-launcher/); [LinuxLinks](https://www.linuxlinks.com/kando-pie-menu)
- Logitech Actions Ring: on-screen overlay with 8 main bubbles plus 9 sub-bubbles groupable into folders; app plugins (e.g. Zoom, Premiere Pro, Chrome, Word, Teams presets) require the Logi Plugin Service; triggered on MX Master 4 by the thumb button, which vibrates by default (haptics configurable); works with MX mice and MX Creative Console. Support docs have a troubleshooting article for the ring icon disappearing. — [Logitech support](https://support.logi.com/hc/sv/articles/17859365804439-What-is-the-Actions-Ring-feature-in-Logi-Options); [Logitech troubleshooting](https://support.logi.com/hc/vi/articles/18118701623959-Actions-Ring-icon-does-not-show-up-has-disappeared-from-Logi-Options-Home-screen); [Spider's Web review (PL)](https://spidersweb.pl/2025/09/mysz-logitech-mx-master-4-recenzja-opinie.html)
- A Galaxus MX Master 4 reviewer prefers keyboard shortcuts and sees no reason to change workflow, and his named flaw is the dampening rubbers, not the ring. — [Galaxus](https://www.galaxus.at/en/page/logitech-mx-master-4-tested-genius-mouse-with-one-frustrating-flaw-39723)
- PopClip: see section 1 for price/extension facts; the Macworld review highlights single-click actions on any text selection and a long extension list. — [Macworld](https://www.macworld.com/article/706796/popclip-review.html)
- Raycast Quicklinks and Snippets are in the free plan; free team plan caps shared quicklinks and snippets at 30 each. — [costbench](https://costbench.com/software/ai-productivity/raycast/); [toolradar](https://toolradar.com/tools/raycast/pricing)

### Inferences
- Kando is the closest UX relative but is trigger-by-keyboard, mouse-agnostic and visually plain; Pluck's differentiation is the physical blob and content-aware labels, not the radial idea itself.
- The ring's hardware gating and plugin-service dependency is a recognised failure mode (icon disappearing needs its own support article).

### Gaps
- No Kando macOS-specific issues, release cadence or download counts retrieved.
- No user reviews or quotes for Actions Ring beyond reviewers above; no Reddit/HN evidence of accidental-trigger complaints.
- PopClip current official pricing, extension gallery size and adoption not confirmed.

## 3. Gaps and proof of demand; cautionary tales

### Takeaway
Demand for radial plus per-app context is demonstrated by Radial, Pie Menu, Kando and Logitech, but evidence of strong adoption is thin. I found no documented abandoned radial launcher cases.

### Cited Findings
- Radial's developer said sub-menus and a menu switcher were the most requested features after launch, i.e. users want more depth and context switching. — [Product Hunt](https://www.producthunt.com/p/radial)
- Pie Menu's free tier is capped at 10 uses a day, showing a usage-gated trial model. — [hunted.space](https://hunted.space/product/pie-menu)
- Marking-menu research: menus must support novices (press-and-wait shows menu) and experts (fast mark without waiting) in the same interaction; marks were on average 3.5 times faster than menu selection in a field study; experts still return to the menu to refresh memory; limits exist on items per level and depth; a mobile paper says transition to recall is hard to facilitate but users reached a dozen commands after three ten-minute sessions. — [Autodesk Research / Kurtenbach and Buxton](https://www.research.autodesk.com/publications/the-design-and-evaluation-of-marking-menus); [Buxton](https://www.billbuxton.com/MMExpert.html); [Buxton, user learning](https://billbuxton.com/MMUserLearn.html)

### Inferences
- Gap Pluck could fill: content-under-pointer detection (selected text, link, file, image, window) driving radial labels. Radial and Pie Menu key off the frontmost app, not the object under the pointer; PopClip does selection only, with no radial. This is my inference from limited descriptions and should be verified by hands-on testing.
- Four fixed directions (N/E/S/W) fit marking-menu limits and support the expert "flick without looking" path; cancel-by-releasing-near-pin matches the marking-menu principle that cancel must be cheap.

### Gaps
- No failed or abandoned radial products identified (Fly-Pie being superseded by Kando is the only lineage note).
- No data on whether Radial, Pie Menu or Launchy retain users.

## 4. Delight mechanics and retention loops

### Takeaway
Found little direct evidence. Documented examples: haptic feedback on the Logitech ring trigger, extension/plugin ecosystems (PopClip, Logitech, Raycast), user-shareable macro libraries (Radial), and per-app menus.

### Cited Findings
- MX Master 4 vibrates when the ring-opening thumb button is pressed, configurable in Options+. — [Spider's Web](https://spidersweb.pl/2025/09/mysz-logitech-mx-master-4-recenzja-opinie.html)
- Radial's developer profile mentions macro sharing via a preset library. — [HN profile](https://news.ycombinator.com/threads?id=Glubker)
- PopClip extensions are free and installable by double-click. — [PCWeenies](https://pcweenies.com/?p=9212)
- Raycast Pro includes custom themes. — [costbench](https://costbench.com/software/ai-productivity/raycast/)

### Inferences
- Sound, animation personality, Easter eggs and skins were not evidenced in sources; claims about them for these products would be unsourced.
- Shareable action packs plus themes appear to be the main retention levers in this category.

### Gaps
- No sources on sound design, Easter eggs or community gallery metrics.

## 5. Lessons to copy (inference, grounded in sections above) and mistakes to avoid

### Takeaway
Draw on marking-menu research and the comparables' pricing, gating and ecosystem patterns. All items are my synthesis, not sourced facts, unless a section reference is given.

### Inferences
Copy:
1. Support press-and-wait for novices and quick flick for experts (Autodesk/Buxton research).
2. Keep per-app and per-content menus automatic (Kando per-app menus, Radial macros).
3. Offer a graphical editor for custom actions (Kando).
4. Ship an installable action format (PopClip double-click extensions) and a shareable library (Radial presets).
5. Use one-time or lifetime pricing in the $9 to $36 range; the category norm (section 1).
6. Include a generous trial (PopClip 150 uses; Pie Menu 10 per day).
7. Make the haptic feedback configurable and off-able (Logitech ring).
8. Keep first-party defaults useful with zero configuration (Raycast free core features).
9. Add sub-menu/folder depth but keep top level small (Radial v4, Logitech 8 plus folders).
10. Support non-keyboard triggers such as mouse buttons and trackpad (BTT, Logitech).

Avoid:
1. Hardware-gated features (Logitech MX only).
2. Reliance on a separate background plugin service that can fail (Logitech plugin service issue).
3. Mutually exclusive menu and mark modes (research).
4. Too many items per level or deep hierarchies (Kurtenbach/Buxton limits).
5. Subscription for a small utility without cloud value (Raycast Pro is justified by AI and sync).
6. Capping extension counts in free tiers in ways that frustrate (Raycast 30 shared snippets).
7. Visual-only polish with no discoverability path (marking-menu self-revelation).
8. Unclear price/trial terms; sources for PopClip disagree on price and trial.
9. Accidental triggers on a high-traffic button (thumb button, inference); require a deliberate chord or hold.
10. Permission sprawl per extension (PopClip extensions request extra permissions).

### Gaps
- Items about accidental triggers and permission fatigue are not backed by retrieved user reports.
