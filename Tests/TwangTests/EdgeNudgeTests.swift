import CoreGraphics
import TwangCore
import XCTest

final class EdgeNudgeTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testInteriorPointIsUntouched() {
        let p = CGPoint(x: 700, y: 400)
        XCTAssertEqual(EdgeNudge.inset(p, in: screen), p)
    }

    func testLeftEdgeIsNudgedInward() {
        let p = EdgeNudge.inset(CGPoint(x: 0, y: 400), in: screen)
        XCTAssertEqual(p.x, EdgeNudge.defaultMargin, accuracy: 0.001)
        XCTAssertEqual(p.y, 400, accuracy: 0.001)
    }

    func testCornerIsNudgedOnBothAxes() {
        let p = EdgeNudge.inset(CGPoint(x: 1440, y: 900), in: screen)
        XCTAssertEqual(p.x, 1440 - EdgeNudge.defaultMargin, accuracy: 0.001)
        XCTAssertEqual(p.y, 900 - EdgeNudge.defaultMargin, accuracy: 0.001)
    }

    func testOffsetScreenFrames() {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let p = EdgeNudge.inset(CGPoint(x: 1441, y: -199), in: second)
        XCTAssertEqual(p.x, 1440 + EdgeNudge.defaultMargin, accuracy: 0.001)
        XCTAssertEqual(p.y, -200 + EdgeNudge.defaultMargin, accuracy: 0.001)
    }

    func testTinyScreenCenters() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(EdgeNudge.inset(CGPoint(x: 5, y: 5), in: tiny), CGPoint(x: 50, y: 50))
    }
}
