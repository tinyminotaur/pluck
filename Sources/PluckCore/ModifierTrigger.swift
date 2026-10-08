import Foundation

/// Modifier keys, independent of AppKit so the trigger rules can be unit-tested.
public struct ModifierSet: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let shift = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)
    /// ⌃⌥⇧⌘ together (the "Hyper" key many people map Caps Lock to).
    public static let hyper: ModifierSet = [.control, .option, .shift, .command]
}

/// The no-click trigger: hold the modifier(s), move to stretch, release the modifier to commit.
public enum ModifierTrigger: Int, CaseIterable, Sendable {
    case off = 0
    case option = 1
    case hyper = 2

    public var required: ModifierSet {
        switch self {
        case .off: return []
        case .option: return .option
        case .hyper: return .hyper
        }
    }

    /// ⌥ alone is common (alt-drag, special characters), so it must be held still for a moment.
    /// Hyper is almost never held by accident, so it arms on the hold time alone.
    public var requiresStillness: Bool { self == .option }

    /// To start a watch, the held modifiers must match exactly (⌥⌘ is a shortcut, not our trigger).
    public func shouldArm(held: ModifierSet) -> Bool {
        self != .off && held == required
    }

    /// Once running, extra modifiers are fine; the gesture ends when a required one is released.
    public func shouldContinue(held: ModifierSet) -> Bool {
        self != .off && held.isSuperset(of: required)
    }
}
