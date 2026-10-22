public import CoreGraphics
public import DenDomain
public import DenPresentationModels
public import Foundation

public struct BoardLayout {
    public struct Parameters {
        public static let defaultSideSpacing: CGFloat = 4

        public let centering: FocusedBoardCentering
        public let boards: [BoardState]
        public let maximizedBoardID: BoardID?
        public let windowWidth: CGFloat
        public let horizontalPadding: CGFloat
        public let spacing: CGFloat
        public var sideSpacing: CGFloat = defaultSideSpacing

        public init(
            centering: FocusedBoardCentering, boards: [BoardState], maximizedBoardID: BoardID?, windowWidth: CGFloat,
            horizontalPadding: CGFloat, spacing: CGFloat, sideSpacing: CGFloat = defaultSideSpacing
        ) {
            self.centering = centering
            self.boards = boards
            self.maximizedBoardID = maximizedBoardID
            self.windowWidth = windowWidth
            self.horizontalPadding = horizontalPadding
            self.spacing = spacing
            self.sideSpacing = sideSpacing
        }

        public var maximizedBoardWidth: CGFloat {
            max(CGFloat(BoardState.minimumWidth), windowWidth - horizontalPadding * 2)
        }

        public var requiredBoardsWidth: CGFloat {
            let totalBoardsWidth = boards.reduce(0.0) { sum, board in
                sum + (maximizedBoardID == board.id ? maximizedBoardWidth : board.width)
            }
            let totalSpacing = (0..<max(0, boards.count - 1)).reduce(CGFloat.zero) { sum, index in
                sum + spacingAfterBoard(at: index)
            }
            return totalBoardsWidth + totalSpacing
        }

        public var boardsOverflow: Bool {
            requiredBoardsWidth > windowWidth - horizontalPadding * 2 + 1
        }

        public func spacingAfterBoard(at index: Int) -> CGFloat {
            guard boards.indices.contains(index) else { return spacing }
            let nextIndex = index + 1
            guard boards.indices.contains(nextIndex) else { return spacing }
            return boards[nextIndex].sideBoardTargetBoardID == boards[index].id ? sideSpacing : spacing
        }
    }

    public static func shouldCenterFocusedBoard(for params: Parameters) -> Bool {
        params.centering == .always
            || (params.centering == .onOverflow && params.boardsOverflow)
    }

    public static func scrollTargetToRevealBoard(
        for boardIndex: Int,
        in params: Parameters,
        currentScrollX: CGFloat,
        contentWidth: CGFloat,
        containerWidth: CGFloat
    ) -> CGFloat? {
        guard
            let boardRange = boardContentRange(for: boardIndex, in: params),
            containerWidth > 0,
            contentWidth > 0
        else { return nil }

        let leadingEdge = currentScrollX + params.horizontalPadding
        let trailingEdge = currentScrollX + containerWidth - params.horizontalPadding
        let targetOffsetX: CGFloat

        if boardRange.minX < leadingEdge {
            targetOffsetX = boardRange.minX - params.horizontalPadding
        } else if boardRange.maxX > trailingEdge {
            targetOffsetX = boardRange.maxX - containerWidth + params.horizontalPadding
        } else {
            return nil
        }

        let maximumOffset = max(0, contentWidth - containerWidth)
        return min(max(0, targetOffsetX), maximumOffset)
    }

    public static func centeredScrollX(
        for boardIndex: Int,
        in params: Parameters,
        containerWidth: CGFloat,
        contentWidth: CGFloat
    ) -> CGFloat? {
        centeredScrollX(
            for: boardIndex...boardIndex,
            in: params,
            containerWidth: containerWidth,
            contentWidth: contentWidth)
    }

    public static func centeredScrollX(
        for boardRange: ClosedRange<Int>,
        in params: Parameters,
        containerWidth: CGFloat,
        contentWidth: CGFloat
    ) -> CGFloat? {
        guard
            params.boards.indices.contains(boardRange.lowerBound),
            params.boards.indices.contains(boardRange.upperBound),
            containerWidth > 0,
            contentWidth > 0
        else {
            return nil
        }

        guard
            let firstRange = boardContentRange(for: boardRange.lowerBound, in: params),
            let lastRange = boardContentRange(for: boardRange.upperBound, in: params)
        else { return nil }
        let boardCenter = (firstRange.minX + lastRange.maxX) / 2
        let maximumOffset = max(0, contentWidth - containerWidth)
        return min(max(0, boardCenter - containerWidth / 2), maximumOffset)
    }

    public static func boardContentRange(
        for boardIndex: Int,
        in params: Parameters
    ) -> (minX: CGFloat, maxX: CGFloat)? {
        guard params.boards.indices.contains(boardIndex) else { return nil }

        let paddings = calculatePaddings(for: params)
        let precedingWidth = (0..<boardIndex).reduce(0.0) { total, index in
            total + boardWidth(params.boards[index], in: params) + params.spacingAfterBoard(at: index)
        }
        let minX = paddings.leading + precedingWidth
        return (minX, minX + boardWidth(params.boards[boardIndex], in: params))
    }

    public static func restingScrollX(for params: Parameters) -> CGFloat {
        guard params.centering == .onOverflow, !params.boardsOverflow else { return 0 }
        let centeredPadding = max(
            params.horizontalPadding,
            (params.windowWidth - params.requiredBoardsWidth) / 2)
        return max(0, calculatePaddings(for: params).leading - centeredPadding)
    }

    public static func calculatePaddings(
        for params: Parameters
    ) -> (leading: CGFloat, trailing: CGFloat) {
        switch params.centering {
        case .always, .onOverflow:
            let leading = max(params.horizontalPadding, params.windowWidth / 2)
            let trailingAdjustment =
                params.boards.isEmpty
                ? 0
                : DenLayout.openBoardAtEndButtonSize + params.spacing
            let trailing = max(params.horizontalPadding, params.windowWidth / 2 - trailingAdjustment)
            return (leading, trailing)
        case .never:
            return (params.horizontalPadding, params.horizontalPadding)
        }
    }

    public static func contentWidth(
        for params: Parameters,
        isDeskFilterPresented: Bool = false
    ) -> CGFloat {
        guard !params.boards.isEmpty else { return params.windowWidth }
        let paddings = calculatePaddings(for: params)
        let openAtEndWidth =
            isDeskFilterPresented
            ? 0
            : DenLayout.openBoardAtEndButtonSize + params.spacing
        return paddings.leading + params.requiredBoardsWidth + openAtEndWidth + paddings.trailing
    }

    public static func visibleBoardIDs(
        in params: Parameters,
        offsetX: CGFloat,
        containerWidth: CGFloat
    ) -> Set<BoardID> {
        guard containerWidth > 0 else { return [] }
        var visibleIDs = Set<BoardID>()
        for (index, board) in params.boards.enumerated() {
            guard let range = boardContentRange(for: index, in: params) else { continue }
            let visibleWidth = max(
                0,
                min(range.maxX, offsetX + containerWidth) - max(range.minX, offsetX))
            guard visibleWidth / (range.maxX - range.minX) >= 0.05 else { continue }
            visibleIDs.insert(board.id)
        }
        return visibleIDs
    }

    private static func boardWidth(_ board: BoardState, in params: Parameters) -> CGFloat {
        params.maximizedBoardID == board.id ? params.maximizedBoardWidth : board.width
    }
}
