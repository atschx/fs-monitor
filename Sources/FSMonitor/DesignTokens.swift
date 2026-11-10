#if os(macOS)
import AppKit
import SwiftUI

/// D2 theme accents used sparingly on top of native macOS controls.
/// Principle (Albert): native visual/UI first; warm/teal brand is secondary tint only —
/// do not replace system buttons, segmented controls, or semantic status colors.
enum FSTheme {
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16

    static let radiusCard: CGFloat = 8

    /// D2 warm primary tint for the prominent rescan control (#9C4F39).
    static let primaryAction = Color(red: 156 / 255, green: 79 / 255, blue: 57 / 255)
    /// Identity coral (#BE7054) — optional accent only; never status/failure/monitoring.
    static let brandCoral = Color(red: 190 / 255, green: 112 / 255, blue: 84 / 255)

    static var windowBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
}
#endif
