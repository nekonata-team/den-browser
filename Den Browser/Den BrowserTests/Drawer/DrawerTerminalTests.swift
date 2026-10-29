import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import GhosttyTerminal
import SwiftUI
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DrawerTerminalTests {
    @Test func creatingTerminalSelectsAndExpandsItWithoutAddingBoard() throws {
        // Arrange
        let (session, _) = sessions(DrawerItem(terminal: .shell(workingDirectory: "/tmp")))
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }

        // Act
        composition.model.drawer.createTerminal()

        // Assert
        let item = try #require(session.resources.state.drawerItems.first)
        #expect(session.resources.state.drawerItems.count == 2)
        #expect(item.terminal == .shell(workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path))
        #expect(composition.model.isDrawerOpen)
        #expect(composition.model.drawer.selectedItemID == item.id)
        #expect(composition.model.drawer.expandedItemID == item.id)
        #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        #expect(session.resources.drawerRuntimes.terminal.isEmpty)
    }

    @Test(arguments: ["project", "/work", "Build"])
    func filterFindsTerminalSessionAfterItsTitleChanges(query: String) {
        // Arrange
        let item = DrawerItem(
            terminal: .zmx(ZmxBoardState(sessionName: "project", workingDirectory: "/work", rootSessionName: nil)),
            title: "Build")
        let (session, _) = sessions(item)
        let model = DenWindowComposition(session: session).model.drawer

        // Act
        model.setQuery(query)

        // Assert
        #expect(model.filteredItems == [item])
        #expect(session.resources.drawerRuntimes.terminal.isEmpty)
    }

    @Test func terminalMovesBetweenWindowsAndTransfersToBoardWithoutRestarting() throws {
        // Arrange
        let item = DrawerItem(terminal: .shell(workingDirectory: "/tmp"))
        let (first, second) = sessions(item)
        let firstComposition = DenWindowComposition(session: first)
        let secondComposition = DenWindowComposition(session: second)
        firstComposition.connect()
        secondComposition.connect()
        defer {
            firstComposition.disconnect()
            secondComposition.disconnect()
            first.runtimes.releaseRuntimes()
        }
        firstComposition.model.focusDrawerItem(item.id)
        let runtime = first.drawer.drawerTerminalRuntime(for: item)

        // Act
        secondComposition.model.focusDrawerItem(item.id)
        let moved = second.drawer.drawerTerminalRuntime(for: item)
        let boardID = try #require(second.drawer.placeDrawerItemAsBoard(item.id))
        runtime.terminalDidChangeWorkingDirectory("/tmp/continued")
        runtime.terminalDidChangeTitle("Continued")

        // Assert
        #expect(moved === runtime)
        #expect(firstComposition.model.drawer.expandedItemID == nil)
        #expect(first.windowResources.drawerTerminalPeek == nil)
        #expect(second.windowResources.drawerTerminalPeek == nil)
        #expect(boardID == BoardID(item.id))
        #expect(second.resources.terminalRuntimes[boardID] === runtime)
        #expect(second.resources.drawerRuntimes.terminal.isEmpty)
        #expect(second.navigation.focusedBoard?.terminalWorkingDirectory == "/tmp/continued")
        #expect(second.navigation.focusedBoard?.label == "Continued")
        #expect(runtime.terminalView.controller != nil)
    }

    @Test func failedPlacementRetainsTerminalAndDiscardDisposesIt() throws {
        // Arrange
        let item = DrawerItem(terminal: .shell(workingDirectory: "/tmp"))
        let (session, _) = sessions(item)
        defer { session.runtimes.releaseRuntimes() }
        let runtime = session.drawer.drawerTerminalRuntime(for: item)

        // Act
        let result = session.drawer.placeDrawerItemAsBoard(item.id, deskID: DeskID())

        // Assert
        #expect(result == nil)
        #expect(session.resources.drawerRuntimes.terminal[item.id] === runtime)
        #expect(session.resources.state.drawerItems == [item])
        #expect(runtime.terminalView.controller != nil)

        // Act
        session.runtimes.releaseDrawerPeek()
        session.drawer.discardDrawerItem(item.id)

        // Assert
        #expect(session.resources.drawerRuntimes.terminal.isEmpty)
        #expect(runtime.terminalView.controller == nil)
    }

    @Test func terminalEventsSurviveThePresentingWindowClosing() async {
        // Arrange
        let item = DrawerItem(terminal: .shell(workingDirectory: "/tmp"))
        let (first, second) = sessions(item)
        defer { second.runtimes.releaseRuntimes() }
        let runtime = first.drawer.drawerTerminalRuntime(for: item)

        // Act
        first.connection.disconnect()
        first.runtimes.releaseWindowResources()
        runtime.terminalDidChangeWorkingDirectory("/tmp/continued")
        runtime.terminalDidChangeTitle("Continued")
        runtime.terminalDidRequestDesktopNotification(title: "Finished", body: "Work completed")

        // Assert
        #expect(second.resources.state.drawerItems[0].terminal == .shell(workingDirectory: "/tmp/continued"))
        #expect(second.resources.state.drawerItems[0].title == "Continued")
        #expect(second.resources.drawerRuntimes.terminal[item.id] === runtime)
        #expect(second.feedback.latest?.target == .drawerItem(item.id))

        // Act
        runtime.terminalDidClose(processAlive: false)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        // Assert
        #expect(second.resources.state.drawerItems.isEmpty)
        #expect(second.resources.drawerRuntimes.terminal.isEmpty)
        #expect(runtime.terminalView.controller == nil)
    }

    @Test func releasingProfileRuntimesClearsEveryTerminalPresentation() {
        // Arrange
        let item = DrawerItem(terminal: .shell(workingDirectory: "/tmp"))
        let (first, second) = sessions(item)
        let runtime = first.drawer.drawerTerminalRuntime(for: item)

        // Act
        second.runtimes.releaseRuntimes()

        // Assert
        #expect(first.windowResources.drawerTerminalPeek == nil)
        #expect(second.windowResources.drawerTerminalPeek == nil)
        #expect(first.resources.drawerRuntimes.terminal.isEmpty)
        #expect(runtime.terminalView.controller == nil)
    }

    @Test func shellStateSurvivesUnmountingAndPlacement() async throws {
        // Arrange
        let item = DrawerItem(terminal: .shell(workingDirectory: "/tmp"))
        let (session, _) = sessions(item)
        let runtime = session.drawer.drawerTerminalRuntime(for: item)
        let window = TestWindow()
        defer {
            window.contentView = nil
            session.runtimes.releaseRuntimes()
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        window.contentView = NSHostingView(rootView: surface(runtime))
        window.contentView?.layoutSubtreeIfNeeded()
        runtime.runCommand("drawer_probe_value=retained; printf 'drawer_ready_%s\\n' '\(token)'")
        try await waitForText("drawer_ready_\(token)", runtime: runtime)

        // Act
        window.contentView = nil
        session.runtimes.releaseDrawerPeek()
        let boardID = try #require(session.drawer.placeDrawerItemAsBoard(item.id))
        let placed = try #require(session.resources.terminalRuntimes[boardID])
        window.contentView = NSHostingView(rootView: surface(placed))
        window.contentView?.layoutSubtreeIfNeeded()
        placed.runCommand("printf 'drawer_continued_%s_%s\\n' '\(token)' \"$drawer_probe_value\"")
        try await waitForText("drawer_continued_\(token)_retained", runtime: placed)

        // Assert
        #expect(placed === runtime)
        #expect(!placed.terminalView.isHidden)
        #expect(placed.terminalView.window === window)
    }

    private func surface(_ runtime: TerminalRuntime) -> TerminalBoardSurface {
        TerminalBoardSurface(
            terminalView: runtime.terminalView, onSurfaceVisibilityChange: { runtime.setSurfaceVisible($0) },
            onBeforeHide: {}, isHidden: false, focusRequest: nil, onSurfaceReady: { _ in true })
    }

    private func waitForText(_ text: String, runtime: TerminalRuntime) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while runtime.readViewportText()?.contains(text) != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(runtime.readViewportText()?.contains(text) == true)
    }

    private func sessions(_ item: DrawerItem) -> (ProfileWindowSession, ProfileWindowSession) {
        let desks = [DeskState(label: "First", boards: []), DeskState(label: "Second", boards: [])]
        let resources = DenProfileResources(
            state: DenState(desks: desks, focusedDeskID: desks[0].id, drawerItems: [item]))
        let configuration = makeTestBoardRuntimeConfiguration()
        let make = { (desk: DeskState) in
            ProfileWindowSession(
                resources: resources, configuration: configuration, presentedDeskID: desk.id,
                canPresentDesk: { _ in true }, onDeskPresentationRequest: { _ in true }, onWillResetDen: {})
        }
        return (make(desks[0]), make(desks[1]))
    }
}
