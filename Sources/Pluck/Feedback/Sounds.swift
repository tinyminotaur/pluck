import AppKit

/// Optional, very quiet audio feedback using the built-in macOS sounds (no assets shipped). Off by default so it is
/// safe in a meeting; like haptics it is a bonus on top of the visuals, never the only feedback.
@MainActor
enum Sounds {
    private static var cache: [String: NSSound] = [:]
    private static var lastPlay: CFTimeInterval = 0

    /// A direction latched: the softest tick.
    static func latch() { play("Tink", volume: 0.07) }

    /// Committed: a soft drop-like plip as the droplet leaves.
    static func commit() { play("Pop", volume: 0.20) }

    private static func play(_ name: String, volume: Float) {
        guard PluckConfig.shared.soundEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastPlay > 0.05 else { return }
        lastPlay = now
        let sound = cache[name] ?? NSSound(named: NSSound.Name(name))
        guard let sound else { return }
        cache[name] = sound
        sound.stop()
        sound.volume = volume
        sound.play()
    }
}
