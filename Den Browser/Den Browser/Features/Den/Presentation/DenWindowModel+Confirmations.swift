import DenApplication
import DenDomain
import DenPresentation
import Foundation

@MainActor
extension DenWindowModel {
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
        _ = onConfirmOperation(.resetDen)
        pendingConfirmation = nil
    }

    func cancelResetDen() {
        guard isResetDenPending else { return }
        pendingConfirmation = nil
    }

    func confirmDeskDeletion() {
        guard let request = pendingConfirmation, case .deleteDesk = request else { return }
        _ = onConfirmOperation(request)
        pendingConfirmation = nil
    }

    func confirmDeskReplacement() {
        guard let request = pendingConfirmation, case .replaceDesk = request else { return }
        _ = onConfirmOperation(request)
        pendingConfirmation = nil
    }

    func cancelConfirmation() {
        pendingConfirmation = nil
    }
}
