import AppKit
import DenDomain
import Foundation

extension DenViewModel {
    var isDrawerOpen: Bool { temporaryContext == .drawer }
    var isOpenBoardPanelPresented: Bool { temporaryContext == .openBoard }
    var isZmxSessionsPresented: Bool { temporaryContext == .zmxSessions }
    var isNewDeskPanelPresented: Bool {
        temporaryContext == .newDesk || temporaryContext == .replaceDesk
            || temporaryContext == .deskPresetManagement
    }
    var isReplaceDeskPanelPresented: Bool { temporaryContext == .replaceDesk }
    var isDeskPresetManagementPresented: Bool { temporaryContext == .deskPresetManagement }
    var isOverviewPresented: Bool { temporaryContext == .overview }
    var isBoardActivityPresented: Bool { temporaryContext == .boardActivity }
    var isKeyboardShortcutsPresented: Bool { temporaryContext == .keyboardShortcuts }
    var isBoardWidthPanelPresented: Bool { temporaryContext == .boardWidth }
    var isSaveDeskPresetPanelPresented: Bool { temporaryContext == .saveDeskPreset }
    var isZmxDuplicationPanelPresented: Bool { temporaryContext == .zmxDuplication }
    var isEditBoardLinkPanelPresented: Bool { temporaryContext == .editBoardLink }
    var isRenameBoardPanelPresented: Bool { temporaryContext == .renameBoard }
    var isRenameDeskPanelPresented: Bool { temporaryContext == .renameDesk }
    var isSaveEssentialPanelPresented: Bool { temporaryContext == .saveEssential }
    var isBoardRailPresented: Bool {
        get { store.preferences.isBoardRailPresented }
        set { store.preferences.setBoardRailPresented(newValue) }
    }

    var isBoardDragging: Bool {
        guard case .board? = store.activeDrag else { return false }
        return true
    }
    var isDeskDragging: Bool {
        guard case .desk? = store.activeDrag else { return false }
        return true
    }

    func setTemporaryContext(_ context: TemporaryContext?) {
        if context != nil {
            deskFilter.dismiss()
            closeNotificationList()
        }
        if let previousContext = temporaryContext, previousContext != context {
            endTemporaryContext(previousContext, transitioningTo: context)
        }
        temporaryContext = context
    }

    private func endTemporaryContext(_ context: TemporaryContext, transitioningTo nextContext: TemporaryContext?) {
        switch context {
        case .openBoard:
            openBoard.endPresentation(
                preservingDraft: nextContext == .zmxSessions && zmxSessionsReturnToOpenBoard)
        case .overview:
            overview.endPresentation()
        case .boardWidth:
            boardWidthPanelMessage = nil
        case .drawer:
            drawer.endPresentation()
        case .zmxDuplication:
            store.cancelZmxDuplicationRequest()
            zmxDuplicationRootSessionName = nil
        case .zmxSessions:
            let wasReturningToOpenBoard = zmxSessionsReturnToOpenBoard
            zmxSessionsReturnToOpenBoard = false
            zmxSessions.stop()
            if wasReturningToOpenBoard, nextContext != .openBoard {
                openBoard.endPresentation(preservingDraft: false)
            }
        case .saveEssential:
            saveEssentialDraft = nil
        default:
            break
        }
    }

    func resetPresentation() {
        setTemporaryContext(nil)
        deskFilter.dismiss()
        openBoard.resetPresentation()
        overview.endPresentation()
        drawer.resetPresentation()
        saveEssentialDraft = nil
        selectedEssentialID = nil
        pendingConfirmation = nil
        maximizedBoardID = nil
        isZenViewPresented = false
        isFocusModePresented = false
        isDenMode = false
        closeNotificationList()
        boardWidthPanelMessage = nil
    }

    func enterEssentialsPrefix() {
        guard isDenMode else { return }
        showEssentialsPrefix()
    }

    func showEssentialsPrefix() {
        guard temporaryContext == nil else { return }
        selectedEssentialID = store.essentials.first?.id
        setTemporaryContext(.essentialsPrefix)
    }

    func moveEssentialSelection(by offset: Int) {
        selectedEssentialID = DenSelectionNavigation.next(
            selectedEssentialID,
            among: store.essentials.map(\.id),
            by: offset
        )
    }

    func selectEssential(_ id: UUID) {
        guard store.essentials.contains(where: { $0.id == id }) else { return }
        selectedEssentialID = id
    }

    func launchSelectedEssential() {
        guard let selectedEssentialID else {
            exitEssentialsPrefix()
            return
        }
        launchEssential(id: selectedEssentialID)
    }

    func launchEssential(id: UUID) {
        guard let essential = store.essentials.first(where: { $0.id == id }) else {
            exitEssentialsPrefix()
            return
        }
        exitEssentialsPrefix()
        openBoard.message = nil
        guard !store.openBoard(input: essential.input, preferredWidth: defaultBoardWidth) else { return }
        let message = openBoard.message ?? "Could not open Essential '\(essential.name)'."
        openBoard.message = nil
        store.reportFeedback(message, severity: .warning)
    }

    func exitEssentialsPrefix() {
        guard temporaryContext == .essentialsPrefix else { return }
        selectedEssentialID = nil
        setTemporaryContext(nil)
    }

    func toggleDenMode() {
        guard temporaryContext == nil || temporaryContext == .drawer else { return }
        isDenMode.toggle()
        if isDenMode {
            store.dispatchDenOperationEvent(.denModeEntered)
        } else {
            deskFilter.dismiss()
        }
    }

    func exitDenMode() {
        guard temporaryContext == nil || temporaryContext == .drawer else { return }
        deskFilter.dismiss()
        isDenMode = false
    }

    func toggleZenView() { isZenViewPresented.toggle() }

    func setBoardRailPresented(_ isPresented: Bool) {
        guard !isZenViewPresented else { return }
        store.preferences.setBoardRailPresented(isPresented)
    }

    func toggleBoardRail() { setBoardRailPresented(!isBoardRailPresented) }
    func toggleFocusMode() { isFocusModePresented.toggle() }

    func showKeyboardShortcuts() {
        setTemporaryContext(.keyboardShortcuts)
        if isDenMode { store.dispatchDenOperationEvent(.keyboardShortcutsShown) }
    }

    func hideKeyboardShortcuts() {
        if temporaryContext == .keyboardShortcuts { setTemporaryContext(nil) }
    }

    func showOpenBoardPanel(initialURL: URL? = nil, afterBoardID: BoardID? = nil) {
        openBoard.preparePresentation(initialURL: initialURL, afterBoardID: afterBoardID)
        setTemporaryContext(.openBoard)
    }

    func hideOpenBoardPanel() {
        if temporaryContext == .openBoard { setTemporaryContext(nil) }
    }

    func submitOpenBoard(_ input: String? = nil, preferredWidth: Double? = nil) {
        let input = input ?? openBoard.input
        let rootSessionName: String?
        if case .session(let sessionName)? = DenStore.resolveZmxInput(input) {
            rootSessionName = zmxSessions.rootSessionName(for: sessionName)
        } else {
            rootSessionName = nil
        }
        openBoard.submit(
            input,
            preferredWidth: preferredWidth ?? defaultBoardWidth,
            zmxRootSessionName: rootSessionName)
    }

    func openBoardFromClipboard(pasteboard: NSPasteboard? = nil, preferredWidth: Double? = nil) {
        let pasteboard = pasteboard ?? store.pasteboard
        guard
            let input = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !input.isEmpty
        else {
            store.reportFeedback("Clipboard is empty.", severity: .warning)
            return
        }

        openBoard.message = nil
        guard
            !store.openBoard(
                input: input,
                preferredWidth: preferredWidth ?? defaultBoardWidth,
                afterBoardID: store.focusedBoard?.id)
        else { return }
        let message = openBoard.message ?? "Could not open board from clipboard."
        openBoard.message = nil
        store.reportFeedback(message, severity: .warning)
    }

    func openRecentItem(_ item: RecentItem, preferredWidth: Double? = nil) {
        submitOpenBoard(item.displayText, preferredWidth: preferredWidth)
    }

    func showZmxSessions(selectedSessionName: String? = nil, returnsToOpenBoard: Bool = false) {
        guard store.zmxClient.isConfigured else {
            store.reportFeedback("Set an absolute zmx executable path in Settings > Terminal.", severity: .warning)
            return
        }
        zmxSessionsReturnToOpenBoard = returnsToOpenBoard
        zmxSessions.start(client: store.zmxClient, selectedSessionName: selectedSessionName)
        setTemporaryContext(.zmxSessions)
    }

    func hideZmxSessions(returnToSource: Bool = true) {
        if temporaryContext == .zmxSessions {
            let returnsToOpenBoard = returnToSource && zmxSessionsReturnToOpenBoard
            setTemporaryContext(returnsToOpenBoard ? .openBoard : nil)
        }
    }

    func hideZmxDuplicationPanel() {
        if temporaryContext == .zmxDuplication { setTemporaryContext(nil) }
    }

    func showEditBoardLinkPanel() {
        guard store.focusedBoard?.isWeb == true else {
            store.reportFeedback("No focused Web Board.", severity: .warning)
            return
        }
        setTemporaryContext(.editBoardLink)
    }

    func hideEditBoardLinkPanel() {
        if temporaryContext == .editBoardLink { setTemporaryContext(nil) }
    }

    func showNewDeskPanel() {
        guard store.canCreateDesk else {
            store.reportFeedback("Desks are limited to 10.", severity: .warning)
            return
        }
        setTemporaryContext(.newDesk)
    }

    func showReplaceDeskPanel() {
        guard store.focusedDesk != nil else { return }
        setTemporaryContext(.replaceDesk)
    }

    func showDeskPresetManagement() { setTemporaryContext(.deskPresetManagement) }

    func hideNewDeskPanel(exitsDenMode: Bool = false) {
        if temporaryContext == .newDesk || temporaryContext == .replaceDesk
            || temporaryContext == .deskPresetManagement
        {
            setTemporaryContext(nil)
            if exitsDenMode { isDenMode = false }
        }
    }

    func showSaveDeskPresetPanel() {
        guard store.focusedDesk?.boards.isEmpty == false else {
            store.reportFeedback("Desk has no boards to save as a preset.", severity: .warning)
            return
        }
        setTemporaryContext(.saveDeskPreset)
    }

    func hideSaveDeskPresetPanel() {
        if temporaryContext == .saveDeskPreset { setTemporaryContext(nil) }
    }

    func showRenameBoardPanel() {
        guard store.focusedDesk?.focusedBoardID != nil else { return }
        setTemporaryContext(.renameBoard)
    }

    func hideRenameBoardPanel() {
        if temporaryContext == .renameBoard { setTemporaryContext(nil) }
    }

    func showRenameDeskPanel() {
        guard store.focusedDesk != nil else { return }
        setTemporaryContext(.renameDesk)
    }

    func hideRenameDeskPanel() {
        if temporaryContext == .renameDesk { setTemporaryContext(nil) }
    }

    func showSaveEssentialPanel(name: String = "", key: String = "", input: String = "") {
        saveEssentialDraft = SaveEssentialDraft(name: name, key: key, input: input)
        setTemporaryContext(.saveEssential)
    }

    func showSaveEssentialPanel(for board: BoardState) {
        guard let input = board.essentialInput else { return }
        store.focusBoard(board.id)
        showSaveEssentialPanel(name: board.defaultEssentialName, key: "", input: input)
    }

    func showSaveEssentialPanel(for item: RecentItem) {
        showSaveEssentialPanel(name: item.defaultEssentialName, key: "", input: item.displayText)
    }

    @discardableResult
    func saveEssential(name: String, key: String, input: String) -> Bool {
        guard store.saveEssential(name: name, key: key, input: input) else { return false }
        hideSaveEssentialPanel()
        return true
    }

    func hideSaveEssentialPanel() {
        if temporaryContext == .saveEssential { setTemporaryContext(nil) }
    }

    func saveFocusedBoardAsEssential() {
        guard let board = store.focusedBoard else {
            store.reportFeedback("No focused board.", severity: .warning)
            return
        }
        showSaveEssentialPanel(for: board)
    }
}
