# Actions by context: what each direction actually does

Directions have a **fixed meaning**; only the verb changes with what is under the pointer.

| Direction | Role | Meaning | Rule of thumb |
|---|---|---|---|
| North | **Keep** | Retain / store / save, local and non-destructive | "Put it somewhere I can get it back" |
| East | **Go** | The primary forward action: open, act, continue | "Do the obvious thing" |
| South | **Give** | Send outward: share, export, hand off | "Get it to someone / somewhere else" |
| West | **Ask** | Learn about it or transform it: look up, info, AI | "Tell me more / help me with this" |

Release near the pin (inside the ~24 pt ring) always cancels. Empty slots stay empty (never duplicated).

## 1. How the context is chosen (`ContextResolver.resolve`, in priority order)

1. Pointer in a window's title-bar / chrome → **window**
2. Non-empty text selection (via AX) → **text**
3. Element under the pointer is a link → **link**
4. Element is a file (Finder row etc.) → **image** if an image extension, else **file**
5. Pointer is in a text field with no selection → **clipboard (paste mode)**
6. Anything else → **clipboard (promote mode)**

## 2. What is implemented TODAY (from `ContextResolver` / `ActionRunner`)

(Real actions run only when Feel Lab mode is off.)

| Context | North · Keep | East · Go | South · Give | West · Ask |
|---|---|---|---|---|
| Selected text | Copy → pasteboard | Search → opens DuckDuckGo for the text | Share → system share picker | Look Up → `dict://` Dictionary for the first word |
| Link | Copy Link → URL string to pasteboard | Open → `NSWorkspace.open(url)` | Share → share picker | "Copy Text" → **currently identical to Copy Link** (placeholder) |
| File | Copy → file to pasteboard | Quick Look (opens the file **and** runs `qlmanage -p`) | Share → share picker | Get Info → Finder info window via AppleScript |
| Image file | Copy Image → image to pasteboard | Quick Look | Save → copy to ~/Downloads | Get Info (**slot missing if no file URL**) |
| Window title bar | Fill (maximize on main display) | Right half | Bottom half | Left half |
| Text field, no selection | Up to 4 recent clips fill N,E,S,W in order; releasing **pastes** that clip | | | |
| Elsewhere (no field) | Same 4 recent clips; releasing **promotes** it to the current clipboard ("Ready to paste") | | | |
| Clipboard history empty | "Keep" (no-op) if something is on the clipboard | "Paste" (in a field only) | – | "Empty" (no-op) if nothing copied |

### Known inconsistencies in today's schema
- **Window** uses N/E/S/W as spatial positions (Fill/Right/Bottom/Left), which breaks the Keep/Go/Give/Ask meaning used everywhere else. It also moves the app's *first* window (not the one under the pointer) on `NSScreen.main` (not the pointer's display).
- **Clipboard** treats the four slots as four recent items, again not Keep/Go/Give/Ask.
- Link West duplicates North; Image drops West without a file URL; the Quick Look action opens the app *and* shows Quick Look.
- Share via `NSSharingServicePicker` needs an on-screen anchor and a click; it is not a one-gesture action.

## 3. Proposed schema (the full contexts story)

Legend: **bold** = built today, plain = proposed, `[!]` = risky, needs the stretch-to-arm confirm (below).

| Context | N · Keep | E · Go | S · Give | W · Ask |
|---|---|---|---|---|
| **Selected text (prose)** | **Copy** (+ add to clipboard history) | **Search** (default engine) | **Share** / Send to… (Messages, Mail, Notes) | **Look Up** / Define · long-press → Ask AI "explain this" |
| **Selected text (looks like a date/time)** | Copy | Create Calendar event | Share | Show in Calendar (free/busy) |
| **Selected text (email / phone / address)** | Add to Contacts | Mail / Call / Maps | Share contact | Look up person (Contacts) |
| **Selected text (code in an editor)** | Copy as fenced markdown | Run / Search docs | Share as gist/snippet | Explain with AI |
| **Terminal selection** | Copy | Run again / Open path | Share output | Explain error with AI |
| **Link** | Copy Link · hold → Save to Reading List | **Open** (new tab) | **Share** | Preview / Page title + summary (AI) |
| **File in Finder** | **Copy** · or Tag / Add to a "Keep" folder | **Open** / Quick Look | **Share** / AirDrop | **Get Info** · Rename |
| **Image** | **Copy Image** | Quick Look / Open in Preview | **Save** to Downloads / Share | Info · Live Text (copy text from image) |
| **PDF / Preview text** | Copy · Highlight | Search | Share | Look Up / Translate |
| **Email or chat message (selected)** | Save to Notes / Todo | Reply (draft) | Forward | Summarize / Draft reply (AI) |
| **Window title bar** | Keep on top / Minimize | Maximize / Next display | Move to another Space/display `[!]` | Show window info · Tile picker |
| **Text field, no selection** | Paste last clip | Paste clip #2 | Paste clip #3 | Paste clip #4 (clipboard-ring mode) |
| **Empty desktop / nothing under pointer** | Copy current clipboard to history | Open launcher | Share clipboard | Ask AI about the clipboard |
| **Menu-bar / Dock item** | Pin | Open | Quit app `[!]` | App info |

### Variants that use the physical nature
- **Two-zone stretch**: pull *into* the lobe = preview shown inside the blob (e.g. snapped window outline, destination folder, the clip text); pull *past* it = armed. Destructive or outward actions (Send, Quit, Move file, Delete) require the second zone; releasing at the first zone cancels.
- **Stretch distance as a value** (cheap, already measured): on Go for Media = scrub; on Give for Share = which target in a ring; on Keep = how many items ("last 3 clips").
- **Release velocity** (flick): in window context, a fast flick on Go = throw to the other display; a slow release = snap.
- **Hold at lobe** (0.5 s): secondary action for the same slot (the "hold" variants above), shown by the lobe swelling.

### Why this schema
- Muscle memory: N is always "keep" so after a few uses you don't read labels (labels fade for experts).
- Safe default: nothing destructive in a default slot; outward actions need arming; everything undoable where possible (undo toast).
- Evidence level: the catalog is design judgment informed by what PopClip/Alfred/Raycast expose; no usage data exists for these actions. See `reports/Physical blob tool applications.md`.

## 4. Suggested implementation order
1. Fix inconsistencies in section 2 (window under pointer + pointer's display; link West; image West; Quick Look; clipboard keep semantics).
2. Add context kinds: text subtype detectors (date, email/phone, code), PDF text, message.
3. Move actions from a hard-coded `switch` to a table keyed by (context, role) so users can rebind (Shortcuts / URL schemes / AI prompts).
4. Two-zone stretch + undo toast, then velocity-based window throw.
