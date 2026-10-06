import CoreGraphics
import DenDesign
import DenDomain

extension DenLayout {
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
