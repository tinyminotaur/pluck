import CoreGraphics
import PluckCore
import XCTest

final class HoldArmTests: XCTestCase {
    func testReadyAfterHoldWithoutMoving() {
        var arm = HoldArm(holdSeconds: 0.2, moveTolerance: 8)
        arm.press(at: CGPoint(x: 100, y: 100), time: 10)
        XCTAssertFalse(arm.isReady(at: 10.1))
        arm.move(to: CGPoint(x: 103, y: 102)) // jitter within tolerance
        XCTAssertTrue(arm.isReady(at: 10.25))
    }

    func testMovingBeyondToleranceBreaksTheHold() {
        var arm = HoldArm(holdSeconds: 0.2, moveTolerance: 8)
        arm.press(at: .zero, time: 0)
        arm.move(to: CGPoint(x: 20, y: 0))
        XCTAssertTrue(arm.wasBroken)
        XCTAssertFalse(arm.isReady(at: 1))
        // Coming back does not un-break it: that press was an ordinary drag.
        arm.move(to: .zero)
        XCTAssertFalse(arm.isReady(at: 1))
    }

    func testReleaseResets() {
        var arm = HoldArm()
        arm.press(at: .zero, time: 0)
        arm.release()
        XCTAssertFalse(arm.isPressed)
        XCTAssertFalse(arm.isReady(at: 5))
        arm.press(at: .zero, time: 6)
        XCTAssertFalse(arm.wasBroken)
    }
}
