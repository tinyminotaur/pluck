import Foundation

/// Example packs that ship with the app, and the template for new ones. They double as documentation.
enum PackExamples {
    static let readme = """
    # Your Twang animation

    Edit `pack.json` and save: Twang reloads it automatically (open Settings > Library to see any errors).

    - `layers` are drawn in order. Types: `path`, `shape`, `text`, `image`.
    - Any number can be a plain value or an expression such as `"sin(s*10 - t*4) * 20 * pull"`.
    - Variables: t (seconds), s/u (0 to 1 along a path or across instances), i, n, chord (distance between the points),
      angle, pull (0 to 1 as you stretch), pinR/headR (the two ends' sizes), mass (pin's share of the mass), speed,
      charge (0 to 1 while you hold), fired (1 after release), tr (release progress 0 to 1), commit (1 if committed), emerge.
    - Functions: sin cos tan abs min max clamp smoothstep mix pow sqrt floor fract sign noise rand tri atan2 exp step round ceil saw.
    - Colours: "#rrggbb", "#rrggbbaa", the theme colours "@a" "@b" "@c" "@body", or {"h": expr, "s": 0.8, "v": 1}.
    - `space`: "span" (origin at the pin, x along the span), "head" (origin at the head), "screen".
    - `params` become sliders in the Library tab.

    Full guide: docs/PACKS.md in the Twang repository.
    """

    static func template(id: String) -> String {
        """
        {
          "format": 1,
          "id": "\(id)",
          "name": "My Animation",
          "version": "0.1.0",
          "author": "You",
          "license": "CC-BY-4.0",
          "tagline": "A glowing line with orbiting sparks",
          "params": [
            { "name": "wiggle", "label": "Wiggle", "default": 0.6, "min": 0, "max": 1 }
          ],
          "release": { "duration": 0.8, "behavior": "stay" },
          "layers": [
            { "type": "path", "count": 48, "along": "s * chord",
              "offset": "sin(s * 9 - t * 4) * 16 * wiggle * pull * sin(s * pi)",
              "width": "3 + 3 * mass", "color": { "h": "s * 0.3 + t * 0.05", "s": 0.7, "v": 1 },
              "glow": 8, "alpha": "pull * (1 - tr)" },
            { "type": "shape", "shape": "spark", "count": 14, "along": "u * chord",
              "offset": "sin(i * 1.7 + t * 3) * 26 * pull",
              "size": "5 + 5 * rand(i)", "rotation": "t + i", "color": "@c", "glow": 6,
              "alpha": "pull * (0.5 + 0.5 * sin(t * 4 + i)) * (1 - tr)" },
            { "type": "shape", "shape": "circle", "space": "screen", "along": 0, "offset": 0,
              "size": "pinR * 0.8", "color": "@a", "alpha": "1 - tr" },
            { "type": "shape", "shape": "ring", "space": "head", "size": "headR * 1.3 + 3 * sin(t * 5)",
              "color": "#ffffff", "strokeWidth": 2, "alpha": "0.7 * pull * (1 - tr)" }
          ]
        }
        """
    }

    static let builtIn: [(String, String)] = [
        ("heartbeat-line", """
        {
          "format": 1, "id": "heartbeat-line", "name": "Heartbeat Line", "version": "1.0.0", "author": "Twang", "license": "CC0-1.0",
          "tagline": "A neon pulse trace runs between the points",
          "theme": "aurora",
          "params": [ { "name": "rate", "label": "Heart rate", "default": 0.9, "min": 0.3, "max": 2 } ],
          "release": { "duration": 0.7, "behavior": "stay" },
          "layers": [
            { "type": "path", "count": 140, "along": "s * chord",
              "offset": "pull * (30 * exp(-pow((fract(s * 2.5 - t * rate) - 0.32) * 26, 2)) - 12 * exp(-pow((fract(s * 2.5 - t * rate) - 0.38) * 34, 2)) + 5 * exp(-pow((fract(s * 2.5 - t * rate) - 0.55) * 9, 2)))",
              "width": 3, "color": "#7dffb0", "glow": 10, "alpha": "1 - tr" },
            { "type": "path", "count": 2, "along": "s * chord", "width": 1, "color": "#7dffb055", "dash": [4, 8], "alpha": "pull * (1 - tr)" },
            { "type": "shape", "shape": "circle", "size": "pinR * 0.7 * (1 + 0.15 * sin(t * rate * 6.28))", "space": "screen", "color": "#7dffb0", "glow": 14, "alpha": "1 - tr" },
            { "type": "shape", "shape": "circle", "size": "headR * 0.7 * (1 + 0.15 * sin(t * rate * 6.28 + 1))", "space": "head", "color": "#7dffb0", "glow": 14, "alpha": "1 - tr" }
          ]
        }
        """),
        ("confetti-cannon", """
        {
          "format": 1, "id": "confetti-cannon", "name": "Confetti Cannon", "version": "1.0.0", "author": "Twang", "license": "CC0-1.0",
          "tagline": "A cannon at the pin fires streams of confetti toward the target",
          "theme": "neon-jelly",
          "params": [ { "name": "spread", "label": "Spread", "default": 0.7, "min": 0.1, "max": 1.5 } ],
          "release": { "duration": 1.2, "behavior": "stay" },
          "layers": [
            { "type": "shape", "shape": "rect", "count": 90, "along": "chord * pull * fract(t * 0.6 + u * 3 + rand(i))",
              "offset": "(rand(i + 7) - 0.5) * 120 * spread * fract(t * 0.6 + u * 3 + rand(i)) + sin(t * 6 + i) * 6 + (fired * tr * (rand(i + 3) - 0.5) * 260)",
              "size": "5 + 3 * rand(i + 2)", "size2": "2.5", "rotation": "t * 5 + i * 2",
              "color": { "h": "rand(i + 11)", "s": 0.75, "v": 1 }, "alpha": "pull * (1 - fract(t * 0.6 + u * 3 + rand(i))) * (1 - tr)" },
            { "type": "shape", "shape": "circle", "space": "screen", "size": "pinR * 0.8", "color": "@a", "alpha": "1 - tr" },
            { "type": "shape", "shape": "star", "space": "head", "count": 3, "size": "headR * (0.5 + 0.3 * sin(t * 6 + i * 2))", "rotation": "t * (1 + i)", "color": "@c", "alpha": "pull * (1 - tr)" }
          ]
        }
        """),
        ("orbit-ribbons", """
        {
          "format": 1, "id": "orbit-ribbons", "name": "Orbit Ribbons", "version": "1.0.0", "author": "Twang", "license": "CC0-1.0",
          "tagline": "Colourful ribbons and stars weave around the span",
          "theme": "oil-slick",
          "params": [ { "name": "wiggle", "label": "Wiggle", "default": 0.6, "min": 0, "max": 1 } ],
          "release": { "duration": 0.7, "behavior": "stay" },
          "layers": [
            { "type": "path", "count": 60, "along": "s * chord", "offset": "sin(s * 10 - t * 4) * 22 * wiggle * pull * sin(s * pi)", "width": "3 + 2 * mass",
              "color": { "h": "t * 0.05", "s": 0.7, "v": 1 }, "glow": 8, "alpha": "pull * (1 - tr)" },
            { "type": "path", "count": 60, "along": "s * chord", "offset": "sin(s * 10 - t * 4 + pi) * 22 * wiggle * pull * sin(s * pi)", "width": "2 + mass",
              "color": { "h": "t * 0.05 + 0.5", "s": 0.7, "v": 1 }, "glow": 8, "alpha": "pull * (1 - tr)" },
            { "type": "shape", "shape": "star", "count": 12, "along": "u * chord", "offset": "sin(i * 1.7 + t * 3) * 34 * pull", "size": "6 + 5 * rand(i)", "rotation": "t + i",
              "color": "@c", "glow": 6, "alpha": "pull * (1 - tr)" },
            { "type": "shape", "shape": "ring", "space": "head", "size": "headR * 1.5 + 4 * sin(t * 5)", "color": "#ffffff", "alpha": "0.6 * pull * (1 - tr)" }
          ]
        }
        """),
    ]
}
