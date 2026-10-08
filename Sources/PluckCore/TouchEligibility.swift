import Foundation

/// Decides whether the current trackpad contacts look like a deliberate three-finger landing.
///
/// A raw contact count can't tell three fingers from two-finger scrolling plus a resting thumb or palm.
/// Two-finger scroll/pinch/rotate move content, not the pointer, so a pointer-stillness check passes too.
/// So we also require:
/// - the three contacts landed together (all within `landingWindow` of the first touch),
/// - never more than three at once since the pad was last empty,
/// - no scroll/magnify/rotate event for `scrollQuiet` seconds.
public struct TouchEligibility: Sendable {
    public var landingWindow: Double
    public var scrollQuiet: Double

    private var count = 0
    private var landedAt: Double = 0
    private var eligible = true
    private var lastScrollAt: Double = -1000

    public init(landingWindow: Double = 0.18, scrollQuiet: Double = 0.35) {
        self.landingWindow = landingWindow
        self.scrollQuiet = scrollQuiet
    }

    public var contactCount: Int { count }

    public mutating func countChanged(_ n: Int, at t: Double) {
        let previous = count
        count = n
        if n == 0 {
            eligible = true
            return
        }
        if previous == 0 { landedAt = t }
        if n >= 4 { eligible = false }
        if n == 3, previous < 3, t - landedAt > landingWindow { eligible = false }
    }

    public mutating func scrolled(at t: Double) {
        lastScrollAt = t
    }

    public func canArm(at t: Double) -> Bool {
        count == 3 && eligible && t - lastScrollAt > scrollQuiet
    }
}
