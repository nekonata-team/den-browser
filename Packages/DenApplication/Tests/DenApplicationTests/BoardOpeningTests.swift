import DenApplication
import DenDomain
import Foundation
import Testing

@MainActor
struct BoardOpeningTests {
    @Test func webDecisionCarriesCanonicalURLWidthAndRecent() throws {
        // Arrange
        let input = "https://example.com/docs#section"

        // Act
        let decision = resolve(input)

        // Assert
        guard case .createBoard(let board, let recent) = decision else {
            Issue.record("Expected a Board creation decision")
            return
        }
        #expect(board.currentSheetURL == WebURLPolicy.canonicalSheetURL(try #require(URL(string: input))))
        #expect(board.label == "example.com")
        #expect(board.width == 520)
        #expect(recent == .url(try #require(URL(string: input))))
    }

    @Test(arguments: [2_048, 2_049])
    func recentInputLengthLimitDoesNotPreventCreation(length: Int) {
        // Arrange
        let input = String(repeating: "x", count: length)

        // Act
        let decision = resolve(input)

        // Assert
        guard case .createBoard(_, let recent) = decision else {
            Issue.record("Expected a Board creation decision")
            return
        }
        #expect(recent == (length <= BoardOpening.maximumPersistedRecentInputLength ? .search(input) : nil))
    }

    @Test func sessionSelectionReturnsWithoutCreatingABoard() {
        // Arrange
        let input = ":zmx"

        // Act
        let decision = resolve(input)

        // Assert
        guard case .selectZmxSession = decision else {
            Issue.record("Expected Session selection")
            return
        }
    }

    @Test func tutorialReturnsWithoutResolvingATerminalDirectory() {
        // Arrange
        let input = "  :tutorial\n"

        // Act
        let decision = resolve(input) { _ in
            Issue.record("Tutorial must not resolve a Terminal directory")
            return false
        }

        // Assert
        guard case .openTutorial = decision else {
            Issue.record("Expected a Tutorial opening decision")
            return
        }
    }

    @Test func zmxDecisionPreservesRootSessionAndHomeDirectory() {
        // Arrange
        let input = ":zmx project"

        // Act
        let decision = resolve(input)

        // Assert
        guard case .createBoard(let board, let recent) = decision else {
            Issue.record("Expected a Board creation decision")
            return
        }
        #expect(board.zmxSessionName == "project")
        #expect(board.zmxRootSessionName == "root")
        #expect(board.terminalWorkingDirectory == "/home/test")
        #expect(recent == .zmx(sessionName: "project"))
    }

    @Test(arguments: [":zmx project", ":zellij project"])
    func unconfiguredSessionToolsAreRejected(input: String) {
        // Arrange
        let configuration = BoardOpening.Configuration(
            searchEngine: .google, zmxConfigured: false, zellijConfigured: false,
            homeDirectory: URL(fileURLWithPath: "/home/test"))

        // Act
        let decision = BoardOpening.resolve(
            input: input, width: 520, configuration: configuration, directoryExists: { _ in true })

        // Assert
        switch decision {
        case .rejected(.zmxNotConfigured): #expect(input == ":zmx project")
        case .rejected(.zellijNotConfigured): #expect(input == ":zellij project")
        default: Issue.record("Expected a missing-tool configuration failure")
        }
    }

    @Test func missingTerminalDirectoryReturnsTheResolvedPath() {
        // Arrange
        let input = ":terminal missing"

        // Act
        let decision = resolve(input, directoryExists: { _ in false })

        // Assert
        guard case .rejected(.terminalDirectoryMissing(let path)) = decision else {
            Issue.record("Expected a missing-directory failure")
            return
        }
        #expect(path == "/home/test/missing")
    }

    private func resolve(
        _ input: String, directoryExists: (String) -> Bool = { _ in true }
    ) -> BoardOpening.Decision {
        BoardOpening.resolve(
            input: input, width: 520, zmxRootSessionName: "root",
            configuration: BoardOpening.Configuration(
                searchEngine: .google, zmxConfigured: true, zellijConfigured: true,
                homeDirectory: URL(fileURLWithPath: "/home/test")),
            directoryExists: directoryExists)
    }
}
