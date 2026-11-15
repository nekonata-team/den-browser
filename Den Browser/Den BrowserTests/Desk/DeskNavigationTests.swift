import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DeskNavigationTests {
    @Test func returnToPreviousDeskTogglesBetweenMostRecentDesks() {
        let first = makeTestDesk("First")
        let second = makeTestDesk("Second")
        let third = makeTestDesk("Third")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [first, second, third], focusedDeskID: first.id)
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.boardNavigation.focusDesk(second.id)
        session.boardNavigation.focusDesk(third.id)
        session.boardNavigation.returnToPreviousDesk()
        #expect(session.navigation.focusedDesk?.id == second.id)

        session.boardNavigation.returnToPreviousDesk()
        #expect(session.navigation.focusedDesk?.id == third.id)
    }

    @Test func normalizedPersistedStateEnsuresFocusedObjects() {
        let boardItem = makeTestBoard("Board")
        let tutorialBoard = BoardState(
            label: "Tutorial",
            width: 520,
            tutorial: TutorialBoardState()
        )
        var first = makeTestDesk(
            "First",
            boards: [tutorialBoard, boardItem],
            focusedBoardID: tutorialBoard.id
        )
        first.anchorBoardID = tutorialBoard.id
        first.scrollOffsetX = 80
        let second = makeTestDesk("Second")
        let tutorialOnlyBoard = BoardState(
            label: "Tutorial",
            width: 520,
            tutorial: TutorialBoardState()
        )
        let tutorialOnlyDesk = makeTestDesk(
            "Tutorial only",
            boards: [tutorialOnlyBoard],
            focusedBoardID: tutorialOnlyBoard.id
        )
        let rawState = DenState(desks: [second, first, tutorialOnlyDesk], focusedDeskID: DeskID())

        let normalized = DenStateNormalization.normalize(rawState)
        #expect(normalized.focusedDeskID == second.id)
        #expect(normalized.desks[1].focusedBoardID == boardItem.id)
        #expect(normalized.desks[1].boards.map(\.id) == [boardItem.id])
        #expect(normalized.desks[1].anchorBoardID == nil)
        #expect(normalized.desks[1].scrollOffsetX == nil)
        #expect(normalized.desks[2].boards.isEmpty)
        #expect(normalized.desks[2].focusedBoardID == nil)
    }

    @Test func focusDeskByNumberDelegatesToFocusDesk() {
        let first = makeTestDesk("First")
        let second = makeTestDesk("Second")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [first, second], focusedDeskID: first.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.isDenMode = true
        session.boardNavigation.focusDesk(number: 2)
        #expect(session.navigation.focusedDesk?.id == second.id)
        #expect(!windowModel.isDenMode)
    }

    @Test func deskLinkExportPreservesBoardOrderAndSkipsEmptyBoards() throws {
        let first = BoardState(
            label: "First [Reference]",
            width: 520,
            currentSheetURL: URL(string: "https://first.example/")
        )
        let empty = BoardState(label: "Empty", width: 520, currentSheetURL: nil)
        let second = BoardState(
            label: "Second",
            width: 520,
            currentSheetURL: URL(string: "https://second.example/path")
        )
        let desk = DeskState(label: "Research", boards: [first, empty, second])

        let expected = [
            "# Research",
            "",
            "- [First \\[Reference\\]](<https://first.example/>)",
            "- [Second](<https://second.example/path>)",
            "",
        ].joined(separator: "\n")
        #expect(DeskLinkExport.markdown(for: desk) == expected)
    }

    @Test func deskDragReordersPersistedDesksWithoutChangingTheirContents() {
        let firstBoard = makeTestBoard("First Board")
        let secondBoard = makeTestBoard("Second Board")
        let first = makeTestDesk("First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let second = makeTestDesk("Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let third = makeTestDesk("Third")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [first, second, third], focusedDeskID: first.id)
                ),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        #expect(session.resources.deskMovement.beginDrag(second.id))
        session.resources.deskMovement.preview(second.id, to: DeskIndex(rawValue: 2))
        session.runtimes.updateBoard(
            boardID: secondBoard.id,
            url: URL(string: "https://updated.example/"),
            title: "Updated title"
        )

        #expect(savedState == nil)

        session.resources.deskMovement.finishDrag()

        #expect(session.resources.state.desks.map(\.id) == [first.id, third.id, second.id])
        #expect(session.navigation.focusedDesk?.id == first.id)
        #expect(session.resources.state.desks[2].boards.map(\.id) == [secondBoard.id])
        #expect(session.resources.state.desks[2].focusedBoardID == secondBoard.id)
        #expect(
            session.resources.state.desks[2].boards[0].currentSheetURL == URL(string: "https://updated.example/")
        )
        #expect(session.resources.state.desks[2].boards[0].label == "Updated title")
        #expect(savedState == session.resources.state)

        session.resources.deskMovement.preview(second.id, to: DeskIndex(rawValue: 2))
        #expect(session.resources.state.desks.map(\.id) == [first.id, third.id, second.id])
    }

    @Test func movingDeskByAccessibilityActionReordersOneStepAndPreservesFocus() {
        let first = makeTestDesk("First")
        let second = makeTestDesk("Second")
        let third = makeTestDesk("Third")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [first, second, third], focusedDeskID: second.id)
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.resources.deskMovement.move(first.id, by: 1)

        #expect(session.resources.state.desks.map(\.id) == [second.id, first.id, third.id])
        #expect(session.navigation.focusedDesk?.id == second.id)

        session.resources.deskMovement.move(third.id, by: 1)
        #expect(session.resources.state.desks.map(\.id) == [second.id, first.id, third.id])

        #expect(session.resources.deskMovement.beginDrag(first.id))
        session.resources.deskMovement.move(third.id, by: -1)
        #expect(session.resources.state.desks.map(\.id) == [second.id, first.id, third.id])
        session.resources.deskMovement.finishDrag()
    }

    @Test func digitDeskMovementFocusesAndMovesToNumberedDesk() {
        let moving = makeTestBoard("Moving")
        let targetBoard = makeTestBoard("Target")
        let source = makeTestDesk("One", boards: [moving])
        let target = makeTestDesk("Two", boards: [targetBoard])
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, target]))
            )
        ) { session in
            session.boardNavigation.moveFocusedBoard(toDeskNumber: 2)

            #expect(session.navigation.focusedDesk?.id == target.id)
            #expect(session.resources.state.desks[1].boards.map(\.id) == [targetBoard.id, moving.id])

            session.boardNavigation.focusDesk(number: 1)
            #expect(session.navigation.focusedDesk?.id == source.id)
        }
    }

    @Test func deskRenaming() {
        let firstBoard = makeTestBoard("Google")
        let desk1 = makeTestDesk("Main", boards: [firstBoard], focusedBoardID: firstBoard.id)

        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk1]))
            )
        ) { session, windowModel in
            // 1. Enter Den Mode, show rename panel
            windowModel.isDenMode = true
            windowModel.showRenameDeskPanel()
            #expect(windowModel.isRenameDeskPanelPresented)

            // 2. Rename the desk to a custom name
            session.desks.renameFocusedDesk(to: "Web Search")
            #expect(!windowModel.isRenameDeskPanelPresented)
            #expect(session.navigation.focusedDesk?.label == "Web Search")

            // 3. Rename with empty name should be ignored (keep old name)
            windowModel.showRenameDeskPanel()
            session.desks.renameFocusedDesk(to: "")
            #expect(!windowModel.isRenameDeskPanelPresented)
            #expect(session.navigation.focusedDesk?.label == "Web Search")
        }
    }

    @Test func copyDeskIDCopiesLowercasedUUIDToPasteboardAndShowsFeedback() {
        let deskA = makeTestDesk("Desk A")
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [deskA]))
            )
        ) { session in
            let pasteboard = NSPasteboard.withUniqueName()
            session.desks.copyDeskID(deskA.id, pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == deskA.id.rawValue.uuidString.lowercased())
            #expect(session.feedback.latest?.message == "Copied Desk ID.")
            #expect(session.feedback.latest?.severity == .success)
        }
    }

    @Test func copyDeskIDIgnoresUnknownDeskID() {
        let deskA = makeTestDesk("Desk A")
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [deskA]))
            )
        ) { session in
            let pasteboard = NSPasteboard.withUniqueName()
            session.desks.copyDeskID(DeskID(), pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == nil)
            #expect(session.feedback.latest == nil)
        }
    }
}
