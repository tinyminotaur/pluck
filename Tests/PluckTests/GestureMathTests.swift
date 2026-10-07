import CoreGraphics
import PluckCore
import XCTest

final class GestureMathTests: XCTestCase {
    let pin = CGPoint(x: 100, y: 100)
    let all = CompassRole.allCases

    private func tracker(_ available: [CompassRole] = CompassRole.allCases) -> GestureTracker {
        GestureTracker(pin: pin, available: available)
    }

    // y is UP in AppKit screen space: north is a larger y.
    func testDirectionsAreYUp() {
        var t = tracker()
        XCTAssertEqual(t.update(pointer: CGPoint(x: 100, y: 200)), .north)
        t = tracker()
        XCTAssertEqual(t.update(pointer: CGPoint(x: 100, y: 0)), .south)
        t = tracker()
        XCTAssertEqual(t.update(pointer: CGPoint(x: 200, y: 100)), .east)
        t = tracker()
        XCTAssertEqual(t.update(pointer: CGPoint(x: 0, y: 100)), .west)
    }

    func testCompassUnitVectorsAreYUp() {
        XCTAssertEqual(CompassRole.north.unit.y, 1, accuracy: 1e-6)
        XCTAssertEqual(CompassRole.south.unit.y, -1, accuracy: 1e-6)
        XCTAssertEqual(CompassRole.east.unit.x, 1, accuracy: 1e-6)
        XCTAssertEqual(CompassRole.west.unit.x, -1, accuracy: 1e-6)
    }

    func testDeadZoneCancels() {
        var t = tracker()
        XCTAssertNil(t.update(pointer: CGPoint(x: 110, y: 105)))
        XCTAssertNil(t.releaseRole)
        XCTAssertFalse(t.engaged)
    }

    func testExitDeadZoneIsSmallerThanEnter() {
        var t = tracker()
        t.update(pointer: CGPoint(x: 100 + GestureMath.enterDeadZone + 2, y: 100))
        XCTAssertTrue(t.engaged)
        // Pull back to between exit and enter: still engaged.
        t.update(pointer: CGPoint(x: 100 + (GestureMath.exitDeadZone + GestureMath.enterDeadZone) / 2, y: 100))
        XCTAssertTrue(t.engaged)
        XCTAssertEqual(t.releaseRole, .east)
        // Back inside the exit radius: canceled.
        t.update(pointer: CGPoint(x: 100 + GestureMath.exitDeadZone - 2, y: 100))
        XCTAssertFalse(t.engaged)
        XCTAssertNil(t.releaseRole)
    }

    func testHysteresisHoldsCurrentNearBoundary() {
        var t = tracker()
        XCTAssertEqual(t.update(pointer: CGPoint(x: 180, y: 100)), .east)
        // 50° above the east axis is past the 45° boundary, but inside the hysteresis band.
        let a: CGFloat = 50 * .pi / 180
        let p = CGPoint(x: 100 + cos(a) * 80, y: 100 + sin(a) * 80)
        XCTAssertEqual(t.update(pointer: p), .east)
        // Well past the boundary switches to north.
        let b: CGFloat = 70 * .pi / 180
        XCTAssertEqual(t.update(pointer: CGPoint(x: 100 + cos(b) * 80, y: 100 + sin(b) * 80)), .north)
    }

    func testUnavailableRoleCapturesNothing() {
        var t = tracker([.north, .south])
        XCTAssertNil(t.update(pointer: CGPoint(x: 200, y: 100)))
        XCTAssertTrue(t.engaged)
        XCTAssertNil(t.releaseRole)
        XCTAssertEqual(t.pointing, .east)
        XCTAssertEqual(t.update(pointer: CGPoint(x: 100, y: 200)), .north)
    }

    func testReleaseUsesWhatYouSaw() {
        var t = tracker()
        t.update(pointer: CGPoint(x: 180, y: 100))
        let a: CGFloat = 48 * .pi / 180
        t.update(pointer: CGPoint(x: 100 + cos(a) * 80, y: 100 + sin(a) * 80))
        XCTAssertEqual(t.captured, .east)
        XCTAssertEqual(t.releaseRole, .east)
    }

    func testVirtualLengthMonotonicAndCapped() {
        var last: CGFloat = -1
        for d in stride(from: CGFloat(0), through: 1200, by: 5) {
            let v = GestureMath.virtualLength(d)
            XCTAssertGreaterThanOrEqual(v, last - 1e-6, "monotonic at \(d)")
            XCTAssertLessThanOrEqual(v, GestureMath.defaultMaxLength + 1e-3)
            last = v
        }
        XCTAssertEqual(GestureMath.virtualLength(10), 10, accuracy: 0.5, "≈1:1 near the pin")
        XCTAssertGreaterThan(GestureMath.virtualLength(140), 140 * 1.5, "boosted further out")
    }

    func testVirtualHeadKeepsDirection() {
        let h = GestureMath.virtualHead(pin: pin, pointer: CGPoint(x: 100, y: 160))
        XCTAssertEqual(h.x, 100, accuracy: 1e-6)
        XCTAssertGreaterThan(h.y, 160)
    }

    func testExcludeListDefaults() {
        XCTAssertTrue(ExcludeList.defaultExcludes.contains("com.valvesoftware.steam"))
    }
}
