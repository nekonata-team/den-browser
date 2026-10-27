import DenDomain
import DenModels
import DenViews
import Testing

@testable import Den_Browser

@MainActor
struct BoardLayoutTests {
    @Test func visibleBoardsRequireMinimumOverlapAndPositiveViewport() {
        // Arrange
        let params = parameters(centering: .never, boardCount: 3)
        let first = BoardLayout.boardContentRange(for: 0, in: params)!
        let width = first.maxX - first.minX

        // Act
        let belowThreshold = BoardLayout.visibleBoardIDs(
            in: params, offsetX: first.maxX - width * 0.04, containerWidth: width)
        let aboveThreshold = BoardLayout.visibleBoardIDs(
            in: params, offsetX: first.maxX - width * 0.06, containerWidth: width)
        let emptyViewport = BoardLayout.visibleBoardIDs(in: params, offsetX: 0, containerWidth: 0)

        // Assert
        #expect(!belowThreshold.contains(params.boards[0].id))
        #expect(aboveThreshold.contains(params.boards[0].id))
        #expect(aboveThreshold.contains(params.boards[1].id))
        #expect(emptyViewport.isEmpty)
    }

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

    @Test func centersCombinedBoardSpan() {
        let params = parameters(centering: .always, boardCount: 4)

        #expect(
            BoardLayout.centeredScrollX(
                for: 1...2,
                in: params,
                containerWidth: 1_000,
                contentWidth: 2_000
            ) == 652
        )
    }

    @Test func removalCentersTheRemainingFocusedBoardWithoutMeasuredContentWidth() {
        // Arrange
        let params = parameters(centering: .always, boardCount: 2)

        // Act
        let target = BoardLayout.scrollTargetAfterLayoutChange(
            for: params.boards[1].id, in: params, currentScrollX: 1_500)

        // Assert
        #expect(target == 488)
    }

    @Test func removalReturnsToRestingPositionWhenBoardsNoLongerOverflow() {
        // Arrange
        let params = parameters(centering: .onOverflow, boardCount: 3)

        // Act
        let target = BoardLayout.scrollTargetAfterLayoutChange(
            for: params.boards[1].id, in: params, currentScrollX: 1_000)

        // Assert
        #expect(target == 488)
    }

    @Test func removalClampsScrollToTheRemainingContentWhenCenteringIsDisabled() {
        // Arrange
        let params = parameters(centering: .never, boardCount: 3)

        // Act
        let target = BoardLayout.scrollTargetAfterLayoutChange(
            for: params.boards[2].id, in: params, currentScrollX: 800)
        let fittingParams = parameters(centering: .never, boardCount: 1)
        let fittingTarget = BoardLayout.scrollTargetAfterLayoutChange(
            for: fittingParams.boards[0].id, in: fittingParams, currentScrollX: 800)

        // Assert
        #expect(target == 52)
        #expect(fittingTarget == 0)
    }

    @Test func removalRevealsTheFocusedBoardWhenCenteringIsDisabled() {
        // Arrange
        let params = parameters(centering: .never, boardCount: 4)

        // Act
        let target = BoardLayout.scrollTargetAfterLayoutChange(
            for: params.boards[3].id, in: params, currentScrollX: 0)

        // Assert
        #expect(target == 324)
    }

    @Test func removalCentersTheRemainingPrimaryAndSideBoardTogether() {
        // Arrange
        let primary = BoardState(label: "Primary", width: 500, currentSheetURL: nil)
        let side = BoardState(label: "Inspection Board", width: 360, targetBoardID: primary.id)
        let params = BoardLayout.Parameters(
            centering: .always, boards: [primary, side], maximizedBoardID: nil,
            windowWidth: 1_000, horizontalPadding: 10, spacing: 8)

        // Act
        let primaryTarget = BoardLayout.scrollTargetAfterLayoutChange(
            for: primary.id, in: params, currentScrollX: 1_000)
        let sideTarget = BoardLayout.scrollTargetAfterLayoutChange(
            for: side.id, in: params, currentScrollX: 1_000)

        // Assert
        #expect(primaryTarget == 432)
        #expect(sideTarget == primaryTarget)
    }

    @Test(arguments: [-80.0, 80.0])
    func resizingMovesScrollWithTheFocusedBoardCenter(delta: Double) {
        // Arrange
        let original = parameters(centering: .always, boardCount: 4)
        var boards = original.boards
        for index in boards.indices { boards[index].width = BoardState.constrainedWidth(boards[index].width + delta) }
        let resized = BoardLayout.Parameters(
            centering: original.centering, boards: boards, maximizedBoardID: nil,
            windowWidth: original.windowWidth, horizontalPadding: original.horizontalPadding,
            spacing: original.spacing)
        let focusedIndex = 2
        let originalOffset = BoardLayout.scrollTargetAfterLayoutChange(
            for: boards[focusedIndex].id, in: original, currentScrollX: 0)!

        // Act
        let resizedOffset = BoardLayout.scrollTargetAfterLayoutChange(
            for: boards[focusedIndex].id, in: resized, currentScrollX: originalOffset)!

        // Assert
        let widthChange = boards[focusedIndex].width - original.boards[focusedIndex].width
        #expect(abs(resizedOffset - originalOffset - widthChange * (Double(focusedIndex) + 0.5)) < 0.001)
        let range = BoardLayout.boardContentRange(for: focusedIndex, in: resized)!
        #expect(abs((range.minX + range.maxX) / 2 - resizedOffset - resized.windowWidth / 2) < 0.001)
    }

    @Test(arguments: [FocusedBoardCentering.never, .onOverflow])
    func explicitCenterRequestOverridesRestingResizePosition(centering: FocusedBoardCentering) {
        // Arrange
        let params = parameters(centering: centering, boardCount: 3)
        let boardIndex = 2

        // Act
        let target = BoardLayout.scrollTargetAfterLayoutChange(
            for: params.boards[boardIndex].id, in: params, currentScrollX: 0, forceCenter: true)
        let expected = BoardLayout.centeredScrollX(
            for: boardIndex, in: params,
            containerWidth: params.windowWidth, contentWidth: BoardLayout.contentWidth(for: params))

        // Assert
        #expect(target == expected)
        #expect(target != BoardLayout.restingScrollX(for: params))
    }

    @Test func calculatesContentWidthForEachMode() {
        let alwaysParams = parameters(centering: .always, boardCount: 3)
        #expect(BoardLayout.contentWidth(for: alwaysParams) == 1_976)
        #expect(BoardLayout.contentWidth(for: alwaysParams, isDeskFilterPresented: true) == 1_920)

        let neverParams = parameters(centering: .never, boardCount: 3)
        #expect(BoardLayout.contentWidth(for: neverParams) == 1_052)
        #expect(BoardLayout.contentWidth(for: neverParams, isDeskFilterPresented: true) == 996)

        let emptyParams = parameters(centering: .always, boardCount: 0)
        #expect(BoardLayout.contentWidth(for: emptyParams) == 1_000)
    }

    @Test func usesTighterSpacingBetweenPrimaryAndSideBoard() {
        let primary = BoardState(label: "Primary", width: 500, currentSheetURL: nil)
        let side = BoardState(label: "Inspection Board", width: 360, targetBoardID: primary.id)
        let next = BoardState(label: "Next", width: 500, currentSheetURL: nil)
        let params = BoardLayout.Parameters(
            centering: .never,
            boards: [primary, side, next],
            maximizedBoardID: nil,
            windowWidth: 1_000,
            horizontalPadding: 10,
            spacing: 8
        )

        #expect(params.spacingAfterBoard(at: 0) == 4)
        #expect(params.spacingAfterBoard(at: 1) == 8)
        #expect(BoardLayout.boardContentRange(for: 0, in: params)?.minX == 10)
        #expect(BoardLayout.boardContentRange(for: 1, in: params)?.minX == 514)
        #expect(BoardLayout.boardContentRange(for: 2, in: params)?.minX == 882)
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
