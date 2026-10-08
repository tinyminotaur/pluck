import CoreGraphics
import Foundation

/// "Press and hold without moving" detector for the trackpad trigger. Pure state so it can be
/// unit-tested: feed it press / move / release and ask whether the hold has matured.
public struct HoldArm: Sendable {
    public let holdSeconds: Double
    public let moveTolerance: CGFloat

    private var origin: CGPoint?
    private var startTime: Double = 0
    private var broken = false

    public init(holdSeconds: Double = 0.22, moveTolerance: CGFloat = 8) {
        self.holdSeconds = holdSeconds
        self.moveTolerance = moveTolerance
    }

    public var isPressed: Bool { origin != nil }
    /// True once the pointer moved beyond tolerance during the press (a normal drag, not our gesture).
    public var wasBroken: Bool { broken }

    public mutating func press(at point: CGPoint, time: Double) {
        origin = point
        startTime = time
        broken = false
    }

    public mutating func move(to point: CGPoint) {
        guard let origin, !broken else { return }
        if hypot(point.x - origin.x, point.y - origin.y) > moveTolerance { broken = true }
    }

    public func isReady(at time: Double) -> Bool {
        origin != nil && !broken && time - startTime >= holdSeconds
    }

    public mutating func release() {
        origin = nil
        broken = false
    }
}
