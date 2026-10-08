import CoreGraphics
import PluckCore
import XCTest

final class LabelLayoutTests: XCTestCase {
    func testNorthIsUpInViewSpace() {
        let pin = CGPoint(x: 500, y: 500)
        let c = LabelLayout.center(pin: pin, role: .north)
        XCTAssertGreaterThan(c.y, pin.y)           // y-up view space
        XCTAssertEqual(c.x, pin.x, accuracy: 0.001)
        XCTAssertLessThan(LabelLayout.center(pin: pin, role: .south).y, pin.y)
        XCTAssertGreaterThan(LabelLayout.center(pin: pin, role: .east).x, pin.x)
        XCTAssertLessThan(LabelLayout.center(pin: pin, role: .west).x, pin.x)
    }

    func testClampKeepsLabelOnScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 100, height: 40)
        let p = LabelLayout.clamped(center: CGPoint(x: 990, y: 5), size: size, in: bounds, margin: 12)
        XCTAssertEqual(p.x, 1000 - 12 - 50, accuracy: 0.001)
        XCTAssertEqual(p.y, 12 + 20, accuracy: 0.001)
        let inside = LabelLayout.clamped(center: CGPoint(x: 400, y: 400), size: size, in: bounds)
        XCTAssertEqual(inside, CGPoint(x: 400, y: 400))
    }

    func testClampHandlesTinyBounds() {
        let p = LabelLayout.clamped(center: .zero, size: CGSize(width: 100, height: 100),
                                    in: CGRect(x: 0, y: 0, width: 50, height: 50))
        XCTAssertEqual(p, CGPoint(x: 25, y: 25))
    }
}
