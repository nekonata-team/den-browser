import SwiftUI

public enum DenSurfaceColors {
    /// Backgrounds of selected or keyboard-focused items.
    public static let selectionOpacity: Double = 0.20
    /// Strong focus and selection outlines.
    public static let emphasisOpacity: Double = 0.80
    public static let focusedBoardHeaderOpacity: Double = 0.12

    /// Background for filled filter inputs while entering text or browsing results.
    public static func filterInputBackground(isActive: Bool) -> Color {
        Color.primary.opacity(isActive ? 0.08 : 0.04)
    }

    /// Border for filled filter inputs; glass-backed inputs retain their own idle border.
    public static func filterInputBorder(
        isActive: Bool,
        profileColor: Color,
        differentiateWithoutColor: Bool
    ) -> Color {
        if isActive {
            return differentiateWithoutColor ? .primary : profileColor.opacity(emphasisOpacity)
        }
        return Color.primary.opacity(0.10)
    }

    /// Focus border shared by mounted and unactivated Boards.
    public static func boardBorder(isFocused: Bool, profileColor: Color) -> Color {
        isFocused ? profileColor.opacity(emphasisOpacity) : Color.primary.opacity(0.16)
    }

    /// Dragging raises a Board above focused and inactive Boards.
    public static func boardShadow(isFocused: Bool, isDragging: Bool) -> Color {
        Color.black.opacity(isDragging ? 0.55 : (isFocused ? 0.42 : 0.30))
    }

    public static let denModeBackgroundGradientColors = [
        Color(red: 0.03, green: 0.18, blue: 0.23),
        Color(red: 0.06, green: 0.10, blue: 0.18),
    ]

    public static let standardBackgroundColor = Color(red: 0.08, green: 0.10, blue: 0.12)
    public static let standardBackgroundGradientColors = [
        standardBackgroundColor,
        Color(red: 0.15, green: 0.16, blue: 0.19),
    ]

    public static let privateDenBackgroundGradientColors = [
        Color(red: 0.11, green: 0.08, blue: 0.16),
        Color(red: 0.20, green: 0.15, blue: 0.26),
    ]

    public static let privateDenModeBackgroundGradientColors = [
        Color(red: 0.14, green: 0.04, blue: 0.22),
        Color(red: 0.06, green: 0.04, blue: 0.12),
    ]
}
