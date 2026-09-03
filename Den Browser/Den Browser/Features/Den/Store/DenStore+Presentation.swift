import Foundation

extension DenStore {
    func enterEssentialsPrefix() {
        guard isDenMode else { return }
        showEssentialsPrefix()
    }

    func showEssentialsPrefix() {
        guard temporaryContext == nil else { return }
        setTemporaryContext(.essentialsPrefix)
    }

    func exitEssentialsPrefix() {
        if temporaryContext == .essentialsPrefix {
            setTemporaryContext(nil)
        }
    }

    func toggleDenMode() {
        guard temporaryContext == nil || temporaryContext == .drawer else { return }
        isDenMode.toggle()
        if !isDenMode {
            dismissDeskFilter()
        }
    }

    func exitDenMode() {
        guard temporaryContext == nil || temporaryContext == .drawer else { return }
        dismissDeskFilter()
        isDenMode = false
    }

    func toggleZenView() {
        isZenViewPresented.toggle()
    }

    func toggleFocusMode() {
        isFocusModePresented.toggle()
    }

    func showKeyboardShortcuts() {
        setTemporaryContext(.keyboardShortcuts)
    }

    func hideKeyboardShortcuts() {
        if temporaryContext == .keyboardShortcuts {
            setTemporaryContext(nil)
        }
    }

    func showOpenBoardPanel(initialURL: URL? = nil) {
        openBoardPanelInitialURL = initialURL
        openBoardPanelMessage = nil
        setTemporaryContext(.openBoard)
    }

    func hideOpenBoardPanel() {
        if temporaryContext == .openBoard {
            openBoardPanelInitialURL = nil
            openBoardPanelMessage = nil
            setTemporaryContext(nil)
        }
    }

    func showZmxSessions(selectedSessionName: String? = nil, returnsToOpenBoard: Bool = false) {
        guard zmxClient.isConfigured else {
            showToast("Set an absolute zmx executable path in Settings > Terminal.", style: .warning)
            return
        }
        zmxSessionSelectedName = selectedSessionName
        zmxSessionQuery = ""
        zmxSessionFilterPhase = .inactive
        zmxSessionsReturnToOpenBoard = returnsToOpenBoard
        refreshZmxSessions()
        setTemporaryContext(.zmxSessions)
    }

    func hideZmxSessions(returnToSource: Bool = true) {
        if temporaryContext == .zmxSessions {
            let returnsToOpenBoard = returnToSource && zmxSessionsReturnToOpenBoard
            zmxSessionRefreshTask?.cancel()
            zmxSessionRefreshTask = nil
            zmxSessionsIsLoading = false
            zmxSessionGroups = []
            zmxSessionsMessage = nil
            zmxSessionSelectedName = nil
            zmxSessionQuery = ""
            zmxSessionFilterPhase = .inactive
            zmxSessionPendingDeletion = nil
            zmxSessionsReturnToOpenBoard = false
            setTemporaryContext(returnsToOpenBoard ? .openBoard : nil)
        }
    }

    var isZmxDuplicationPanelPresented: Bool {
        temporaryContext == .zmxDuplication
    }

    func showZmxDuplicationPanel() {
        guard
            let board = focusedBoard,
            board.isZmx,
            let rootSessionName = zmxRootSessionName(for: board)
        else { return }
        updateZmxDuplicationRootSessionName(rootSessionName)
        setTemporaryContext(.zmxDuplication)
    }

    func hideZmxDuplicationPanel() {
        if temporaryContext == .zmxDuplication {
            setTemporaryContext(nil)
        }
    }

    var isEditBoardLinkPanelPresented: Bool {
        temporaryContext == .editBoardLink
    }

    func showEditBoardLinkPanel() {
        guard focusedBoard?.isTerminal == false else {
            showToast("No focused board.", style: .warning)
            return
        }
        setTemporaryContext(.editBoardLink)
    }

    func hideEditBoardLinkPanel() {
        if temporaryContext == .editBoardLink {
            setTemporaryContext(nil)
        }
    }

    func showNewDeskPanel() {
        guard canCreateDesk else {
            showToast("Desks are limited to 10.", style: .warning)
            return
        }
        setTemporaryContext(.newDesk)
    }

    func showReplaceDeskPanel() {
        guard focusedDesk != nil else { return }
        setTemporaryContext(.replaceDesk)
    }

    func showDeskPresetManagement() {
        setTemporaryContext(.deskPresetManagement)
    }

    func hideNewDeskPanel(exitsDenMode: Bool = false) {
        if temporaryContext == .newDesk
            || temporaryContext == .replaceDesk
            || temporaryContext == .deskPresetManagement
        {
            setTemporaryContext(nil)
            if exitsDenMode {
                isDenMode = false
            }
        }
    }

    func showSaveDeskPresetPanel() {
        guard focusedDesk?.boards.isEmpty == false else {
            showToast("Desk has no boards to save as a preset.", style: .warning)
            return
        }
        setTemporaryContext(.saveDeskPreset)
    }

    func hideSaveDeskPresetPanel() {
        if temporaryContext == .saveDeskPreset {
            setTemporaryContext(nil)
        }
    }

    var isRenameBoardPanelPresented: Bool {
        temporaryContext == .renameBoard
    }

    func showRenameBoardPanel() {
        guard focusedDesk?.focusedBoardID != nil else { return }
        setTemporaryContext(.renameBoard)
    }

    func hideRenameBoardPanel() {
        if temporaryContext == .renameBoard {
            setTemporaryContext(nil)
        }
    }

    var isRenameDeskPanelPresented: Bool {
        temporaryContext == .renameDesk
    }

    func showRenameDeskPanel() {
        guard focusedDesk != nil else { return }
        setTemporaryContext(.renameDesk)
    }

    func hideRenameDeskPanel() {
        if temporaryContext == .renameDesk {
            setTemporaryContext(nil)
        }
    }
}
