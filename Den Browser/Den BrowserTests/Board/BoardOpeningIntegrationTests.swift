import DenApplication
import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct BoardOpeningIntegrationTests {
    @Test(arguments: [true, false])
    func recentAndPersistenceFollowSuccessfulInsertion(targetExists: Bool) {
        // Arrange
        let anchor = BoardState(label: "Anchor", width: 520, workingDirectory: "/tmp")
        var events: [String] = []
        withTestController(
            boards: [anchor],
            onRecentItemsSave: { _ in
                events.append("recent")
                return true
            },
            onSave: { state in
                #expect(state.desks.flatMap(\.boards).count == 2)
                events.append("save")
                return true
            },
            body: { controller in
                // Act
                let result = controller.requestOpenBoard(
                    input: "https://example.com", afterBoardID: targetExists ? anchor.id : BoardID())

                // Assert
                #expect(controller.state.desks.flatMap(\.boards).count == (targetExists ? 2 : 1))
                #expect(controller.recentItems.count == (targetExists ? 1 : 0))
                #expect(events == (targetExists ? ["save"] : []))
                switch result {
                case .accepted: #expect(targetExists)
                case .rejected: #expect(!targetExists)
                }
            })
    }

    @Test func oversizedInputSavesInsertionWithoutRecent() {
        // Arrange
        var saveCount = 0
        let input = String(repeating: "x", count: BoardOpening.maximumPersistedRecentInputLength + 1)
        withTestController(
            onRecentItemsSave: { _ in
                Issue.record("Oversized input must not be recorded")
                return true
            },
            onSave: { _ in
                saveCount += 1
                return true
            },
            body: { controller in
                // Act
                let result = controller.requestOpenBoard(input: input)

                // Assert
                guard case .accepted = result else {
                    Issue.record("Expected a Board to open")
                    return
                }
                #expect(controller.state.desks.flatMap(\.boards).count == 1)
                #expect(controller.recentItems.isEmpty)
                #expect(saveCount == 1)
            })
    }
}
