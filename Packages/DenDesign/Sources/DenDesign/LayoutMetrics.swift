import CoreGraphics

public enum DenLayout {
    public static let outerInset: CGFloat = 8
    public static let chromeHorizontalPadding: CGFloat = 12
    public static let boardHeaderHeight: CGFloat = 38
    public static let boardControlSize: CGFloat = 24
    public static let minimumBoardHeight: CGFloat = 420
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

    public static let denHeaderHeight = deskSwitcherHeight
}

public enum DenPanelLayout {
    public static let padding: CGFloat = 16
    public static let contentSpacing: CGFloat = 12
    public static let controlSpacing: CGFloat = 10
    public static let titleHeight: CGFloat = 38
    public static let deskPresetListMaxHeight: CGFloat = 360
    public static let narrowWidth: CGFloat = 380
    public static let compactWidth: CGFloat = 420
    public static let standardWidth: CGFloat = 520
    public static let wideWidth: CGFloat = 620
}

public enum DenKeyboardShortcutsLayout {
    public static let guideSize = CGSize(width: 760, height: 560)
    public static let guidePadding: CGFloat = 18
}
