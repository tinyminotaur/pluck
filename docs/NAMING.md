# Naming

"Pluck" fit when this was a gesture launcher. It is now a **playful pointer toy and presenter tool**: hold a trigger,
stretch a shape from where you are to where you point, let go; 40+ looks, community packs, optional actions.

## Why not keep "Pluck"
- A GitHub project, `advegaf/pluck`, is a macOS utility in a similar niche (flagged during research).
- Trademark records exist for "Pluck, Inc." (mobile apps) plus lapsed filings. Needs a real clearance search.
- It is a common English word, which is hard to search for.
This is a risk assessment, not legal advice: have the name cleared before spending on a launch.

## What the name should do
1. Evoke **stretch and release** (the one gesture the whole product is built on).
2. Feel like a **toy** first (delight), without sounding unserious as a presenter tool.
3. Be short, speakable, searchable, and available as `<name>.app` / a GitHub repo / a Homebrew cask.
4. Sit comfortably under **Tiny Minotaur** (myth, labyrinths, Ariadne's thread).

## Candidates (availability NOT verified; searches were inconclusive and DNS cannot be checked from the build sandbox)
| Name | Why it works | Risks found | Fit |
|---|---|---|---|
| **Twang** | The *sound* of a stretched string being released, which is exactly the interaction; keeps the string metaphor of "Pluck"; one syllable; verb-able ("twang it") | No Mac app found. Old iOS guitar app (2010) and a voice app "TwangMe" exist. Common word in trademark class 9 is possible | Best overall for the toy-first positioning |
| **Tendril** | Organic, stretchy, elegant; works for liquid and plant-like styles; reads more "pro" | No Mac app found; word is used by unrelated companies in other fields | Best if you want a calmer, more design-y brand |
| **Taffy** | Literally stretches; warm and funny | A well-known Rust layout library is called Taffy (developer search noise); no Mac app found | Good toy name, weaker for presenters |
| **Clew** | A clew is a ball of thread (origin of "clue"), i.e. Ariadne's thread: ties to Tiny Minotaur's labyrinth | Crowded: several unrelated products already use it (a Mac search app, an AI IDE, an AR app); sounds like "clue" | Strongest story, weakest availability |
| **Thwip** | Fun release sound | An iOS/watchOS soundboard called Thwip exists | Skip |
| Boing / Gloop / Wobble | Playful | Very common, hard to own | Skip |

## Recommendation
1. **Twang** for the product, shown as "Twang by Tiny Minotaur", tagline ideas: *Stretch it. Let go.* / *A small physical toy for your cursor.*
2. Keep **Tendril** as the fallback if Twang fails clearance.
3. Use the Ariadne's-thread idea as a **feature name** instead (e.g. the tether between pin and pointer is "the thread") so the Tiny Minotaur myth shows up without the availability problems of Clew.

## Before committing
- Search the USPTO trademark database (classes 9 and 42) and the App Store for the shortlisted names.
- Check domains (`<name>.app`, `get<name>.com`), the GitHub org/repo, and the Homebrew cask namespace.
- Say the name out loud in the sentence "I use ___ to ..." and check that it is easy to spell from hearing it.

## Doing the rename
`scripts/rename-project.py --name Twang` renames targets, source folders, defaults keys, bundle id (default
`co.tinyminotaur.twang`), docs and workflows in one pass (`--dry-run` first). Then build and test, rename the GitHub repo
(old URLs redirect), and re-grant Accessibility once because the bundle id changes. Do it **before** the first notarized
release, since the bundle id is what macOS ties permissions to.
