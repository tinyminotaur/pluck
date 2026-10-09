import AppKit
import Foundation
import TwangCore

/// Real actions (copy, share, search, save, tile windows, the clipboard watcher) are an opt-in beta.
/// Off by default: Twang then only draws, and never reads the clipboard or touches your files and windows.
enum RealActions {
    private static let key = "twang.realActions"
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// What the compass shows when real actions are off: the four directions with their playful names, so the
/// gesture can be tried without anything happening.
enum Playground {
    static let context = GrabContext(
        kind: .clipboard,
        nucleusTitle: "",
        items: [
            CompassItem(role: .north, title: "North", subtitle: "Share", actionID: "play.north"),
            CompassItem(role: .east, title: "East", subtitle: "Go", actionID: "play.east"),
            CompassItem(role: .south, title: "South", subtitle: "Save", actionID: "play.south"),
            CompassItem(role: .west, title: "West", subtitle: "Ask", actionID: "play.west"),
        ]
    )

    static func title(for role: CompassRole?) -> String {
        guard let role else { return "Canceled" }
        switch role {
        case .north: return "North"
        case .east: return "East"
        case .south: return "South"
        case .west: return "West"
        }
    }
}

extension Notification.Name {
    static let twangRealActionsChanged = Notification.Name("twang.realActionsChanged")
}
