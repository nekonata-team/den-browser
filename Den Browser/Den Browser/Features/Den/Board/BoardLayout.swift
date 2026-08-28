import CoreGraphics
import Foundation

enum FocusedBoardCentering: String, CaseIterable, Identifiable {
    case never
    case always
    case onOverflow = "on-overflow"

    var id: Self { self }

    var label: String {
        switch self {
        case .never: "Never"
        case .always: "Always"
        case .onOverflow: "When Overflowing"
        }
    }
}

struct BoardLayout {
    struct Parameters {
        let centering: FocusedBoardCentering
        let boards: [BoardState]
        let maximizedBoardID: UUID?
        let windowWidth: CGFloat
        let horizontalPadding: CGFloat
        let spacing: CGFloat

        var maximizedBoardWidth: CGFloat {
            max(CGFloat(BoardState.minimumWidth), windowWidth - horizontalPadding * 2)
        }

        var requiredBoardsWidth: CGFloat {
            let totalBoardsWidth = boards.reduce(0.0) { sum, board in
                sum + (maximizedBoardID == board.id ? maximizedBoardWidth : board.width)
            }
            let totalSpacing = CGFloat(max(0, boards.count - 1)) * spacing
            return totalBoardsWidth + totalSpacing
        }

        var boardsOverflow: Bool {
            requiredBoardsWidth > windowWidth - horizontalPadding * 2 + 1
        }
    }

    static func shouldCenterFocusedBoard(for params: Parameters) -> Bool {
        params.centering == .always
            || (params.centering == .onOverflow && params.boardsOverflow)
    }

    static func scrollTargetToRevealBoard(
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

    static func centeredScrollX(
        for boardIndex: Int,
        in params: Parameters,
        containerWidth: CGFloat,
        contentWidth: CGFloat
    ) -> CGFloat? {
        guard params.boards.indices.contains(boardIndex), containerWidth > 0, contentWidth > 0 else {
            return nil
        }

        guard let boardRange = boardContentRange(for: boardIndex, in: params) else { return nil }
        let boardCenter = (boardRange.minX + boardRange.maxX) / 2
        let maximumOffset = max(0, contentWidth - containerWidth)
        return min(max(0, boardCenter - containerWidth / 2), maximumOffset)
    }

    static func boardContentRange(
        for boardIndex: Int,
        in params: Parameters
    ) -> (minX: CGFloat, maxX: CGFloat)? {
        guard params.boards.indices.contains(boardIndex) else { return nil }

        let paddings = calculatePaddings(for: params)
        let precedingWidth = params.boards.prefix(boardIndex).reduce(0.0) { total, board in
            total + boardWidth(board, in: params) + params.spacing
        }
        let minX = paddings.leading + precedingWidth
        return (minX, minX + boardWidth(params.boards[boardIndex], in: params))
    }

    static func restingScrollX(for params: Parameters) -> CGFloat {
        guard params.centering == .onOverflow, !params.boardsOverflow else { return 0 }
        let centeredPadding = max(
            params.horizontalPadding,
            (params.windowWidth - params.requiredBoardsWidth) / 2)
        return max(0, calculatePaddings(for: params).leading - centeredPadding)
    }

    static func calculatePaddings(
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

    private static func boardWidth(_ board: BoardState, in params: Parameters) -> CGFloat {
        params.maximizedBoardID == board.id ? params.maximizedBoardWidth : board.width
    }
}
