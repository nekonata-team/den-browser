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
        frame: CGRect,
        currentScrollX: CGFloat,
        contentWidth: CGFloat,
        containerWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> CGFloat? {
        let leadingEdge = horizontalPadding
        let trailingEdge = containerWidth - horizontalPadding
        let adjustment: CGFloat

        if frame.minX < leadingEdge {
            adjustment = frame.minX - leadingEdge
        } else if frame.maxX > trailingEdge {
            adjustment = frame.maxX - trailingEdge
        } else {
            return nil
        }

        let maximumOffset = max(0, contentWidth - containerWidth)
        return min(max(0, currentScrollX + adjustment), maximumOffset)
    }

    static func restingScrollX(for params: Parameters) -> CGFloat {
        guard params.centering == .onOverflow, !params.boardsOverflow else { return 0 }
        let centeredPadding = max(
            params.horizontalPadding,
            (params.windowWidth - params.requiredBoardsWidth) / 2)
        return max(0, edgePaddings(for: params).leading - centeredPadding)
    }

    static func calculatePaddings(
        for params: Parameters
    ) -> (leading: CGFloat, trailing: CGFloat) {
        switch params.centering {
        case .always, .onOverflow:
            edgePaddings(for: params)
        case .never:
            (params.horizontalPadding, params.horizontalPadding)
        }
    }

    private static func edgePaddings(
        for params: Parameters
    ) -> (leading: CGFloat, trailing: CGFloat) {
        let firstBoardWidth =
            params.boards.first.map {
                params.maximizedBoardID == $0.id ? params.maximizedBoardWidth : $0.width
            } ?? params.windowWidth

        let lastBoardWidth =
            params.boards.last.map {
                params.maximizedBoardID == $0.id ? params.maximizedBoardWidth : $0.width
            } ?? params.windowWidth

        return (
            max(params.horizontalPadding, (params.windowWidth - firstBoardWidth) / 2),
            max(params.horizontalPadding, (params.windowWidth - lastBoardWidth) / 2)
        )
    }
}
