import Testing

@testable import Den_Browser

@MainActor
struct BoardLayoutTests {
    @Test func appliesCenteringPaddingForEachMode() {
        #expect(paddings(for: .always, boardCount: 3) == (leading: 340, trailing: 340))
        #expect(paddings(for: .never, boardCount: 3) == (leading: 10, trailing: 10))
        #expect(paddings(for: .onOverflow, boardCount: 3) == (leading: 12, trailing: 12))
        #expect(paddings(for: .onOverflow, boardCount: 4) == (leading: 340, trailing: 340))
    }

    private func paddings(
        for centering: FocusedBoardCentering,
        boardCount: Int
    ) -> (leading: CGFloat, trailing: CGFloat) {
        BoardLayout.calculatePaddings(
            for: .init(
                centering: centering,
                boards: (0..<boardCount).map {
                    BoardState(label: "Board \($0)", width: 320, currentSheetURL: nil)
                },
                maximizedBoardID: nil,
                windowWidth: 1_000,
                horizontalPadding: 10,
                spacing: 8))
    }
}
