import CoreGraphics
import Foundation

/// Four compass roles. Labels change with context; empty roles are omitted.
public enum CompassRole: String, CaseIterable, Codable, Hashable, Sendable {
    case north = "keep"
    case east = "go"
    case south = "give"
    case west = "ask"

    /// Angle in AppKit screen space (origin bottom-left, **y up**), radians.
    /// North is up on the display.
    public var angle: CGFloat {
        switch self {
        case .north: return .pi / 2
        case .east: return 0
        case .south: return -.pi / 2
        case .west: return .pi
        }
    }

    /// Unit vector in AppKit screen space (y up).
    public var unit: CGPoint {
        CGPoint(x: cos(angle), y: sin(angle))
    }

    public var accessibilityLabel: String {
        switch self {
        case .north: return "Keep"
        case .east: return "Go"
        case .south: return "Give"
        case .west: return "Ask"
        }
    }
}

public struct CompassItem: Identifiable, Equatable, Sendable {
    public let role: CompassRole
    public let title: String
    public let subtitle: String?
    public let actionID: String

    public var id: String { "\(role.rawValue)-\(actionID)" }

    public init(role: CompassRole, title: String, subtitle: String?, actionID: String) {
        self.role = role
        self.title = title
        self.subtitle = subtitle
        self.actionID = actionID
    }
}

public enum GrabKind: Equatable, Sendable {
    case text(String)
    case link(URL)
    case file(URL)
    case image(URL?)
    case clipboard
    case window(pid: pid_t, windowNumber: CGWindowID)
}

public struct GrabContext: Equatable, Sendable {
    public let kind: GrabKind
    public let nucleusTitle: String
    public let items: [CompassItem]

    public init(kind: GrabKind, nucleusTitle: String, items: [CompassItem]) {
        self.kind = kind
        self.nucleusTitle = nucleusTitle
        self.items = items
    }
}
