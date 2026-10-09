# Context-sensitive quick actions for a 4-direction gesture selector (Pluck, macOS)

Legend: "Cited" = from a fetched/searched source. "Inference" = my judgment. Sourcing was thin: ~9 searches, no usage-statistics source found.

## 1. Best four actions (Keep N / Go E / Give S / Ask W) per context

### Takeaway
No published ranking of most-used context actions exists (see Q2), so the catalog below is my judgment, anchored on what PopClip, Alfred and Raycast ship by default. Keep the direction meaning stable (N=retain, E=open/go, S=send/give, W=ask/lookup) and vary only the verb.

### Cited Findings
- PopClip built-ins: Cut, Copy, Paste, Dictionary (only when the word is in an enabled dictionary), Reveal in Finder (for selected paths), Spelling. Actions appear only when relevant to the selection — [PopClip guide](https://www.popclip.app/guide/actions)
- Search and translate are third-party descriptions of PopClip (translate via extensions such as Google Translate/DeepL) — [Setapp](https://setapp.com/apps/popclip)
- Alfred Universal Actions: choose an item (file, text, URL) then an action; filtered by item type; 60+ defaults, e.g. copy to clipboard, save as snippet, web search, extract URLs from text — [Alfred help](https://www.alfredapp.com/help/features/universal-actions/)
- Raycast built-in AI commands on selection: Improve Writing, Fix Spelling and Grammar, Professional/Friendly tone, Explain in Simple Terms; translate is a user-made AI command with `{selection}` — [Raycast manual](https://manual.raycast.com/ai/ai-commands)
- Raycast Quick Fix (v0.61, May 2026): one hotkey corrects selection and pastes it back — [Raycast changelog](https://www.raycast.com/changelog/macos/0-61)

### Proposed catalog (inference; ranked by my estimate of frequency, most valuable first within each row)
| Context | N Keep | E Go | S Give | W Ask |
|---|---|---|---|---|
| Selected text | Copy + save to history/clip (alt: append to note) | Search web / open if URL or path | Share sheet / send to (Messages, Mail) | Look up/define; long-press variant translate or ask AI |
| Link | Save to reading list / bookmark / copy URL | Open in default browser (alt: open in background) | Share / copy as Markdown | Ask AI to summarize; Quick Look preview |
| File/folder (Finder) | Tag / copy path / add to shelf | Open (alt: Open With, Reveal) | Share / AirDrop / Move to... | Quick Look (preview), Get Info |
| Image | Copy image / save to Photos or folder | Open in Preview | Share / AirDrop | Live Text OCR, ask AI, reverse search |
| Window title bar/chrome | Pin on top / save window layout | Move to next display / full screen | Send window to Space / close-adjacent | Window info / app help |
| Empty desktop / clipboard | Save clipboard to history/snippet | Paste (plain text variant) | Share clipboard contents | Ask AI about clipboard |
| Code editor selection | Copy as fenced Markdown / snippet | Open file:line / search repo | Share as gist/link | Explain with AI; look up docs |
| Email/Slack message | Save to task app (Things/Todoist/Reminders) | Open original/thread | Forward / reply with quote | Summarize / draft reply with AI |
| PDF/Preview text | Highlight + copy with citation | Search web | Share excerpt | Define / translate / ask AI |
| Terminal | Copy output / last command | Re-run / open path | Share selection | Explain command/error with AI |
| Browser tab/page | Bookmark / reading list / archive | Open in other browser/profile | Share URL / copy as Markdown | Summarize page with AI |

### Inferences
- Rows for window chrome, terminal and code editor are least grounded; no source found for those contexts. Treat as hypotheses to test.
- Safest high-frequency core is copy / search / share / lookup, since those match PopClip and Alfred defaults.

### Gaps
- No source ranking actions per context; no Slack/Mail/terminal-specific action sources fetched.

## 2. Usage evidence and popularity signals

### Takeaway
I found no published usage statistics for macOS context-menu, Services, share-sheet or clipboard-manager actions. Only product feature lists exist.

### Cited Findings
- PopClip's extension directory contains 210 extensions and is curated by the developer; no popularity sort found — [PopClip guide](https://www.popclip.app/guide/extensions)
- The pilotmoon/PopClip-Extensions repo has ~2.0k stars — [GitHub mirror](https://gittrend.io/repo/pilotmoon/PopClip-Extensions) (shows interest in code, not per-action usage)
- Clipboard managers commonly offer plain-text paste (stripping formatting) — [Pasty](https://apps.apple.com/app/id1544620654), [TidBITS Talk](https://talk.tidbits.com/t/five-solutions-for-pasting-plain-text-on-a-mac/18775)
- Yoink shelf offers force-copy/force-move, grouping, Handoff and Shortcuts integration — [TidBITS](https://tidbits.com/2017/09/05/yoink-takes-mac-drag-and-drop-to-the-next-level/)

### Inferences
- Plain-text paste, copy, search, define, translate recur across all tools, so they are a reasonable proxy for "most used".

### Gaps
- Brett Terpstra's extension list, the PopClip directory contents, Reddit/HN threads and any telemetry were not examined. Rename/tag/move-to/quick-look frequency: no data.

## 3. Conventions that make four slots learnable

### Takeaway
Marking-menu research supports stable direction-to-command mapping: users progress from showing the menu to blind gestures, and marks were on average 3.5x faster than menu selection.

### Cited Findings
- Marking menus let users pop up a radial menu or just stroke in the item's direction; novices use the menu, experts use marks — [Kurtenbach & Buxton via Autodesk Research](https://research.autodesk.com/publications/user-learning-and-performance-with-marking-menus)
- Field study: marks were ~3.5x faster than menu selection; experts still return to the menu to refresh memory of layout — [Buxton](https://billbuxton.com/MMUserLearn.html)
- Marking menus have faced adoption challenges even on touchscreens; M3 grid design reported users could move to recall-based execution of about a dozen commands — [Zheng et al.](https://www.springerpflege.de/doi/10.1145/1753326.1753663)

### Inferences
- Rule: direction = semantic role, verb = per context. N always retains something, E always advances/opens, S always sends outward, W always asks/looks up. Showing labels on the blob (menu mode) serves novices; the same stroke works blind for experts.
- With fewer than four useful actions: leave the slot empty (cancel-like, dimmed) rather than duplicating, to keep spatial memory and avoid accidental trigger. Duplicate only if the duplicate is the same role (e.g. two ways to "Keep").
- Contexts reuse the same four roles; at most ~11 contexts (table above) is manageable because roles, not verbs, are memorised. Not empirically tested.

### Gaps
- No study of 4-slot context-varying labels specifically; the 4-direction limit is smaller than studied marking menus (8 typical).

## 4. User-defined actions

### Takeaway
Let each (context, direction) slot bind to one "action" of types: Shortcut, shell/AppleScript, URL scheme, or AI prompt template. Pass context as a typed payload.

### Cited Findings
- `shortcuts run "Name"`; `-i/--input-path` for files, `-o/--output-path` for output; text can be passed via a here-string (`<<<`), since `-i` accepted only files per a 2022 report (unverified on current macOS); shortcuts with prompts hang the CLI, non-zero exit on failure/cancel — [Six Colors](https://sixcolors.com/post/2022/01/shortcuts-applescript-terminal-working-around-automation-roadblocks/), [Apple Shortcuts guide](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac), [Flavio Copes](https://flaviocopes.com/courses/automate-macos/run-shortcuts-from-terminal/)
- Alfred workflows add custom entries that appear only for matching argument types (files/URLs/text) — [Alfred](https://www.alfredapp.com/help/features/universal-actions/)
- Raycast AI commands are prompt templates with `{selection}`, duplicable and editable (prompt, model, creativity) — [Raycast manual](https://manual.raycast.com/ai/ai-commands)

### Inferences (design)
- Model: slot = {context filter, label, icon, executor, template}. Template variables {selection} {url} {path} {clipboard} {app} {title}. Same model supports Raycast-like AI prompts, so no 4-slot break: users override a slot per context, with fallback to defaults.
- Examples: Ask W: URL scheme to ChatGPT/Claude app or CLI with prompt + {selection}. Keep N: `things:///add?title={selection}`, Todoist URL scheme, `shortcuts run` for Reminders; Obsidian `obsidian://daily` / `obsidian://new?...append` (URL schemes - from my knowledge, not verified here); calendar event from text via Shortcuts "Add New Event" or AppleScript.
- Per-app override layering: app-specific > context-type > global.

### Gaps
- Did not verify Things/Todoist/Obsidian/Claude URL scheme syntax or Shortcuts text-input behaviour on macOS 14+.

## 5. Risky/destructive actions and gesture handling

### Takeaway
No source found; all of this is design judgment. Keep destructive actions out of default slots; where offered, require deliberate gesture extent plus undo.

### Inferences
- Default catalog contains no delete/overwrite. Send (mail/Slack) actions create a draft rather than send, or show an undo toast with delay (e.g. 5 s).
- Confirm by stretch distance: a second "lobe"/threshold beyond the normal one arms the action (blob changes colour), release there to run; release at the normal range gives non-destructive variant or cancel. Hold-at-lobe (~400 ms) is an alternative. Release near pin always cancels (given).
- Prefer reversible: Move to Trash (undoable) over delete; copy over move.

### Gaps
- No usability evidence on stretch-to-confirm.

## 6. Feasibility on macOS 14+

### Takeaway
Everything is feasible, but Accessibility use means no App Sandbox (Developer ID distribution, not Mac App Store).

### Cited Findings
- Apple DTS: Accessibility APIs are not supported in sandboxed apps; AXIsProcessTrusted returns false and the app is not listed in the Accessibility pane when sandboxed; solution reported: no sandbox, code-sign — [Apple Developer Forums 810677](https://developer.apple.com/forums/thread/810677), [thread 24288](https://developer.apple.com/forums/thread/24288)
- `kCGWindowName` is only populated with Screen Recording permission (DTS) — same forum results above
- `NSSharingService.sharingServices(forItems:)` returns services that can share all given items; usable to build custom UI or an NSMenu; `NSSharingService(named:)` since 10.8; `canPerform(withItems:)` — [Apple docs](https://developer.apple.com/documentation/appkit/nssharingservice/init(named:).md)
- `NSSharingService` shares URLs, strings, images consistently — [Apple docs](https://developer.apple.com/documentation/appkit/nssharingservice.md)

### Inferences (from my knowledge; not verified in this session)
- Selected text: AXUIElement kAXSelectedTextAttribute on focused element; fallback simulate Cmd-C and read NSPasteboard (restore afterward). Electron/terminal apps often expose poor AX, so fallback needed.
- Link/file under pointer: AXUIElementCopyElementAtPosition then kAXURLAttribute / kAXDocumentAttribute; Finder file via AppleScript/Apple Events (needs Automation permission) or selected items.
- Open/Reveal/Open With: NSWorkspace; Quick Look: QLPreviewPanel or `qlmanage -p`; Tags: URLResourceValues.tagNames; Move to: FileManager; Define: DCSCopyTextDefinition / NSView showDefinition; Translate: macOS 14 Translation framework (SwiftUI-hosted, limited) or URL to translate site; Services menu: NSPerformService (needs service name) is limited; Shortcuts via `Process` calling /usr/bin/shortcuts; AppleScript via NSAppleScript (Automation consent per target app); URL schemes via NSWorkspace.open.
- Permissions needed: Accessibility, possibly Input Monitoring (global mouse/event tap), Automation per target app, Screen Recording only for window titles via CGWindow.

### Gaps
- Not verified: DCSCopyTextDefinition behaviour, Translation framework headless use, Services invocation API limits.
