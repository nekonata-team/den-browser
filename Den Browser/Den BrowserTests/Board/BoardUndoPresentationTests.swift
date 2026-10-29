import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct BoardUndoPresentationTests {
    @Test(arguments: [false, true])
    func denModeUndoUsesTheSameHistoryWithDrawerOpen(drawerOpen: Bool) throws {
        // Arrange
        let board = BoardState(width: 520, workingDirectory: "/tmp")
        let first = DeskState(label: "First", boards: [board], focusedBoardID: board.id)
        let second = DeskState(label: "Second", boards: [])
        let session = makeSession([first, second])
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        let model = composition.model
        #expect(session.resources.boardMovement.place(board.id, in: second.id, before: nil))
        session.boardNavigation.focusDesk(second.id)
        if drawerOpen { model.openDrawer() }
        model.isDenMode = true
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, characters: "u", charactersIgnoringModifiers: "u", isARepeat: false, keyCode: 32))

        // Act
        let decision = KeyboardRouter.route(
            event: KeyEvent(event),
            context: InputContext(session: session, windowModel: model, event: event),
            shortcuts: ShortcutConfiguration(preferences: session.configuration.preferences))
        if case .perform(let action) = decision {
            AppActionHandler.perform(action, session: session, windowModel: model, openSettings: {})
        }

        // Assert
        #expect(decision == .perform(.board(.undo)))
        #expect(session.resources.state.desks[0].boards.map(\.id) == [board.id])
        #expect(session.resources.state.desks[1].boards.isEmpty)
        #expect(session.navigation.presentedDeskID == first.id)
        #expect(model.isDenMode)
        #expect(!model.isDrawerOpen)
    }

    @Test(arguments: [false, true])
    func undoPlacementShowsReturnedDrawerItemAndPreservesInputMode(denMode: Bool) throws {
        // Arrange
        let item = DrawerItem(terminal: .shell(workingDirectory: "/tmp"))
        let desk = DeskState(label: "Desk", boards: [])
        let session = makeSession([desk])
        session.resources.state.drawerItems = [item]
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        #expect(session.drawer.placeDrawerItemAsBoard(item.id) == BoardID(item.id))
        composition.model.isDenMode = denMode

        // Act
        session.boardRemoval.undoBoardOperation()

        // Assert
        #expect(composition.model.isDrawerOpen)
        #expect(composition.model.drawer.selectedItemID == item.id)
        #expect(composition.model.drawer.expandedItemID == item.id)
        #expect(composition.model.isDenMode == denMode)
    }

    @Test func undoDrawerMoveClosesDrawerEvenWhenOtherItemsRemain() throws {
        // Arrange
        let board = BoardState(width: 640, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let session = makeSession([desk])
        let other = DrawerItem(terminal: .shell(workingDirectory: "/tmp"))
        session.resources.state.drawerItems = [other]
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.moveBoardToDrawer(board.id)
        composition.model.openDrawer()
        composition.model.isDenMode = true

        // Act
        #expect(session.boardRemoval.undoBoardOperation() == board.id)

        // Assert
        #expect(!composition.model.isDrawerOpen)
        #expect(session.resources.state.drawerItems.map(\.id) == [other.id])
        #expect(session.navigation.focusedBoard?.id == board.id)
        #expect(composition.model.isDenMode)
    }

    @Test func undoPlacementInOverviewKeepsOverviewInsteadOfOpeningDrawer() throws {
        // Arrange
        let item = DrawerItem(terminal: .shell(workingDirectory: "/tmp"))
        let desk = DeskState(label: "Desk", boards: [])
        let session = makeSession([desk])
        session.resources.state.drawerItems = [item]
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        #expect(session.drawer.placeDrawerItemAsBoard(item.id) == BoardID(item.id))
        composition.model.showOverview()

        // Act
        composition.model.overview.undoBoardOperation()

        // Assert
        #expect(composition.model.isOverviewPresented)
        #expect(!composition.model.isDrawerOpen)
        #expect(session.resources.state.drawerItems.map(\.id) == [item.id])
    }

    @Test(arguments: [false, true])
    func overviewUndoSelectsReturnedBoardAndKeepsOverviewOpen(fromMenu: Bool) {
        // Arrange
        let board = BoardState(width: 520, workingDirectory: "/tmp")
        let first = DeskState(label: "First", boards: [board], focusedBoardID: board.id)
        let second = DeskState(label: "Second", boards: [])
        let session = makeSession([first, second])
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        composition.model.showOverview()
        session.resources.boardMovement.transferInOverview(board.id, by: 1)
        composition.model.overview.selectBoard(board.id)

        // Act
        AppActionHandler.perform(
            fromMenu ? .board(.undo) : .overview(.undoBoardOperation), session: session,
            windowModel: composition.model, openSettings: {})

        // Assert
        #expect(session.resources.state.desks[0].boards.map(\.id) == [board.id])
        #expect(composition.model.overview.selectionDeskID == first.id)
        #expect(composition.model.overview.selectionBoardID == board.id)
        #expect(composition.model.isOverviewPresented)
        #expect(session.navigation.presentedDeskID == first.id)
    }

    @Test func undoDrawerRoundTripPreservesWebRuntimeAndRoutesMetadataToItsCurrentOwner() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "sheet.html")
        try "<html><body>Work</body></html>".write(to: url, atomically: true, encoding: .utf8)
        let board = BoardState(label: "Work", width: 640, currentSheetURL: url)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let session = makeSession([desk])
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer {
            composition.disconnect()
            session.runtimes.releaseRuntimes()
        }
        let runtime = session.runtimes.webRuntime(for: board)
        composition.model.isDenMode = true

        // Act
        session.drawer.moveBoardToDrawer(board.id)
        #expect(session.resources.drawerRuntimes.web[board.id.rawValue] === runtime)
        #expect(session.boardRemoval.undoBoardOperation() == board.id)
        runtime.handleURLOrTitleChange(url: url, title: "Continued")

        // Assert
        #expect(session.resources.webRuntimes[board.id] === runtime)
        #expect(session.resources.drawerRuntimes.web.isEmpty)
        #expect(session.navigation.focusedBoard?.label == "Continued")
        #expect(session.navigation.focusedBoard?.width == 640)
        #expect(composition.model.isDenMode)

        // Act: undo placement in the opposite direction.
        session.drawer.moveBoardToDrawer(board.id)
        #expect(session.drawer.placeDrawerItemAsBoard(board.id.rawValue) == board.id)
        session.boardRemoval.undoBoardOperation()
        runtime.handleURLOrTitleChange(url: url, title: "In Drawer")

        // Assert
        #expect(session.resources.drawerRuntimes.web[board.id.rawValue] === runtime)
        #expect(session.resources.webRuntimes[board.id] == nil)
        #expect(session.resources.state.drawerItems.first?.title == "In Drawer")
    }

    @Test func undoDrawerMoveKeepsTerminalRuntimeAndItsEventDestination() throws {
        // Arrange
        let board = BoardState(width: 640, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let session = makeSession([desk])
        defer { session.runtimes.releaseRuntimes() }
        let runtime = session.runtimes.terminalRuntime(for: board)
        session.drawer.moveBoardToDrawer(board.id)

        // Act
        #expect(session.boardRemoval.undoBoardOperation() == board.id)
        runtime.terminalDidChangeWorkingDirectory("/var/tmp")
        runtime.terminalDidChangeTitle("Continued")

        // Assert
        #expect(session.resources.terminalRuntimes[board.id] === runtime)
        #expect(session.resources.drawerRuntimes.terminal.isEmpty)
        #expect(session.navigation.focusedBoard?.terminalWorkingDirectory == "/var/tmp")
        #expect(session.navigation.focusedBoard?.label == "Continued")
    }

    private func makeSession(_ desks: [DeskState]) -> ProfileWindowSession {
        ProfileWindowSession(
            resources: DenProfileResources(state: DenState(desks: desks, focusedDeskID: desks[0].id)),
            configuration: makeTestBoardRuntimeConfiguration())
    }
}
