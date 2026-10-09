import CoreGraphics
import PluckCore
import XCTest

final class PackTests: XCTestCase {
    static let example = """
    {
      "format": 1, "id": "test.orbit-ribbons", "name": "Orbit Ribbons", "version": "1.0.0", "author": "Tester", "license": "CC0-1.0",
      "tagline": "Ribbons orbiting the span",
      "params": [ { "name": "wiggle", "label": "Wiggle", "default": 0.5, "min": 0, "max": 1 } ],
      "release": { "duration": 0.6, "behavior": "stay" },
      "layers": [
        { "type": "path", "count": 40, "along": "s*chord", "offset": "sin(s*10 - t*4)*20*wiggle*pull",
          "width": "3 + 2*mass", "color": { "h": "s*0.3 + t*0.05", "s": 0.7, "v": 1 }, "glow": 6, "alpha": "pull" },
        { "type": "shape", "shape": "star", "count": 12, "along": "u*chord", "offset": "sin(i*1.7 + t*3)*30*pull",
          "size": "6 + 5*rand(i)", "rotation": "t + i", "color": "@c", "alpha": "pull * (1 - tr)" },
        { "type": "shape", "shape": "ring", "space": "head", "size": "headR*1.6 + 4*sin(t*5)", "color": "#ffffff", "alpha": "0.6*pull", "visible": "pull > 0.05" },
        { "type": "text", "text": "{chord} px", "along": "chord/2", "offset": 24, "fontSize": 12, "color": "#ffffffcc" }
      ]
    }
    """

    func compile(_ json: String) -> (PackProgram?, [PackIssue]) {
        let (m, issues) = PackDecoder.decode(Data(json.utf8))
        guard let m else { return (nil, issues) }
        return PackProgram.compile(m)
    }

    func testExamplePackCompilesAndDraws() throws {
        let (prog, issues) = compile(Self.example)
        XCTAssertTrue(issues.isEmpty, "\(issues)")
        var sim = PackSim(); sim.program = prog; sim.theme = ["@a": PackRGBA(r: 1, g: 0.5, b: 0.1, a: 1), "@c": PackRGBA(r: 1, g: 0.7, b: 0.2, a: 1)]
        sim.reset(pin: CGPoint(x: 100, y: 100))
        for i in 0..<300 { sim.step(dt: 1 / 120, pin: CGPoint(x: 100, y: 100), head: CGPoint(x: 100 + min(400, CGFloat(i) * 8), y: 140)) }
        let ops = sim.evaluate(emerge: 1)
        var paths = 0, shapes = 0, texts = 0
        for op in ops {
            switch op {
            case .path(let pts, let c, let w, _, _, _, _, _): paths += 1; XCTAssertEqual(pts.count, 40); XCTAssertTrue(pts.allSatisfy { $0.x.isFinite && $0.y.isFinite }); XCTAssertTrue(c.a > 0.5); XCTAssertGreaterThan(w, 3)
            case .shape(_, let p, _, _, _, _, _, _, _): shapes += 1; XCTAssertTrue(p.x.isFinite && p.y.isFinite)
            case .text(let s, _, _, _, _): texts += 1; XCTAssertTrue(s.hasSuffix(" px"))
            case .image: break
            }
        }
        XCTAssertEqual(paths, 1); XCTAssertEqual(shapes, 13); XCTAssertEqual(texts, 1)
    }

    func testReleaseRunsTheFinale() {
        let (prog, _) = compile(Self.example)
        var sim = PackSim(); sim.program = prog
        sim.reset(pin: .zero)
        for i in 0..<200 { sim.step(dt: 1 / 120, pin: .zero, head: CGPoint(x: min(300, CGFloat(i) * 6), y: 0)) }
        XCTAssertFalse(sim.isFinished)
        sim.release(commit: CGPoint(x: 1, y: 0))
        for _ in 0..<40 { sim.step(dt: 1 / 120, pin: .zero, head: CGPoint(x: 300, y: 0)) }
        XCTAssertTrue(sim.frame(emerge: 1).committed)
        XCTAssertGreaterThan(sim.frame(emerge: 1).tr, 0.4)
        for _ in 0..<60 { sim.step(dt: 1 / 120, pin: .zero, head: CGPoint(x: 300, y: 0)) }
        XCTAssertTrue(sim.isFinished)
    }

    func testBadPacksAreRejectedWithClearMessages() {
        func issues(_ s: String) -> [PackIssue] { compile(s).1 }
        XCTAssertFalse(issues(#"{"format":2,"id":"a","name":"A","layers":[{"type":"shape"}]}"#).isEmpty)
        XCTAssertTrue(issues(#"{"format":1,"id":"bad id!","name":"A","layers":[{"type":"shape"}]}"#).contains { $0.where_ == "id" })
        XCTAssertTrue(issues(#"{"format":1,"id":"a","name":"A","layers":[]}"#).contains { $0.where_ == "layers" })
        XCTAssertTrue(issues(#"{"format":1,"id":"a","name":"A","layers":[{"type":"shape","size":"nope + 1"}]}"#).contains { $0.message.contains("unknown variable") })
        XCTAssertTrue(issues(#"{"format":1,"id":"a","name":"A","layers":[{"type":"shape","size":"system(1)"}]}"#).contains { $0.message.contains("unknown function") })
        XCTAssertTrue(issues(#"{"format":1,"id":"a","name":"A","layers":[{"type":"shape","count":9999}]}"#).contains { $0.where_.hasSuffix("count") })
        XCTAssertTrue(issues(#"{"format":1,"id":"a","name":"A","layers":[{"type":"shape","color":"red"}]}"#).contains { $0.where_.hasSuffix("color") })
        XCTAssertTrue(issues(#"{"format":1,"id":"a","name":"A","layers":[{"type":"image","asset":"../../etc/passwd"}]}"#).contains { $0.where_.hasSuffix("asset") })
        XCTAssertTrue(issues(#"{"format":1,"id":"a","name":"A","layers":[{"type":"wat"}]}"#).contains { $0.where_.hasSuffix("type") })
        XCTAssertTrue(issues("{ not json").first?.where_ == "pack.json")
        // Too many shapes overall.
        let many = (0..<5).map { _ in #"{"type":"shape","count":200}"# }.joined(separator: ",")
        XCTAssertTrue(issues(#"{"format":1,"id":"a","name":"A","layers":[\#(many)]}"#).contains { $0.message.contains("too many") })
    }

    func testPacksOnlyReadTheirOwnParametersAndCannotEscape() {
        // Unknown names fail, parameters work, and nothing else is reachable.
        let ok = #"{"format":1,"id":"a","name":"A","params":[{"name":"k","default":2,"min":0,"max":5}],"layers":[{"type":"shape","size":"5*k"}]}"#
        let (prog, issues) = compile(ok)
        XCTAssertTrue(issues.isEmpty)
        var f = PackFrame(); f.emerge = 1; f.params = ["k": 4]
        guard case .shape(_, _, let size, _, _, _, _, _, _)? = prog?.evaluate(f).first else { return XCTFail("no shape") }
        XCTAssertEqual(size, 20, accuracy: 0.01)
    }
}
