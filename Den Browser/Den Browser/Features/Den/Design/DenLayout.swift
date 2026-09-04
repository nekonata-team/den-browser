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
    static let openBoardAtEndButtonSize: CGFloat = 48
    static let focusModeBlurRadius: CGFloat = 8
    static let focusModeHaloRadius: CGFloat = 24
    static let boardIndicatorHeight: CGFloat = 14

    static let denHeaderHeight = deskSwitcherHeight

    static func boardWidth(
        toFit count: Int,
        in availableWidth: Double,
        spacing: Double = outerInset
    ) -> Double? {
        guard (1...9).contains(count), availableWidth > 0 else { return nil }
        let width = (availableWidth - spacing * Double(count - 1)) / Double(count)
        guard width >= BoardState.minimumWidth else { return nil }
        return width
    }

    static func newBoardWidth(in size: CGSize, focusedBoardWidth: Double?) -> Double {
        if let focusedBoardWidth { return focusedBoardWidth }
        let availableWidth = Double(size.width - outerInset * 2)
        return boardWidth(toFit: 2, in: availableWidth, spacing: outerInset)
            ?? BuiltInDeskPreset.boardWidth
    }

    static func boardHeight(
        for size: CGSize,
        shouldShowHeader: Bool,
        shouldShowIndicator: Bool = false
    ) -> CGFloat {
        let topInset = shouldShowHeader ? denHeaderHeight : outerInset
        let bottomInset = outerInset + (shouldShowIndicator ? boardIndicatorHeight : 0)
        return max(minimumBoardHeight, size.height - topInset - bottomInset)
    }
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
