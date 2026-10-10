import DenApplication
import DenDomain
import Foundation
import Testing

@MainActor
struct BoardOpeningTests {
    @Test(arguments: [true, false])
    func recordsRecentOnlyAfterSuccessfulInsertion(_ succeeds: Bool) {
        // Arrange
        var events: [String] = []
        let actions = BoardOpening.Actions(
            openTutorial: { _, _ in false },
            insertBoard: { _, _, savesImmediately in
                #expect(!savesImmediately)
                events.append("insert")
                return succeeds
            },
            recordRecent: { _ in events.append("recent") })

        // Act
        let outcome = open("https://example.com", actions: actions)

        // Assert
        #expect(events == (succeeds ? ["insert", "recent"] : ["insert"]))
        if succeeds {
            guard case .openedBoard = outcome else {
                Issue.record("Expected a Board to open")
                return
            }
        } else {
            guard case .rejected(.creationFailed) = outcome else {
                Issue.record("Expected insertion failure")
                return
            }
        }
    }

    @Test func sessionSelectionDoesNotCreateBoardOrRecordRecent() {
        // Arrange
        let actions = BoardOpening.Actions(
            openTutorial: { _, _ in false },
            insertBoard: { _, _, _ in
                Issue.record("Session selection must not insert a Board")
                return false
            },
            recordRecent: { _ in Issue.record("Session selection must not record Recent") })

        // Act
        let outcome = open(":zmx", actions: actions)

        // Assert
        guard case .selectZmxSession = outcome else {
            Issue.record("Expected Session selection")
            return
        }
    }

    @Test func longInputOpensWithoutRecordingRecent() {
        // Arrange
        var inserted = false
        let input = String(repeating: "x", count: BoardOpening.maximumPersistedRecentInputLength + 1)
        let actions = BoardOpening.Actions(
            openTutorial: { _, _ in false },
            insertBoard: { _, _, savesImmediately in
                #expect(savesImmediately)
                inserted = true
                return true
            },
            recordRecent: { _ in Issue.record("Oversized input must not be recorded") })

        // Act
        let outcome = open(input, actions: actions)

        // Assert
        #expect(inserted)
        guard case .openedBoard = outcome else {
            Issue.record("Expected a Board to open")
            return
        }
    }

    private func open(_ input: String, actions: BoardOpening.Actions) -> BoardOpening.Outcome {
        BoardOpening.open(
            input: input,
            width: 520,
            configuration: BoardOpening.Configuration(
                searchEngine: .google,
                zmxConfigured: true,
                zellijConfigured: true,
                homeDirectory: URL(fileURLWithPath: "/home/test")),
            directoryExists: { _ in true },
            actions: actions)
    }
}
