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
        guard focusedBoard != nil else {
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

    func showDeskPresetManagement() {
        setTemporaryContext(.deskPresetManagement)
    }

    func hideNewDeskPanel(exitsDenMode: Bool = false) {
        if temporaryContext == .newDesk || temporaryContext == .deskPresetManagement {
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
