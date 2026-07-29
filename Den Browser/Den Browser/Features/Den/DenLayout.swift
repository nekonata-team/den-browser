import CoreGraphics

enum DenLayout {
    static let outerInset: CGFloat = 8
    static let chromeHorizontalPadding: CGFloat = 12
    static let boardHeaderHeight: CGFloat = 38
    static let boardControlSize: CGFloat = 24
    static let minimumBoardHeight: CGFloat = 420
    static let deskSwitcherHeight: CGFloat = 36
    static let deskButtonHeight: CGFloat = 28
    static let deskButtonMaxWidth: CGFloat = 180
    static let panelGap: CGFloat = 26
    static let overlayInset: CGFloat = 18
    static let deskFilterWidth: CGFloat = 320

    static let boardTopInsetWithDeskSwitcher = outerInset + deskSwitcherHeight
    static let panelTopInset = boardTopInsetWithDeskSwitcher + panelGap
}

enum DenPanelLayout {
    static let padding: CGFloat = 16
    static let contentSpacing: CGFloat = 12
    static let controlSpacing: CGFloat = 10
    static let titleHeight: CGFloat = 38
    static let compactWidth: CGFloat = 420
    static let standardWidth: CGFloat = 520
    static let wideWidth: CGFloat = 620
}

enum DenKeyboardShortcutsLayout {
    static let guideSize = CGSize(width: 760, height: 560)
    static let guidePadding: CGFloat = 18
}
