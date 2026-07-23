import Foundation

extension DenStore {
    func toggleDenMode() {
        guard temporaryContext == nil else { return }
        isDenMode.toggle()
    }

    func exitDenMode() {
        guard temporaryContext == nil else { return }
        isDenMode = false
    }

    func toggleZenView() {
        isZenViewPresented.toggle()
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
        setTemporaryContext(.openBoard)
    }

    func hideOpenBoardPanel() {
        if temporaryContext == .openBoard {
            openBoardPanelInitialURL = nil
            setTemporaryContext(nil)
        }
    }

    var isEditBoardLinkPanelPresented: Bool {
        temporaryContext == .editBoardLink
    }

    func showEditBoardLinkPanel() {
        guard focusedBoard != nil else { return }
        setTemporaryContext(.editBoardLink)
    }

    func hideEditBoardLinkPanel() {
        if temporaryContext == .editBoardLink {
            setTemporaryContext(nil)
        }
    }

    func showNewDeskPanel() {
        guard canCreateDesk else { return }
        setTemporaryContext(.newDesk)
    }

    func showDeskPresetManagement() {
        setTemporaryContext(.deskPresetManagement)
    }

    func hideNewDeskPanel() {
        if temporaryContext == .newDesk || temporaryContext == .deskPresetManagement {
            setTemporaryContext(nil)
        }
    }

    func showSaveDeskPresetPanel() {
        guard focusedDesk?.boards.isEmpty == false else { return }
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
