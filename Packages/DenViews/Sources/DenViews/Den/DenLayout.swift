import CoreGraphics
import DenDomain
import DenModels

public extension DenLayout {
    static func boardWidth(
        toFit count: Int,
        in availableWidth: Double,
        spacing: Double = outerInset
    ) -> Double? {
        BoardLayoutMetrics(availableWidth: availableWidth, spacing: spacing).boardWidth(toFit: count)
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
