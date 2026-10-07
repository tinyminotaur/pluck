import AppKit
import Foundation
import PluckCore

/// Feel Lab: gesture + liquid only. No clipboard/files/window actions.
enum FeelLab {
    /// Default on until we graduate past feel.
    static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "pluck.feelLab") == nil { return true }
            return UserDefaults.standard.bool(forKey: "pluck.feelLab")
        }
        set { UserDefaults.standard.set(newValue, forKey: "pluck.feelLab") }
    }

    static let context = GrabContext(
        kind: .clipboard,
        nucleusTitle: "",
        items: [
            CompassItem(role: .north, title: "North", subtitle: "Keep", actionID: "feel.north"),
            CompassItem(role: .east, title: "East", subtitle: "Go", actionID: "feel.east"),
            CompassItem(role: .south, title: "South", subtitle: "Give", actionID: "feel.south"),
            CompassItem(role: .west, title: "West", subtitle: "Ask", actionID: "feel.west"),
        ]
    )

    static func title(for role: CompassRole?) -> String {
        guard let role else { return "Canceled" }
        switch role {
        case .north: return "North · Keep"
        case .east: return "East · Go"
        case .south: return "South · Give"
        case .west: return "West · Ask"
        }
    }
}
