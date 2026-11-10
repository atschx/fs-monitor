#if os(macOS)
import SwiftUI

/// Batch-1 visual tokens from Huluwa handoff (v0.1.1-beta.1). Semantic status
/// colors stay system green/red; identity coral is accent only, never failure/monitoring.
enum FSTheme {
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24

    static let radiusCard: CGFloat = 10
    static let radiusButton: CGFloat = 6
    static let radiusBar: CGFloat = 8

    /// Primary rescan fill — D2 warm action (#9C4F39), white label; handoff contrast ≥5.85:1.
    static let primaryAction = Color(red: 156 / 255, green: 79 / 255, blue: 57 / 255)
    /// Identity accent (#BE7054) — brand only, not status.
    static let brandCoral = Color(red: 190 / 255, green: 112 / 255, blue: 84 / 255)
    /// Selected tab fill (#97C5D1) with dark ink (#25344A); handoff contrast ≥6.73:1.
    static let tabSelectedFill = Color(red: 151 / 255, green: 197 / 255, blue: 209 / 255)
    static let tabSelectedInk = Color(red: 37 / 255, green: 52 / 255, blue: 74 / 255)
    /// Light illustration wash (#F5E6DC) — decorative only.
    static let wash = Color(red: 245 / 255, green: 230 / 255, blue: 220 / 255)

    static let windowLight = Color(red: 243 / 255, green: 243 / 255, blue: 245 / 255)
    static let windowDark = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let cardLight = Color.white
    static let cardDark = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    static let textPrimaryLight = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)
    static let textPrimaryDark = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let textSecondaryLight = Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255)
    static let textSecondaryDark = Color(red: 161 / 255, green: 161 / 255, blue: 166 / 255)

    static func windowBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? windowDark : windowLight
    }

    static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? cardDark : cardLight
    }

    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? textPrimaryDark : textPrimaryLight
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? textSecondaryDark : textSecondaryLight
    }

    static func divider(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                FSTheme.primaryAction.opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.45),
                in: RoundedRectangle(cornerRadius: FSTheme.radiusButton, style: .continuous)
            )
    }
}

struct SecondaryOutlineButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(FSTheme.primaryText(for: colorScheme).opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                FSTheme.cardBackground(for: colorScheme).opacity(configuration.isPressed ? 0.7 : 1),
                in: RoundedRectangle(cornerRadius: FSTheme.radiusButton, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FSTheme.radiusButton, style: .continuous)
                    .stroke(FSTheme.divider(for: colorScheme), lineWidth: 1)
            )
    }
}
#endif
