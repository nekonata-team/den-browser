import CoreGraphics

enum DenLayout {
    static let outerInset: CGFloat = 8
    static let chromeHorizontalPadding: CGFloat = 12
    static let boardHeaderHeight: CGFloat = 38
    static let boardControlSize: CGFloat = 24
    static let deskSwitcherHeight: CGFloat = 36
    static let deskButtonHeight: CGFloat = 28
    static let deskButtonMaxWidth: CGFloat = 180
    static let panelGap: CGFloat = 26
    static let overlayInset: CGFloat = 18

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

enum DenDrawerLayout {
    static let headerHeight: CGFloat = 58
    static let headerHorizontalPadding: CGFloat = 14
    static let itemHeight: CGFloat = 52
    static let discardButtonWidth: CGFloat = 32
    static let minimumHeight: CGFloat = 360
    static let windowClearance: CGFloat = 72
    static let previewReservedHeight: CGFloat = 160
}

enum DenOverviewLayout {
    static let contentPadding: CGFloat = 18
    static let closeButtonInset: CGFloat = 14
    static let searchFieldWidth: CGFloat = 320
    static let selectionIndicatorSize: CGFloat = 6
    static let emptyBoardSize = CGSize(width: 150, height: 88)
    static let boardSize = CGSize(width: 158, height: 96)
    static let boardPadding: CGFloat = 10
    static let widthIndicatorRange: ClosedRange<CGFloat> = 24...92
    static let widthIndicatorHeight: CGFloat = 5
    static let widthIndicatorScale: CGFloat = 9
}
