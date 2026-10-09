import CoreGraphics

/// Ferromagnet-style attraction between the liquid's head and the cursor.
///
/// A magnet pulls hardest when the gap is small: the mass trails behind when you whip the cursor away
/// (it is heavy, it sloshes), then snaps in and sticks as it catches up. Modelled as a spring whose
/// stiffness rises as the gap closes.
public enum MagnetPull {
    /// Gap (points) over which the extra "stick" fades out.
    public static let stickRange: CGFloat = 36

    /// Spring angular frequency for a given gap. `base` is the far-field frequency (rad/s); `stick` is the
    /// extra fraction added right at the cursor (0 = a plain spring, 1 = twice as stiff when touching).
    public static func omega(distance: CGFloat, base: CGFloat, stick: CGFloat) -> CGFloat {
        base * (1 + max(0, stick) * CGFloat(exp(-Double(max(0, distance) / stickRange))))
    }
}
