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

    func showOpenBoardPanel() {
        setTemporaryContext(.openBoard)
    }

    func hideOpenBoardPanel() {
        if temporaryContext == .openBoard {
            setTemporaryContext(nil)
        }
    }

    func showNewDeskPanel() {
        guard canCreateDesk else { return }
        setTemporaryContext(.newDesk)
    }

    func hideNewDeskPanel() {
        if temporaryContext == .newDesk {
            setTemporaryContext(nil)
        }
    }

    func showSaveDeskTemplatePanel() {
        guard focusedDesk?.boards.isEmpty == false else { return }
        setTemporaryContext(.saveDeskTemplate)
    }

    func hideSaveDeskTemplatePanel() {
        if temporaryContext == .saveDeskTemplate {
            setTemporaryContext(nil)
        }
    }
}
