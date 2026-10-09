import TwangCore
import XCTest

final class PackExpressionTests: XCTestCase {
    private let vars = ["t": 0, "x": 1, "chord": 2]

    private func v(_ src: String, _ env: [Double] = [2, 3, 100]) throws -> Double { try PackExpression(src, variables: vars).eval(env) }

    func testArithmeticAndPrecedence() throws {
        XCTAssertEqual(try v("1 + 2 * 3"), 7)
        XCTAssertEqual(try v("(1 + 2) * 3"), 9)
        XCTAssertEqual(try v("2 ^ 3 ^ 2"), 512, accuracy: 1e-9)       // right-associative
        XCTAssertEqual(try v("-x + 5"), 2)
        XCTAssertEqual(try v("10 % 4"), 2)
        XCTAssertEqual(try v("t * x"), 6)
    }

    func testFunctionsAndConstants() throws {
        XCTAssertEqual(try v("sin(pi / 2)"), 1, accuracy: 1e-9)
        XCTAssertEqual(try v("clamp(chord, 0, 50)"), 50)
        XCTAssertEqual(try v("mix(0, 10, 0.25)"), 2.5, accuracy: 1e-9)
        XCTAssertEqual(try v("smoothstep(0, 10, 5)"), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try v("max(1, 2) + min(5, 4)"), 6)
        XCTAssertEqual(try v("fract(2.75)"), 0.75, accuracy: 1e-9)
        let n = try v("noise(1.5)"); XCTAssertTrue(n >= 0 && n <= 1)
        XCTAssertEqual(try v("rand(7)"), try v("rand(7)"))                // deterministic
    }

    func testComparisonsLogicAndTernary() throws {
        XCTAssertEqual(try v("x > 2 ? 10 : 20"), 10)
        XCTAssertEqual(try v("t == 2 && x == 3"), 1)
        XCTAssertEqual(try v("t == 9 || x == 3"), 1)
        XCTAssertEqual(try v("!(x > 5)"), 1)
        XCTAssertEqual(try v("x != 3"), 0)
        XCTAssertEqual(try v("x <= 3"), 1)
    }

    func testRejectsAnythingUnsafeOrUnknown() {
        XCTAssertThrowsError(try v("secret + 1"))
        XCTAssertThrowsError(try v("system(1)"))
        XCTAssertThrowsError(try v("sin(1, 2)"))
        XCTAssertThrowsError(try v("1 +"))
        XCTAssertThrowsError(try v("1 ; 2"))
        XCTAssertThrowsError(try v(String(repeating: "1+", count: 300) + "1"))
        XCTAssertThrowsError(try v(String(repeating: "(", count: 20) + "1" + String(repeating: ")", count: 20) + String(repeating: "+1", count: 200)))
    }

    func testNeverReturnsNonFinite() throws {
        XCTAssertEqual(try v("1 / 0"), 0)
        XCTAssertEqual(try v("sqrt(-4)"), 0)
        XCTAssertTrue(try v("exp(1000)").isFinite)
        XCTAssertTrue(try v("10 ^ 999").isFinite)
    }
}
