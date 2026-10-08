import PluckCore
import XCTest

final class ModifierTriggerTests: XCTestCase {
    func testOptionArmsOnlyOnExactOption() {
        XCTAssertTrue(ModifierTrigger.option.shouldArm(held: .option))
        XCTAssertFalse(ModifierTrigger.option.shouldArm(held: [.option, .command]))
        XCTAssertFalse(ModifierTrigger.option.shouldArm(held: []))
        XCTAssertFalse(ModifierTrigger.option.shouldArm(held: .shift))
    }

    func testHyperNeedsAllFour() {
        XCTAssertTrue(ModifierTrigger.hyper.shouldArm(held: .hyper))
        XCTAssertFalse(ModifierTrigger.hyper.shouldArm(held: [.control, .option, .command]))
        XCTAssertFalse(ModifierTrigger.hyper.shouldArm(held: .option))
    }

    func testContinuesWithExtraModifiersEndsWhenRequiredReleased() {
        XCTAssertTrue(ModifierTrigger.option.shouldContinue(held: [.option, .shift]))
        XCTAssertFalse(ModifierTrigger.option.shouldContinue(held: .shift))
        XCTAssertTrue(ModifierTrigger.hyper.shouldContinue(held: .hyper))
        XCTAssertFalse(ModifierTrigger.hyper.shouldContinue(held: [.control, .option, .shift]))
    }

    func testOffNeverArms() {
        XCTAssertFalse(ModifierTrigger.off.shouldArm(held: []))
        XCTAssertFalse(ModifierTrigger.off.shouldContinue(held: .hyper))
    }

    func testStillnessOnlyForOption() {
        XCTAssertTrue(ModifierTrigger.option.requiresStillness)
        XCTAssertFalse(ModifierTrigger.hyper.requiresStillness)
    }
}
