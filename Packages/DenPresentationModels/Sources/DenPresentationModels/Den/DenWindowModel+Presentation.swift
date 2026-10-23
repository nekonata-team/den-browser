import DenDomain
import Foundation

public extension DenWindowModel {
    func showUniversalSearch(commandsOnly: Bool = false) {
        universalSearch.prepare(commandsOnly: commandsOnly)
        setTemporaryContext(.universalSearch)
    }

    func hideUniversalSearch() {
        if temporaryContext == .universalSearch { setTemporaryContext(nil) }
    }

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
        get { inputs.isBoardRailPresented() }
        set { windowActions.setBoardRailPresented(newValue) }
    }

    var isBoardDragging: Bool {
        inputs.isBoardDragging()
    }
    var isDeskDragging: Bool {
        inputs.isDeskDragging()
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
            zmxActions.cancelDuplication()
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
        selectedEssentialID = inputs.essentials().first?.id
        setTemporaryContext(.essentialsPrefix)
    }

    func moveEssentialSelection(by offset: Int) {
        selectedEssentialID = SelectionNavigation.next(
            selectedEssentialID,
            among: inputs.essentials().map(\.id),
            by: offset
        )
    }

    func selectEssential(_ id: UUID) {
        guard inputs.essentials().contains(where: { $0.id == id }) else { return }
        selectedEssentialID = id
    }

    func launchSelectedEssential(inDrawer: Bool = false) {
        guard let selectedEssentialID else {
            exitEssentialsPrefix()
            return
        }
        launchEssential(id: selectedEssentialID, inDrawer: inDrawer)
    }

    func launchEssential(id: UUID, inDrawer: Bool = false) {
        exitEssentialsPrefix()
        onLaunchEssential(id, defaultBoardWidth, inDrawer)
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
            windowActions.didEnterDenMode()
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
        windowActions.setBoardRailPresented(isPresented)
    }

    func toggleBoardRail() { setBoardRailPresented(!isBoardRailPresented) }
    func toggleFocusMode() { isFocusModePresented.toggle() }

    func showKeyboardShortcuts() {
        setTemporaryContext(.keyboardShortcuts)
        if isDenMode { windowActions.didShowKeyboardShortcuts() }
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

    func showZmxSessions(selectedSessionName: String? = nil, returnsToOpenBoard: Bool = false) {
        guard zmxActions.canPresentSessions() else { return }
        zmxSessionsReturnToOpenBoard = returnsToOpenBoard
        zmxSessions.start(selectedSessionName: selectedSessionName)
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
        guard navigation.focusedBoard?.isWeb == true else {
            windowActions.reportWarning("No focused Web Board.")
            return
        }
        setTemporaryContext(.editBoardLink)
    }

    func hideEditBoardLinkPanel() {
        if temporaryContext == .editBoardLink { setTemporaryContext(nil) }
    }

    func showNewDeskPanel() {
        guard desks.canCreateDesk else {
            windowActions.reportWarning("Desks are limited to 10.")
            return
        }
        setTemporaryContext(.newDesk)
    }

    func showReplaceDeskPanel() {
        guard navigation.focusedDesk != nil else { return }
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
        guard navigation.focusedDesk?.boards.isEmpty == false else {
            windowActions.reportWarning("Desk has no boards to save as a preset.")
            return
        }
        setTemporaryContext(.saveDeskPreset)
    }

    func hideSaveDeskPresetPanel() {
        if temporaryContext == .saveDeskPreset { setTemporaryContext(nil) }
    }

    func showRenameBoardPanel() {
        guard navigation.focusedDesk?.focusedBoardID != nil else { return }
        setTemporaryContext(.renameBoard)
    }

    func hideRenameBoardPanel() {
        if temporaryContext == .renameBoard { setTemporaryContext(nil) }
    }

    func showRenameDeskPanel() {
        guard navigation.focusedDesk != nil else { return }
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
        boardActions.focusBoard(board.id, false)
        showSaveEssentialPanel(name: board.defaultEssentialName, key: "", input: input)
    }

    func showSaveEssentialPanel(for item: RecentItem) {
        showSaveEssentialPanel(name: item.defaultEssentialName, key: "", input: item.displayText)
    }

    @discardableResult
    func saveEssential(name: String, key: String, input: String) -> Bool {
        guard onSaveEssential(name, key, input) else { return false }
        if essentialPendingReplacement == nil { hideSaveEssentialPanel() }
        return true
    }

    var essentialPendingReplacement: Essential? {
        guard case .replaceEssential(let existing, _)? = pendingConfirmation else { return nil }
        return existing
    }

    func confirmEssentialReplacement() {
        guard let request = pendingConfirmation, case .replaceEssential = request,
            onConfirmOperation(request)
        else { return }
        pendingConfirmation = nil
        hideSaveEssentialPanel()
    }

    func cancelEssentialReplacement() {
        if essentialPendingReplacement != nil { pendingConfirmation = nil }
    }

    func hideSaveEssentialPanel() {
        if temporaryContext == .saveEssential { setTemporaryContext(nil) }
    }

    func saveFocusedBoardAsEssential() {
        guard let board = navigation.focusedBoard else {
            windowActions.reportWarning("No focused board.")
            return
        }
        showSaveEssentialPanel(for: board)
    }
}
