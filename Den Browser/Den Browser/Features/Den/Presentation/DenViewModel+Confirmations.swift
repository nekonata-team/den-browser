import Foundation

@MainActor
extension DenViewModel {
    var isResetDenPending: Bool {
        if case .resetDen? = pendingConfirmation { return true }
        return false
    }

    var hasPendingConfirmation: Bool {
        pendingConfirmation != nil || !zmxSessions.pendingDeletion.isEmpty
    }

    func requestResetDenConfirmation() {
        pendingConfirmation = .resetDen
    }

    func confirmResetDen() {
        guard isResetDenPending else { return }
        store.resetDen()
        pendingConfirmation = nil
    }

    func cancelResetDen() {
        guard isResetDenPending else { return }
        pendingConfirmation = nil
    }

    func confirmDeskDeletion() {
        guard case .deleteDesk(let desk)? = pendingConfirmation else { return }
        store.confirmDeskDeletion(desk.id)
        pendingConfirmation = nil
    }

    func confirmDeskReplacement() {
        guard case .replaceDesk(let replacement)? = pendingConfirmation else { return }
        store.confirmDeskReplacement(replacement)
        pendingConfirmation = nil
    }

    func cancelConfirmation() {
        pendingConfirmation = nil
    }
}
