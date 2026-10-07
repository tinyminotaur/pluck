import CoreGraphics
import PluckCore
import XCTest

final class GestureMathTests: XCTestCase {
    let pin = CGPoint(x: 100, y: 100)
    let all = CompassRole.allCases

    func testDeadZoneCancels() {
        let near = CGPoint(x: 110, y: 105)
        XCTAssertNil(GestureMath.roleAtRelease(pin: pin, pointer: near, available: all))
        XCTAssertNil(GestureMath.capture(pin: pin, pointer: near, available: all, current: nil))
    }

    func testEastRelease() {
        let east = CGPoint(x: 200, y: 100)
        XCTAssertEqual(GestureMath.roleAtRelease(pin: pin, pointer: east, available: all), .east)
    }

    func testNorthRelease() {
        // Screen coords: y down, so north is smaller y.
        let north = CGPoint(x: 100, y: 20)
        XCTAssertEqual(GestureMath.roleAtRelease(pin: pin, pointer: north, available: all), .north)
    }

    func testWestRelease() {
        let west = CGPoint(x: 20, y: 100)
        XCTAssertEqual(GestureMath.roleAtRelease(pin: pin, pointer: west, available: all), .west)
    }

    func testSouthRelease() {
        let south = CGPoint(x: 100, y: 200)
        XCTAssertEqual(GestureMath.roleAtRelease(pin: pin, pointer: south, available: all), .south)
    }

    func testStretchGain() {
        let pointer = CGPoint(x: 140, y: 100)
        let head = GestureMath.stretchedHead(pin: pin, pointer: pointer)
        XCTAssertEqual(head.x, 100 + 40 * GestureMath.stretchGain, accuracy: 0.01)
        XCTAssertEqual(head.y, 100, accuracy: 0.01)
    }

    func testHysteresisHoldsCurrent() {
        // Capture east, then move slightly toward south — should stay east.
        let east = CGPoint(x: 180, y: 100)
        let captured = GestureMath.capture(pin: pin, pointer: east, available: all, current: nil)
        XCTAssertEqual(captured, .east)

        let slightlySouth = CGPoint(x: 170, y: 130)
        let held = GestureMath.capture(pin: pin, pointer: slightlySouth, available: all, current: .east)
        XCTAssertEqual(held, .east)
    }

    func testAvailableSubset() {
        let onlyNS: [CompassRole] = [.north, .south]
        let eastish = CGPoint(x: 200, y: 100)
        // Nearest among available is north or south depending on angle; east angle → closest of N/S is ambiguous near horizontal.
        // Straight east is equidistant in angle to N and S? No — east is 0°, north -90, south 90 — equidistant.
        // min(by:) is stable-ish; just assert it's one of the available.
        let role = GestureMath.roleAtRelease(pin: pin, pointer: eastish, available: onlyNS)
        XCTAssertTrue(role == .north || role == .south)
    }

    func testDeadZoneHysteresisKeepsRoleNearPin() {
        // Between deadZoneExit and deadZone: armed only if already captured.
        let near = CGPoint(x: 100 + (GestureMath.deadZone + GestureMath.deadZoneExit) / 2, y: 100)
        XCTAssertNil(GestureMath.capture(pin: pin, pointer: near, available: all, current: nil))
        XCTAssertEqual(GestureMath.capture(pin: pin, pointer: near, available: all, current: .east), .east)
        let inside = CGPoint(x: 100 + GestureMath.deadZoneExit - 1, y: 100)
        XCTAssertNil(GestureMath.capture(pin: pin, pointer: inside, available: all, current: .east))
    }

    func testAngularHysteresisHoldsPastBoundary() {
        // 50° below east is nearer south (45° boundary) but within the hysteresis band.
        let a: CGFloat = 50 * .pi / 180
        let p = CGPoint(x: 100 + 150 * cos(a), y: 100 + 150 * sin(a))
        XCTAssertEqual(GestureMath.capture(pin: pin, pointer: p, available: all, current: .east), .east)
        XCTAssertEqual(GestureMath.capture(pin: pin, pointer: p, available: all, current: nil), .south)
        // Well past the band, it switches.
        let b: CGFloat = 70 * .pi / 180
        let q = CGPoint(x: 100 + 150 * cos(b), y: 100 + 150 * sin(b))
        XCTAssertEqual(GestureMath.capture(pin: pin, pointer: q, available: all, current: .east), .south)
    }

    func testReleaseMatchesCapturedRole() {
        let a: CGFloat = 50 * .pi / 180
        let p = CGPoint(x: 100 + 150 * cos(a), y: 100 + 150 * sin(a))
        XCTAssertEqual(
            GestureMath.roleAtRelease(pin: pin, pointer: p, available: all, current: .east),
            .east
        )
    }

    func testDampingIsFrameRateIndependent() {
        let perFrame: CGFloat = 0.93
        let at60 = pow(GestureMath.damping(perFrame, dt: 1.0 / 60), 60)
        let at120 = pow(GestureMath.damping(perFrame, dt: 1.0 / 120), 120)
        XCTAssertEqual(at60, at120, accuracy: 1e-6)
        XCTAssertEqual(GestureMath.damping(perFrame, dt: 1.0 / 60), perFrame, accuracy: 1e-6)
        XCTAssertEqual(GestureMath.smoothingAlpha(retain: 0.55, dt: 1.0 / 60), 0.45, accuracy: 1e-6)
    }

    func testExcludeListDefaults() {
        XCTAssertTrue(ExcludeList.defaultExcludes.contains("com.valvesoftware.steam"))
    }
}
