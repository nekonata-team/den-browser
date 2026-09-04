import Testing

@testable import Den_Browser

@MainActor
struct BoardLayoutTests {
    @Test func appliesCenteringPaddingForEachMode() {
        #expect(paddings(for: .always, boardCount: 3) == (leading: 500, trailing: 444))
        #expect(paddings(for: .never, boardCount: 3) == (leading: 10, trailing: 10))
        #expect(paddings(for: .onOverflow, boardCount: 3) == (leading: 500, trailing: 444))
        #expect(paddings(for: .onOverflow, boardCount: 4) == (leading: 500, trailing: 444))
    }

    @Test func keepsCenteringPaddingStableWhenEdgeBoardWidthsChange() {
        let baseParams = parameters(centering: .always, boardCount: 3)
        var boards = baseParams.boards
        boards[0].width = 500
        boards[2].width = 700
        let params = BoardLayout.Parameters(
            centering: baseParams.centering,
            boards: boards,
            maximizedBoardID: baseParams.maximizedBoardID,
            windowWidth: baseParams.windowWidth,
            horizontalPadding: baseParams.horizontalPadding,
            spacing: baseParams.spacing)

        #expect(BoardLayout.calculatePaddings(for: params) == (leading: 500, trailing: 444))
    }

    @Test func keepsOnOverflowCoordinatesStableWhenBoardsStartOverflowing() {
        #expect(restingScrollX(for: .onOverflow, boardCount: 3) == 488)
        #expect(restingScrollX(for: .onOverflow, boardCount: 4) == 0)
    }

    @Test func centersFocusedBoardOnlyForAlwaysOrOverflowLayout() {
        #expect(shouldCenterFocusedBoard(for: .always, boardCount: 3))
        #expect(!shouldCenterFocusedBoard(for: .never, boardCount: 3))
        #expect(!shouldCenterFocusedBoard(for: .onOverflow, boardCount: 3))
        #expect(!shouldCenterFocusedBoard(for: .never, boardCount: 4))
        #expect(shouldCenterFocusedBoard(for: .onOverflow, boardCount: 4))
    }

    @Test func revealsBoardFromStableLayoutGeometry() {
        #expect(
            BoardLayout.scrollTargetToRevealBoard(
                for: 0,
                in: parameters(centering: .never, boardCount: 3),
                currentScrollX: 100,
                contentWidth: 1_500,
                containerWidth: 1_000
            ) == 0
        )
        #expect(
            BoardLayout.scrollTargetToRevealBoard(
                for: 2,
                in: parameters(centering: .never, boardCount: 3),
                currentScrollX: 0,
                contentWidth: 1_500,
                containerWidth: 500
            ) == 496
        )
        #expect(
            BoardLayout.scrollTargetToRevealBoard(
                for: 1,
                in: parameters(centering: .never, boardCount: 3),
                currentScrollX: 200,
                contentWidth: 1_500,
                containerWidth: 1_000
            ) == nil
        )
        #expect(
            BoardLayout.scrollTargetToRevealBoard(
                for: 2,
                in: parameters(centering: .never, boardCount: 3),
                currentScrollX: 300,
                contentWidth: 1_500,
                containerWidth: 500
            ) == 496
        )
    }

    @Test func centersBoardFromStableLayoutGeometry() {
        let params = parameters(centering: .always, boardCount: 4)

        #expect(
            BoardLayout.centeredScrollX(
                for: 1,
                in: params,
                containerWidth: 1_000,
                contentWidth: 2_000
            ) == 488
        )
        #expect(
            BoardLayout.centeredScrollX(
                for: 3,
                in: params,
                containerWidth: 1_000,
                contentWidth: 1_200
            ) == 200
        )
    }

    @Test func calculatesBoardHeightWithOptionalIndicator() {
        let size = CGSize(width: 1000, height: 800)
        let heightWithHeader = DenLayout.boardHeight(for: size, shouldShowHeader: true, shouldShowIndicator: false)
        let heightWithoutHeader = DenLayout.boardHeight(for: size, shouldShowHeader: false, shouldShowIndicator: false)
        let heightWithIndicator = DenLayout.boardHeight(for: size, shouldShowHeader: true, shouldShowIndicator: true)

        #expect(heightWithHeader == 800 - DenLayout.denHeaderHeight - DenLayout.outerInset)
        #expect(heightWithoutHeader == 800 - DenLayout.outerInset - DenLayout.outerInset)
        #expect(heightWithIndicator == heightWithHeader - DenLayout.boardIndicatorHeight)
    }

    @Test func newBoardWidthUsesHalfAvailableWindowWidthOrFocusedWidth() {
        let size = CGSize(width: 1000, height: 800)

        #expect(DenLayout.newBoardWidth(in: size, focusedBoardWidth: nil) == 488)
        #expect(DenLayout.newBoardWidth(in: size, focusedBoardWidth: 760) == 760)
    }

    @Test func boardWidthCalculatesEvenDistributionConstrainedToLimits() {
        #expect(DenLayout.boardWidth(toFit: 2, in: 1000, spacing: 10) == 495)
        #expect(DenLayout.boardWidth(toFit: 0, in: 1000) == nil)
        #expect(DenLayout.boardWidth(toFit: 10, in: 1000) == nil)
        #expect(DenLayout.boardWidth(toFit: 4, in: 800, spacing: 12) == nil)
        #expect(DenLayout.boardWidth(toFit: 1, in: 2000) == 2000)
    }

    private func paddings(
        for centering: FocusedBoardCentering,
        boardCount: Int
    ) -> (leading: CGFloat, trailing: CGFloat) {
        BoardLayout.calculatePaddings(for: parameters(centering: centering, boardCount: boardCount))
    }

    private func shouldCenterFocusedBoard(
        for centering: FocusedBoardCentering,
        boardCount: Int
    ) -> Bool {
        BoardLayout.shouldCenterFocusedBoard(for: parameters(centering: centering, boardCount: boardCount))
    }

    private func restingScrollX(
        for centering: FocusedBoardCentering,
        boardCount: Int
    ) -> CGFloat {
        BoardLayout.restingScrollX(for: parameters(centering: centering, boardCount: boardCount))
    }

    private func parameters(
        centering: FocusedBoardCentering,
        boardCount: Int
    ) -> BoardLayout.Parameters {
        .init(
            centering: centering,
            boards: (0..<boardCount).map {
                BoardState(label: "Board \($0)", width: 320, currentSheetURL: nil)
            },
            maximizedBoardID: nil,
            windowWidth: 1_000,
            horizontalPadding: 10,
            spacing: 8)
    }
}
