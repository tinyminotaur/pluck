import AppKit

/// Trackpad haptics for the fidget feel. Silent by design (fine in a meeting) and a no-op
/// on a mouse: `NSHapticFeedbackManager` only fires on a Force Touch trackpad, so this is a
/// bonus that must always be paired with visual feedback.
@MainActor
enum Haptics {
    private static var lastTick: CFTimeInterval = 0

    static func tick(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard TwangConfig.shared.hapticsEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastTick > 0.04 else { return }
        lastTick = now
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
