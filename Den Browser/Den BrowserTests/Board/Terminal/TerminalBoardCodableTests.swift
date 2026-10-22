import DenDomain
import Foundation
import Testing

@MainActor
struct TerminalBoardCodableTests {
    @Test(arguments: [nil, "project"] as [String?])
    func zellijPreservesOptionalSessionName(sessionName: String?) throws {
        // Arrange
        let board = BoardState(width: 520, zellijSessionName: sessionName)

        // Act
        let restored = try JSONDecoder().decode(BoardState.self, from: JSONEncoder().encode(board))

        // Assert
        #expect(restored.kind == .terminal(.zellij(ZellijBoardState(sessionName: sessionName))))
    }

    @Test(arguments: [nil, "root"] as [String?])
    func zmxPreservesSessionDirectoryAndRoot(rootSessionName: String?) throws {
        // Arrange
        let board = BoardState(
            width: 520, zmxSessionName: "project", workingDirectory: "/tmp/project",
            rootSessionName: rootSessionName)

        // Act
        let restored = try JSONDecoder().decode(BoardState.self, from: JSONEncoder().encode(board))

        // Assert
        #expect(
            restored.kind
                == .terminal(
                    .zmx(
                        ZmxBoardState(
                            sessionName: "project", workingDirectory: "/tmp/project", rootSessionName: rootSessionName))
                ))
    }
}
