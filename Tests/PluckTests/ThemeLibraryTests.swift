import PluckCore
import XCTest

final class ThemeLibraryTests: XCTestCase {
    func testEveryThemeIsValidAndIdsAreUnique() {
        XCTAssertGreaterThanOrEqual(ThemeLibrary.all.count, 9)
        XCTAssertEqual(Set(ThemeLibrary.all.map(\.id)).count, ThemeLibrary.all.count)
        for t in ThemeLibrary.all { XCTAssertTrue(t.isValid, t.id) }
    }

    func testPaletteIsCyclicAndContinuous() {
        for t in ThemeLibrary.all {
            // Wraps seamlessly, and no jumps along the cycle.
            let start = t.color(at: 0), end = t.color(at: 0.99999)
            XCTAssertEqual(start.r, end.r, accuracy: 0.01, t.id)
            var prev = t.color(at: 0)
            for i in 1...300 {
                let c = t.color(at: Float(i) / 300)
                XCTAssertLessThan(abs(c.r - prev.r) + abs(c.g - prev.g) + abs(c.b - prev.b), 0.2, "\(t.id) at \(i)")
                prev = c
            }
            // The three stops are hit exactly.
            XCTAssertEqual(t.color(at: 1.0 / 3).g, t.b.g, accuracy: 1e-4, t.id)
        }
    }

    func testPresetsReferenceRealThemesAndKnobs() {
        XCTAssertEqual(Set(PresetLibrary.all.map(\.id)).count, PresetLibrary.all.count)
        for p in PresetLibrary.all {
            XCTAssertNotNil(ThemeLibrary.theme(id: p.themeID), "\(p.id) theme")
            for (k, v) in p.values {
                XCTAssertNotNil(PresetLibrary.baseline[k], "\(p.id) uses unknown knob \(k)")
                XCTAssertTrue(v.isFinite)
            }
            XCTAssertEqual(PresetLibrary.resolvedValues(p).count, PresetLibrary.baseline.count)
        }
    }

    func testStyledPresetsAreRealAndUseTheirStyle() {
        XCTAssertEqual(Set(PresetLibrary.everything.map(\.id)).count, PresetLibrary.everything.count)
        for p in PresetLibrary.styled {
            XCTAssertNotEqual(p.style, .liquid, p.id)
            XCTAssertNotNil(ThemeLibrary.theme(id: p.themeID), p.id)
            for k in p.values.keys { XCTAssertNotNil(PresetLibrary.baseline[k], "\(p.id) unknown knob \(k)") }
        }
        XCTAssertTrue(PresetLibrary.styled.contains { $0.style == .ferro })
        XCTAssertTrue(PresetLibrary.styled.contains { $0.style == .crystal })
        XCTAssertNotNil(PresetLibrary.preset(id: "frost"))
    }

    func testPresetsAreMeaningfullyDifferent() {
        // Each preset (besides the default) changes several knobs and feels different from the others.
        for p in PresetLibrary.all where p.id != "obsidian-ember" {
            XCTAssertGreaterThanOrEqual(p.values.count, 6, p.id)
        }
        let magnet = Set(PresetLibrary.all.compactMap { PresetLibrary.resolvedValues($0)["magnetPull"] })
        XCTAssertGreaterThanOrEqual(magnet.count, 6)
    }

    func testRandomThemeIsValidDeterministicAndVaried() {
        XCTAssertEqual(ThemeLibrary.random(seed: 5), ThemeLibrary.random(seed: 5))
        XCTAssertNotEqual(ThemeLibrary.random(seed: 5), ThemeLibrary.random(seed: 6))
        for s in UInt64(0)..<200 {
            let t = ThemeLibrary.random(seed: s)
            XCTAssertTrue(t.isValid, "seed \(s)")
            // The body stays dark so the glass reads as dark glass with colour at the edges.
            XCTAssertLessThan(t.body.r + t.body.g + t.body.b, 0.5)
        }
    }

    func testThemeRoundTripsThroughJSON() throws {
        let t = ThemeLibrary.random(seed: 42)
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(LiquidTheme.self, from: data), t)
    }
}
