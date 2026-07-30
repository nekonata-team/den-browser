import Testing

@testable import Den_Browser

@MainActor
struct BoardLayoutTests {
    @Test func appliesCenteringPaddingForEachMode() {
        #expect(paddings(for: .always, boardCount: 3) == (leading: 340, trailing: 340))
        #expect(paddings(for: .never, boardCount: 3) == (leading: 10, trailing: 10))
        #expect(paddings(for: .onOverflow, boardCount: 3) == (leading: 340, trailing: 340))
        #expect(paddings(for: .onOverflow, boardCount: 4) == (leading: 340, trailing: 340))
    }

    @Test func keepsOnOverflowCoordinatesStableWhenBoardsStartOverflowing() {
        #expect(restingScrollX(for: .onOverflow, boardCount: 3) == 328)
        #expect(restingScrollX(for: .onOverflow, boardCount: 4) == 0)
    }

    @Test func centersFocusedBoardOnlyWhenRequestedOrBoardsOverflow() {
        #expect(shouldCenterFocusedBoard(for: .always, boardCount: 3))
        #expect(!shouldCenterFocusedBoard(for: .never, boardCount: 3))
        #expect(!shouldCenterFocusedBoard(for: .onOverflow, boardCount: 3))
        #expect(shouldCenterFocusedBoard(for: .never, boardCount: 4))
        #expect(shouldCenterFocusedBoard(for: .onOverflow, boardCount: 4))
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
