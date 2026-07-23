import Foundation
import CoreGraphics

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
            max(280, windowWidth - horizontalPadding * 2)
        }
    }

    static func calculatePaddings(
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

        let leadingPadding: CGFloat
        let trailingPadding: CGFloat

        switch params.centering {
        case .always:
            leadingPadding = max(params.horizontalPadding, (params.windowWidth - firstBoardWidth) / 2)
            trailingPadding = max(params.horizontalPadding, (params.windowWidth - lastBoardWidth) / 2)

        case .never:
            leadingPadding = params.horizontalPadding
            trailingPadding = params.horizontalPadding

        case .onOverflow:
            let totalBoardsWidth = params.boards.reduce(0.0) { sum, board in
                let w = params.maximizedBoardID == board.id ? params.maximizedBoardWidth : board.width
                return sum + w
            }
            let totalSpacing = CGFloat(max(0, params.boards.count - 1)) * params.spacing
            let totalRequiredWidth = totalBoardsWidth + totalSpacing

            if totalRequiredWidth <= params.windowWidth - params.horizontalPadding * 2 + 1 {
                let centerPadding = max(params.horizontalPadding, (params.windowWidth - totalRequiredWidth) / 2)
                leadingPadding = centerPadding
                trailingPadding = centerPadding
            } else {
                leadingPadding = max(params.horizontalPadding, (params.windowWidth - firstBoardWidth) / 2)
                trailingPadding = max(params.horizontalPadding, (params.windowWidth - lastBoardWidth) / 2)
            }
        }

        return (leadingPadding, trailingPadding)
    }
}
