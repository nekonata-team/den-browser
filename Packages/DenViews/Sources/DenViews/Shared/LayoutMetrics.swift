import CoreGraphics

/// Shared dimensions whose uses have the same visual meaning and should change together.
///
/// Keep feature-specific metrics with their component; equal values alone do not justify sharing.
public enum DenLayout {
    public static let outerInset: CGFloat = 8
    public static let chromeHorizontalPadding: CGFloat = 12
    public static let boardHeaderHeight: CGFloat = 38
    public static let boardControlSize: CGFloat = 24
    public static let minimumBoardHeight: CGFloat = 420
    public static let sideBoardInitialWidth: CGFloat = 360
    public static let deskSwitcherHeight: CGFloat = 32
    public static let deskButtonHeight: CGFloat = 28
    public static let deskButtonMaxWidth: CGFloat = 180
    public static let panelGap: CGFloat = 26
    public static let overlayInset: CGFloat = 18
    public static let deskFilterWidth: CGFloat = 320
    public static let openBoardAtEndButtonSize: CGFloat = 48
    public static let focusModeBlurRadius: CGFloat = 8
    public static let focusModeHaloRadius: CGFloat = 24
    public static let boardIndicatorHeight: CGFloat = 14
    public static let fallbackBoardHeight: CGFloat = 600
    public static let overviewFacingHeight: CGFloat = 120
    public static let minimumWindowWidth: CGFloat = 720
    public static let minimumWindowHeight: CGFloat = 640

    public static let denHeaderHeight = deskSwitcherHeight
}

/// Internal panel spacing and sizing.
///
/// Window placement belongs to `DenActivePanelOverlay`.
/// Let panel height follow its content; constrain candidate lists rather than the whole panel.
public enum DenPanelLayout {
    public static let padding: CGFloat = 16
    public static let contentSpacing: CGFloat = 12
    public static let controlSpacing: CGFloat = 10
    public static let titleHeight: CGFloat = 38
    public static let standardListMaxHeight: CGFloat = 360
    public static let tallListMaxHeight: CGFloat = 420
    public static let previewedListMaxHeight: CGFloat = 240
    public static let standardWidth: CGFloat = 480
    public static let wideWidth: CGFloat = 600
    public static let presetFacingHeight: CGFloat = 100
}

public enum DenKeyboardShortcutsLayout {
    public static let guideSize = CGSize(width: 760, height: 560)
    public static let guidePadding: CGFloat = 18
}

public enum DenFeedbackLayout {
    public static let horizontalPadding: CGFloat = 14
    public static let verticalPadding: CGFloat = 10
    public static let width: CGFloat = 320
}
