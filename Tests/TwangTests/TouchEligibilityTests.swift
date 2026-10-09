import TwangCore
import XCTest

final class TouchEligibilityTests: XCTestCase {
    func testDeliberateLandingArms() {
        var e = TouchEligibility()
        e.countChanged(1, at: 0.00)
        e.countChanged(2, at: 0.04)
        e.countChanged(3, at: 0.09)
        XCTAssertTrue(e.canArm(at: 0.5))
    }

    func testThirdContactJoiningRestingTwoFingersIsRejected() {
        var e = TouchEligibility()
        e.countChanged(1, at: 0.00)
        e.countChanged(2, at: 0.05)
        e.countChanged(3, at: 0.60) // a thumb or palm landing late
        XCTAssertFalse(e.canArm(at: 1.5))
    }

    func testRejectionClearsOnceThePadIsEmpty() {
        var e = TouchEligibility()
        e.countChanged(1, at: 0); e.countChanged(2, at: 0.05); e.countChanged(3, at: 0.6)
        XCTAssertFalse(e.canArm(at: 1))
        e.countChanged(0, at: 1.2)
        e.countChanged(1, at: 2.0); e.countChanged(2, at: 2.03); e.countChanged(3, at: 2.06)
        XCTAssertTrue(e.canArm(at: 2.5))
    }

    func testFourContactsDisqualifyUntilEmpty() {
        var e = TouchEligibility()
        e.countChanged(1, at: 0); e.countChanged(2, at: 0.02); e.countChanged(3, at: 0.04); e.countChanged(4, at: 0.06)
        e.countChanged(3, at: 0.1)
        XCTAssertFalse(e.canArm(at: 1))
    }

    func testRecentScrollBlocksArming() {
        var e = TouchEligibility()
        e.countChanged(1, at: 0); e.countChanged(2, at: 0.02); e.countChanged(3, at: 0.04)
        e.scrolled(at: 0.3)
        XCTAssertFalse(e.canArm(at: 0.5))
        XCTAssertTrue(e.canArm(at: 0.7))
    }

    func testNeedsExactlyThree() {
        var e = TouchEligibility()
        e.countChanged(1, at: 0); e.countChanged(2, at: 0.02)
        XCTAssertFalse(e.canArm(at: 1))
    }
}
