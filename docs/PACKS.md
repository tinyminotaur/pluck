# Twang animation packs

Anyone can make a Twang animation, share it, and have it show up in the app: a bit like Winamp skins. A **pack** is a
small folder (or a zipped `.twangpack`) containing a `pack.json` and optional images. It describes *what to draw* with
shapes, paths and tiny formulas. It contains **no code**, so installing one can never run anything on your Mac.

## Why data, not plugins

| Option | Safe to install | Works in a web editor | Easy to write |
| --- | --- | --- | --- |
| Native plugin (dylib) | No: arbitrary code | No | Hard |
| Embedded scripting (JS/Lua) | Mostly: needs a sandbox, can still hang or burn the CPU | Yes | Medium |
| **Declarative JSON + tiny expressions (what Twang uses)** | **Yes: can only produce numbers and shapes; size-limited** | **Yes: the spec is small enough to re-implement in JS** | **Easy; live-reloads as you save** |

The engine enforces limits (layers, shapes, expression size) so a pack cannot make the app slow.

## Making one in two minutes

1. Open **Feel Lab > Library > New pack from template**. A working pack opens in your editor.
2. Change a number, save. Twang reloads it instantly (mistakes are listed in the Library tab, in red).
3. Pick it under **Looks > Community**, or assign it to a direction in **Presenter** mode.

Check a pack from the command line (handy for CI):

```bash
Twang.app/Contents/MacOS/Twang --validate-pack path/to/my-pack
```

## pack.json

```json
{
  "format": 1,
  "id": "com.you.my-animation",
  "name": "My Animation",
  "version": "1.0.0",
  "author": "You",
  "license": "CC-BY-4.0",
  "tagline": "One line that sells it",
  "theme": "aurora",
  "params": [ { "name": "wiggle", "label": "Wiggle", "default": 0.6, "min": 0, "max": 1 } ],
  "release": { "duration": 0.8, "behavior": "stay" },
  "layers": [ ... ]
}
```

- `id`: letters, digits, `.`, `-`, `_`. The folder name must match it.
- `theme` (optional): the colour theme the pack suggests (it is still the person's choice).
- `params`: each becomes a slider in the Library tab and a variable in your formulas.
- `release`: how long the finale lasts, and what the head does: `stay` (holds still while your finale plays; the usual
  choice), `ease` (drawn back smoothly) or `spring` (snaps back with a bounce). Pick what fits the idea; a kite should
  not bounce, a rubber band should.

### Layers

Layers draw in order. Every number may be a plain value or a formula string.

| `type` | What it draws | Main fields |
| --- | --- | --- |
| `path` | a line through `count` sample points | `along`, `offset`, `width`, `color`, `glow`, `dash`, `dashSpeed`, `fill`, `close` |
| `shape` | `count` copies of a shape | `shape`, `along`, `offset`, `size`, `size2`, `rotation`, `color`, `stroke`, `strokeWidth`, `glow` |
| `text` | text; `{formula}` parts are filled in | `text`, `fontSize`, `color`, `along`, `offset` |
| `image` | a PNG/JPEG from your pack | `asset`, `size`, `rotation` |

Shapes: `circle ring rect diamond star heart drop triangle cross spark`.
Common to all: `visible` (formula; 0 hides it), `alpha`, `space`.

`space` sets the coordinate system for `along`/`offset`: `span` (origin at the pin, `along` runs toward the head,
`offset` is sideways: the default), `head` (origin at the head), or `screen` (origin at the pin, plain x and y).

Colours: `"#rrggbb"`, `"#rrggbbaa"`, theme colours `"@a"`, `"@b"`, `"@c"`, `"@body"` (so your pack follows the
person's chosen colours), or `{ "h": formula, "s": 0.8, "v": 1 }`.

### Formulas

Variables:

| name | meaning |
| --- | --- |
| `t` | seconds since the gesture began |
| `s`, `u` | 0 to 1 along a path or across the copies of a shape |
| `i`, `n` | copy index and count |
| `chord`, `angle` | distance and direction between the two points |
| `pull` | 0 to 1 as you stretch (smoothed) |
| `pinR`, `headR`, `mass` | the two ends' sizes and the pin's share of the mass (the pin gets smaller as you pull) |
| `speed` | how fast the head is moving |
| `charge` | 0 to 1 over the first 1.6 s of holding |
| `fired`, `commit`, `tr` | 1 after release; 1 if it was committed; 0 to 1 progress through your finale |
| `emerge` | 0 to 1 fade in/out of the whole thing |

Functions: `sin cos tan atan2 abs min max clamp smoothstep mix pow sqrt exp floor ceil round fract sign step tri saw noise rand`.
Operators: `+ - * / % ^`, comparisons, `&& || !` and `cond ? a : b`. Constants: `pi tau e`.
`rand(i)` and `noise(x)` are deterministic, so animations are repeatable.

### Limits (enforced, with clear error messages)

48 layers; 300 copies per shape layer and 700 in total; 160 points per path; 12 parameters; 400 characters and 240 nodes per
formula; images PNG/JPEG only, each under 4 MB; a whole pack under 12 MB zipped, 24 MB unzipped, 200 files.

## Sharing: best practices

**Format.** Version everything (`format`, `version`, and later `minApp`), keep the spec small and stable, and never add
a feature that needs code. New capabilities become new layer types with a bumped `format`.

**Distribution.** Host static files on your site or any object store: no server code needed.

```
https://your-site/twang/library.json        the index
https://your-site/twang/packs/<id>-<version>.twangpack
https://your-site/twang/previews/<id>.png   (and later a short GIF/MP4)
```

`library.json` (see `docs/library-example/library.json`):

```json
{ "format": 1, "packs": [
  { "id": "confetti-cannon", "name": "Confetti Cannon", "author": "Twang", "version": "1.0.0",
    "tagline": "...", "download": "https://.../confetti-cannon-1.0.0.twangpack",
    "sha256": "<hex digest of the .twangpack>", "size": 1234 } ] }
```

Twang fetches the index only when someone presses **Refresh**, requires `https`, checks every download against its
`sha256`, rejects anything over the size limits, and validates the pack before installing it. There is no telemetry.

Make a pack file and its checksum:

```bash
cd my-pack && zip -r ../my-pack-1.0.0.twangpack . -x '.*' && shasum -a 256 ../my-pack-1.0.0.twangpack
```

**Curation.** Accept submissions as pull requests to a repo that holds the packs; a CI job runs `--validate-pack`
on each, builds the zips and `library.json` (with checksums) and publishes them to the site. Require a `license`
and `author`, and a preview image. Because packs are data, review is mostly "does it look good and is it appropriate".

**Trust, later.** If the library grows, sign `library.json` with an Ed25519 key whose public half ships in the app,
so a compromised host cannot swap packs. The sha256 per pack already stops tampering in transit.

**Authoring tools (a staged plan).**
1. *Done:* hot-reload of the packs folder, validation errors in the Library tab, a template, and the CLI validator.
2. *Next:* a static web editor on your site: the formula engine is ~300 lines and the renderer is a small canvas
   routine, so both are easy to port to JavaScript; it can show a live preview with the same sliders and export a `.twangpack`.
3. *Later:* an in-app visual editor (layer list, formula fields with autocomplete, scrub bar for `pull`/`tr`).

**Quality bar for the library.** Respect the person's theme (`@a/@b/@c`), keep `emerge` in the alpha so it fades in and out,
make the finale fit the concept (not everything should bounce), and test at small and large `chord`.
