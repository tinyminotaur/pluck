# Positioning, Distribution, Trust, Pricing and Legal for a Delightful macOS Accessibility-Permission Gesture Utility (Pluck)

Research depth note: ~11 searches; most WebFetch calls failed (network), so findings rest on search-result summaries. Items marked "unverified" need checking against primary pages.

## Distribution: Mac App Store (sandbox) vs direct (Developer ID + Sparkle) vs Setapp

### Takeaway
Cross-app Accessibility use is contested under App Sandbox (Apple engineers have given conflicting answers), the best-documented comparable (PopClip) was forced out of the MAS by sandbox rules, and private-API use is disallowed by review rules. Direct Developer ID distribution (optionally plus Setapp) is the realistic primary path for Pluck.

### Cited Findings
- Apple DTS engineers disagree: one said sandboxing does not prohibit Accessibility permission and that sandboxed apps can monitor events; a later DTS engineer said documentation makes clear Accessibility APIs are not supported in sandboxed apps (pointing to "Review functionality that is incompatible with App Sandbox"). — [Apple Developer Forums 756130](https://developer.apple.com/forums/thread/756130), [Forums 836644](https://developer.apple.com/forums/thread/836644)
- A window-manager developer reported AXUIElementSetAttributeValue does not work in the sandbox even with Accessibility granted, and the submission was rejected by the automated checker; no entitlement answer found. — [Apple Developer Forums 836644](https://developer.apple.com/forums/thread/836644)
- One blog claims a tiler shipped on the MAS by delegating window movement to Shortcuts (Apple Events scripting-target entitlements), and asserts no entitlement unlocks cross-app Accessibility (author's claim, not Apple's). — [Blake Crosley](https://blakecrosley.com/blog/window-manager-mac-app-store-sandbox)
- PopClip left the MAS (March 2024): developer Nick Moore said he could no longer ship new features under sandboxing policy; review said removing new features would get an update accepted; he argued Accessibility is already protected by user-granted TCC. PopClip is now sold via Setapp and its website, and MAS owners are upgraded from the website. — [Michael Tsai summary](https://mjtsai.com/blog/2024/03/21/popclip-leaving-the-mac-app-store/) (via search summary; page fetch failed), [ifun.de](https://www.ifun.de/popclip-muss-den-mac-app-store-verlassen-229659/)
- Maccy is open source and distributed both via the MAS (paid, ~10 EUR "support the developer") and GitHub/Homebrew (free). Developer's reasons not found. — [sir-apfelot](https://www.sir-apfelot.de/maccy-durchdachter-zwischenablage-manager-fuer-den-mac-39941/), [iphonesoft.fr](https://iphonesoft.fr/2025/02/15/maccy-app-open-source-booste-presse-papiers-mac)
- Magnet is sold on the MAS at $4.99 (sale history to $0.99); Rectangle is free/open-source (MIT) via direct download/Homebrew with a paid Rectangle Pro (price unverified; a third-party site listed 1,668 yen one-time, 10-day trial). — [MacStories](https://www.macstories.net/?p=48075), [Rectangle vs Magnet page (unofficial byline)](https://sites.google.com/view/rectangle-app/rectangle-vs-magnet-mac-window-manager), [atsoho](https://atsoho.com/apps/p/rectangle)
- Direct distribution needs Apple Developer Program, Developer ID cert and notarization; trades Apple-hosted updates/payments for control of price, timing and no commission. — [Flavio Copes](https://flaviocopes.com/courses/ship-macos-apps/choose-source-app-store-or-direct/)
- Non-public API use is cited under guideline 2.5; rejections can name the symbol/framework and can come from bundled third-party libraries. No documented MultitouchSupport rejection found. — [Apple Forums 740163](https://developer.apple.com/forums/thread/740163), [Michael Tsai on Transfer Toolbox rejection](https://mjtsai.com/blog/2023/06/26/transfer-toolbox-rejected-from-the-mac-app-store)
- Setapp: usage-based payout (more apps used per user = less per developer); reported 70% guaranteed usage share plus up to 20% referral (third-party directory; original 2023 reporting tied to iOS store plans). Setapp claims only 34% of Mac users rely solely on the MAS (vendor stat). Single-app "Marketplace" reportedly launched March 2026 (directory listing). — [Tidbits](https://tidbits.com/?p=17018), [MacStories](https://www.macstories.net/news/mac-app-subscription-service-setapp-goes-live/), [thegtmdirectory](https://thegtmdirectory.com/tools/setapp), [Setapp](https://setapp.com/app-reviews/app-monetisation-strategies)

### Inferences
- Pluck's private MultitouchSupport trigger alone likely blocks MAS acceptance; the NSEvent global monitor + AX reads are a second risk. A MAS "lite" without three-finger/AX actions is possible but would gut the product.
- Plan: Developer ID + notarization + Sparkle as primary; Setapp as secondary discovery channel (PopClip precedent); keep the private-API code behind a build flag/optional runtime load so the main build can degrade gracefully when macOS changes it.
- Note: NSEvent global monitors observe but do not require an event tap; on recent macOS they are gated by Accessibility/Input Monitoring prompts — verify which TCC pane Pluck actually triggers on macOS 14/15/26 (not established in sources).

### Gaps
- No primary Apple text retrieved on exact sandbox restrictions for NSEvent global monitors/Input Monitoring.
- No primary source on Rectangle Pro/Magnet/Raycast current USD prices or on Setapp's current developer terms.
- No MultitouchSupport-specific review case found.

## Permissions UX and trust

### Takeaway
No Apple best-practice doc found; practice is: explain before the system alert, deep-link to Privacy & Security > Accessibility, detect the grant, and handle stale TCC entries. Recurring re-prompts apply to Screen Recording (monthly), not Accessibility — so avoid Screen Recording if possible.

### Cited Findings
- Sequoia screen-recording re-approval started weekly in beta, softened to monthly (beta 6), reboot prompt dropped; no developer API/entitlement to suppress documented (Persistent Content Capture entitlement mentioned without docs). — [9to5Mac](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/), [Macworld](https://www.macworld.com/article/2429205/macos-sequoia-requires-regular-permission-checks-when-using-certain-apps.html), [TidBITS](https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly)
- Apple tells users to grant Accessibility only to apps they trust; the grant is done in System Settings > Privacy & Security > Accessibility. — [Apple Mac User Guide](https://support.apple.com/guide/mac-help/mh43185/)
- Vendor guidance: explain why before the alert, list dependent features, include path to the pane; stale entries may need removing/re-adding (drag app from Finder) or a restart. — [Irradiated Software](https://www.irradiatedsoftware.com/help/accessibility/)
- PopClip's developer's argument that TCC already protects Accessibility is a useful trust framing. — [Michael Tsai](https://mjtsai.com/blog/2024/03/21/popclip-leaving-the-mac-app-store/)

### Inferences
- Trust levers: open-source core (Apache-2.0 already), no network entitlement/no analytics, signed+notarized, a one-page privacy statement, and an in-app "what we read/never do" panel. Verifiable claims ("no network code; here is the grep") beat assertions.
- Pre-permission screen should show the blob working in a sandboxed demo area (no permission needed) first, then ask — earns the grant after delight.
- Poll AXIsProcessTrusted on app activation/timer to auto-advance when granted; offer "relaunch" if the event monitors need it.
- "Listen-only, never synthesizes input" claim is credible only if true in code; Pluck's "acts on release" via AppleScript/Shortcuts should be disclosed as the exception.

### Gaps
- Examples of good vs bad onboarding (Rectangle, Raycast, BetterTouchTool, Bartender) not retrieved.
- macOS 26 (Tahoe) permission-behavior changes not verified.

## Discoverability and onboarding for a hidden gesture

### Takeaway
Marking-menu research directly supports Pluck's design: show labels to novices, let experts "mark ahead", and let the same physical motion serve both.

### Cited Findings
- Kurtenbach's principles: self-revelation, guidance, rehearsal; rehearsal means the guidance physically rehearses the expert's mark. — [Buxton, Marking Menus](https://billbuxton.com/MMUserLearn.html), [Autodesk Research](https://www.research.autodesk.com/publications/user-learning-and-performance-with-marking-menus/)
- Novices wait for the pop-up menu; with memorization they "mark ahead"; the two are the same interaction (press-and-wait or not). — [Kurtenbach, Sellen, Buxton 1993 / Autodesk PDF](https://research.autodesk.com/app/uploads/2023/03/the-design-and-evaluation.pdf_recCzWoTgz02K2Ubb.pdf)
- Field study: marks ~3.5x faster than menu selection; experts still revert to the menu to refresh memory. — [Kurtenbach & Buxton 1994 (Buxton site)](https://www.billbuxton.com/MMExpert.html)

### Inferences
- Map onto Pluck: stretch-and-hold reveals the four action labels (delay-based reveal); fast flicks skip labels. Fade labels per direction as that direction's use count rises; keep reveal on a longer hold.
- First-run: practice blob with a fake target, then a real action on a harmless sample; success metric = first successful real action within session 1, 7-day retained users with >=3 actions/day, ratio of label-less (expert) releases. These metrics are my proposals, not sourced.
- Raycast/Arc/Linear onboarding approaches were not researched here.

### Gaps
- No sourced onboarding teardowns of Raycast/Arc/Linear; no re-engagement benchmarks.

## Positioning and naming

### Takeaway
Little sourced evidence found; guidance below is inference. Product Hunt anecdotes favor visual demo and a way to try.

### Cited Findings
- A macOS menubar dev's first PH launch (no video, unpolished screenshots) got 10 upvotes; relaunch with demo video reached #3 and downloads nearly doubled. — [Hackernoon](https://hackernoon.com/lite/i-turned-a-failed-product-hunt-launch-into-a-top-3-win-on-a-budget)
- Another dev: lack of a trial hurt PH conversion; PH discounts help; top products usually offer a trial, are free, or open source. Mac-site reviews reportedly bring little traffic. — [Indie Hackers](https://www.indiehackers.com/post/results-lessons-learned-from-my-first-product-hunt-launch-dbf1641187)

### Inferences
- Lead with the 3-5 second looping clip of the stretch-release; lead copy with productivity ("four context actions under your pointer") and let delight be the proof, not the apology.
- Segments in order of fit: Mac power users/launcher fans, designers, fidgeters/ADHD (be careful: do not make medical claims), streamers/educators (visible gesture on camera). Accessibility-user claims should be validated before marketing (physical stretch gesture may exclude some users).
- Press angles (MacStories, 9to5Mac, DF, Verge) not researched; treat as outreach targets, not evidence.

### Gaps
- No sourced taglines, TikTok/X/HN strategy data, or press-coverage precedents.

## Pricing and business model

### Takeaway
Comparable utilities cluster at low one-time prices (Magnet $4.99; BTT ~two-tier license), often with a free open-source base and paid pro; Setapp adds subscription-pool revenue. Conversion data is anecdotal only.

### Cited Findings
- Magnet $4.99 one-time on the MAS. — [MacStories](https://www.macstories.net/?p=48075)
- BetterTouchTool: reported $9 (2-year updates) / $21 (lifetime) in an older Macworld review; later $12 / $24 per How-To Geek; current price unverified. — [Macworld](https://www.macworld.com/article/551700/mac-gems-bettertouchtool-review.html), [Yahoo/How-To Geek](https://tech.yahoo.com/general/articles/why-think-bettertouchtool-mac-essential-173012620.html)
- Rectangle: free OSS + paid Pro; Maccy: free GitHub + paid MAS copy. — sources above.
- Setapp claims subscription suits long-term-value apps and one-time suits specialised utilities (vendor opinion). — [Setapp](https://setapp.com/app-reviews/app-monetisation-strategies)
- PH conversion anecdotes range from ~31% (self-reported, 14-day window incl. iOS) to 0.25% (non-Mac AI tool). — [Indie Hackers 1](https://www.indiehackers.com/interview/growing-my-first-app-to-profitability-with-no-marketing-experience-31549472ff), [Indie Hackers 2](https://www.indiehackers.com/post/400-signups-from-product-hunt-1-paying-customer-what-4-days-taught-me-about-launch-vs-traction-7c0aacf745)

### Inferences
- A fidget-toy utility has limited recurring value, so a one-time license (roughly $10-25 range, my inference) with free trial and optional free OSS core fits; a skins/actions marketplace is a plausible lever but I found no sourced evidence on ecosystem revenue.

### Gaps
- No verified 2024-2026 prices for Rectangle Pro, Raycast Pro, CleanShot, Paste, PopClip; no indie conversion benchmarks beyond anecdotes.

## Legal and safety (not legal advice; verify with a professional)

### Takeaway
"Pluck" has prior trademark records and at least one same-named macOS GitHub utility; a proper clearance search is needed before investing in the name.

### Cited Findings
- Pluck, Inc. has trademark applications (serials 86947014, 86947017) for mobile apps; PLUCK Reg. 3193110 (content aggregation software) cancelled 2017; Canadian PLUCK application 1407292 abandoned. — [Justia owner page](https://trademark.justia.com/owners/pluck-inc-3276371), [Justia 78814213](https://trademarks.justia.com/788/14/pluck-78814213.html), [CIPO](https://ised-isde.canada.ca/cipo/trademark-search/1407292)
- A GitHub project "advegaf/pluck" is a macOS utility (press-and-hold to copy selected text; macOS 26+) — a direct name collision in the same niche. — [gitblind mirror](https://gitblind.noratr.app/advegaf/pluck)
- Private-API rules: Apple guideline 2.5 (see Distribution).

### Inferences
- Run a USPTO/EUIPO Class 9 + 42 search, check app-store and domain/handle availability, consider a more distinctive name or mark; confirm Apache-2.0 compatibility of any bundled dependencies; a short privacy policy (no data collected) is still advisable for site/Sparkle appcast; check accessibility (WCAG-style/VoiceOver, reduced-motion alternative) for the blob UI.

### Gaps
- Live USPTO status not retrieved; no sourced accessibility-compliance requirements for desktop utilities.
