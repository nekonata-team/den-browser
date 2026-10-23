import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import WebKit

@MainActor
final class BoardNavigation {
    private let context: WindowNativeContext
    private var runtimes: BoardRuntimeAccess { context.runtimes }
    private var storage: DenProfileResources { context.storage }
    private var state: DenState { context.storage.state }
    private var preferences: AppPreferences { context.configuration.preferences }
    private var pasteboard: NSPasteboard { context.pasteboard }
    private var focusedDesk: DeskState? { context.focusedDesk }
    private var focusedBoard: BoardState? { context.focusedBoard }
    private var focusedDeskIndex: DeskIndex? { context.focusedDeskIndex }
    private var presentedDeskID: DeskID { context.navigation.presentedDeskID }
    private var navigation: WindowNavigationBindings { context.navigation }
    private var activeDrag: ActiveDrag? { context.storage.activeDrag }
    private var inputSourceTracker: BoardInputSourceTracker { context.inputSourceTracker }
    private var sheetNavigation: SheetNavigationManager { context.configuration.sheetNavigation }
    private var canPresentDesk: ((DeskID) -> Bool)? { context.canPresentDesk }
    private var onDeskPresentationRequest: ((DeskID) -> Bool)? { context.onDeskPresentationRequest }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }
    private var webRuntimes: [BoardID: WebRuntime] {
        get { context.storage.webRuntimes }
        set { context.storage.webRuntimes = newValue }
    }

    init(context: WindowNativeContext) {
        self.context = context
    }

    func focusDesk(_ deskID: DeskID) {
        let changedDesk = setFocusedDesk(deskID)
        guard changedDesk || presentedDeskID == deskID else { return }
        if let boardID = focusedDesk?.focusedBoardID {
            inputSourceTracker.boardDidFocus(boardID, isEnabled: preferences.rememberBoardInputMethod)
            if !changedDesk {
                storage.notificationOperations.markAllRead(for: boardID)
            }
        }
        onWindowEffect?(.dismissDeskFilter)
        onWindowEffect?(.exitDenMode)
        if changedDesk { storage.saveDeferredState() }
    }

    func focusBoard(_ boardID: BoardID, exitsDenMode: Bool = false) {
        inputSourceTracker.boardDidFocus(boardID, isEnabled: preferences.rememberBoardInputMethod)
        guard let indices = context.boardIndices(for: boardID) else { return }
        let deskID = state.desks[indices.deskOffset].id
        let changed = presentedDeskID != deskID || state.desks[indices.deskOffset].focusedBoardID != boardID
        if !changed {
            storage.notificationOperations.markAllRead(for: boardID)
            if exitsDenMode {
                onWindowEffect?(.exitDenMode)
            }
            return
        }
        onWindowEffect?(.clearBoardInputRequests)
        storage.state.desks[indices.deskOffset].focusedBoardID = boardID
        let changedDesk = setFocusedDesk(deskID)
        if !changedDesk && presentedDeskID == deskID {
            storage.notificationOperations.markAllRead(for: boardID)
        }
        if exitsDenMode {
            onWindowEffect?(.exitDenMode)
        }
        storage.saveDeferredState()
    }

    func focusPreviousDesk() {
        moveDeskFocus(by: -1)
    }

    func focusNextDesk() {
        moveDeskFocus(by: 1)
    }

    func focusPreviousBoard() {
        moveBoardFocus(by: -1)
    }

    func focusNextBoard() {
        moveBoardFocus(by: 1)
    }

    func focusFirstBoardInDesk(containing boardID: BoardID) {
        guard
            let deskIndex = context.boardIndices(for: boardID)?.deskOffset,
            let firstBoardID = state.desks[deskIndex].boards.first?.id
        else { return }
        focusBoard(firstBoardID)
    }

    func focusLastBoardInDesk(containing boardID: BoardID) {
        guard
            let deskIndex = context.boardIndices(for: boardID)?.deskOffset,
            let lastBoardID = state.desks[deskIndex].boards.last?.id
        else { return }
        focusBoard(lastBoardID)
    }

    func moveFocusedBoardLeft() {
        moveFocusedBoard(by: -1)
    }

    func moveFocusedBoardRight() {
        moveFocusedBoard(by: 1)
    }

    func moveFocusedBoardToPreviousDesk() {
        moveFocusedBoardToDesk(by: -1)
    }

    func moveFocusedBoardToNextDesk() {
        moveFocusedBoardToDesk(by: 1)
    }

    func toggleFocusedBoardSheetNavigationPause() {
        guard let focusedBoardID = focusedDesk?.focusedBoardID else { return }
        toggleBoardSheetNavigationPause(focusedBoardID)
    }

    func toggleBoardSheetNavigationPause(_ boardID: BoardID) {
        guard
            let indices = context.boardIndices(for: boardID),
            state.desks[indices.deskOffset].boards[indices.boardOffset].isWeb
        else { return }

        storage.state.desks[indices.deskOffset].boards[indices.boardOffset].sheetNavigationPaused.toggle()
        let paused = state.desks[indices.deskOffset].boards[indices.boardOffset].sheetNavigationPaused
        sheetNavigation.setBoardPaused(paused, for: boardID)
        storage.save()
    }

    func centerFocusedBoard() {
        guard let focusedDeskIndex, focusedDesk?.focusedBoardID != nil else { return }
        if state.desks[focusedDeskIndex.rawValue].scrollOffsetX != nil {
            storage.state.desks[focusedDeskIndex.rawValue].scrollOffsetX = nil
            storage.save()
        }
        onWindowEffect?(.centerFocusedBoard)
    }

    func revealPreviousBoard() {
        guard focusedDesk?.focusedBoardID != nil else { return }
        onWindowEffect?(.revealPreviousBoard)
    }

    func revealNextBoard() {
        guard focusedDesk?.focusedBoardID != nil else { return }
        onWindowEffect?(.revealNextBoard)
    }

    func focusDesk(number: Int) {
        guard (1...DeskCreation.maximumDeskCount).contains(number) else { return }
        guard state.desks.indices.contains(number - 1) else {
            context.feedback.publish("Desk \(number) does not exist.", severity: .warning)
            return
        }
        focusDesk(state.desks[number - 1].id)
    }

    func moveFocusedBoard(toDeskNumber number: Int) {
        guard (1...DeskCreation.maximumDeskCount).contains(number) else { return }
        guard state.desks.indices.contains(number - 1) else {
            context.feedback.publish("Desk \(number) does not exist.", severity: .warning)
            return
        }
        moveFocusedBoard(toDeskAt: DeskIndex(rawValue: number - 1))
    }

    func focusedBoardIndex(in deskIndex: DeskIndex) -> BoardIndex? {
        let deskOffset = deskIndex.rawValue
        guard let focusedBoardID = state.desks[deskOffset].focusedBoardID else { return nil }
        return state.desks[deskOffset].boards.firstIndex { $0.id == focusedBoardID }
            .map { BoardIndex(rawValue: $0) }
    }

    func beginBoardDrag(_ boardID: BoardID) -> Bool {
        storage.boardMovement.beginDrag(boardID, in: presentedDeskID) {
            onWindowEffect?(.clearMaximizedBoard)
        }
    }

    func requestBoardDragCancellation() {
        guard case .board? = activeDrag else { return }
        onWindowEffect?(.cancelBoardDrag)
    }

    func requestDeskDragCancellation() {
        guard case .desk? = activeDrag else { return }
        onWindowEffect?(.cancelDeskDrag)
    }

    private func moveDeskFocus(by delta: Int) {
        guard let currentIndex = focusedDeskIndex, !state.desks.isEmpty else { return }
        onWindowEffect?(.dismissDeskFilter)
        let nextIndex = wrappedIndex(currentIndex.rawValue + delta, count: state.desks.count)
        let targetDeskID = state.desks[nextIndex].id
        guard setFocusedDesk(targetDeskID) else { return }
        storage.saveDeferredState()
    }

    private func moveBoardFocus(by delta: Int) {
        guard let deskIndex = focusedDeskIndex else { return }
        let boards = state.desks[deskIndex.rawValue].boards
        guard !boards.isEmpty else { return }

        let nextIndex: BoardIndex
        if let currentIndex = focusedBoardIndex(in: deskIndex) {
            nextIndex = BoardIndex(rawValue: wrappedIndex(currentIndex.rawValue + delta, count: boards.count))
        } else {
            nextIndex = BoardIndex(rawValue: delta >= 0 ? 0 : boards.count - 1)
        }
        let boardID = boards[nextIndex.rawValue].id
        let changesFocus = state.desks[deskIndex.rawValue].focusedBoardID != boardID
        storage.state.desks[deskIndex.rawValue].focusedBoardID = boardID
        storage.notificationOperations.markAllRead(for: boardID)
        guard changesFocus else { return }
        inputSourceTracker.boardDidFocus(boardID, isEnabled: preferences.rememberBoardInputMethod)
        runtimes.restoreFocusedFirstResponder()
        storage.recordOperation(.boardFocusMoved)
        storage.saveDeferredState()
    }

    private func moveFocusedBoard(by delta: Int) {
        guard let board = focusedBoard else { return }
        storage.boardMovement.shiftAndCenter(board.id, by: delta) { centerFocusedBoard() }
    }

    private func moveFocusedBoardToDesk(by delta: Int) {
        guard
            state.desks.count > 1,
            let sourceDeskIndex = focusedDeskIndex
        else { return }

        moveFocusedBoard(
            toDeskAt: DeskIndex(rawValue: wrappedIndex(sourceDeskIndex.rawValue + delta, count: state.desks.count)))
    }

    private func moveFocusedBoard(toDeskAt targetDeskIndex: DeskIndex) {
        guard state.desks.indices.contains(targetDeskIndex.rawValue), let board = focusedBoard else { return }
        storage.boardMovement.transferAndPresent(board.id, to: state.desks[targetDeskIndex.rawValue].id) { deskID in
            setFocusedDesk(deskID, autoPIP: false)
            onWindowEffect?(.exitDenMode)
        }
    }

    func copyBoardID(_ boardID: BoardID, pasteboard: NSPasteboard? = nil) {
        let pasteboard = pasteboard ?? self.pasteboard
        guard state.desks.contains(where: { $0.boards.contains { $0.id == boardID } }) else { return }
        pasteboard.clearContents()
        pasteboard.setString(boardID.rawValue.uuidString.lowercased(), forType: .string)
        context.feedback.publish("Copied Board ID.", severity: .success)
    }

    func copyBoardLocation(_ boardID: BoardID? = nil, pasteboard: NSPasteboard? = nil) {
        let pasteboard = pasteboard ?? self.pasteboard
        let board: BoardState?
        if let boardID {
            guard let indices = context.boardIndices(for: boardID) else { return }
            board = state.desks[indices.deskOffset].boards[indices.boardOffset]
        } else {
            board = focusedBoard
        }
        guard let board else { return }

        let value: String
        let message: String
        switch board.kind {
        case .web(let web):
            guard let url = web.currentSheetURL ?? web.firstSheetURL else { return }
            value = url.absoluteString
            message = "Copied Current Sheet URL."
        case .inspection:
            guard let targetBoardID = board.sideBoardTargetBoardID else { return }
            value = targetBoardID.rawValue.uuidString.lowercased()
            message = "Copied target Board ID."
        case .terminal(let terminal):
            switch terminal {
            case .shell(let workingDirectory):
                value = workingDirectory
                message = "Copied Terminal working directory."
            case .zellij(let zellij):
                guard let sessionName = zellij.sessionName, !sessionName.isEmpty else { return }
                value = sessionName
                message = "Copied Zellij session name."
            case .zmx(let zmx):
                value = zmx.sessionName
                message = "Copied zmx session name."
            }
        case .tutorial:
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        context.feedback.publish(message, severity: .success)
    }

    func toggleAnchorBoard() {
        guard let desk = focusedDesk, let focusedBoardID = desk.focusedBoardID else { return }
        toggleAnchorBoard(focusedBoardID, in: desk.id)
    }

    func toggleAnchorBoard(_ boardID: BoardID, in deskID: DeskID) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }),
            state.desks[deskIndex].boards.contains(where: { $0.id == boardID })
        else { return }

        if state.desks[deskIndex].anchorBoardID == boardID {
            storage.state.desks[deskIndex].anchorBoardID = nil
            context.feedback.publish("Cleared Anchor Board")
        } else {
            storage.state.desks[deskIndex].anchorBoardID = boardID
            context.feedback.publish("Set Anchor Board")
        }
        storage.save()
    }

    func jumpToAnchorBoard() {
        guard let deskIndex = focusedDeskIndex else { return }
        let desk = state.desks[deskIndex.rawValue]
        guard let anchorBoardID = desk.anchorBoardID,
            desk.boards.contains(where: { $0.id == anchorBoardID })
        else {
            context.feedback.publish("No Anchor Board in Desk", severity: .warning)
            return
        }

        let currentBoardID = desk.focusedBoardID
        if currentBoardID != anchorBoardID {
            navigation.anchorJumpOriginBoardIDByDesk[desk.id] = currentBoardID
            focusBoard(anchorBoardID)
            centerFocusedBoard()
        } else if let originID = navigation.anchorJumpOriginBoardIDByDesk[desk.id],
            originID != anchorBoardID,
            desk.boards.contains(where: { $0.id == originID })
        {
            navigation.anchorJumpOriginBoardIDByDesk[desk.id] = anchorBoardID
            focusBoard(originID)
            centerFocusedBoard()
        }
    }

    func enterOverviewSelection(deskID: DeskID, boardID: BoardID?) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else {
            onWindowEffect?(.dismissTemporaryPresentation)
            return
        }

        let previousFocusedDeskID = state.focusedDeskID
        let previousFocusedBoardID = state.desks[deskIndex].focusedBoardID
        if let boardID, state.desks[deskIndex].boards.contains(where: { $0.id == boardID }) {
            storage.state.desks[deskIndex].focusedBoardID = boardID
        } else if state.desks[deskIndex].focusedBoardID == nil {
            storage.state.desks[deskIndex].focusedBoardID = state.desks[deskIndex].boards.first?.id
        }
        let changedDesk = setFocusedDesk(deskID)
        if !changedDesk,
            presentedDeskID == deskID,
            let boardID = state.desks[deskIndex].focusedBoardID
        {
            storage.notificationOperations.markAllRead(for: boardID)
        }
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        if state.focusedDeskID != previousFocusedDeskID
            || state.desks[deskIndex].focusedBoardID != previousFocusedBoardID
        {
            storage.saveDeferredState()
        }
    }

    @discardableResult
    func prepareBoardLinkFocus(
        _ boardID: BoardID,
        origin: BoardOperationOrigin = .interactive
    ) -> BoardLinkFocusIntent {
        let intent = BoardLinkFocusIntent(boardID: boardID, origin: origin)
        onWindowEffect?(.boardLinkFocusRequested(intent))
        return intent
    }

    @discardableResult
    func setFocusedDesk(_ deskID: DeskID, autoPIP: Bool = true) -> Bool {
        guard presentedDeskID != deskID else { return false }
        guard state.desks.contains(where: { $0.id == deskID }) else { return false }
        guard onDeskPresentationRequest?(deskID) ?? true else { return false }
        if autoPIP {
            enterPictureInPictureForDeskSwitch()
        }
        navigation.present(deskID)
        storage.deskUpdates.recordPresentedDesk(deskID)
        onWindowEffect?(.clearBoardInputRequests)
        if let boardID = focusedDesk?.focusedBoardID {
            inputSourceTracker.boardDidFocus(boardID, isEnabled: preferences.rememberBoardInputMethod)
            storage.notificationOperations.markAllRead(for: boardID)
        }
        return true
    }

    private func enterPictureInPictureForDeskSwitch() {
        guard
            preferences.automaticPIPOnDeskSwitch,
            let focusedDesk,
            let focusedBoardID = focusedDesk.focusedBoardID,
            let runtime = webRuntimes[focusedBoardID]
        else { return }

        runtime.enterPictureInPictureIfPlaying()
    }

    func canSelectDesk(_ deskID: DeskID) -> Bool {
        deskID == presentedDeskID || (canPresentDesk?(deskID) ?? true)
    }

    func returnToPreviousDesk() {
        guard let previousFocusedDeskID = navigation.previousFocusedDeskID else { return }
        guard setFocusedDesk(previousFocusedDeskID) else {
            self.navigation.previousFocusedDeskID = nil
            return
        }
        onWindowEffect?(.exitDenMode)
        storage.saveDeferredState()
    }

    func wrappedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }

    func updateFullscreenStatus(boardID: BoardID, isFullscreen: Bool) {
        if isFullscreen {
            onWindowEffect?(.exitDenMode)
            onWindowEffect?(.fullscreenChanged(true))
        } else {
            let focusedBoardIDs = Set(focusedDesk?.boards.map(\.id) ?? [])
            let isFullscreenActive = webRuntimes.contains { boardID, runtime in
                focusedBoardIDs.contains(boardID)
                    && (runtime.webView.fullscreenState == .inFullscreen
                        || runtime.webView.fullscreenState == .enteringFullscreen)
            }
            onWindowEffect?(.fullscreenChanged(isFullscreenActive))
        }
    }
}
