import CoreGraphics
import Foundation

/// Placement of direction labels around the pin. Works in AppKit view space (y-up); roles are
/// defined in y-down screen space, so the vertical component is flipped here.
public enum LabelLayout {
    /// Distance from pin to label centre when idle (points).
    public static let distance: CGFloat = 92

    /// Unit direction of a role in y-up view space.
    public static func direction(of role: CompassRole) -> CGPoint {
        let u = role.unit
        return CGPoint(x: u.x, y: -u.y)
    }

    public static func center(pin: CGPoint, role: CompassRole, distance: CGFloat = LabelLayout.distance) -> CGPoint {
        let d = direction(of: role)
        return CGPoint(x: pin.x + d.x * distance, y: pin.y + d.y * distance)
    }

    /// Shift a label so it stays inside `bounds`. Only the label moves; the selection slices
    /// are never changed (moving the geometry is what makes edge menus mis-select).
    public static func clamped(center: CGPoint, size: CGSize, in bounds: CGRect, margin: CGFloat = 12) -> CGPoint {
        let halfW = size.width / 2
        let halfH = size.height / 2
        let minX = bounds.minX + margin + halfW
        let maxX = bounds.maxX - margin - halfW
        let minY = bounds.minY + margin + halfH
        let maxY = bounds.maxY - margin - halfH
        return CGPoint(
            x: minX <= maxX ? min(max(center.x, minX), maxX) : bounds.midX,
            y: minY <= maxY ? min(max(center.y, minY), maxY) : bounds.midY
        )
    }
}
