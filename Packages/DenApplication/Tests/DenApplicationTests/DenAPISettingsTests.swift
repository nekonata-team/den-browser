import DenApplication
import DenDomain
import Foundation
import Testing

nonisolated struct DenAPISettingsTests {
    private final class State {
        var snapshot: DenSharedState
        init(_ snapshot: DenSharedState) { self.snapshot = snapshot }
    }

    @Test func boardFlagSurvivesNavigationAndCodingWhileLegacyBoardsRemainDisabled() throws {
        // Arrange
        let original = URL(fileURLWithPath: "/tmp/Sketch notes.html")
        var board = BoardState(label: "Sketch", width: 520, currentSheetURL: original)
        board.denAPIEnabled = true

        // Act
        board.currentSheetURL = URL(string: "https://example.com/")
        let restored = try JSONDecoder().decode(BoardState.self, from: JSONEncoder().encode(board))
        let legacy = BoardState(label: "Legacy", width: 520, currentSheetURL: original)
        let restoredLegacy = try JSONDecoder().decode(BoardState.self, from: JSONEncoder().encode(legacy))

        // Assert
        #expect(restored.denAPIEnabled)
        #expect(!DenAPIPolicy.isLocalHTML(restored.currentSheetURL))
        #expect(DenAPIPolicy.isLocalHTML(original))
        #expect(!restoredLegacy.denAPIEnabled)
    }

    @Test(arguments: ["https://example.com/file.html", "file:///tmp/report.pdf", "file://remote/tmp/file.html"])
    func rejectsUnsupportedTargets(value: String) {
        // Arrange / Act / Assert
        #expect(!DenAPIPolicy.isLocalHTML(URL(string: value)))
    }

    @Test func permissionSaveRetainsIntendedStateOnFailureAndCanBeDisabled() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp/sketch.html")
        let board = BoardState(label: "Sketch", width: 520, currentSheetURL: url)
        let desk = DeskState(label: "Desk", boards: [board])
        let state = State(DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var canSave = false
        var saved: DenState?
        let updates = BoardUpdates(
            reader: DenStateReader { state.snapshot },
            writer: DenStateWriter { $0(&state.snapshot) },
            persist: { den in
                if canSave { saved = den }
                return canSave
            })

        // Act / Assert
        #expect(!updates.setDenAPIEnabled(board.id, enabled: true))
        #expect(state.snapshot.den.board(for: board.id)?.denAPIEnabled == true)
        canSave = true
        #expect(updates.setDenAPIEnabled(board.id, enabled: true))
        #expect(saved?.board(for: board.id)?.denAPIEnabled == true)
        #expect(updates.setDenAPIEnabled(board.id, enabled: false))
        #expect(saved?.board(for: board.id)?.denAPIEnabled == false)
    }

    @Test func creationGrantsOnlyTheNewBoardAndRejectsNonHTMLBeforeInsertion() throws {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [])
        let state = State(DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let reader = DenStateReader { state.snapshot }
        let writer = DenStateWriter { $0(&state.snapshot) }
        let creation = BoardCreation(
            reader: reader, writer: writer, recents: Recents(reader: reader, writer: writer),
            directoryExists: { _ in true })
        let url = URL(fileURLWithPath: "/tmp/sketch.html")

        // Act
        let enabled = try #require(
            creation.createWeb(
                urlString: url.absoluteString, width: 520, searchEngine: .google,
                target: .init(presentedDeskID: desk.id), denAPI: true, notify: { _ in }))
        let plain = try #require(
            creation.createWeb(
                urlString: url.absoluteString, width: 520, searchEngine: .google,
                target: .init(presentedDeskID: desk.id), notify: { _ in }))
        let rejected = creation.createWeb(
            urlString: "https://example.com/", width: 520, searchEngine: .google,
            target: .init(presentedDeskID: desk.id), denAPI: true, notify: { _ in })

        // Assert
        #expect(state.snapshot.den.board(for: enabled)?.denAPIEnabled == true)
        #expect(state.snapshot.den.board(for: plain)?.denAPIEnabled == false)
        #expect(rejected == nil)
        #expect(state.snapshot.den.desks[0].boards.count == 2)
    }
}
