import DenApplication
import DenDomain
import Foundation
import Testing

nonisolated struct DeskLinkExportTests {
    @Test func urlsPreserveBoardOrderAndDuplicatesWithoutDecoration() throws {
        // Arrange
        let firstURL = try #require(URL(string: "https://first.example/path?q=one&limit=2#section"))
        let secondURL = try #require(URL(string: "https://second.example/"))
        let desk = DeskState(
            label: "Research",
            boards: [
                BoardState(label: "First", width: 520, currentSheetURL: firstURL),
                BoardState(label: "Empty", width: 520, currentSheetURL: nil),
                BoardState(label: "Second", width: 520, currentSheetURL: secondURL),
                BoardState(label: "Duplicate", width: 520, currentSheetURL: firstURL),
            ])

        // Act
        let urls = DeskLinkExport.urls(for: desk)

        // Assert
        #expect(
            urls
                == "https://first.example/path?q=one&limit=2#section\nhttps://second.example/\nhttps://first.example/path?q=one&limit=2#section"
        )
    }

    @Test(arguments: [false, true])
    func urlsAreUnavailableWithoutCurrentSheetLinks(hasBoard: Bool) {
        // Arrange
        let boards = hasBoard ? [BoardState(label: "Empty", width: 520, currentSheetURL: nil)] : []
        let desk = DeskState(label: "Empty", boards: boards)

        // Act
        let urls = DeskLinkExport.urls(for: desk)

        // Assert
        #expect(urls == nil)
    }
}
